import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'main.dart'; // To navigate to ChatScreen

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // 1. COLORS FROM YOUR DESIGN
  final Color _backgroundColor = const Color(0xFF1B202D);
  final Color _searchBarColor = const Color(0xFF292F3F);
  final Color _accentBlue = const Color(0xFF375FFF);
  final Color _textSecondary = const Color(0xFF7A8194);

  @override
  void initState() {
    super.initState();
    _saveUserToFirestore();
  }

  void _saveUserToFirestore() async {
    User? currentUser = _auth.currentUser;
    if (currentUser != null) {
      await FirebaseFirestore.instance.collection('users').doc(currentUser.uid).set({
        'uid': currentUser.uid,
        'email': currentUser.email,
        // We will add 'avatarUrl' later for the images
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _backgroundColor, // Dark Background
      body: SafeArea(
        child: Column(
          children: [
            // PART 1: HEADER & SEARCH
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      height: 50,
                      decoration: BoxDecoration(
                        color: _searchBarColor,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const TextField(
                        style: TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          hintText: "Search",
                          hintStyle: TextStyle(color: Colors.grey),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(horizontal: 20),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Search Button (Square)
                  Container(
                    height: 50,
                    width: 50,
                    decoration: BoxDecoration(
                      color: _searchBarColor,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.search, color: Colors.white),
                  ),
                ],
              ),
            ),

            // PART 2: THE CHAT LIST
            Expanded(
              child: StreamBuilder(
                stream: FirebaseFirestore.instance.collection('users').snapshots(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

                  var users = snapshot.data!.docs;

                  return ListView.builder(
                    itemCount: users.length,
                    itemBuilder: (context, index) {
                      var userData = users[index].data();
                      
                      // Skip displaying ourselves
                      if (_auth.currentUser?.email == userData['email']) {
                        return const SizedBox.shrink(); 
                      }

                      return _buildChatTile(
                        name: userData['email'].split('@')[0], // Use part of email as name
                        message: "This is a placeholder message...", // Fake last message
                        time: "2 min",
                        unreadCount: 2, // Fake unread count for design
                        userData: userData,
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
      
      // PART 3: FLOATING ACTION BUTTON
      floatingActionButton: FloatingActionButton(
        backgroundColor: _searchBarColor,
        child: const Icon(Icons.add, color: Colors.white),
        onPressed: () {},
      ),

      // PART 4: BOTTOM NAVIGATION BAR
      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: _backgroundColor,
        selectedItemColor: Colors.white,
        unselectedItemColor: Colors.grey,
        showSelectedLabels: false,
        showUnselectedLabels: false,
        
        // ADD THIS LOGIC:
        onTap: (index) {
          // If the user clicks the 3rd icon (Person/Index 2)
          if (index == 2) {
            FirebaseAuth.instance.signOut();
          }
        },
        
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.tune), label: ''),
          BottomNavigationBarItem(icon: Icon(Icons.chat_bubble), label: ''),
          BottomNavigationBarItem(icon: Icon(Icons.logout), label: 'Logout'), // Changed icon to visualize it
        ],
      ),
    );
  }

  // CUSTOM TILE WIDGET TO MATCH FIGMA
  Widget _buildChatTile({
    required String name,
    required String message,
    required String time,
    required int unreadCount,
    required Map<String, dynamic> userData,
  }) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ChatScreen(
              receiverUserEmail: userData['email'],
              receiverUserID: userData['uid'],
            ),
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(
          children: [
            // 1. AVATAR
            CircleAvatar(
              radius: 28,
              backgroundColor: Colors.blueGrey,
              // If we had an image URL, we would use NetworkImage here
              // For now, we use the first letter of the name
              child: Text(
                name[0].toUpperCase(),
                style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(width: 16),
            
            // 2. NAME AND MESSAGE
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    message,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: _textSecondary,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
            
            // 3. TIME AND BADGE
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // Unread Badge (Blue Box)
                if (unreadCount > 0)
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: _accentBlue,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      unreadCount.toString(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                if (unreadCount == 0)
                  Text(time, style: TextStyle(color: _textSecondary, fontSize: 12)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}