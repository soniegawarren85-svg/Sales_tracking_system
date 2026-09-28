import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'profile_avatar.dart';

List<Map<String, dynamic>> messagePreviewContacts(
  String me,
  Iterable<Map<String, dynamic>> accounts,
  Iterable<Map<String, dynamic>> chats,
) {
  final contacts = <String, Map<String, dynamic>>{};
  for (final account in accounts) {
    final id = '${account['_id']}';
    if (id == me ||
        account['adminId'] == me ||
        account['isDeleted'] == true ||
        ['rejected', 'disabled'].contains('${account['status']}'.toLowerCase()))
      continue;
    final full = '${account['firstName'] ?? ''} ${account['lastName'] ?? ''}'
        .trim();
    contacts[id] = {
      ...account,
      'name':
          account['name'] ??
          account['fullName'] ??
          (full.isEmpty ? 'Staff' : full),
      'lastMessage': 'Start a conversation',
      'updated': 0,
    };
  }
  for (final chat in chats) {
    for (final id
        in (chat['participantIds'] as List? ?? [])
            .map((id) => '$id')
            .where((id) => id != me)) {
      if (!contacts.containsKey(id)) continue;
      final timestamp = chat['updatedAt'];
      contacts[id] = {
        ...contacts[id]!,
        'lastMessage': chat['lastMessage'] ?? 'Start a conversation',
        'updated': timestamp is Timestamp
            ? timestamp.millisecondsSinceEpoch
            : 0,
      };
    }
  }
  return (contacts.values.toList()..sort((a, b) {
        final recent = (b['updated'] as int).compareTo(a['updated'] as int);
        return recent != 0 ? recent : '${a['name']}'.compareTo('${b['name']}');
      }))
      .take(5)
      .toList();
}

class AdminMessagePreview extends StatefulWidget {
  const AdminMessagePreview({
    super.key,
    required this.adminId,
    required this.onOpen,
  });
  final String adminId;
  final ValueChanged<String> onOpen;
  @override
  State<AdminMessagePreview> createState() => _AdminMessagePreviewState();
}

class _AdminMessagePreviewState extends State<AdminMessagePreview> {
  late final accounts = FirebaseFirestore.instance
      .collection('staff_requests')
      .snapshots();
  late final chats = FirebaseFirestore.instance
      .collection('messages')
      .where('participantIds', arrayContains: widget.adminId)
      .snapshots();
  @override
  Widget build(BuildContext context) =>
      StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: accounts,
        builder: (context, people) =>
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: chats,
              builder: (context, messages) {
                if (people.hasError || messages.hasError)
                  return const Center(child: Text('Unable to load contacts.'));
                if (!people.hasData || !messages.hasData)
                  return const Center(child: CircularProgressIndicator());
                final rows = messagePreviewContacts(
                  widget.adminId,
                  people.data!.docs.map(
                    (doc) => {...doc.data(), '_id': doc.id},
                  ),
                  messages.data!.docs.map((doc) => doc.data()),
                );
                if (rows.isEmpty)
                  return const Center(child: Text('No available contacts.'));
                return ListView.separated(
                  itemCount: rows.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final row = rows[index];
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: ProfileAvatar(data: row),
                      title: Text('${row['name']}'),
                      subtitle: Text(
                        '${row['lastMessage']}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => widget.onOpen('${row['_id']}'),
                    );
                  },
                );
              },
            ),
      );
}
