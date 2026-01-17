import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'home_page.dart';
import 'login_or_register.dart'; // IMPORT THIS

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          // If User is logged in
          if (snapshot.hasData) {
            return const HomePage();
          }
          // If User is NOT logged in
          else {
            return const LoginOrRegister(); // Show our custom UI
          }
        },
      ),
    );
  }
}