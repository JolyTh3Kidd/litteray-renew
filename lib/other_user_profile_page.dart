import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart'; // IMPORT THIS

class OtherUserProfilePage extends StatelessWidget {
  final String userId;
  final String userName; 

  const OtherUserProfilePage({super.key, required this.userId, required this.userName});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF101216), 
      appBar: AppBar(
        title: const Text("Profile"),
        centerTitle: true,
        backgroundColor: const Color(0xFF101216),
        elevation: 0,
        actions: [IconButton(onPressed: () {}, icon: const Icon(Icons.more_vert))],
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection('users').doc(userId).snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          
          final data = snapshot.data!.data() as Map<String, dynamic>? ?? {};
          final profilePic = data['profilePic'];

          return Container(
            margin: const EdgeInsets.only(top: 10),
            decoration: const BoxDecoration(
              color: Color(0xFF161A22), 
              borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  // AVATAR
                  GestureDetector(
                     onTap: () {
                        if (profilePic != null) {
                           showDialog(context: context, builder: (_) => Dialog(child: Image.memory(base64Decode(profilePic))));
                        }
                     },
                    child: CircleAvatar(
                      radius: 50,
                      backgroundColor: const Color(0xFF375FFF),
                      backgroundImage: profilePic != null ? MemoryImage(base64Decode(profilePic)) : null,
                      child: profilePic == null ? Text(userName[0].toUpperCase(), style: const TextStyle(fontSize: 40, color: Colors.white)) : null,
                    ),
                  ),
                  const SizedBox(height: 15),
                  Text(data['displayName'] ?? userName, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                  Text("@${data['username'] ?? 'user'}", style: const TextStyle(color: Colors.grey, fontSize: 14)),
                  
                  const SizedBox(height: 25),

                  // BUTTONS ROW
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          // --- FIXED CALL BUTTON LOGIC ---
                          onPressed: () async {
                            final String? phone = data['phoneNumber'];
                            if (phone != null && phone.isNotEmpty && phone != "Hidden") {
                              final Uri launchUri = Uri(scheme: 'tel', path: phone);
                              if (await canLaunchUrl(launchUri)) {
                                await launchUrl(launchUri);
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Could not launch dialer")));
                              }
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Phone number not available")));
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF375FFF),
                            padding: const EdgeInsets.symmetric(vertical: 15),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                          ),
                          child: const Text("Call", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        ),
                      ),
                      const SizedBox(width: 15),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () => Navigator.pop(context), 
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1D222C), 
                            padding: const EdgeInsets.symmetric(vertical: 15),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                          ),
                          child: const Text("Message", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        ),
                      ),
                      const SizedBox(width: 15),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: const Color(0xFF1D222C), borderRadius: BorderRadius.circular(15)),
                        child: const Icon(Icons.person_add_outlined, color: Colors.white),
                      )
                    ],
                  ),

                  const SizedBox(height: 30),

                  // INFO
                  const Align(alignment: Alignment.centerLeft, child: Text("Information", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold))),
                  const SizedBox(height: 15),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(color: const Color(0xFF1D222C), borderRadius: BorderRadius.circular(20)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _infoItem(data['phoneNumber'] ?? "Hidden", "Phone number"),
                        const SizedBox(height: 20),
                        _infoItem(data['bio'] ?? "No bio", "Bio"),
                        const SizedBox(height: 20),
                        _infoItem(data['birthDate'] ?? "Unknown", "Birthday date"),
                      ],
                    ),
                  ),

                  const SizedBox(height: 30),

                  // POSTS
                  const Align(alignment: Alignment.centerLeft, child: Text("Posts", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold))),
                  const SizedBox(height: 15),
                  StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance.collection('posts').where('userId', isEqualTo: userId).snapshots(),
                    builder: (context, postSnap) {
                      if (!postSnap.hasData) return const SizedBox();
                      final posts = postSnap.data!.docs;
                      
                      // Manual Sort
                      posts.sort((a, b) => (b['timestamp'] as Timestamp).compareTo(a['timestamp'] as Timestamp));

                      return GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 15, mainAxisSpacing: 15, childAspectRatio: 1),
                        itemCount: posts.length,
                        itemBuilder: (context, index) {
                          return GestureDetector(
                            onTap: () {
                              showDialog(context: context, builder: (_) => Dialog(
                                backgroundColor: Colors.transparent,
                                child: ClipRRect(borderRadius: BorderRadius.circular(20), child: Image.memory(base64Decode(posts[index]['image']))),
                              ));
                            },
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(20),
                              child: Image.memory(base64Decode(posts[index]['image']), fit: BoxFit.cover),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _infoItem(String value, String label) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15)),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
      ],
    );
  }
}