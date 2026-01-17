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

class MessengerApp extends StatefulWidget {
  const MessengerApp({super.key});

  @override
  State<MessengerApp> createState() => _MessengerAppState();
}

class _MessengerAppState extends State<MessengerApp> with WidgetsBindingObserver {
  final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();
  StreamSubscription? _globalMsgSubscription;
  AppLifecycleState _appState = AppLifecycleState.resumed;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initNotifications();
    _startGlobalListener();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _globalMsgSubscription?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appState = state;
  }

  void _initNotifications() async {
    const AndroidInitializationSettings androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher'); 
    const InitializationSettings settings = InitializationSettings(android: androidSettings);
    await _notificationsPlugin.initialize(settings);
    _notificationsPlugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.requestNotificationsPermission();
  }

  void _startGlobalListener() {
    FirebaseAuth.instance.authStateChanges().listen((user) {
      _globalMsgSubscription?.cancel();
      if (user != null) {
        try {
          _globalMsgSubscription = FirebaseFirestore.instance
              .collectionGroup('messages')
              .where('receiverId', isEqualTo: user.uid)
              .orderBy('timestamp', descending: true)
              .limit(1)
              .snapshots()
              .listen((snapshot) {
            
            if (snapshot.docs.isNotEmpty) {
              for (var change in snapshot.docChanges) {
                if (change.type == DocumentChangeType.added) {
                  var data = change.doc.data() as Map<String, dynamic>;
                  Timestamp? ts = data['timestamp'];
                  if (ts != null) {
                    final now = DateTime.now();
                    final msgTime = ts.toDate();
                    if (now.difference(msgTime).inSeconds < 30) {
                       if (_appState != AppLifecycleState.resumed) {
                         _showNotification(data['message'] ?? "New Message");
                       }
                    }
                  }
                }
              }
            }
          }, onError: (error) {
            debugPrint("Global Listener Error (Likely missing index): $error");
          });
        } catch (e) {
          debugPrint("Error initializing global listener: $e");
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
    if (content.length > 100 && !content.contains(" ")) content = "📷 Photo";
    
    await _notificationsPlugin.show(
      DateTime.now().millisecond, 
      "New Message", 
      content, 
      details
    );
  }

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
  final bool isGroup;
  final String? roomId;

  const ChatScreen({
    super.key, 
    required this.receiverUserID, 
    required this.receiverName,
    this.isGroup = false,
    this.roomId
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  final TextEditingController _msgController = TextEditingController();
  final AudioRecorder _recorder = AudioRecorder();
  final ScrollController _scrollController = ScrollController();

  Timer? _typingTimer;
  bool _isRec = false;
  bool _isMuted = false;

  String? _editingMsgId;
  String? _replyingToText;
  String? _replyingToSenderId;
  String? _replyingToMessageId; 

  int _limit = 30;
  final int _limitIncrement = 20;
  
  StreamSubscription? _roomSubscription;
  
  final Map<String, GlobalKey> _messageKeys = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _setUserStatus(true);
    _markAsRead();
    _listenForRoomChanges();
    
    _scrollController.addListener(() {
      if (_scrollController.hasClients && 
          _scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
         setState(() => _limit += _limitIncrement);
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _setUserStatus(false);
    _roomSubscription?.cancel();
    _msgController.dispose();
    _recorder.dispose();
    _scrollController.dispose();
    _typingTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _setUserStatus(true);
    } else {
      _setUserStatus(false);
    }
  }

  void _setUserStatus(bool isOnline) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      FirebaseFirestore.instance.collection('users').doc(uid).update({
        'isOnline': isOnline,
        'lastActive': Timestamp.now(),
      });
    }
  }

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

  void _updateGroupPic() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(source: ImageSource.gallery, imageQuality: 20);
    if (image != null) {
      final bytes = await image.readAsBytes();
      final base64String = base64Encode(bytes);
      await FirebaseFirestore.instance.collection('chat_rooms').doc(_getRoomId()).update({
        'groupPic': base64String
      });
    }
  }

  void _showGroupParticipants() async {
    final doc = await FirebaseFirestore.instance.collection('chat_rooms').doc(_getRoomId()).get();
    if (!doc.exists) return;

    List<dynamic> participants = doc.data()?['participants'] ?? [];

    if (mounted) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: const Color(0xFF1D222C),
          title: const Text("Participants", style: TextStyle(color: Colors.white)),
          content: SizedBox(
            width: double.maxFinite,
            height: 300,
            child: ListView.builder(
              itemCount: participants.length,
              itemBuilder: (context, index) {
                return FutureBuilder<DocumentSnapshot>(
                  future: FirebaseFirestore.instance.collection('users').doc(participants[index]).get(),
                  builder: (context, snap) {
                    if (!snap.hasData) return const SizedBox();
                    var user = snap.data!.data() as Map<String, dynamic>;
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundImage: user['profilePic'] != null ? MemoryImage(base64Decode(user['profilePic'])) : null,
                        child: user['profilePic'] == null ? Text((user['username'] ?? "U")[0].toUpperCase()) : null,
                      ),
                      title: Text(user['username'] ?? "User", style: const TextStyle(color: Colors.white)),
                    );
                  },
                );
              },
            ),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text("Close"))],
        ),
      );
    }
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

  void _toggleMute() async {
    final roomId = _getRoomId();
    final uid = FirebaseAuth.instance.currentUser!.uid;
    await FirebaseFirestore.instance.collection('chat_rooms').doc(roomId).set({
      'mutedFor': {uid: !_isMuted}
    }, SetOptions(merge: true));
  }

  void _deleteChat() async {
    bool confirm = await showDialog(
      context: context, 
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1D222C),
        title: const Text("Delete Chat?", style: TextStyle(color: Colors.white)),
        content: const Text("This will permanently delete all messages.", style: TextStyle(color: Colors.grey)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancel")),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text("Delete", style: TextStyle(color: Colors.redAccent))),
        ],
      )
    ) ?? false;

    if (!confirm) return;

    final roomId = _getRoomId();
    final msgs = await FirebaseFirestore.instance.collection('chat_rooms').doc(roomId).collection('messages').get();
    final batch = FirebaseFirestore.instance.batch();
    
    for (var doc in msgs.docs) {
      batch.delete(doc.reference);
    }
    batch.delete(FirebaseFirestore.instance.collection('chat_rooms').doc(roomId));
    await batch.commit();

    if (mounted) Navigator.pop(context); 
  }

  String _getRoomId() {
    if (widget.isGroup && widget.roomId != null) {
      return widget.roomId!;
    }
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
        'senderId': senderId, 
        'receiverId': widget.isGroup ? roomId : widget.receiverUserID, 
        'message': msg, 
        'type': type, 
        'timestamp': timestamp, 
        'isRead': false, 
        'replyToText': currentReplyText, 
        'replyToUserId': currentReplySenderId, 
        'replyToMessageId': currentReplyMessageId
      };

      WriteBatch batch = FirebaseFirestore.instance.batch();
      DocumentReference msgRef = FirebaseFirestore.instance.collection('chat_rooms').doc(roomId).collection('messages').doc();
      DocumentReference roomRef = FirebaseFirestore.instance.collection('chat_rooms').doc(roomId);

      batch.set(msgRef, messageData);
      String preview = type == 'image' ? '📷 Photo' : (type == 'audio' ? '🎤 Voice' : msg);
      
      // --- FIX: Don't set participants to null for groups, use conditional map key ---
      batch.set(roomRef, {
        if (!widget.isGroup) 'participants': [senderId, widget.receiverUserID],
        'lastMessage': preview, 
        'lastMessageTimestamp': timestamp,
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
            if (widget.isGroup) {
              _showGroupParticipants();
            } else {
               Navigator.push(context, MaterialPageRoute(builder: (context) => OtherUserProfilePage(userId: widget.receiverUserID, userName: widget.receiverName)));
            }
          },
          child: Row(
            children: [
              if (widget.isGroup)
                StreamBuilder<DocumentSnapshot>(
                  stream: FirebaseFirestore.instance.collection('chat_rooms').doc(_getRoomId()).snapshots(),
                  builder: (context, snapshot) {
                    var data = snapshot.data?.data() as Map<String, dynamic>?;
                    String? groupPic = data?['groupPic'];
                    
                    return GestureDetector(
                      onTap: _updateGroupPic, 
                      child: Container(
                        padding: const EdgeInsets.all(1.5),
                        decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: const Color(0xFF2B303B))),
                        child: CircleAvatar(
                          radius: 20,
                          backgroundColor: const Color(0xFF2B303B),
                          backgroundImage: groupPic != null ? MemoryImage(base64Decode(groupPic)) : null,
                          child: groupPic == null ? const Icon(Icons.group, color: Colors.white) : null,
                        ),
                      ),
                    );
                  }
                )
              else 
                StreamBuilder<DocumentSnapshot>(
                  stream: FirebaseFirestore.instance.collection('users').doc(widget.receiverUserID).snapshots(),
                  builder: (context, snap) {
                    if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
                       return Container(width: 40, height: 40, decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF2B303B)));
                    }
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
                    
                    if (!widget.isGroup)
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
                    else 
                      const Text("Tap for info", style: TextStyle(color: Colors.grey, fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          if (!widget.isGroup) ...[
            IconButton(icon: const Icon(Icons.call), onPressed: _makePhoneCall),
            IconButton(icon: const Icon(Icons.videocam), onPressed: _makeVideoCall),
          ],
          
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
          addAutomaticKeepAlives: true,
          itemBuilder: (context, index) {
            var doc = docs[index];
            if (!_messageKeys.containsKey(doc.id)) _messageKeys[doc.id] = GlobalKey();
            
            return MessageBubble(
              key: _messageKeys[doc.id],
              data: doc.data() as Map<String, dynamic>,
              id: doc.id,
              isMe: doc['senderId'] == FirebaseAuth.instance.currentUser!.uid,
              // --- FIX: Pass isGroup to MessageBubble ---
              isGroup: widget.isGroup,
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

class MessageBubble extends StatefulWidget {
  final Map<String, dynamic> data;
  final String id;
  final bool isMe;
  final Function(Map<String, dynamic>, String, bool) onLongPress;
  final Function(String) onReplyTap;
  final Function(String) onImageTap;
  // --- FIX: Add isGroup parameter ---
  final bool isGroup;

  const MessageBubble({
    super.key,
    required this.data,
    required this.id,
    required this.isMe,
    required this.onLongPress,
    required this.onReplyTap,
    required this.onImageTap,
    this.isGroup = false,
  });

  @override
  State<MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<MessageBubble> {
  Uint8List? _decodedImage;

  @override
  void initState() {
    super.initState();
    if (widget.data['type'] == 'image' && widget.data['message'] != null) {
      _decodedImage = base64Decode(widget.data['message']);
    }
  }

  @override
  Widget build(BuildContext context) {
    String time = "";
    if (widget.data['timestamp'] != null) {
      DateTime dt = (widget.data['timestamp'] as Timestamp).toDate();
      time = DateFormat('h:mm a').format(dt);
    }
    bool isPhoto = widget.data['type'] == 'image';

    // --- FIX: Logic to build MessageBubble content ---
    Widget bubbleContent = Container(
      constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: widget.data['type'] == 'audio' ? const LinearGradient(colors: [Color(0xFF7B51FF), Color(0xFF375FFF)]) : null,
        color: widget.data['type'] == 'audio' ? null : (widget.isMe ? const Color(0xFF1D222C) : const Color(0xFF161A22)),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          widget.data['type'] == 'audio'
              ? VoiceWaveformBubble(base64Audio: widget.data['message'])
              : isPhoto
                  ? GestureDetector(
                      onTap: () => widget.onImageTap(widget.data['message']),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: _decodedImage != null 
                            ? Image.memory(_decodedImage!, gaplessPlayback: true) 
                            : const SizedBox(),
                      ),
                    )
                  : Text(widget.data['message'], style: const TextStyle(color: Colors.white, fontSize: 15)),
        ],
      ),
    );

    // --- FIX: Wrap in Row if Group Chat and Not Me ---
    Widget messageRow;
    if (widget.isGroup && !widget.isMe) {
      messageRow = Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          StreamBuilder<DocumentSnapshot>(
            stream: FirebaseFirestore.instance.collection('users').doc(widget.data['senderId']).snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const SizedBox(width: 32);
              var userData = snapshot.data!.data() as Map<String, dynamic>?;
              String? pic = userData?['profilePic'];
              String name = userData?['username'] ?? "U";
              
              return Container(
                margin: const EdgeInsets.only(right: 8, bottom: 4),
                child: CircleAvatar(
                  radius: 16,
                  backgroundColor: Colors.grey.shade800,
                  backgroundImage: pic != null ? MemoryImage(base64Decode(pic)) : null,
                  child: pic == null ? Text(name[0].toUpperCase(), style: const TextStyle(fontSize: 12, color: Colors.white)) : null,
                ),
              );
            },
          ),
          bubbleContent,
        ],
      );
    } else {
      messageRow = bubbleContent;
    }

    return GestureDetector(
      onLongPress: () => widget.onLongPress(widget.data, widget.id, widget.isMe),
      child: Container(
        margin: const EdgeInsets.only(bottom: 20),
        child: Column(
          crossAxisAlignment: widget.isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (widget.data['replyToText'] != null)
              GestureDetector(
                onTap: () {
                   if (widget.data['replyToMessageId'] != null) widget.onReplyTap(widget.data['replyToMessageId']);
                },
                child: Container(
                  margin: EdgeInsets.only(bottom: 4, left: widget.isMe ? 0 : (widget.isGroup && !widget.isMe ? 40 : 10), right: widget.isMe ? 10 : 0),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(border: Border(left: BorderSide(color: widget.isMe ? Colors.white54 : const Color(0xFF7B51FF), width: 3))),
                  child: Text("Replying to: ${widget.data['replyToText']}", maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.grey, fontSize: 11)),
                ),
              ),
            
            messageRow, // Insert the conditional row here
            
            Padding(
              padding: EdgeInsets.only(top: 6, left: widget.isGroup && !widget.isMe ? 40 : 4, right: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.data['isEdited'] == true) const Text("edited • ", style: TextStyle(fontSize: 10, color: Colors.grey)),
                  Text(time, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                  if (widget.isMe) ...[
                    const SizedBox(width: 4),
                    Icon(Icons.done_all, size: 15, color: widget.data['isRead'] == true ? const Color(0xFF7B51FF) : Colors.grey),
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