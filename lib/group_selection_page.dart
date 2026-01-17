import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'main.dart'; // To access ChatScreen

class GroupSelectionPage extends StatefulWidget {
  const GroupSelectionPage({super.key});

  @override
  State<GroupSelectionPage> createState() => _GroupSelectionPageState();
}

class _GroupSelectionPageState extends State<GroupSelectionPage> {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _groupNameController = TextEditingController();
  String _searchQuery = "";
  
  // Stores selected user IDs
  final Set<String> _selectedUserIds = {};

  final Color _bgColor = const Color(0xFF101216);
  final Color _cardColor = const Color(0xFF1D222C);
  final Color _inputBackgroundColor = const Color(0xFF161A22);
  final Color _accentBlue = const Color(0xFF375FFF);

  void _createGroup() async {
    if (_selectedUserIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Select at least one user")));
      return;
    }

    // Ask for Group Name
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _cardColor,
        title: const Text("Enter Group Name", style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: _groupNameController,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: "Group Name...",
            hintStyle: const TextStyle(color: Colors.grey),
            filled: true,
            fillColor: _inputBackgroundColor,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          TextButton(
            onPressed: () async {
              if (_groupNameController.text.trim().isNotEmpty) {
                Navigator.pop(context);
                await _finalizeGroupCreation(_groupNameController.text.trim());
              }
            },
            child: Text("Create", style: TextStyle(color: _accentBlue, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _finalizeGroupCreation(String groupName) async {
    final currentUid = FirebaseAuth.instance.currentUser!.uid;
    final List<String> participants = [currentUid, ..._selectedUserIds];
    
    // Create Chat Room
    DocumentReference roomRef = await FirebaseFirestore.instance.collection('chat_rooms').add({
      'isGroup': true,
      'groupName': groupName,
      'participants': participants,
      'groupAdmin': currentUid,
      'lastMessage': "Group created",
      'lastMessageTimestamp': Timestamp.now(),
      'typingStatus': {},
      'mutedFor': {},
    });

    if (mounted) {
      // Navigate to Chat Screen with the new Room ID
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => ChatScreen(
            receiverUserID: "", // Not used for groups
            receiverName: groupName,
            isGroup: true,
            roomId: roomRef.id,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final String currentUserId = FirebaseAuth.instance.currentUser?.uid ?? "";

    return Scaffold(
      backgroundColor: _bgColor,
      appBar: AppBar(
        title: const Text("New Group", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: _bgColor,
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
        actions: [
          // Create Button
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: TextButton(
              onPressed: _createGroup,
              child: Text(
                "Create (${_selectedUserIds.length})",
                style: TextStyle(color: _selectedUserIds.isNotEmpty ? _accentBlue : Colors.grey, fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
          )
        ],
      ),
      body: Column(
        children: [
          // Search Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 15.0),
            child: Container(
              height: 50,
              decoration: BoxDecoration(color: _inputBackgroundColor, borderRadius: BorderRadius.circular(15)),
              child: TextField(
                controller: _searchController,
                onChanged: (value) => setState(() => _searchQuery = value.toLowerCase()),
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  hintText: "Search users",
                  hintStyle: TextStyle(color: Colors.grey),
                  border: InputBorder.none,
                  prefixIcon: Icon(Icons.search, color: Colors.grey),
                  contentPadding: EdgeInsets.symmetric(vertical: 15),
                ),
              ),
            ),
          ),

          // User List
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('users').snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

                final docs = snapshot.data!.docs;
                var users = docs.where((doc) => doc.id != currentUserId).toList();

                if (_searchQuery.isNotEmpty) {
                  users = users.where((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    final name = (data['username'] ?? data['displayName'] ?? "").toString().toLowerCase();
                    return name.contains(_searchQuery);
                  }).toList();
                }

                return ListView.builder(
                  itemCount: users.length,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemBuilder: (context, index) {
                    final doc = users[index];
                    final data = doc.data() as Map<String, dynamic>;
                    final String displayName = data['username'] ?? data['displayName'] ?? "Unknown";
                    final String? profilePic = data['profilePic'];
                    final bool isSelected = _selectedUserIds.contains(doc.id);

                    return GestureDetector(
                      onTap: () {
                        setState(() {
                          if (isSelected) {
                            _selectedUserIds.remove(doc.id);
                          } else {
                            _selectedUserIds.add(doc.id);
                          }
                        });
                      },
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          // Selected = Blue, Unselected = Card Color
                          color: isSelected ? _accentBlue.withOpacity(0.2) : _cardColor,
                          borderRadius: BorderRadius.circular(20),
                          border: isSelected ? Border.all(color: _accentBlue) : null,
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(2),
                              child: CircleAvatar(
                                radius: 25,
                                backgroundColor: Colors.grey.shade800,
                                backgroundImage: profilePic != null ? MemoryImage(base64Decode(profilePic)) : null,
                                child: profilePic == null 
                                    ? Text(displayName[0].toUpperCase(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)) 
                                    : null,
                              ),
                            ),
                            const SizedBox(width: 15),
                            Expanded(
                              child: Text(
                                displayName,
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                            ),
                            Icon(
                              isSelected ? Icons.check_circle : Icons.circle_outlined,
                              color: isSelected ? _accentBlue : Colors.grey,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}