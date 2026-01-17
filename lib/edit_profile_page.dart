import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class EditProfilePage extends StatefulWidget {
  const EditProfilePage({super.key});

  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  final _nameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _bioController = TextEditingController();
  final _phoneController = TextEditingController();
  final _birthController = TextEditingController();
  
  // Security Controllers
  final _emailController = TextEditingController();
  final _newPasswordController = TextEditingController();

  final _auth = FirebaseAuth.instance;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  void _loadData() async {
    final user = _auth.currentUser;
    if (user != null) {
      _emailController.text = user.email ?? '';
      
      final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        setState(() {
          _nameController.text = data['displayName'] ?? '';
          _usernameController.text = data['username'] ?? '';
          _bioController.text = data['bio'] ?? '';
          _phoneController.text = data['phoneNumber'] ?? '';
          _birthController.text = data['birthDate'] ?? '';
        });
      }
    }
  }

  // Helper to ask for current password before sensitive actions
  Future<String?> _askForPassword() async {
    String? password;
    await showDialog(
      context: context,
      builder: (context) {
        String input = "";
        return AlertDialog(
          backgroundColor: const Color(0xFF1D222C),
          title: const Text("Security Check", style: TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text("Please enter your current password to confirm this change.", style: TextStyle(color: Colors.grey)),
              const SizedBox(height: 15),
              TextField(
                obscureText: true,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: "Current Password",
                  hintStyle: const TextStyle(color: Colors.grey),
                  filled: true,
                  fillColor: const Color(0xFF101216),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onChanged: (val) => input = val,
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
            TextButton(
              onPressed: () {
                password = input;
                Navigator.pop(context);
              }, 
              child: const Text("Confirm", style: TextStyle(color: Color(0xFF375FFF)))
            ),
          ],
        );
      }
    );
    return password;
  }

  void _save() async {
    try {
      final user = _auth.currentUser!;
      
      // 1. Update Basic Info (Firestore)
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'displayName': _nameController.text,
        'username': _usernameController.text,
        'bio': _bioController.text,
        'phoneNumber': _phoneController.text,
        'birthDate': _birthController.text, // Added Birthday
      }, SetOptions(merge: true));

      // 2. Check for Security Changes (Auth)
      bool securityChanged = false;
      if (_emailController.text != user.email || _newPasswordController.text.isNotEmpty) {
        
        // Ask for password to re-authenticate
        final currentPass = await _askForPassword();
        if (currentPass == null || currentPass.isEmpty) {
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Update cancelled: Password required.")));
          return;
        }

        // Re-authenticate
        AuthCredential credential = EmailAuthProvider.credential(email: user.email!, password: currentPass);
        await user.reauthenticateWithCredential(credential);

        // Update Email
        if (_emailController.text != user.email) {
          await user.verifyBeforeUpdateEmail(_emailController.text);
          securityChanged = true;
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Verification email sent to new address.")));
        }

        // Update Password
        if (_newPasswordController.text.isNotEmpty) {
          await user.updatePassword(_newPasswordController.text);
          securityChanged = true;
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(securityChanged ? "Profile & Security updated!" : "Profile updated!")));
        Navigator.pop(context);
      }

    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: ${e.toString()}")));
    }
  }

  void _deleteAccount() async {
    final currentPass = await _askForPassword();
    if (currentPass == null || currentPass.isEmpty) return;

    try {
      final user = _auth.currentUser!;
      // Re-authenticate
      AuthCredential credential = EmailAuthProvider.credential(email: user.email!, password: currentPass);
      await user.reauthenticateWithCredential(credential);

      // Delete Firestore Data
      await FirebaseFirestore.instance.collection('users').doc(user.uid).delete();
      
      // Optional: Delete user's posts or other data here
      
      // Delete Auth Account
      await user.delete();

      if (mounted) {
        Navigator.popUntil(context, (route) => route.isFirst); // Go to splash/login
      }

    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error deleting account: $e")));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF101216),
      appBar: AppBar(
        title: const Text("Edit Profile"),
        backgroundColor: const Color(0xFF101216),
        actions: [
          TextButton(onPressed: _save, child: const Text("Save", style: TextStyle(color: Color(0xFF375FFF), fontWeight: FontWeight.bold)))
        ],
      ),
      body: Container(
        margin: const EdgeInsets.only(top: 10),
        decoration: const BoxDecoration(
          color: Color(0xFF161A22),
          borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        ),
        padding: const EdgeInsets.all(20.0),
        child: ListView(
          children: [
            const SizedBox(height: 10),
            _buildField("Display Name", _nameController),
            _buildField("Username", _usernameController),
            _buildField("Bio", _bioController, maxLines: 3),
            _buildField("Phone Number", _phoneController),
            
            // Birthday Field
            GestureDetector(
              onTap: () async {
                DateTime? picked = await showDatePicker(
                  context: context, 
                  initialDate: DateTime(2000), 
                  firstDate: DateTime(1900), 
                  lastDate: DateTime.now(),
                  builder: (context, child) {
                    return Theme(data: ThemeData.dark(), child: child!);
                  }
                );
                if (picked != null) {
                  setState(() => _birthController.text = "${picked.day}/${picked.month}/${picked.year}");
                }
              },
              child: AbsorbPointer(child: _buildField("Birth Date", _birthController, icon: Icons.calendar_today)),
            ),
            
            const SizedBox(height: 20),
            const Text("Security Settings", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 15),
            
            // Editable Email
            _buildField("Email", _emailController),
            
            // Editable Password
            _buildField("New Password (leave empty to keep)", _newPasswordController, isPassword: true),

            const SizedBox(height: 40),
            
            // Delete Account Button
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _deleteAccount,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent.withOpacity(0.1),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                  side: const BorderSide(color: Colors.redAccent)
                ),
                child: const Text("Delete Account", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  Widget _buildField(String label, TextEditingController controller, {int maxLines = 1, bool isPassword = false, IconData? icon}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
          const SizedBox(height: 8),
          TextField(
            controller: controller,
            maxLines: maxLines,
            obscureText: isPassword,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              filled: true,
              fillColor: const Color(0xFF1D222C),
              suffixIcon: icon != null ? Icon(icon, color: Colors.grey, size: 20) : null,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            ),
          ),
        ],
      ),
    );
  }
}