import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_options.dart';
import 'auth_gate.dart';
import 'home_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const MessengerApp());
}

class MessengerApp extends StatelessWidget {
  const MessengerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      // We start at the AuthGate to check if user is logged in
      home: const AuthGate(),
    );
  }
}

// --- THIS IS THE PART YOU WERE MISSING ---
class ChatScreen extends StatefulWidget {
  // We accept the person we want to talk to
  final String receiverUserEmail;
  final String receiverUserID;

  const ChatScreen({
    super.key,
    required this.receiverUserEmail,
    required this.receiverUserID,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}
// -----------------------------------------

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _textController = TextEditingController();
  final FirebaseAuth _auth = FirebaseAuth.instance;

  void _sendMessage() async {
    if (_textController.text.isNotEmpty) {
      String currentUserURI = _auth.currentUser!.uid;
      String currentUserEmail = _auth.currentUser!.email!;
      Timestamp timestamp = Timestamp.now();

      // Construct a unique Chat Room ID (sorted to ensure uniqueness)
      List<String> ids = [currentUserURI, widget.receiverUserID];
      ids.sort(); // This ensures "A_B" and "B_A" are always "A_B"
      String chatRoomId = ids.join('_');

      // Add to the specific room collection
      await FirebaseFirestore.instance
          .collection('chat_rooms')
          .doc(chatRoomId)
          .collection('messages')
          .add({
        'senderId': currentUserURI,
        'senderEmail': currentUserEmail,
        'receiverId': widget.receiverUserID,
        'message': _textController.text,
        'timestamp': timestamp,
      });

      _textController.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Re-calculate the Chat Room ID to listen to the right stream
    String currentUserURI = _auth.currentUser!.uid;
    List<String> ids = [currentUserURI, widget.receiverUserID];
    ids.sort();
    String chatRoomId = ids.join('_');

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.receiverUserEmail), // Show THEIR name
        backgroundColor: Colors.blueAccent,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder(
              // LISTEN TO THE SPECIFIC ROOM
              stream: FirebaseFirestore.instance
                  .collection('chat_rooms')
                  .doc(chatRoomId)
                  .collection('messages')
                  .orderBy('timestamp', descending: false)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) return const Text("Error");
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                return ListView(
                  children: snapshot.data!.docs.map((doc) {
                    var data = doc.data();
                    bool isMe = data['senderId'] == _auth.currentUser!.uid;

                    return Align(
                      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 5, horizontal: 10),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isMe ? Colors.blue[100] : Colors.grey[300],
                          borderRadius: BorderRadius.circular(15),
                        ),
                        child: Text(
                          data['message'],
                          style: const TextStyle(fontSize: 16),
                        ),
                      ),
                    );
                  }).toList(),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _textController,
                    decoration: InputDecoration(
                      hintText: "Type a message...",
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(25)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.send, color: Colors.blue),
                  onPressed: _sendMessage,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}