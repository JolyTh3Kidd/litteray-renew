import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'home_page.dart'; // Go here on success
import 'login_page.dart'; // Reuse MyButton

class OtpVerifyPage extends StatefulWidget {
  final String verificationId;
  final String phoneNumber;

  const OtpVerifyPage({
    super.key, 
    required this.verificationId, 
    required this.phoneNumber
  });

  @override
  State<OtpVerifyPage> createState() => _OtpVerifyPageState();
}

class _OtpVerifyPageState extends State<OtpVerifyPage> {
  // We need 4 controllers for the 4 separate boxes
  final List<TextEditingController> _controllers = List.generate(4, (index) => TextEditingController());
  final Color _backgroundColor = const Color(0xFF0F1115);
  final Color _buttonColor = const Color(0xFF202631);

  void verifyCode() async {
    // Combine the 4 boxes into one string
    String smsCode = _controllers.map((c) => c.text).join();

    if (smsCode.length != 4 && smsCode.length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Enter full code")));
      return;
    }

    showDialog(context: context, builder: (context) => const Center(child: CircularProgressIndicator()));

    try {
      // Create the credential
      PhoneAuthCredential credential = PhoneAuthProvider.credential(
        verificationId: widget.verificationId,
        smsCode: smsCode,
      );

      // Link phone number to the current email user
      await FirebaseAuth.instance.currentUser?.linkWithCredential(credential);

      // Save phone number to Firestore
      String uid = FirebaseAuth.instance.currentUser!.uid;
      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'phone': widget.phoneNumber,
      });

      if (mounted) Navigator.pop(context); // Pop loading
      
      // GO TO HOME
      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => const HomePage()),
          (route) => false,
        );
      }

    } catch (e) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Invalid Code: $e")));
    }
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
              const Text(
                "Confirm your\nphone number",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              const Text(
                "Enter the confirmation code\nthat we have sent you",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey, fontSize: 16),
              ),

              const SizedBox(height: 50),

              // 4-Digit Input Row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: List.generate(4, (index) {
                  return Container(
                    width: 60,
                    height: 60,
                    decoration: const BoxDecoration(
                      border: Border(bottom: BorderSide(color: Colors.grey, width: 2)),
                    ),
                    child: TextField(
                      controller: _controllers[index],
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontSize: 24),
                      keyboardType: TextInputType.number,
                      maxLength: 1,
                      decoration: const InputDecoration(counterText: "", border: InputBorder.none),
                      onChanged: (value) {
                        // Auto-focus next field
                        if (value.isNotEmpty && index < 3) {
                          FocusScope.of(context).nextFocus();
                        }
                      },
                    ),
                  );
                }),
              ),

              const SizedBox(height: 50),

              MyButton(
                text: "Confirm",
                onTap: verifyCode,
                color: _buttonColor,
              ),
            ],
          ),
        ),
      ),
    );
  }
}