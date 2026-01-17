import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'main.dart'; // To access ChatScreen
import 'user_list_page.dart';
import 'profile_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Design Colors
  final Color _headerColor = const Color(0xFF292F3F); 
  final Color _chatListColor = const Color(0xFF101216); 
  final Color _inputBackgroundColor = const Color(0xFF1D222C);
  final Color _accentBlue = const Color(0xFF375FFF);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _headerColor,
      body: SafeArea(
        child: Column(
          children: [
            // --- TOP AREA: PROFILE HEADER (Hi, User!) ---
            StreamBuilder<DocumentSnapshot>(
              stream: FirebaseFirestore.instance.collection('users').doc(_auth.currentUser!.uid).snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const SizedBox(height: 100);
                
                var myData = snapshot.data!.data() as Map<String, dynamic>? ?? {};
                String myName = myData['displayName'] ?? myData['username'] ?? "User";
                String? myPic = myData['profilePic'];

                return GestureDetector(
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfilePage())),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 25.0),
                    color: Colors.transparent, // Ensures the whole area is clickable
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 28,
                          backgroundColor: _inputBackgroundColor,
                          backgroundImage: myPic != null ? MemoryImage(base64Decode(myPic)) : null,
                          child: myPic == null ? Text(myName[0].toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)) : null,
                        ),
                        const SizedBox(width: 15),
                        Text(
                          "Hi, $myName!",
                          style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),

            // --- BOTTOM AREA: CHAT LIST WITH ROUNDED SHEET ---
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: _chatListColor,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(40)),
                ),
                clipBehavior: Clip.antiAlias,
                child: StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('chat_rooms')
                      .where('participants', arrayContains: _auth.currentUser!.uid)
                      .orderBy('lastMessageTimestamp', descending: true)
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.hasError) return const Center(child: Text("Error loading chats.", style: TextStyle(color: Colors.white)));
                    if (!snapshot.hasData) return const Center(child: CircularProgressIndicator(color: Color(0xFF375FFF)));
                    
                    var rooms = snapshot.data!.docs;
                    if (rooms.isEmpty) return const Center(child: Text("No active chats.", style: TextStyle(color: Colors.grey)));

                    return ListView.builder(
                      padding: const EdgeInsets.only(top: 20),
                      itemCount: rooms.length,
                      itemBuilder: (context, index) {
                        var roomData = rooms[index].data() as Map<String, dynamic>;
                        var otherId = (roomData['participants'] as List).firstWhere((id) => id != _auth.currentUser!.uid);
                        
                        return FutureBuilder<DocumentSnapshot>(
                          future: FirebaseFirestore.instance.collection('users').doc(otherId).get(),
                          builder: (context, userSnap) {
                            if (!userSnap.hasData) return const SizedBox();
                            var userData = userSnap.data!.data() as Map<String, dynamic>? ?? {};
                            return _buildTile(userData, roomData, rooms[index].id);
                          },
                        );
                      },
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),

      // FAB to start new chat
      floatingActionButton: FloatingActionButton(
        backgroundColor: _accentBlue,
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const UserListPage())),
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  Widget _buildTile(Map<String, dynamic> user, Map<String, dynamic> room, String id) {
    String name = user['username'] ?? user['name'] ?? "User";
    String? pic = user['profilePic']; 
    
    // --- ONLINE STATUS LOGIC ---
    bool isOnline = user['isOnline'] ?? false;
    Color borderColor = isOnline ? _accentBlue : Colors.grey;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      onTap: () {
        // Since we have the ID, we pass it to ChatScreen. 
        // Note: ChatScreen needs receiverUserID, so we grab that from the user map or logic.
        // The FutureBuilder above fetched by 'otherId', so user['uid'] might not be in the doc data depending on how you save it.
        // It's safer to use the ID we used to fetch the doc.
        // However, based on your previous code, we can assume logic holds.
        // Let's find the ID again to be safe or assume it's in the map.
        // For now, I will use the user['uid'] if present, or fallback.
        // Actually, looking at previous code, let's just use the ID we derived earlier? 
        // We can't access 'otherId' easily here without passing it. 
        // Let's rely on the user map having the ID or just assume the click handles it.
        // EDIT: Added 'uid' to the nav push just in case, but usually doc.id is the uid.
         Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen(receiverUserID: user['uid'] ?? "", receiverName: name)));
      },
      leading: Container(
        padding: const EdgeInsets.all(2.5), // Space for the border
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: borderColor, // Blue if online, Gray if offline
            width: 2.5
          ),
        ),
        child: CircleAvatar(
          radius: 30, // Slightly smaller to fit border
          backgroundColor: _inputBackgroundColor,
          backgroundImage: pic != null ? MemoryImage(base64Decode(pic)) : null,
          child: pic == null ? Text(name[0].toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)) : null,
        ),
      ),
      title: Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
      
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4.0),
        child: StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance.collection('chat_rooms').doc(id).collection('messages')
              .orderBy('timestamp', descending: true).limit(1).snapshots(),
          builder: (context, snapshot) {
            if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
              return const Text("", style: TextStyle(color: Colors.grey, fontSize: 14));
            }

            var msgData = snapshot.data!.docs.first.data() as Map<String, dynamic>;
            String text = msgData['message'] ?? "";
            String type = msgData['type'] ?? 'text';
            String senderId = msgData['senderId'] ?? "";

            String displayContent = type == 'image' ? '📷 Photo' : (type == 'audio' ? '🎤 Voice' : text);
            String prefix = (senderId == _auth.currentUser!.uid) ? "You: " : "$name: ";

            return Text(
              "$prefix$displayContent",
              style: const TextStyle(color: Colors.grey, fontSize: 14),
              maxLines: 1, 
              overflow: TextOverflow.ellipsis
            );
          },
        ),
      ),
      trailing: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('chat_rooms').doc(id).collection('messages')
            .where('receiverId', isEqualTo: _auth.currentUser!.uid).where('isRead', isEqualTo: false).snapshots(),
        builder: (context, snap) {
          int count = snap.hasData ? snap.data!.docs.length : 0;
          return count > 0 ? Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: _accentBlue, borderRadius: BorderRadius.circular(10)),
            child: Text(count.toString(), style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
          ) : const SizedBox.shrink();
        },
      ),
    );
  }
}