import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'main.dart'; // To access ChatScreen
import 'user_list_page.dart';
import 'group_selection_page.dart'; // Import the new file
import 'profile_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  final Color _headerColor = const Color(0xFF1D222C); 
  final Color _chatListColor = const Color(0xFF101216); 
  final Color _inputBackgroundColor = const Color(0xFF1D222C);
  final Color _accentBlue = const Color(0xFF375FFF);

  void _showFabOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: _headerColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(Icons.chat_bubble_outline, color: Colors.white),
                title: const Text("Open all chats", style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const UserListPage()));
                },
              ),
              ListTile(
                leading: const Icon(Icons.group_add_outlined, color: Colors.white),
                title: const Text("Create Group Chat", style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const GroupSelectionPage()));
                },
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _headerColor,
      body: SafeArea(
        child: Column(
          children: [
            // PROFILE HEADER
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
                    color: Colors.transparent, 
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

            // CHAT LIST
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
                        bool isGroup = roomData['isGroup'] ?? false;
                        
                        if (isGroup) {
                          return GroupChatTile(
                            roomData: roomData, 
                            roomId: rooms[index].id,
                            currentUserId: _auth.currentUser!.uid,
                            accentBlue: _accentBlue, 
                            inputBackgroundColor: _inputBackgroundColor
                          );
                        } else {
                          var otherId = (roomData['participants'] as List).firstWhere((id) => id != _auth.currentUser!.uid, orElse: () => "");
                          return ChatTile(
                            roomId: rooms[index].id,
                            otherUserId: otherId,
                            currentUserId: _auth.currentUser!.uid,
                            accentBlue: _accentBlue,
                            inputBackgroundColor: _inputBackgroundColor,
                          );
                        }
                      },
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),

      floatingActionButton: FloatingActionButton(
        backgroundColor: _accentBlue,
        onPressed: _showFabOptions,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }
}

// --- UPDATED GROUP WIDGET TO SHOW AVATAR ---
class GroupChatTile extends StatelessWidget {
  final Map<String, dynamic> roomData;
  final String roomId;
  final String currentUserId;
  final Color accentBlue;
  final Color inputBackgroundColor;

  const GroupChatTile({
    super.key,
    required this.roomData,
    required this.roomId,
    required this.currentUserId,
    required this.accentBlue,
    required this.inputBackgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    String groupName = roomData['groupName'] ?? "Group Chat";
    String? groupPic = roomData['groupPic']; // Fetch group picture

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen(
        receiverUserID: "",
        receiverName: groupName,
        isGroup: true,
        roomId: roomId,
      ))),
      leading: Container(
        padding: const EdgeInsets.all(2.5),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.transparent, width: 2.5),
        ),
        child: CircleAvatar(
          radius: 30,
          backgroundColor: inputBackgroundColor,
          // --- UPDATED: Show group image if available ---
          backgroundImage: groupPic != null ? MemoryImage(base64Decode(groupPic)) : null,
          child: groupPic == null 
              ? const Icon(Icons.group, color: Colors.white) 
              : null,
        ),
      ),
      title: Text(groupName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4.0),
        child: Text(
          roomData['lastMessage'] ?? "",
          style: const TextStyle(color: Colors.grey, fontSize: 14),
          maxLines: 1, 
          overflow: TextOverflow.ellipsis
        ),
      ),
      trailing: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('chat_rooms').doc(roomId).collection('messages')
            .where('receiverId', isEqualTo: currentUserId)
            .where('isRead', isEqualTo: false).snapshots(),
        builder: (context, countSnap) {
          int count = countSnap.hasData ? countSnap.data!.docs.length : 0;
          return count > 0 ? Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: accentBlue, borderRadius: BorderRadius.circular(10)),
            child: Text(count.toString(), style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
          ) : const SizedBox.shrink();
        },
      ),
    );
  }
}

class ChatTile extends StatelessWidget {
  final String roomId;
  final String otherUserId;
  final String currentUserId;
  final Color accentBlue;
  final Color inputBackgroundColor;

  const ChatTile({
    super.key,
    required this.roomId,
    required this.otherUserId,
    required this.currentUserId,
    required this.accentBlue,
    required this.inputBackgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('users').doc(otherUserId).snapshots(),
      builder: (context, userSnap) {
        if (!userSnap.hasData) {
          return const ListTile(
            leading: CircleAvatar(backgroundColor: Colors.grey),
            title: Text("Loading...", style: TextStyle(color: Colors.grey)),
          ); 
        }

        var userData = userSnap.data!.data() as Map<String, dynamic>? ?? {};
        String name = userData['username'] ?? userData['name'] ?? "User";
        String? pic = userData['profilePic'];
        bool isOnline = userData['isOnline'] ?? false;
        Color borderColor = isOnline ? accentBlue : Colors.grey;

        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen(receiverUserID: otherUserId, receiverName: name))),
          leading: Container(
            padding: const EdgeInsets.all(2.5),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: borderColor, width: 2.5),
            ),
            child: CircleAvatar(
              radius: 30,
              backgroundColor: inputBackgroundColor,
              backgroundImage: pic != null ? MemoryImage(base64Decode(pic)) : null,
              child: pic == null ? Text(name[0].toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)) : null,
            ),
          ),
          title: Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4.0),
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('chat_rooms').doc(roomId).collection('messages')
                  .orderBy('timestamp', descending: true).limit(1).snapshots(),
              builder: (context, msgSnap) {
                if (!msgSnap.hasData || msgSnap.data!.docs.isEmpty) {
                  return const Text("No messages yet", style: TextStyle(color: Colors.grey, fontSize: 14));
                }
                var msgData = msgSnap.data!.docs.first.data() as Map<String, dynamic>;
                String text = msgData['message'] ?? "";
                String type = msgData['type'] ?? 'text';
                String senderId = msgData['senderId'] ?? "";
                String displayContent = type == 'image' ? '📷 Photo' : (type == 'audio' ? '🎤 Voice' : text);
                String prefix = (senderId == currentUserId) ? "You: " : "$name: ";
                return Text("$prefix$displayContent", style: const TextStyle(color: Colors.grey, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis);
              },
            ),
          ),
          trailing: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance.collection('chat_rooms').doc(roomId).collection('messages')
                .where('receiverId', isEqualTo: currentUserId).where('isRead', isEqualTo: false).snapshots(),
            builder: (context, countSnap) {
              int count = countSnap.hasData ? countSnap.data!.docs.length : 0;
              return count > 0 ? Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: accentBlue, borderRadius: BorderRadius.circular(10)),
                child: Text(count.toString(), style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
              ) : const SizedBox.shrink();
            },
          ),
        );
      },
    );
  }
}