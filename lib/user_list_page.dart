import 'dart:convert'; // <--- THIS WAS MISSING
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'main.dart'; // To access ChatScreen

class UserListPage extends StatefulWidget {
  const UserListPage({super.key});

  @override
  State<UserListPage> createState() => _UserListPageState();
}

class _UserListPageState extends State<UserListPage> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = "";

  final Color _bgColor = const Color(0xFF101216);
  final Color _cardColor = const Color(0xFF1D222C);
  final Color _inputBackgroundColor = const Color(0xFF161A22); 

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final String currentUserId = FirebaseAuth.instance.currentUser?.uid ?? "";

    return Scaffold(
      backgroundColor: _bgColor,
      appBar: AppBar(
        title: const Text("Messages", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: _bgColor,
        elevation: 0,
        automaticallyImplyLeading: false,
        // Removed actions (Sign out button)
      ),
      body: Column(
        children: [
          // --- SEARCH BAR ---
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 25.0),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    height: 55,
                    decoration: BoxDecoration(
                      color: _inputBackgroundColor,
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: TextField(
                      controller: _searchController,
                      onChanged: (value) {
                        setState(() {
                          _searchQuery = value.toLowerCase();
                        });
                      },
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        hintText: "Search",
                        hintStyle: TextStyle(color: Colors.grey, fontSize: 16),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  height: 55, width: 55,
                  decoration: BoxDecoration(
                    color: _inputBackgroundColor,
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: const Icon(Icons.search, color: Colors.white, size: 28),
                ),
              ],
            ),
          ),

          // --- USER LIST ---
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('users').snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Center(child: Text("Error loading users", style: TextStyle(color: Colors.white)));
                }

                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(color: Color(0xFF375FFF)));
                }

                final docs = snapshot.data?.docs ?? [];
                var users = docs.where((doc) => doc.id != currentUserId).toList();

                // SEARCH FILTER LOGIC
                if (_searchQuery.isNotEmpty) {
                  users = users.where((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    final email = (data['email'] ?? "").toString().toLowerCase();
                    final username = (data['username'] ?? "").toString().toLowerCase();
                    
                    return email.contains(_searchQuery) || username.contains(_searchQuery);
                  }).toList();
                }

                if (users.isEmpty) {
                  return Center(
                    child: Text(
                      _searchQuery.isEmpty ? "No users found" : "No results for '$_searchQuery'",
                      style: const TextStyle(color: Colors.grey),
                    ),
                  );
                }

                return ListView.builder(
                  itemCount: users.length,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemBuilder: (context, index) {
                    final doc = users[index];
                    final data = doc.data() as Map<String, dynamic>? ?? {};
                    
                    final String displayName = data['username'] ?? data['email'] ?? "Unknown";
                    final String? profilePic = data['profilePic'];

                    return GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => ChatScreen(
                              receiverUserID: doc.id,
                              receiverName: displayName,
                            ),
                          ),
                        );
                      },
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: _cardColor,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          children: [
                            // Avatar
                            Container(
                              padding: const EdgeInsets.all(2),
                              decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF161A22)),
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
                            // Name & Hint
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    displayName,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  const Text(
                                    "Tap to start chatting",
                                    style: TextStyle(color: Colors.grey, fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(Icons.chevron_right, color: Colors.grey),
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