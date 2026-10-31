import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sales_tracking/services/message_delivery.dart';
import 'package:sales_tracking/widgets/admin_message_preview.dart';

void main() {
  test('deactivated contacts are hidden and become visible when restored', () {
    final deactivated = {
      '_id': 'staff-1',
      'firstName': 'Jessica',
      'isDeactivated': true,
    };
    expect(messagePreviewContacts('admin-1', [deactivated], []), isEmpty);
    expect(
      messagePreviewContacts('admin-1', [
        {...deactivated, 'isDeactivated': false},
      ], []).single['name'],
      'Jessica',
    );
  });

  test('message receipt status progresses from sent to delivered to seen', () {
    expect(messageReceiptStatus({}), 'Sent');
    expect(messageReceiptStatus({'deliveredAt': Timestamp.now()}), 'Delivered');
    expect(
      messageReceiptStatus({
        'deliveredAt': Timestamp.now(),
        'readAt': Timestamp.now(),
      }),
      'Seen',
    );
  });

  test(
    'recipient delivery and read receipts update message documents',
    () async {
      final firestore = FakeFirebaseFirestore();
      final chat = firestore.collection('messages').doc('admin_staff');
      await chat.set({
        'participantIds': ['admin', 'staff'],
        'lastMessageId': 'message-1',
        'lastMessageSenderId': 'admin',
        'lastMessageDeliveredAt': null,
      });
      await chat.collection('items').doc('message-1').set({
        'senderId': 'admin',
        'text': 'Hello',
        'createdAt': Timestamp.now(),
      });

      await markLatestMessagesDelivered(
        firestore: firestore,
        chats: (await firestore.collection('messages').get()).docs,
        readerId: 'staff',
      );
      var message = (await chat.collection('items').doc('message-1').get())
          .data()!;
      expect(message['deliveredAt'], isA<Timestamp>());
      expect(messageReceiptStatus(message), 'Delivered');

      await markConversationMessagesRead(
        firestore: firestore,
        messages: (await chat.collection('items').get()).docs,
        readerId: 'staff',
      );
      message = (await chat.collection('items').doc('message-1').get()).data()!;
      expect(message['readAt'], isA<Timestamp>());
      expect(messageReceiptStatus(message), 'Seen');
    },
  );

  test('does not mark sent messages as read by their sender', () async {
    final firestore = FakeFirebaseFirestore();
    final reference = firestore
        .collection('messages')
        .doc('chat')
        .collection('items')
        .doc('message');
    await reference.set({'senderId': 'staff', 'text': 'Hello'});
    await markConversationMessagesRead(
      firestore: firestore,
      messages: (await reference.parent.get()).docs,
      readerId: 'staff',
    );
    expect((await reference.get()).data()?['readAt'], isNull);
  });
}
