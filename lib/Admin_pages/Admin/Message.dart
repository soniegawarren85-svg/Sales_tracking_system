import 'dart:async';
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
  String _search = '';
  String? _selectedId;
  Timer? _searchDebounce;

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

  void _handleSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 180), () {
      if (!mounted) return;
      setState(() => _search = value);
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

  Future<void> _deleteConversation(String chatId) async {
    await FirebaseFirestore.instance.collection('messages').doc(chatId).delete();
    if (mounted) {
      setState(() {
        _selectedId = null;
      });
    }
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
  void dispose() {
    _searchDebounce?.cancel();
    super.dispose();
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
            title: const Text(
              'Messages',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                letterSpacing: 0.2,
                fontSize: 17,
              ),
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
                          lastSeenAt: (data['lastLoginAt'] as Timestamp?)?.toDate(),
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
                      final items = rows.values.where((row) {
                        final query = _search.trim().toLowerCase();
                        return query.isEmpty ||
                            row.name.toLowerCase().contains(query) ||
                            row.role.toLowerCase().contains(query) ||
                            row.lastMessage.toLowerCase().contains(query);
                      }).toList()
                        ..sort((a, b) {
                          if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
                          final unreadCompare = b.unread.compareTo(a.unread);
                          if (unreadCompare != 0) return unreadCompare;
                          return a.name.compareTo(b.name);
                        });
                      if (items.isEmpty) {
                        return const _EmptyInboxState();
                      }
                      final selected = _selectedId == null
                          ? null
                          : rows[_selectedId];
                      return LayoutBuilder(
                        builder: (context, constraints) {
                          final compact = constraints.maxWidth < 760;
                          final contacts = _ContactsPanel(
                            items: items,
                            selectedId: _selectedId,
                            search: _search,
                            onSearchChanged: _handleSearchChanged,
                            onSelect: (row) => setState(() => _selectedId = row.id),
                            onPin: _togglePinned,
                          );
                          if (compact) {
                            return selected == null
                                ? contacts
                                : _ConversationPanel(
                                    key: ValueKey(selected.id),
                                    chatId: _chatId(selected.id),
                                    me: me,
                                    other: selected,
                                    onBack: () => setState(() => _selectedId = null),
                                    onDeleteConversation: () => _deleteConversation(
                                      _chatId(selected.id),
                                    ),
                                  );
                          }
                          return Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              children: [
                                SizedBox(width: 340, child: contacts),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: selected == null
                                      ? const _SelectConversationState()
                                      : _ConversationPanel(
                                          key: ValueKey(selected.id),
                                          chatId: _chatId(selected.id),
                                          me: me,
                                          other: selected,
                                          onDeleteConversation: () => _deleteConversation(
                                            _chatId(selected.id),
                                          ),
                                        ),
                                ),
                              ],
                            ),
                          );
                        },
                      );
                    },
                  );
                },
              ),
      ),
    );
  }
}

String _formatRelativeTime(DateTime? value) {
  if (value == null) return '';

  final now = DateTime.now();
  final diff = now.difference(value);

  if (diff.inDays >= 365) {
    final years = (diff.inDays / 365).floor();
    return years <= 1 ? '1 year ago' : '$years years ago';
  }
  if (diff.inDays >= 30) {
    final months = (diff.inDays / 30).floor();
    return months <= 1 ? '1 month ago' : '$months months ago';
  }
  if (diff.inDays >= 1) {
    return diff.inDays <= 1 ? '1 day ago' : '${diff.inDays} days ago';
  }
  if (diff.inHours >= 1) {
    return diff.inHours <= 1 ? '1 hour ago' : '${diff.inHours} hours ago';
  }
  if (diff.inMinutes >= 1) {
    return diff.inMinutes <= 1 ? '1 minute ago' : '${diff.inMinutes} minutes ago';
  }

  return 'just now';
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
  final DateTime? lastSeenAt;

  const _InboxRow({
    required this.id,
    required this.name,
    required this.role,
    required this.online,
    this.unread = 0,
    this.lastMessage = '',
    this.photoUrl,
    this.pinned = false,
    this.lastSeenAt,
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
      lastSeenAt: lastSeenAt,
    );
  }
}

class _ContactsPanel extends StatelessWidget {
  final List<_InboxRow> items;
  final String? selectedId;
  final String search;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<_InboxRow> onSelect;
  final ValueChanged<String> onPin;

  const _ContactsPanel({
    required this.items,
    required this.selectedId,
    required this.search,
    required this.onSearchChanged,
    required this.onSelect,
    required this.onPin,
  });

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(.62),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: _chatPink.withOpacity(.14)),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                onChanged: onSearchChanged,
                decoration: InputDecoration(
                  hintText: 'Find or start a conversation',
                  prefixIcon: const Icon(Icons.search_rounded),
                  filled: true,
                  fillColor: Colors.white,
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: _chatPink.withOpacity(.25)),
                  ),
                ),
              ),
            ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(10, 2, 10, 10),
                itemCount: items.length,
                separatorBuilder: (_, _) => const SizedBox(height: 6),
                itemBuilder: (context, index) {
                  final row = items[index];
                  return _InboxTile(
                    row: row,
                    selected: row.id == selectedId,
                    compact: true,
                    onPin: () => onPin(row.id),
                    onTap: () => onSelect(row),
                  );
                },
              ),
            ),
          ],
        ),
      );
}

class _SelectConversationState extends StatelessWidget {
  const _SelectConversationState();

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFFFFF7F9),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: _chatPink.withOpacity(.14)),
        ),
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.chat_bubble_outline_rounded, size: 54, color: _chatPink),
              SizedBox(height: 14),
              Text('Select a conversation to start chatting',
                  style: TextStyle(color: _chatDeep, fontWeight: FontWeight.w800, fontSize: 16)),
            ],
          ),
        ),
      );
}

class _ConversationPanel extends StatefulWidget {
  final Map<String, String> me;
  final _InboxRow other;
  final String chatId;
  final VoidCallback? onBack;
  final Future<void> Function()? onDeleteConversation;

  const _ConversationPanel({
    super.key,
    required this.me,
    required this.other,
    required this.chatId,
    this.onBack,
    this.onDeleteConversation,
  });

  @override
  State<_ConversationPanel> createState() => _ConversationPanelState();
}

class _ConversationPanelState extends State<_ConversationPanel> {
  final _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    _markThreadRead();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _markThreadRead() async {
    await FirebaseFirestore.instance
        .collection('messages')
        .doc(widget.chatId)
        .set(
          {'unreadBy': {widget.me['id']!: 0}},
          SetOptions(merge: true),
        );
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    _controller.clear();
    final chatRef = FirebaseFirestore.instance
        .collection('messages')
        .doc(widget.chatId);

    await chatRef.set(
      {
        'participantIds': [widget.me['id'], widget.other.id],
        'participantNames': {
          widget.me['id']: widget.me['name'],
          widget.other.id: widget.other.name,
        },
        'participantPhotos': {
          widget.me['id']: widget.me['photoUrl'] ?? '',
          widget.other.id: widget.other.photoUrl ?? '',
        },
        'lastMessage': text,
        'updatedAt': FieldValue.serverTimestamp(),
        'unreadBy': {widget.other.id: FieldValue.increment(1)},
      },
      SetOptions(merge: true),
    );

    await chatRef.collection('items').add({
      'senderId': widget.me['id'],
      'senderName': widget.me['name'],
      'text': text,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Widget build(BuildContext context) {
    final other = widget.other;
    final statusText = other.online ? 'Online' : _formatRelativeTime(other.lastSeenAt);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7F9),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _chatPink.withOpacity(.14)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: _chatPink.withOpacity(.14)),
              ),
            ),
            child: Row(
              children: [
                if (widget.onBack != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: IconButton(
                      onPressed: widget.onBack,
                      icon: const Icon(Icons.arrow_back_rounded, color: _chatDeep),
                    ),
                  ),
                _ChatAvatar(
                  name: other.name,
                  photoUrl: other.photoUrl,
                  online: other.online,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        other.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFFB5175D),
                          fontWeight: FontWeight.w800,
                          fontSize: 17,
                        ),
                      ),
                      if (statusText.isNotEmpty)
                        Text(
                          statusText,
                          style: TextStyle(
                            color: other.online ? _chatMint : Colors.white70,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert_rounded, color: Colors.white),
                  color: const Color(0xFF1F2430),
                  tooltip: 'Conversation actions',
                  onSelected: (value) async {
                    if (value == 'delete' && widget.onDeleteConversation != null) {
                      final shouldDelete = await showDialog<bool>(
                        context: context,
                        builder: (dialogContext) => AlertDialog(
                          backgroundColor: const Color(0xFF1F2430),
                          title: const Text(
                            'Delete conversation?',
                            style: TextStyle(color: Colors.white),
                          ),
                          content: Text(
                            'This will permanently delete the conversation with ${widget.other.name}.',
                            style: const TextStyle(color: Colors.white70),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(dialogContext, false),
                              child: const Text('Cancel', style: TextStyle(color: _chatPink)),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(dialogContext, true),
                              child: const Text('Delete', style: TextStyle(color: Colors.redAccent)),
                            ),
                          ],
                        ),
                      );

                      if (shouldDelete == true) {
                        await widget.onDeleteConversation!.call();
                      }
                    }
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem<String>(
                      value: 'delete',
                      child: Text('Delete conversation'),
                    ),
                  ],
                ),
              ],
            ),
          ),
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
                        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
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
  final bool selected;
  final bool compact;

  const _InboxTile({
    required this.row,
    required this.onTap,
    required this.onPin,
    this.selected = false,
    this.compact = true,
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
    final timeText = row.online ? 'Online' : _formatRelativeTime(row.lastSeenAt);

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
              color: widget.selected ? const Color(0xFFE9D5DC) : Colors.white,
              borderRadius: BorderRadius.circular(20),
              gradient: widget.selected
                  ? LinearGradient(
                      colors: [
                        const Color(0xFFF5DDE5),
                        const Color(0xFFEDCDD6),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    )
                  : row.pinned
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
                color: widget.selected
                    ? _chatDeep.withOpacity(0.28)
                    : row.pinned
                        ? _chatDeep.withOpacity(0.45)
                        : _chatPink.withOpacity(0.12),
                width: widget.selected ? 1.3 : row.pinned ? 1.4 : 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: _chatPink.withOpacity(widget.selected ? 0.12 : row.pinned ? 0.14 : 0.06),
                  blurRadius: widget.selected ? 16 : row.pinned ? 20 : 14,
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
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 15,
                                color: widget.selected ? const Color(0xFF2F1B23) : const Color(0xFF2A1A22),
                              ),
                            ),
                          ),
                          if (!widget.compact)
                            Text(
                              timeText,
                              style: TextStyle(
                                color: widget.selected ? Colors.white70 : Colors.grey.shade600,
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                              ),
                            ),
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 220),
                            transitionBuilder: (child, anim) => ScaleTransition(
                              scale: anim,
                              child: child,
                            ),
                            child: row.pinned
                                ? Padding(
                                    key: const ValueKey('pinned'),
                                    padding: const EdgeInsets.only(left: 4),
                                    child: Icon(
                                      Icons.push_pin_rounded,
                                      color: widget.selected ? Colors.white70 : _chatDeep,
                                      size: 16,
                                    ),
                                  )
                                : const SizedBox.shrink(key: ValueKey('unpinned')),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              row.lastMessage.isNotEmpty
                                  ? row.lastMessage
                                  : row.role,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: widget.selected ? Colors.white70 : Colors.grey.shade700,
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          if (widget.compact)
                            Text(
                              timeText,
                              style: TextStyle(
                                color: widget.selected ? Colors.white70 : Colors.grey.shade600,
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                              ),
                            ),
                        ],
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
  final String? otherPhotoUrl;

  const ChatThreadPage({
    super.key,
    required this.chatId,
    required this.me,
    required this.otherId,
    required this.otherName,
    this.otherPhotoUrl,
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
                _ChatAvatar(
                  name: widget.otherName,
                  photoUrl: widget.otherPhotoUrl,
                  online: false,
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
