import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'edit_profile_page.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  void _updateProfilePic() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(source: ImageSource.gallery, imageQuality: 20);
    if (image != null) {
      final bytes = await image.readAsBytes();
      final base64String = base64Encode(bytes);
      await FirebaseFirestore.instance.collection('users').doc(FirebaseAuth.instance.currentUser!.uid).update({'profilePic': base64String});
    }
  }

  void _uploadPost(BuildContext context) async {
    final picker = ImagePicker();
    final image = await picker.pickImage(source: ImageSource.gallery, imageQuality: 40);
    if (image != null) {
      final bytes = await image.readAsBytes();
      final base64String = base64Encode(bytes);
      await FirebaseFirestore.instance.collection('posts').add({
        'userId': FirebaseAuth.instance.currentUser!.uid,
        'image': base64String,
        'timestamp': Timestamp.now(),
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser!.uid;

    return Scaffold(
      backgroundColor: const Color(0xFF101216), 
      appBar: AppBar(
        title: const Text("Profile"),
        centerTitle: true,
        backgroundColor: const Color(0xFF101216),
        elevation: 0,
        actions: [
          // SIGN OUT BUTTON IN CONTEXT MENU
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            onSelected: (value) {
              if (value == 'logout') {
                FirebaseAuth.instance.signOut();
              }
            },
            color: const Color(0xFF1D222C),
            itemBuilder: (BuildContext context) {
              return [
                const PopupMenuItem(
                  value: 'logout',
                  child: Row(
                    children: [
                      Icon(Icons.logout, color: Colors.redAccent, size: 20),
                      SizedBox(width: 10),
                      Text("Sign Out", style: TextStyle(color: Colors.white)),
                    ],
                  ),
                ),
              ];
            },
          ),
        ],
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          
          final data = snapshot.data!.data() as Map<String, dynamic>? ?? {};
          final profilePic = data['profilePic'];

          return Container(
            margin: const EdgeInsets.only(top: 10),
            decoration: const BoxDecoration(
              color: Color(0xFF161A22), // Fixed Color: Made it lighter so card is visible
              borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  // AVATAR
                  GestureDetector(
                    onTap: _updateProfilePic,
                    child: CircleAvatar(
                      radius: 50,
                      backgroundColor: const Color(0xFF375FFF),
                      backgroundImage: profilePic != null ? MemoryImage(base64Decode(profilePic)) : null,
                      child: profilePic == null ? Text(data['displayName']?[0].toUpperCase() ?? "U", style: const TextStyle(fontSize: 40, color: Colors.white)) : null,
                    ),
                  ),
                  const SizedBox(height: 15),
                  
                  // NAME
                  Text(data['displayName'] ?? "No Name", style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                  Text("@${data['username'] ?? 'user'}", style: const TextStyle(color: Colors.grey, fontSize: 14)),
                  
                  const SizedBox(height: 25),

                  // EDIT BUTTON
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const EditProfilePage())),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1D222C),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                        elevation: 0,
                      ),
                      child: const Text("Edit", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
                    ),
                  ),

                  const SizedBox(height: 30),

                  // INFO SECTION
                  const Align(alignment: Alignment.centerLeft, child: Text("Information", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold))),
                  const SizedBox(height: 15),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(color: const Color(0xFF1D222C), borderRadius: BorderRadius.circular(20)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _infoItem(data['phoneNumber'] ?? "No phone", "Phone number"),
                        const SizedBox(height: 20),
                        _infoItem(data['bio'] ?? "No bio", "Bio"),
                        const SizedBox(height: 20),
                        _infoItem(_formatDate(data['birthDate']), "Birthday date"),
                      ],
                    ),
                  ),

                  const SizedBox(height: 30),

                  // POSTS SECTION
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text("My Posts", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                      IconButton(onPressed: () => _uploadPost(context), icon: const Icon(Icons.add_circle_outline, color: Color(0xFF375FFF), size: 28))
                    ],
                  ),
                  const SizedBox(height: 15),
                  
                  StreamBuilder<QuerySnapshot>(
                    // REMOVED .orderBy('timestamp') to ensure visibility without custom index
                    stream: FirebaseFirestore.instance.collection('posts').where('userId', isEqualTo: uid).snapshots(),
                    builder: (context, postSnap) {
                      if (!postSnap.hasData) return const SizedBox();
                      final posts = postSnap.data!.docs;
                      
                      // Sort manually in client since we removed backend sort
                      posts.sort((a, b) => (b['timestamp'] as Timestamp).compareTo(a['timestamp'] as Timestamp));

                      return GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 15, mainAxisSpacing: 15, childAspectRatio: 1),
                        itemCount: posts.length,
                        itemBuilder: (context, index) {
                          return ClipRRect(
                            borderRadius: BorderRadius.circular(20),
                            child: Image.memory(base64Decode(posts[index]['image']), fit: BoxFit.cover),
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

  String _formatDate(dynamic date) {
    return date ?? "Jan 01, 2000"; 
  }
}