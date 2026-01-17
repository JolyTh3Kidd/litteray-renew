import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'login_page.dart'; // For MyTextField and MyButton widgets
import 'phone_input_page.dart'; // WE WILL CREATE THIS NEXT

class RegisterPage extends StatefulWidget {
  final VoidCallback onTap;
  const RegisterPage({super.key, required this.onTap});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();     // NEW
  final _usernameController = TextEditingController(); // NEW

  // Colors
  final Color _backgroundColor = const Color(0xFF0F1115);
  final Color _inputFillColor = const Color(0xFF161A22);
  final Color _buttonColor = const Color(0xFF202631);

  void signUserUp() async {
    // 1. Show Loading
    showDialog(
      context: context,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      // 2. Create User in Auth (Email/Pass)
      UserCredential userCredential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: _emailController.text,
        password: _passwordController.text,
      );

      // 3. Save User Details (Name, Username) to Firestore
      await FirebaseFirestore.instance.collection('users').doc(userCredential.user!.uid).set({
        'uid': userCredential.user!.uid,
        'email': _emailController.text,
        'name': _nameController.text,         // SAVING NAME
        'username': _usernameController.text, // SAVING USERNAME
        'phone': '', // Will be updated in next step
      });

      if (mounted) Navigator.pop(context); // Pop Loading Circle

      // 4. NAVIGATE TO PHONE VERIFICATION
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const PhoneInputPage()),
        );
      }

    } on FirebaseAuthException catch (e) {
      if (mounted) Navigator.pop(context);
      showDialog(
        context: context,
        builder: (context) => AlertDialog(title: Text(e.code)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _backgroundColor,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 25.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 50),
                  const Text(
                    "Let's create an account",
                    style: TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 50),

                  // Name Field
                  const Text("Full Name", style: TextStyle(color: Colors.grey)),
                  const SizedBox(height: 10),
                  MyTextField(controller: _nameController, hintText: "e.g. John Doe", obscureText: false, fillColor: _inputFillColor),
                  const SizedBox(height: 20),

                  // Username Field
                  const Text("Username", style: TextStyle(color: Colors.grey)),
                  const SizedBox(height: 10),
                  MyTextField(controller: _usernameController, hintText: "e.g. johndoe123", obscureText: false, fillColor: _inputFillColor),
                  const SizedBox(height: 20),

                  // Email Field
                  const Text("Email", style: TextStyle(color: Colors.grey)),
                  const SizedBox(height: 10),
                  MyTextField(controller: _emailController, hintText: "Enter your email", obscureText: false, fillColor: _inputFillColor),
                  const SizedBox(height: 20),

                  // Password Field
                  const Text("Password", style: TextStyle(color: Colors.grey)),
                  const SizedBox(height: 10),
                  MyTextField(controller: _passwordController, hintText: "Enter your password", obscureText: true, fillColor: _inputFillColor),
                  const SizedBox(height: 50),

                  // Sign Up Button
                  MyButton(text: "Next", onTap: signUserUp, color: _buttonColor),

                  const SizedBox(height: 20),

                  // Login Link
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text("Already have an account?", style: TextStyle(color: Colors.grey[600])),
                      const SizedBox(width: 4),
                      GestureDetector(
                        onTap: widget.onTap,
                        child: const Text("Login now", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}