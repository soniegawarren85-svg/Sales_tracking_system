import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

String messageReceiptStatus(Map<String, dynamic> message) {
  if (message['readAt'] != null) return 'Seen';
  if (message['deliveredAt'] != null) return 'Delivered';
  return 'Sent';
}

Widget messageMetadata(
  BuildContext context,
  Map<String, dynamic> message, {
  required bool mine,
}) {
  final rawDate = message['createdAt'];
  final date = rawDate is Timestamp
      ? rawDate.toDate().toLocal()
      : rawDate is DateTime
      ? rawDate.toLocal()
      : null;
  if (date == null) return const SizedBox.shrink();
  final localizations = MaterialLocalizations.of(context);
  final textColor = mine ? Colors.white70 : Colors.blueGrey.shade500;
  return Padding(
    padding: const EdgeInsets.only(top: 5),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '${localizations.formatMediumDate(date)} • ${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(date))}',
          style: TextStyle(fontSize: 10, color: textColor),
        ),
        if (mine) ...[
          const SizedBox(width: 6),
          Text(
            messageReceiptStatus(message),
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: textColor,
            ),
          ),
        ],
      ],
    ),
  );
}

Future<void> markLatestMessagesDelivered({
  required FirebaseFirestore firestore,
  required Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> chats,
  required String readerId,
}) async {
  final pending = chats
      .where((chat) {
        final data = chat.data();
        return data['lastMessageSenderId'] != null &&
            data['lastMessageSenderId'] != readerId &&
            '${data['lastMessageId'] ?? ''}'.isNotEmpty &&
            data['lastMessageDeliveredAt'] == null;
      })
      .take(450)
      .toList();
  if (pending.isEmpty) return;

  final batch = firestore.batch();
  for (final chat in pending) {
    final data = chat.data();
    final deliveredAt = FieldValue.serverTimestamp();
    batch.set(chat.reference, {
      'lastMessageDeliveredAt': deliveredAt,
    }, SetOptions(merge: true));
    batch.set(
      chat.reference.collection('items').doc(data['lastMessageId'].toString()),
      {'deliveredAt': deliveredAt},
      SetOptions(merge: true),
    );
  }
  await batch.commit();
}

Future<void> markConversationMessagesRead({
  required FirebaseFirestore firestore,
  required Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> messages,
  required String readerId,
}) async {
  final pending = messages
      .where((message) {
        final data = message.data();
        return data['senderId'] != readerId && data['readAt'] == null;
      })
      .take(450)
      .toList();
  if (pending.isEmpty) return;

  final batch = firestore.batch();
  for (final message in pending) {
    final values = <String, dynamic>{'readAt': FieldValue.serverTimestamp()};
    if (message.data()['deliveredAt'] == null) {
      values['deliveredAt'] = FieldValue.serverTimestamp();
    }
    batch.set(message.reference, values, SetOptions(merge: true));
  }
  await batch.commit();
}
