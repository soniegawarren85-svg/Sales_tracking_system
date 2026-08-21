import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _chatPink = Color(0xFFE91E63);
const _chatDeep = Color(0xFFC2105C);
const _chatBg = Color(0xFFFFF8F3);
const _chatMint = Color(0xFF2ECC71);

class MessagePage extends StatefulWidget {
  const MessagePage({super.key});

  @override
  State<MessagePage> createState() => _MessagePageState();
}

class _MessagePageState extends State<MessagePage> {
  Map<String, String>? _me;
  Set<String> _pinnedIds = {};

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
      _loadPinnedIds(adminId);
      return;
    }
    if (lastRole == 'staff') {
      final lastUserId =
          prefs.getString('lastStaffDocId') ?? prefs.getString('lastUserId');
      if ((lastUserId ?? '').isNotEmpty) {
        final staffId = lastUserId!;
        final doc = await FirebaseFirestore.instance
            .collection('staff_requests')
            .doc(staffId)
            .get();
        final data = doc.data() ?? {};
        if (!mounted) return;
        setState(() {
          _me = {'id': staffId, 'name': _displayName(data), 'role': 'staff'};
        });
        _loadPinnedIds(staffId);
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
      _loadPinnedIds(user.uid);
      return;
    }

    final adminId = prefs.getString('adminId') ?? 'ADM-0001';
    if (!mounted) return;
    setState(() {
      _me = {'id': adminId, 'name': 'Admin User', 'role': 'admin'};
    });
    _loadPinnedIds(adminId);
  }

  Future<void> _loadPinnedIds(String meId) async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _pinnedIds = prefs.getStringList('pinned_messages_$meId')?.toSet() ?? {};
    });
  }

  Future<void> _togglePinned(String id) async {
    final meId = _me?['id'] ?? '';
    if (meId.isEmpty) return;
    final next = {..._pinnedIds};
    next.contains(id) ? next.remove(id) : next.add(id);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('pinned_messages_$meId', next.toList());
    if (mounted) setState(() => _pinnedIds = next);
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
      extendBodyBehindAppBar: false,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(64),
        child: Container(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [_chatPink, _chatDeep],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: _chatDeep.withOpacity(0.35),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            foregroundColor: Colors.white,
            centerTitle: false,
            title: Row(
              children: const [
                Icon(Icons.chat_bubble_rounded, size: 22),
                SizedBox(width: 10),
                Text(
                  'Messages',
                  style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.2),
                ),
              ],
            ),
          ),
        ),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [_chatBg, Color(0xFFFFF1E9)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: me == null
            ? const Center(child: _LoadingSpinner())
            : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance
                    .collection('staff_requests')
                    .snapshots(),
                builder: (context, snapshot) {
                  final accountDocs = (snapshot.data?.docs ?? []).where((doc) {
                    final data = doc.data();
                    final status = data['status']?.toString().toLowerCase();
                    return doc.id != me['id'] && status != 'rejected';
                  }).toList();
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: _LoadingSpinner());
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
                          photoUrl:
                              data['photoUrl']?.toString() ??
                              data['profileImageUrl']?.toString(),
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
                        final photos = chat['participantPhotos'];
                        final name = names is Map
                            ? names[otherId]?.toString() ?? 'Admin User'
                            : 'Admin User';
                        rows[otherId] =
                            rows[otherId]?.copyWith(
                              unread: _unreadCount(chat),
                              lastMessage: chat['lastMessage']?.toString() ?? '',
                              photoUrl:
                                  rows[otherId]?.photoUrl ??
                                  (photos is Map
                                      ? photos[otherId]?.toString()
                                      : null),
                              pinned: _pinnedIds.contains(otherId),
                            ) ??
                            _InboxRow(
                              id: otherId,
                              name: name,
                              role: otherId.startsWith('ADM-')
                                  ? 'admin'
                                  : 'staff',
                              online: false,
                              unread: _unreadCount(chat),
                              lastMessage: chat['lastMessage']?.toString() ?? '',
                              pinned: _pinnedIds.contains(otherId),
                            );
                      }

                      for (final id in rows.keys.toList()) {
                        rows[id] = rows[id]!.copyWith(
                          pinned: _pinnedIds.contains(id),
                        );
                      }
                      final items = rows.values.toList()
                        ..sort((a, b) {
                          if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
                          final unreadCompare = b.unread.compareTo(a.unread);
                          if (unreadCompare != 0) return unreadCompare;
                          return a.name.compareTo(b.name);
                        });
                      if (items.isEmpty) {
                        return const _EmptyInboxState();
                      }
                      return Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 900),
                          child: ListView.separated(
                            padding: const EdgeInsets.all(16),
                            itemCount: items.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 10),
                            itemBuilder: (context, index) {
                              final row = items[index];
                              return _EntranceItem(
                                index: index,
                                child: _InboxTile(
                                  row: row,
                                  onPin: () => _togglePinned(row.id),
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
                                ),
                              );
                            },
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
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
  final String? photoUrl;
  final bool pinned;

  const _InboxRow({
    required this.id,
    required this.name,
    required this.role,
    required this.online,
    this.unread = 0,
    this.lastMessage = '',
    this.photoUrl,
    this.pinned = false,
  });

  _InboxRow copyWith({
    int? unread,
    String? lastMessage,
    String? photoUrl,
    bool? pinned,
  }) {
    return _InboxRow(
      id: id,
      name: name,
      role: role,
      online: online,
      unread: unread ?? this.unread,
      lastMessage: lastMessage ?? this.lastMessage,
      photoUrl: photoUrl ?? this.photoUrl,
      pinned: pinned ?? this.pinned,
    );
  }
}

/// Fades + slides an item in on first build, staggered by [index].
class _EntranceItem extends StatefulWidget {
  final int index;
  final Widget child;
  const _EntranceItem({required this.index, required this.child});

  @override
  State<_EntranceItem> createState() => _EntranceItemState();
}

class _EntranceItemState extends State<_EntranceItem>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 380),
  );
  late final Animation<double> _fade =
      CurvedAnimation(parent: _controller, curve: Curves.easeOut);
  late final Animation<Offset> _slide = Tween<Offset>(
    begin: const Offset(0.06, 0),
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));

  @override
  void initState() {
    super.initState();
    Future.delayed(Duration(milliseconds: 35 * widget.index), () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(position: _slide, child: widget.child),
    );
  }
}

class _InboxTile extends StatefulWidget {
  final _InboxRow row;
  final VoidCallback onTap;
  final VoidCallback onPin;

  const _InboxTile({
    required this.row,
    required this.onTap,
    required this.onPin,
  });

  @override
  State<_InboxTile> createState() => _InboxTileState();
}

class _InboxTileState extends State<_InboxTile> {
  double _scale = 1;

  void _setPressed(bool pressed) =>
      setState(() => _scale = pressed ? 0.98 : 1);

  @override
  Widget build(BuildContext context) {
    final row = widget.row;
    return AnimatedScale(
      scale: _scale,
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: widget.onTap,
          onTapDown: (_) => _setPressed(true),
          onTapUp: (_) => _setPressed(false),
          onTapCancel: () => _setPressed(false),
          borderRadius: BorderRadius.circular(20),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              gradient: row.pinned
                  ? LinearGradient(
                      colors: [
                        _chatPink.withOpacity(0.07),
                        Colors.white,
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    )
                  : null,
              border: Border.all(
                color: row.pinned
                    ? _chatDeep.withOpacity(0.45)
                    : _chatPink.withOpacity(0.12),
                width: row.pinned ? 1.4 : 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: _chatPink.withOpacity(row.pinned ? 0.14 : 0.06),
                  blurRadius: row.pinned ? 20 : 14,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              children: [
                _ChatAvatar(
                  name: row.name,
                  photoUrl: row.photoUrl,
                  online: row.online,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              row.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 16,
                                color: Color(0xFF2A1A22),
                              ),
                            ),
                          ),
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 220),
                            transitionBuilder: (child, anim) => ScaleTransition(
                              scale: anim,
                              child: child,
                            ),
                            child: row.pinned
                                ? const Padding(
                                    key: ValueKey('pinned'),
                                    padding: EdgeInsets.only(left: 4),
                                    child: Icon(
                                      Icons.push_pin_rounded,
                                      color: _chatDeep,
                                      size: 16,
                                    ),
                                  )
                                : const SizedBox.shrink(key: ValueKey('unpinned')),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        row.lastMessage.isNotEmpty
                            ? row.lastMessage
                            : '${row.role} • ${row.online ? 'Online' : 'Offline'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.grey.shade700,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (row.unread > 0) _UnreadBadge(count: row.unread),
                _AnimatedPinButton(pinned: row.pinned, onTap: widget.onPin),
                const Icon(Icons.chevron_right_rounded, color: _chatPink),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _UnreadBadge extends StatelessWidget {
  final int count;
  const _UnreadBadge({required this.count});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 350),
      curve: Curves.elasticOut,
      builder: (context, value, child) => Transform.scale(scale: value, child: child),
      child: Container(
        margin: const EdgeInsets.only(right: 4),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [_chatPink, _chatDeep]),
          borderRadius: const BorderRadius.all(Radius.circular(999)),
          boxShadow: [
            BoxShadow(
              color: _chatDeep.withOpacity(0.4),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Text(
          count > 99 ? '99+' : '$count',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}

class _AnimatedPinButton extends StatelessWidget {
  final bool pinned;
  final VoidCallback onTap;
  const _AnimatedPinButton({required this.pinned, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: pinned ? 'Unpin' : 'Pin',
      onPressed: onTap,
      icon: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        transitionBuilder: (child, anim) => RotationTransition(
          turns: Tween<double>(begin: 0.75, end: 1).animate(anim),
          child: ScaleTransition(scale: anim, child: child),
        ),
        child: Icon(
          pinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
          key: ValueKey(pinned),
          color: pinned ? _chatDeep : _chatPink,
        ),
      ),
    );
  }
}

class _ChatAvatar extends StatefulWidget {
  final String name;
  final String? photoUrl;
  final bool online;

  const _ChatAvatar({required this.name, required this.online, this.photoUrl});

  @override
  State<_ChatAvatar> createState() => _ChatAvatarState();
}

class _ChatAvatarState extends State<_ChatAvatar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Uint8List? _bytesFromDataUrl(String dataUrl) {
    final commaIndex = dataUrl.indexOf(',');
    if (!dataUrl.startsWith('data:image/') || commaIndex == -1) return null;
    try {
      return base64Decode(dataUrl.substring(commaIndex + 1));
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final url = widget.photoUrl?.trim() ?? '';
    Widget child;
    if (url.startsWith('data:image/')) {
      final bytes = _bytesFromDataUrl(url);
      child = bytes == null
          ? _fallback()
          : Image.memory(bytes, fit: BoxFit.cover);
    } else if (url.isNotEmpty) {
      child = Image.network(
        url,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _fallback(),
      );
    } else {
      child = _fallback();
    }

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: widget.online
                  ? [_chatMint, _chatPink]
                  : [_chatPink.withOpacity(0.35), _chatDeep.withOpacity(0.35)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: ClipOval(
            child: Container(
              width: 50,
              height: 50,
              color: _chatPink.withOpacity(0.12),
              child: child,
            ),
          ),
        ),
        if (widget.online)
          Positioned(
            right: -1,
            bottom: -1,
            child: AnimatedBuilder(
              animation: _pulseController,
              builder: (context, _) {
                final t = _pulseController.value;
                return Container(
                  width: 15,
                  height: 15,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        width: 10 + t * 6,
                        height: 10 + t * 6,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _chatMint.withOpacity((1 - t) * 0.5),
                        ),
                      ),
                      Container(
                        width: 9,
                        height: 9,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: _chatMint,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          )
        else
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: 13,
              height: 13,
              decoration: BoxDecoration(
                color: Colors.grey.shade400,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
            ),
          ),
      ],
    );
  }

  Widget _fallback() => Center(
    child: Text(
      widget.name.isEmpty ? '?' : widget.name[0].toUpperCase(),
      style: const TextStyle(
        color: _chatDeep,
        fontWeight: FontWeight.w900,
        fontSize: 18,
      ),
    ),
  );
}

class _LoadingSpinner extends StatelessWidget {
  const _LoadingSpinner();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: const [
        SizedBox(
          width: 44,
          height: 44,
          child: CircularProgressIndicator(color: _chatPink, strokeWidth: 3.5),
        ),
        SizedBox(height: 12),
        Text(
          'Loading…',
          style: TextStyle(color: _chatDeep, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

class _EmptyInboxState extends StatelessWidget {
  const _EmptyInboxState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeOut,
        builder: (context, value, child) => Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, (1 - value) * 12),
            child: child,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: _chatPink.withOpacity(0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.forum_rounded,
                size: 48,
                color: _chatPink,
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'No users available.',
              style: TextStyle(
                color: _chatDeep,
                fontWeight: FontWeight.w800,
                fontSize: 15,
              ),
            ),
          ],
        ),
      ),
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
    final chatRef = FirebaseFirestore.instance
        .collection('messages')
        .doc(widget.chatId);
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
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(64),
        child: Container(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [_chatPink, _chatDeep],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: _chatDeep.withOpacity(0.35),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            foregroundColor: Colors.white,
            title: Row(
              children: [
                CircleAvatar(
                  radius: 17,
                  backgroundColor: Colors.white24,
                  child: Text(
                    widget.otherName.isEmpty
                        ? '?'
                        : widget.otherName[0].toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    widget.otherName,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [_chatBg, Color(0xFFFFF1E9)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Column(
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
                  if (docs.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.chat_bubble_outline_rounded,
                            size: 42,
                            color: _chatPink.withOpacity(0.4),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'Say hello 👋',
                            style: TextStyle(
                              color: _chatDeep.withOpacity(0.7),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    );
                  }
                  return ListView.builder(
                    reverse: true,
                    padding: const EdgeInsets.all(16),
                    itemCount: docs.length,
                    itemBuilder: (context, index) {
                      final data = docs[index].data();
                      final mine = data['senderId'] == widget.me['id'];
                      return _BubbleEntrance(
                        key: ValueKey(docs[index].id),
                        mine: mine,
                        child: Align(
                          alignment: mine
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            constraints: BoxConstraints(
                              maxWidth: MediaQuery.of(context).size.width * 0.76,
                            ),
                            decoration: BoxDecoration(
                              gradient: mine
                                  ? const LinearGradient(
                                      colors: [_chatPink, _chatDeep],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    )
                                  : null,
                              color: mine ? null : Colors.white,
                              borderRadius: BorderRadius.only(
                                topLeft: const Radius.circular(18),
                                topRight: const Radius.circular(18),
                                bottomLeft: Radius.circular(mine ? 18 : 4),
                                bottomRight: Radius.circular(mine ? 4 : 18),
                              ),
                              border: mine
                                  ? null
                                  : Border.all(color: _chatPink.withOpacity(0.14)),
                              boxShadow: [
                                BoxShadow(
                                  color: (mine ? _chatDeep : _chatPink)
                                      .withOpacity(0.12),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Text(
                              data['text']?.toString() ?? '',
                              style: TextStyle(
                                color: mine ? Colors.white : Colors.black87,
                                fontWeight: FontWeight.w600,
                              ),
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
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: _chatPink.withOpacity(0.08),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: TextField(
                          controller: _controller,
                          minLines: 1,
                          maxLines: 4,
                          decoration: InputDecoration(
                            hintText: 'Type a message',
                            filled: true,
                            fillColor: Colors.white,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(20),
                              borderSide: BorderSide(
                                color: _chatPink.withOpacity(0.18),
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(20),
                              borderSide: BorderSide(
                                color: _chatPink.withOpacity(0.18),
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(20),
                              borderSide: const BorderSide(
                                color: _chatDeep,
                                width: 1.6,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _SendButton(onPressed: _send),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Small pop + slide entrance for each chat bubble.
class _BubbleEntrance extends StatefulWidget {
  final Widget child;
  final bool mine;
  const _BubbleEntrance({super.key, required this.child, required this.mine});

  @override
  State<_BubbleEntrance> createState() => _BubbleEntranceState();
}

class _BubbleEntranceState extends State<_BubbleEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  )..forward();
  late final Animation<double> _fade =
      CurvedAnimation(parent: _controller, curve: Curves.easeOut);
  late final Animation<Offset> _slide = Tween<Offset>(
    begin: Offset(widget.mine ? 0.12 : -0.12, 0),
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(position: _slide, child: widget.child),
    );
  }
}

class _SendButton extends StatefulWidget {
  final VoidCallback onPressed;
  const _SendButton({required this.onPressed});

  @override
  State<_SendButton> createState() => _SendButtonState();
}

class _SendButtonState extends State<_SendButton> {
  double _scale = 1;

  void _setPressed(bool pressed) =>
      setState(() => _scale = pressed ? 0.88 : 1);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      onTap: widget.onPressed,
      child: AnimatedScale(
        scale: _scale,
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOut,
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [_chatPink, _chatDeep],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: _chatDeep.withOpacity(0.4),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: const Icon(Icons.send_rounded, color: Colors.white, size: 20),
        ),
      ),
    );
  }
}