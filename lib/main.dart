import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';
import 'package:audio_waveforms/audio_waveforms.dart';
import 'package:image_picker/image_picker.dart';
import 'package:record/record.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:url_launcher/url_launcher.dart'; 
import 'firebase_options.dart';
import 'auth_gate.dart';
import 'other_user_profile_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const MessengerApp());
}

class MessengerApp extends StatelessWidget {
  const MessengerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFF101216),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF161A22),
          iconTheme: IconThemeData(color: Colors.white),
        ),
      ),
      home: const AuthGate(),
    );
  }
}

class ChatScreen extends StatefulWidget {
  final String receiverUserID;
  final String receiverName;
  const ChatScreen({super.key, required this.receiverUserID, required this.receiverName});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _msgController = TextEditingController();
  final AudioRecorder _recorder = AudioRecorder();
  final ScrollController _scrollController = ScrollController();
  final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();

  Timer? _typingTimer;
  bool _isRec = false;
  // --- NEW: Mute State ---
  bool _isMuted = false;

  String? _editingMsgId;
  String? _replyingToText;
  String? _replyingToSenderId;
  String? _replyingToMessageId; 

  int _limit = 30;
  final int _limitIncrement = 20;
  
  StreamSubscription? _msgSubscription;
  // --- NEW: Room Subscription for Mute Status ---
  StreamSubscription? _roomSubscription;
  
  final Map<String, GlobalKey> _messageKeys = {};

  @override
  void initState() {
    super.initState();
    _markAsRead();
    _initNotifications();
    _listenForNewMessages();
    _listenForRoomChanges(); // Start listening for mute status
    
    _scrollController.addListener(() {
      if (_scrollController.hasClients && 
          _scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
         setState(() => _limit += _limitIncrement);
      }
    });
  }

  void _initNotifications() async {
    const AndroidInitializationSettings androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher'); 
    const InitializationSettings settings = InitializationSettings(android: androidSettings);
    await _notificationsPlugin.initialize(settings);
    _notificationsPlugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.requestNotificationsPermission();
  }

  // --- NEW: Listen to Room Doc for Mute Status ---
  void _listenForRoomChanges() {
    _roomSubscription = FirebaseFirestore.instance.collection('chat_rooms').doc(_getRoomId()).snapshots().listen((snapshot) {
      if (snapshot.exists) {
        final data = snapshot.data() as Map<String, dynamic>;
        final mutedMap = data['mutedFor'] as Map<String, dynamic>?;
        if (mounted) {
          setState(() {
            _isMuted = mutedMap?[FirebaseAuth.instance.currentUser!.uid] ?? false;
          });
        }
      }
    });
  }

  void _listenForNewMessages() {
    _msgSubscription = FirebaseFirestore.instance
        .collection('chat_rooms').doc(_getRoomId()).collection('messages')
        .orderBy('timestamp', descending: true).limit(1).snapshots().listen((snapshot) {
      if (snapshot.docs.isNotEmpty) {
        for (var change in snapshot.docChanges) {
          if (change.type == DocumentChangeType.added) {
            var data = change.doc.data() as Map<String, dynamic>;
            if (data['senderId'] == widget.receiverUserID) {
               // --- CHANGED: Check mute status before notifying ---
               if (!_isMuted) {
                 _showNotification(data['message']);
               }
            }
          }
        }
      }
    });
  }

  void _showNotification(String message) async {
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'chat_channel_id', 'Messages', importance: Importance.max, priority: Priority.high, playSound: true,
    );
    const NotificationDetails details = NotificationDetails(android: androidDetails);
    
    String content = message;
    if (content.length > 100 && _isBase64(content)) content = "📷 Photo";
    
    await _notificationsPlugin.show(0, widget.receiverName, content, details);
  }

  bool _isBase64(String str) {
    return str.length > 100 && !str.contains(" "); 
  }

  void _makePhoneCall() async {
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(widget.receiverUserID).get();
      final data = doc.data();
      final phone = data?['phoneNumber'];
      
      if (phone != null && phone.isNotEmpty && phone != 'Hidden') {
        final Uri launchUri = Uri(scheme: 'tel', path: phone);
        if (await canLaunchUrl(launchUri)) {
          await launchUrl(launchUri);
        } else {
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Could not launch dialer")));
        }
      } else {
         if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("User has no phone number saved")));
      }
    } catch (e) {
       if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Error connecting call")));
    }
  }

  void _makeVideoCall() {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Video calling requires external API integration.")));
  }

  // --- NEW: TOGGLE MUTE ---
  void _toggleMute() async {
    final roomId = _getRoomId();
    final uid = FirebaseAuth.instance.currentUser!.uid;
    // We toggle the current local state immediately for UI responsiveness
    // logic will be confirmed by Firestore listener
    await FirebaseFirestore.instance.collection('chat_rooms').doc(roomId).set({
      'mutedFor': {uid: !_isMuted}
    }, SetOptions(merge: true));
  }

  // --- NEW: DELETE CHAT ---
  void _deleteChat() async {
    // Show Confirmation Dialog
    bool confirm = await showDialog(
      context: context, 
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1D222C),
        title: const Text("Delete Chat?", style: TextStyle(color: Colors.white)),
        content: const Text("This will permanently delete all messages for both users.", style: TextStyle(color: Colors.grey)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancel")),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text("Delete", style: TextStyle(color: Colors.redAccent))),
        ],
      )
    ) ?? false;

    if (!confirm) return;

    final roomId = _getRoomId();
    
    // 1. Delete Messages Subcollection
    final msgs = await FirebaseFirestore.instance.collection('chat_rooms').doc(roomId).collection('messages').get();
    final batch = FirebaseFirestore.instance.batch();
    
    for (var doc in msgs.docs) {
      batch.delete(doc.reference);
    }
    
    // 2. Delete Room Document
    batch.delete(FirebaseFirestore.instance.collection('chat_rooms').doc(roomId));
    
    await batch.commit();

    if (mounted) Navigator.pop(context); // Exit chat screen
  }

  @override
  void dispose() {
    _msgSubscription?.cancel();
    _roomSubscription?.cancel(); // Cancel room listener
    _msgController.dispose();
    _recorder.dispose();
    _scrollController.dispose();
    _typingTimer?.cancel();
    super.dispose();
  }

  String _getRoomId() {
    List<String> ids = [FirebaseAuth.instance.currentUser!.uid, widget.receiverUserID];
    ids.sort(); return ids.join('_');
  }

  Future<void> _markAsRead() async {
    final roomId = _getRoomId();
    final currentUserId = FirebaseAuth.instance.currentUser!.uid;
    final querySnapshot = await FirebaseFirestore.instance.collection('chat_rooms').doc(roomId).collection('messages')
        .where('receiverId', isEqualTo: currentUserId).where('isRead', isEqualTo: false).get();

    if (querySnapshot.docs.isNotEmpty) {
      WriteBatch batch = FirebaseFirestore.instance.batch();
      for (var doc in querySnapshot.docs) batch.update(doc.reference, {'isRead': true});
      await batch.commit();
    }
  }

  void _updateTyping(bool typing) {
    FirebaseFirestore.instance.collection('chat_rooms').doc(_getRoomId()).set({
      'typingStatus': {FirebaseAuth.instance.currentUser!.uid: typing},
    }, SetOptions(merge: true));
  }

  void _onTextChanged(String val) {
    if (_typingTimer?.isActive ?? false) return;
    _updateTyping(true);
    _typingTimer = Timer(const Duration(seconds: 2), () {
      _updateTyping(false);
      _typingTimer = null;
    });
  }

  void _pinMessage(String msg, String msgId) {
    String content = _isBase64(msg) ? "📷 Photo" : msg;
    FirebaseFirestore.instance.collection('chat_rooms').doc(_getRoomId()).set({
      'pinnedMessage': content,
      'pinnedMessageId': msgId,
    }, SetOptions(merge: true));
  }

  void _scrollToMessage(String msgId) {
    final key = _messageKeys[msgId];
    if (key != null && key.currentContext != null) {
      Scrollable.ensureVisible(key.currentContext!, duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Message is older or not loaded."), duration: Duration(seconds: 1)));
    }
  }

  void _send({String type = 'text', String? content}) async {
    String msg = content ?? _msgController.text.trim();
    if (msg.isEmpty) return;

    final roomId = _getRoomId();
    final senderId = FirebaseAuth.instance.currentUser!.uid;
    final timestamp = Timestamp.now();

    String? currentReplyText = _replyingToText;
    String? currentReplySenderId = _replyingToSenderId;
    String? currentReplyMessageId = _replyingToMessageId;

    _msgController.clear();
    setState(() {
      _replyingToText = null;
      _replyingToSenderId = null;
      _replyingToMessageId = null;
    });

    if (_editingMsgId != null) {
      await FirebaseFirestore.instance.collection('chat_rooms').doc(roomId).collection('messages').doc(_editingMsgId).update({'message': msg, 'isEdited': true});
      setState(() => _editingMsgId = null);
    } else {
      final messageData = {
        'senderId': senderId, 'receiverId': widget.receiverUserID, 'message': msg, 'type': type, 'timestamp': timestamp, 'isRead': false, 
        'replyToText': currentReplyText, 'replyToUserId': currentReplySenderId, 'replyToMessageId': currentReplyMessageId
      };

      WriteBatch batch = FirebaseFirestore.instance.batch();
      DocumentReference msgRef = FirebaseFirestore.instance.collection('chat_rooms').doc(roomId).collection('messages').doc();
      DocumentReference roomRef = FirebaseFirestore.instance.collection('chat_rooms').doc(roomId);

      batch.set(msgRef, messageData);
      String preview = type == 'image' ? '📷 Photo' : (type == 'audio' ? '🎤 Voice' : msg);
      batch.set(roomRef, {
        'participants': [senderId, widget.receiverUserID], 'lastMessage': preview, 'lastMessageTimestamp': timestamp,
      }, SetOptions(merge: true));

      await batch.commit();
    }
    _updateTyping(false);
  }

  // --- UI ---

  void _showOptions(Map<String, dynamic> data, String msgId, bool isMe) {
    bool isPhoto = data['type'] == 'image';
    showModalBottomSheet(
      context: context, backgroundColor: const Color(0xFF161A22),
      builder: (context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Wrap(
          children: [
            _menuItem(Icons.reply, "Reply", () { 
              Navigator.pop(context); 
              setState(() {
                _replyingToText = isPhoto ? "📷 Photo" : data['message'];
                _replyingToSenderId = data['senderId'];
                _replyingToMessageId = msgId;
              }); 
            }),
            if (!isPhoto) _menuItem(Icons.copy, "Copy", () { Clipboard.setData(ClipboardData(text: data['message'])); Navigator.pop(context); }),
            _menuItem(Icons.push_pin, "Pin", () { _pinMessage(data['message'], msgId); Navigator.pop(context); }),
            if (isMe && data['type'] == 'text') _menuItem(Icons.edit, "Edit", () { Navigator.pop(context); _msgController.text = data['message']; setState(() => _editingMsgId = msgId); }),
            _menuItem(Icons.delete_outline, "Delete", () { FirebaseFirestore.instance.collection('chat_rooms').doc(_getRoomId()).collection('messages').doc(msgId).delete(); Navigator.pop(context); }, destructive: true),
          ],
        ),
      ),
    );
  }

  Widget _menuItem(IconData icon, String title, VoidCallback onTap, {bool destructive = false}) {
    return ListTile(leading: Icon(icon, color: destructive ? Colors.redAccent : Colors.white), title: Text(title, style: TextStyle(color: destructive ? Colors.redAccent : Colors.white)), onTap: onTap);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 60,
        backgroundColor: const Color(0xFF161A22),
        elevation: 0,
        automaticallyImplyLeading: true,
        title: GestureDetector(
          onTap: () {
            Navigator.push(context, MaterialPageRoute(builder: (context) => OtherUserProfilePage(userId: widget.receiverUserID, userName: widget.receiverName)));
          },
          child: Row(
            children: [
              StreamBuilder<DocumentSnapshot>(
                stream: FirebaseFirestore.instance.collection('users').doc(widget.receiverUserID).snapshots(),
                builder: (context, snap) {
                  var data = snap.data?.data() as Map<String, dynamic>?;
                  String? pic = data?['profilePic'];
                  return Container(
                    padding: const EdgeInsets.all(1.5),
                    decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: const Color(0xFF2B303B))),
                    child: CircleAvatar(
                      radius: 20,
                      backgroundColor: Colors.grey.shade800,
                      backgroundImage: pic != null ? MemoryImage(base64Decode(pic)) : null,
                      child: pic == null ? Text(widget.receiverName[0].toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 16)) : null,
                    ),
                  );
                },
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.receiverName, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 2),
                    StreamBuilder<DocumentSnapshot>(
                      stream: FirebaseFirestore.instance.collection('users').doc(widget.receiverUserID).snapshots(),
                      builder: (context, userSnap) {
                        bool isOnline = false;
                        if (userSnap.hasData && userSnap.data != null && userSnap.data!.exists) {
                           final userData = userSnap.data!.data() as Map<String, dynamic>;
                           isOnline = userData['isOnline'] ?? false;
                        }
                        return StreamBuilder<DocumentSnapshot>(
                          stream: FirebaseFirestore.instance.collection('chat_rooms').doc(_getRoomId()).snapshots(),
                          builder: (context, roomSnap) {
                            bool typing = false;
                            if (roomSnap.hasData && roomSnap.data!.exists) {
                              var data = roomSnap.data!.data() as Map<String, dynamic>;
                              typing = data['typingStatus']?[widget.receiverUserID] ?? false;
                            }
                            String statusText = typing ? "typing..." : (isOnline ? "Online" : "Offline");
                            Color statusColor = typing ? const Color(0xFF375FFF) : (isOnline ? const Color(0xFF00C853) : Colors.grey);
                            return Row(children: [
                                if (isOnline || typing) Container(width: 7, height: 7, decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle)),
                                if (isOnline || typing) const SizedBox(width: 5),
                                Text(statusText, style: TextStyle(color: statusColor == const Color(0xFF00C853) ? Colors.white70 : statusColor, fontSize: 12)),
                            ]);
                          },
                        );
                      },
                    )
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          IconButton(icon: const Icon(Icons.call), onPressed: _makePhoneCall),
          IconButton(icon: const Icon(Icons.videocam), onPressed: _makeVideoCall),
          
          // --- UPDATED CONTEXT MENU ---
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            color: const Color(0xFF1D222C),
            onSelected: (value) {
              if (value == 'mute') _toggleMute();
              if (value == 'delete') _deleteChat();
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'mute',
                child: Row(
                  children: [
                    Icon(_isMuted ? Icons.notifications_off : Icons.notifications, color: Colors.white, size: 20),
                    const SizedBox(width: 10),
                    Text(_isMuted ? "Unmute Notifications" : "Mute Notifications", style: const TextStyle(color: Colors.white)),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    Icon(Icons.delete, color: Colors.redAccent, size: 20),
                    SizedBox(width: 10),
                    Text("Delete Chat", style: TextStyle(color: Colors.redAccent)),
                  ],
                ),
              ),
            ],
          ),
        ],
        bottom: PreferredSize(preferredSize: const Size.fromHeight(1.0), child: Container(color: Colors.white10, height: 1.0)),
      ),
      body: Column(
        children: [
          _buildPinnedBar(),
          Expanded(child: _buildList()),
          if (_replyingToText != null) _buildReplyPreview(),
          _buildInput(),
        ],
      ),
    );
  }

  Widget _buildPinnedBar() {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('chat_rooms').doc(_getRoomId()).snapshots(),
      builder: (context, snap) {
        if (snap.hasData && snap.data!.exists) {
          var data = snap.data!.data() as Map<String, dynamic>?;
          String pinnedMsg = data?['pinnedMessage'] ?? "";
          String pinnedId = data?['pinnedMessageId'] ?? "";
          
          if (pinnedMsg.isNotEmpty) {
            return GestureDetector(
              onTap: () => _scrollToMessage(pinnedId),
              child: Container(
                width: double.infinity, color: const Color(0xFF1D222C),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    const Icon(Icons.push_pin, size: 14, color: Color(0xFF7B51FF)),
                    const SizedBox(width: 8),
                    Expanded(child: Text(pinnedMsg, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Colors.white70))),
                    GestureDetector(onTap: () => _pinMessage("", ""), child: const Icon(Icons.close, size: 16, color: Colors.grey)),
                  ],
                ),
              ),
            );
          }
        }
        return const SizedBox.shrink();
      },
    );
  }

  Widget _buildList() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('chat_rooms').doc(_getRoomId()).collection('messages')
          .orderBy('timestamp', descending: true).limit(_limit).snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator(color: Color(0xFF375FFF)));
        final docs = snapshot.data!.docs;
        
        if (docs.isNotEmpty) {
           var latest = docs.first.data() as Map<String, dynamic>;
           if (latest['receiverId'] == FirebaseAuth.instance.currentUser!.uid && latest['isRead'] == false) _markAsRead();
        }

        return ListView.builder(
          controller: _scrollController,
          reverse: true,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          itemCount: docs.length,
          cacheExtent: 1000, 
          itemBuilder: (context, index) {
            var doc = docs[index];
            if (!_messageKeys.containsKey(doc.id)) _messageKeys[doc.id] = GlobalKey();
            
            return MessageBubble(
              key: _messageKeys[doc.id],
              data: doc.data() as Map<String, dynamic>,
              id: doc.id,
              isMe: doc['senderId'] == FirebaseAuth.instance.currentUser!.uid,
              onLongPress: _showOptions,
              onReplyTap: _scrollToMessage,
              onImageTap: (img) => Navigator.push(context, MaterialPageRoute(builder: (_) => FullScreenImage(base64Image: img))),
            );
          },
        );
      },
    );
  }

  Widget _buildReplyPreview() {
    return Container(
      padding: const EdgeInsets.all(10), color: const Color(0xFF1D222C),
      child: Row(
        children: [
          const Icon(Icons.reply, color: Colors.grey, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("Replying to message", style: TextStyle(color: Color(0xFF7B51FF), fontSize: 12, fontWeight: FontWeight.bold)),
                Text(_replyingToText ?? "", maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70)),
              ],
            ),
          ),
          IconButton(icon: const Icon(Icons.close, color: Colors.grey), onPressed: () => setState(() => _replyingToText = null))
        ],
      ),
    );
  }

  Widget _buildInput() {
    bool isEditing = _editingMsgId != null;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      color: const Color(0xFF101216),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(color: const Color(0xFF161A22), borderRadius: BorderRadius.circular(20)),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.attach_file, color: Colors.grey),
                    onPressed: () async {
                      final p = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 20);
                      if (p != null) _send(type: 'image', content: base64Encode(await p.readAsBytes()));
                    },
                  ),
                  Expanded(
                    child: TextField(
                        controller: _msgController,
                        onChanged: _onTextChanged,
                        style: const TextStyle(color: Colors.white),
                        maxLines: null, 
                        decoration: InputDecoration(
                          hintText: isEditing ? "Edit message..." : "Type something...",
                          hintStyle: const TextStyle(color: Colors.grey),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
                        )),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onLongPressStart: (_) async {
              if (isEditing) return;
              if (await _recorder.hasPermission()) {
                final dir = await getTemporaryDirectory();
                await _recorder.start(const RecordConfig(), path: '${dir.path}/temp.m4a');
                setState(() => _isRec = true);
                HapticFeedback.mediumImpact();
              }
            },
            onLongPressEnd: (_) async {
              if (isEditing) return;
              final path = await _recorder.stop();
              setState(() => _isRec = false);
              if (path != null) _send(type: 'audio', content: base64Encode(await File(path).readAsBytes()));
            },
            child: Container(
              height: 50, width: 50,
              decoration: BoxDecoration(color: _isRec ? Colors.redAccent : const Color(0xFF161A22), borderRadius: BorderRadius.circular(16)),
              child: Icon(_isRec ? Icons.stop : Icons.mic, color: Colors.white),
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: () => _send(),
            child: Container(
              height: 50, width: 50,
              decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFF7B51FF), Color(0xFF375FFF)]), borderRadius: BorderRadius.circular(16)),
              child: Icon(isEditing ? Icons.check : Icons.send, color: Colors.white, size: 22),
            ),
          ),
        ],
      ),
    );
  }
}

class MessageBubble extends StatelessWidget {
  final Map<String, dynamic> data;
  final String id;
  final bool isMe;
  final Function(Map<String, dynamic>, String, bool) onLongPress;
  final Function(String) onReplyTap;
  final Function(String) onImageTap;

  const MessageBubble({
    super.key,
    required this.data,
    required this.id,
    required this.isMe,
    required this.onLongPress,
    required this.onReplyTap,
    required this.onImageTap,
  });

  @override
  Widget build(BuildContext context) {
    String time = "";
    if (data['timestamp'] != null) {
      DateTime dt = (data['timestamp'] as Timestamp).toDate();
      time = DateFormat('h:mm a').format(dt);
    }
    bool isPhoto = data['type'] == 'image';

    return GestureDetector(
      onLongPress: () => onLongPress(data, id, isMe),
      child: Container(
        margin: const EdgeInsets.only(bottom: 20),
        child: Column(
          crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (data['replyToText'] != null)
              GestureDetector(
                onTap: () {
                   if (data['replyToMessageId'] != null) onReplyTap(data['replyToMessageId']);
                },
                child: Container(
                  margin: EdgeInsets.only(bottom: 4, left: isMe ? 0 : 10, right: isMe ? 10 : 0),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(border: Border(left: BorderSide(color: isMe ? Colors.white54 : const Color(0xFF7B51FF), width: 3))),
                  child: Text("Replying to: ${data['replyToText']}", maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.grey, fontSize: 11)),
                ),
              ),
            
            Container(
              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: data['type'] == 'audio' ? const LinearGradient(colors: [Color(0xFF7B51FF), Color(0xFF375FFF)]) : null,
                color: data['type'] == 'audio' ? null : (isMe ? const Color(0xFF1D222C) : const Color(0xFF161A22)),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  data['type'] == 'audio'
                      ? VoiceWaveformBubble(base64Audio: data['message'])
                      : isPhoto
                          ? GestureDetector(
                              onTap: () => onImageTap(data['message']),
                              child: ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.memory(base64Decode(data['message']), gaplessPlayback: true)),
                            )
                          : Text(data['message'], style: const TextStyle(color: Colors.white, fontSize: 15)),
                ],
              ),
            ),
            
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 4, right: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (data['isEdited'] == true) const Text("edited • ", style: TextStyle(fontSize: 10, color: Colors.grey)),
                  Text(time, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                  if (isMe) ...[
                    const SizedBox(width: 4),
                    Icon(Icons.done_all, size: 15, color: data['isRead'] == true ? const Color(0xFF7B51FF) : Colors.grey),
                  ]
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class FullScreenImage extends StatelessWidget {
  final String base64Image;
  const FullScreenImage({super.key, required this.base64Image});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(backgroundColor: Colors.black, iconTheme: const IconThemeData(color: Colors.white)),
      body: Center(child: InteractiveViewer(child: Image.memory(base64Decode(base64Image)))),
    );
  }
}

class VoiceWaveformBubble extends StatefulWidget {
  final String base64Audio;
  const VoiceWaveformBubble({super.key, required this.base64Audio});
  @override
  State<VoiceWaveformBubble> createState() => _VoiceWaveformBubbleState();
}

class _VoiceWaveformBubbleState extends State<VoiceWaveformBubble> {
  late PlayerController controller;
  bool isLoaded = false;
  @override
  void initState() {
    super.initState();
    controller = PlayerController();
    _initAudio();
  }
  void _initAudio() async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/${widget.base64Audio.hashCode}.m4a');
    if (!await file.exists()) await file.writeAsBytes(base64Decode(widget.base64Audio));
    await controller.preparePlayer(path: file.path, shouldExtractWaveform: true, noOfSamples: 25);
    if (mounted) setState(() => isLoaded = true);
  }
  @override
  void dispose() { controller.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    if (!isLoaded) return const SizedBox(width: 140, height: 40, child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)));
    return Row(mainAxisSize: MainAxisSize.min, children: [
        GestureDetector(
          onTap: () async { controller.playerState.isPlaying ? await controller.pausePlayer() : await controller.startPlayer(); setState(() {}); },
          child: Container(padding: const EdgeInsets.all(8), decoration: const BoxDecoration(color: Colors.white24, shape: BoxShape.circle), child: Icon(controller.playerState.isPlaying ? Icons.pause : Icons.play_arrow, color: Colors.white, size: 24)),
        ),
        const SizedBox(width: 12),
        AudioFileWaveforms(size: const Size(120, 30), playerController: controller, waveformType: WaveformType.fitWidth, playerWaveStyle: const PlayerWaveStyle(fixedWaveColor: Colors.white38, liveWaveColor: Colors.white, spacing: 5, waveThickness: 3, seekLineColor: Colors.white)),
      ]);
  }
}