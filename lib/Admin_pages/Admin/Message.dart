import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _chatPink = Color(0xFFE91E63);
const _chatDeep = Color(0xFFC2105C);
const _chatBg = Color(0xFFFFF8F3);

class MessagePage extends StatefulWidget {
  const MessagePage({super.key});

  @override
  State<MessagePage> createState() => _MessagePageState();
}

class _MessagePageState extends State<MessagePage> {
  Map<String, String>? _me;

  @override
  void initState() {
    super.initState();
    _loadMe();
  }

  Future<void> _loadMe() async {
    final prefs = await SharedPreferences.getInstance();
    final lastRole = prefs.getString('lastRole') ?? '';
    if (lastRole == 'admin') {
      final adminId = prefs.getString('adminId') ?? 'ADM-0001';
      if (!mounted) return;
      setState(() {
        _me = {'id': adminId, 'name': 'Admin User', 'role': 'admin'};
      });
      return;
    }
    if (lastRole == 'staff') {
      final lastUserId =
          prefs.getString('lastStaffDocId') ?? prefs.getString('lastUserId');
      if ((lastUserId ?? '').isNotEmpty) {
        final doc = await FirebaseFirestore.instance
            .collection('staff_requests')
            .doc(lastUserId)
            .get();
        final data = doc.data() ?? {};
        if (!mounted) return;
        setState(() {
          _me = {
            'id': lastUserId!,
            'name': _displayName(data),
            'role': 'staff',
          };
        });
        return;
      }
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final doc = await FirebaseFirestore.instance
          .collection('staff_requests')
          .doc(user.uid)
          .get();
      final data = doc.data() ?? {};
      if (!mounted) return;
      setState(() {
        _me = {
          'id': user.uid,
          'name': _displayName(data),
          'role': (data['role'] ?? 'staff').toString(),
        };
      });
      return;
    }

    final adminId = prefs.getString('adminId') ?? 'ADM-0001';
    if (!mounted) return;
    setState(() {
      _me = {'id': adminId, 'name': 'Admin User', 'role': 'admin'};
    });
  }

  static String _displayName(Map<String, dynamic> data) {
    final first = data['firstName']?.toString().trim() ?? '';
    final last = data['lastName']?.toString().trim() ?? '';
    final full = [first, last].where((part) => part.isNotEmpty).join(' ');
    return full.isEmpty ? (data['name']?.toString() ?? 'User') : full;
  }

  static bool _isOnline(Map<String, dynamic> data) {
    if (data['isOnline'] == true) return true;
    final lastLogin = data['lastLoginAt'];
    if (lastLogin is! Timestamp) return false;
    return DateTime.now().difference(lastLogin.toDate()) <
        const Duration(minutes: 15);
  }

  String _chatId(String otherId) {
    final me = _me?['id'] ?? '';
    final ids = [me, otherId]..sort();
    return ids.join('_');
  }

  int _unreadCount(Map<String, dynamic> chat) {
    final meId = _me?['id'] ?? '';
    final unreadBy = chat['unreadBy'];
    if (unreadBy is Map) {
      final value = unreadBy[meId];
      if (value is num) return value.toInt();
      return int.tryParse(value?.toString() ?? '') ?? 0;
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final me = _me;
    return Scaffold(
      backgroundColor: _chatBg,
      appBar: AppBar(
        backgroundColor: _chatPink,
        foregroundColor: Colors.white,
        title: const Text('Messages'),
      ),
      body: me == null
          ? const Center(child: CircularProgressIndicator(color: _chatPink))
          : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('staff_requests')
                  .snapshots(),
              builder: (context, snapshot) {
                final accountDocs = (snapshot.data?.docs ?? [])
                    .where((doc) {
                      final data = doc.data();
                      final status = data['status']?.toString().toLowerCase();
                      return doc.id != me['id'] && status != 'rejected';
                    })
                    .toList();
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(color: _chatPink),
                  );
                }
                return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: FirebaseFirestore.instance
                      .collection('messages')
                      .where('participantIds', arrayContains: me['id'])
                      .snapshots(),
                  builder: (context, chatSnapshot) {
                    final rows = <String, _InboxRow>{};

                    if (me['role'] != 'admin') {
                      rows['ADM-0001'] = const _InboxRow(
                        id: 'ADM-0001',
                        name: 'Admin User',
                        role: 'admin',
                        online: true,
                      );
                    }

                    for (final doc in accountDocs) {
                      final data = doc.data();
                      rows[doc.id] = _InboxRow(
                        id: doc.id,
                        name: _displayName(data),
                        role: data['role']?.toString() ?? 'staff',
                        online: _isOnline(data),
                      );
                    }

                    for (final chatDoc in chatSnapshot.data?.docs ?? []) {
                      final chat = chatDoc.data();
                      final ids = (chat['participantIds'] as List? ?? [])
                          .map((id) => id.toString())
                          .toList();
                      final otherId = ids.firstWhere(
                        (id) => id != me['id'],
                        orElse: () => '',
                      );
                      if (otherId.isEmpty) continue;
                      final names = chat['participantNames'];
                      final name = names is Map
                          ? names[otherId]?.toString() ?? 'Admin User'
                          : 'Admin User';
                      rows[otherId] = rows[otherId]?.copyWith(
                            unread: _unreadCount(chat),
                            lastMessage: chat['lastMessage']?.toString() ?? '',
                          ) ??
                          _InboxRow(
                            id: otherId,
                            name: name,
                            role: otherId.startsWith('ADM-') ? 'admin' : 'staff',
                            online: false,
                            unread: _unreadCount(chat),
                            lastMessage: chat['lastMessage']?.toString() ?? '',
                          );
                    }

                    final items = rows.values.toList()
                      ..sort((a, b) => b.unread.compareTo(a.unread));
                    if (items.isEmpty) {
                      return const Center(child: Text('No users available.'));
                    }
                    return ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: items.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final row = items[index];
                        return _InboxTile(
                          row: row,
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ChatThreadPage(
                                chatId: _chatId(row.id),
                                me: me,
                                otherId: row.id,
                                otherName: row.name,
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  },
                );
              },
            ),
    );
  }
}

class _InboxRow {
  final String id;
  final String name;
  final String role;
  final bool online;
  final int unread;
  final String lastMessage;

  const _InboxRow({
    required this.id,
    required this.name,
    required this.role,
    required this.online,
    this.unread = 0,
    this.lastMessage = '',
  });

  _InboxRow copyWith({int? unread, String? lastMessage}) {
    return _InboxRow(
      id: id,
      name: name,
      role: role,
      online: online,
      unread: unread ?? this.unread,
      lastMessage: lastMessage ?? this.lastMessage,
    );
  }
}

class _InboxTile extends StatelessWidget {
  final _InboxRow row;
  final VoidCallback onTap;

  const _InboxTile({required this.row, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      tileColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: _chatPink.withOpacity(0.16)),
      ),
      leading: Stack(
        children: [
          CircleAvatar(
            backgroundColor: _chatPink.withOpacity(0.12),
            child: Text(
              row.name.isEmpty ? '?' : row.name[0].toUpperCase(),
              style: const TextStyle(
                color: _chatDeep,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: row.online ? Colors.green : Colors.grey,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
            ),
          ),
        ],
      ),
      title: Text(row.name, style: const TextStyle(fontWeight: FontWeight.w800)),
      subtitle: Text(
        row.lastMessage.isNotEmpty
            ? row.lastMessage
            : row.online
            ? '${row.role} - Online'
            : '${row.role} - Offline',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: row.unread > 0
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: const BoxDecoration(
                color: _chatPink,
                borderRadius: BorderRadius.all(Radius.circular(999)),
              ),
              child: Text(
                row.unread > 99 ? '99+' : '${row.unread}',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                ),
              ),
            )
          : const Icon(Icons.chevron_right_rounded, color: _chatPink),
      onTap: onTap,
    );
  }
}

class ChatThreadPage extends StatefulWidget {
  final String chatId;
  final Map<String, String> me;
  final String otherId;
  final String otherName;

  const ChatThreadPage({
    super.key,
    required this.chatId,
    required this.me,
    required this.otherId,
    required this.otherName,
  });

  @override
  State<ChatThreadPage> createState() => _ChatThreadPageState();
}

class _ChatThreadPageState extends State<ChatThreadPage> {
  final _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    _markThreadRead();
  }

  Future<void> _markThreadRead() async {
    await FirebaseFirestore.instance
        .collection('messages')
        .doc(widget.chatId)
        .set({
          'unreadBy': {widget.me['id']!: 0},
        }, SetOptions(merge: true));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _controller.clear();
    final chatRef =
        FirebaseFirestore.instance.collection('messages').doc(widget.chatId);
    await chatRef.set({
      'participantIds': [widget.me['id'], widget.otherId],
      'participantNames': {
        widget.me['id']: widget.me['name'],
        widget.otherId: widget.otherName,
      },
      'lastMessage': text,
      'updatedAt': FieldValue.serverTimestamp(),
      'unreadBy': {widget.otherId: FieldValue.increment(1)},
    }, SetOptions(merge: true));
    await chatRef.collection('items').add({
      'senderId': widget.me['id'],
      'senderName': widget.me['name'],
      'text': text,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _chatBg,
      appBar: AppBar(
        backgroundColor: _chatPink,
        foregroundColor: Colors.white,
        title: Text(widget.otherName),
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('messages')
                  .doc(widget.chatId)
                  .collection('items')
                  .orderBy('createdAt', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                final docs = snapshot.data?.docs ?? [];
                return ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.all(16),
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final data = docs[index].data();
                    final mine = data['senderId'] == widget.me['id'];
                    return Align(
                      alignment:
                          mine ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        constraints: BoxConstraints(
                          maxWidth: MediaQuery.of(context).size.width * 0.76,
                        ),
                        decoration: BoxDecoration(
                          color: mine ? _chatPink : Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: mine
                                ? _chatPink
                                : _chatPink.withOpacity(0.18),
                          ),
                        ),
                        child: Text(
                          data['text']?.toString() ?? '',
                          style: TextStyle(
                            color: mine ? Colors.white : Colors.black87,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      minLines: 1,
                      maxLines: 4,
                      decoration: InputDecoration(
                        hintText: 'Type a message',
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(18),
                          borderSide:
                              BorderSide(color: _chatPink.withOpacity(0.2)),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    style: IconButton.styleFrom(backgroundColor: _chatPink),
                    onPressed: _send,
                    icon: const Icon(Icons.send_rounded),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
