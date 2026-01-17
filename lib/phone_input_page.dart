import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'login_page.dart'; // reusing MyButton
import 'otp_verify_page.dart'; // WE WILL CREATE THIS NEXT

class PhoneInputPage extends StatefulWidget {
  const PhoneInputPage({super.key});

  @override
  State<PhoneInputPage> createState() => _PhoneInputPageState();
}

class _PhoneInputPageState extends State<PhoneInputPage> {
  final _phoneController = TextEditingController();
  final Color _backgroundColor = const Color(0xFF0F1115);
  final Color _inputFillColor = const Color(0xFF161A22);
  final Color _buttonColor = const Color(0xFF202631);

  void sendOTP() async {
    String phone = _phoneController.text.trim();
    
    // Basic validation
    if (phone.isEmpty) return;

    // Show loading
    showDialog(context: context, builder: (context) => const Center(child: CircularProgressIndicator()));

    await FirebaseAuth.instance.verifyPhoneNumber(
      phoneNumber: phone,
      verificationCompleted: (PhoneAuthCredential credential) async {
        // Android sometimes auto-verifies. If so, link and finish.
        await FirebaseAuth.instance.currentUser?.linkWithCredential(credential);
        Navigator.pop(context); // Pop loading
      },
      verificationFailed: (FirebaseAuthException e) {
        Navigator.pop(context); // Pop loading
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message ?? "Error")));
      },
      codeSent: (String verificationId, int? resendToken) {
        Navigator.pop(context); // Pop loading
        
        // GO TO NEXT SCREEN (Enter Code)
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => OtpVerifyPage(
              verificationId: verificationId, 
              phoneNumber: phone
            ),
          ),
        );
      },
      codeAutoRetrievalTimeout: (String verificationId) {},
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _backgroundColor,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 25.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.mail_outline, size: 100, color: Colors.white), // Envelope Icon
              const SizedBox(height: 20),
              
              const Text(
                "We will send a one time SMS message.\nIt might be in spam section.",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey, fontSize: 16),
              ),

              const SizedBox(height: 50),

              // Phone Input
              Container(
                decoration: BoxDecoration(
                  color: _inputFillColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 15),
                child: TextField(
                  controller: _phoneController,
                  style: const TextStyle(color: Colors.white),
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    hintText: "(+1) 555 123 4567",
                    hintStyle: TextStyle(color: Colors.grey),
                  ),
                ),
              ),

              const SizedBox(height: 50),

              MyButton(
                text: "Next",
                onTap: sendOTP,
                color: _buttonColor,
              ),
            ],
          ),
        ),
      ),
    );
  }
}