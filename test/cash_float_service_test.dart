import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sales_tracking/services/cash_drawer_service.dart';
import 'package:sales_tracking/services/cash_float_service.dart';

void main() {
  test('starting cash can change until the branch records a sale', () {
    expect(
      CashFloatService.canChangeStartingCash(hasSalesToday: false),
      isTrue,
    );
    expect(
      CashFloatService.canChangeStartingCash(hasSalesToday: true),
      isFalse,
    );
  });

  test(
    'starting cash changes apply immediately when sales have not started',
    () async {
      final firestore = FakeFirebaseFirestore();
      final now = DateTime(2026, 11, 7, 18, 30);
      await firestore.collection('branches').doc('branch-one').set({
        'openingMinutes': 9 * 60,
      });
      await firestore.collection('staff_cash_drawer').doc('branch-one').set({
        'drawerDate': CashDrawerService.dayKey(now),
        'balance': 1500,
        'openingCash': 1500,
        'dailyOpeningCash': 1500,
      });
      await firestore.collection('staff_requests').doc('staff-one').set({
        'role': 'staff',
        'status': 'accepted',
        'branchIds': ['branch-one'],
      });

      await CashFloatService.applyImmediateStartingCashChange(
        firestore: firestore,
        branchId: 'branch-one',
        branchName: 'Dagupan',
        amount: 1700,
        actorId: 'super-admin',
        actorName: 'Super Admin',
        actorRole: 'admin',
        now: now,
      );

      final drawer =
          (await firestore
                  .collection('staff_cash_drawer')
                  .doc('branch-one')
                  .get())
              .data()!;
      expect(drawer['balance'], 1700);
      expect(drawer['openingCash'], 1700);
      expect(drawer['dailyOpeningCash'], 1700);
      final budget =
          (await firestore.collection('staff_budget').doc('branch-one').get())
              .data()!;
      expect(budget['allocatedBudget'], 1700);
    },
  );

  test(
    'cash float amounts enforce action-specific minimum and maximum',
    () async {
      final firestore = FakeFirebaseFirestore();
      for (final (amount, startingCash) in [
        (499.0, false),
        (5001.0, false),
        (1499.0, true),
        (5001.0, true),
      ]) {
        await expectLater(
          CashFloatService.createRequest(
            firestore: firestore,
            branchId: 'branch-one',
            branchName: 'Dagupan',
            senderId: 'super-admin',
            senderName: 'Super Admin',
            amount: amount,
            startingCash: startingCash,
          ),
          throwsA(isA<ArgumentError>()),
        );
      }
    },
  );

  test(
    'starting cash change cannot be received after branch sales begin',
    () async {
      final firestore = FakeFirebaseFirestore();
      await firestore.collection('staff_requests').doc('staff-one').set({
        'role': 'staff',
        'status': 'accepted',
        'branchIds': ['branch-one'],
      });
      await firestore.collection('branches').doc('branch-one').set({
        'openingMinutes': 1440,
      });
      final requestId = await CashFloatService.createRequest(
        firestore: firestore,
        branchId: 'branch-one',
        branchName: 'Dagupan',
        senderId: 'super-admin',
        senderName: 'Super Admin',
        amount: 2000,
        startingCash: true,
        startingCashChange: true,
      );
      await firestore.collection('completed_sales').add({
        'branchId': 'branch-one',
        'timestamp': Timestamp.fromDate(DateTime.now()),
      });

      await expectLater(
        CashFloatService.receive(
          firestore: firestore,
          requestId: requestId,
          actorId: 'staff-one',
          actorName: 'Branch Staff',
          actorRole: 'staff',
        ),
        throwsA(isA<StateError>()),
      );
      expect(
        (await firestore
                .collection('staff_cash_drawer')
                .doc('branch-one')
                .get())
            .exists,
        isFalse,
      );
    },
  );

  test('cash float credits once after staff receipt confirmation', () async {
    final firestore = FakeFirebaseFirestore();
    await firestore.collection('staff_requests').doc('staff-one').set({
      'role': 'staff',
      'status': 'accepted',
      'branchIds': ['branch-one'],
    });
    final requestId = await CashFloatService.createRequest(
      firestore: firestore,
      branchId: 'branch-one',
      branchName: 'Dagupan',
      senderId: 'super-admin',
      senderName: 'Super Admin',
      amount: 2000,
      startingCash: true,
    );
    final request =
        (await firestore
                .collection(CashFloatService.collectionName)
                .doc(requestId)
                .get())
            .data()!;
    expect(request['status'], 'pending');
    expect(request['recipientRole'], 'staff');
    final chatId = (request['chatIds'] as List).single as String;
    final sentMessage =
        (await firestore
                .collection('messages')
                .doc(chatId)
                .collection('items')
                .get())
            .docs
            .single
            .data();
    expect(sentMessage['type'], 'cash_float');
    expect(sentMessage['cashFloatRequestId'], requestId);
    final chat = (await firestore.collection('messages').doc(chatId).get())
        .data()!;
    expect(chat['unreadBy'][request['recipientIds'][0]], 1);

    await CashFloatService.receive(
      firestore: firestore,
      requestId: requestId,
      actorId: 'staff-one',
      actorName: 'Branch Staff',
      actorRole: 'staff',
      chatId: chatId,
    );
    final drawer =
        (await firestore
                .collection('staff_cash_drawer')
                .doc('branch-one')
                .get())
            .data()!;
    expect(drawer['balance'], 2000);
    expect(drawer['dailyOpeningCash'], 2000);
    final received =
        (await firestore
                .collection(CashFloatService.collectionName)
                .doc(requestId)
                .get())
            .data()!;
    expect(received['status'], 'received');
    expect(received['receivedById'], 'staff-one');
    expect(received['receivedByRole'], 'staff');
    final receiptMessages =
        (await firestore
                .collection('messages')
                .doc(chatId)
                .collection('items')
                .get())
            .docs
            .map((doc) => doc.data())
            .toList();
    expect(receiptMessages.last['type'], 'cash_float_update');
    expect(receiptMessages.last['text'], contains('confirmed receipt'));
    final receiptChat =
        (await firestore.collection('messages').doc(chatId).get()).data()!;
    expect(receiptChat['unreadBy']['super-admin'], 1);

    await expectLater(
      CashFloatService.receive(
        firestore: firestore,
        requestId: requestId,
        actorId: 'staff-one',
        actorName: 'Branch Staff',
        actorRole: 'staff',
      ),
      throwsA(isA<StateError>()),
    );
    final unchanged =
        (await firestore
                .collection('staff_cash_drawer')
                .doc('branch-one')
                .get())
            .data()!;
    expect(unchanged['balance'], 2000);

    final topUpId = await CashFloatService.createRequest(
      firestore: firestore,
      branchId: 'branch-one',
      branchName: 'Dagupan',
      senderId: 'super-admin',
      senderName: 'Super Admin',
      amount: 500,
      startingCash: false,
    );
    await CashFloatService.receive(
      firestore: firestore,
      requestId: topUpId,
      actorId: 'staff-one',
      actorName: 'Branch Staff',
      actorRole: 'staff',
    );
    final topUpDrawer =
        (await firestore
                .collection('staff_cash_drawer')
                .doc('branch-one')
                .get())
            .data()!;
    expect(topUpDrawer['balance'], 2500);
    expect(topUpDrawer['dailyOpeningCash'], 2000);
    final budget =
        (await firestore.collection('staff_budget').doc('branch-one').get())
            .data()!;
    expect(budget['allocatedBudget'], 2500);
  });

  test('not-received report records reason without crediting drawer', () async {
    final firestore = FakeFirebaseFirestore();
    await firestore.collection('staff_requests').doc('admin-one').set({
      'role': 'admin',
      'status': 'accepted',
      'adminId': 'ADM-001',
      'branchIds': ['branch-one'],
    });
    final requestId = await CashFloatService.createRequest(
      firestore: firestore,
      branchId: 'branch-one',
      branchName: 'Dagupan',
      senderId: 'super-admin',
      senderName: 'Super Admin',
      amount: 500,
      startingCash: false,
    );
    final chatId =
        ((await firestore
                            .collection(CashFloatService.collectionName)
                            .doc(requestId)
                            .get())
                        .data()!['chatIds']
                    as List)
                .single
            as String;
    final pending =
        (await firestore
                .collection(CashFloatService.collectionName)
                .doc(requestId)
                .get())
            .data()!;
    expect(pending['recipientRole'], 'admin');
    expect(pending['recipientIds'], ['ADM-001']);
    final chat = (await firestore.collection('messages').doc(chatId).get())
        .data()!;
    expect(chat['participantIds'], ['ADM-001', 'super-admin']);

    await CashFloatService.reportNotReceived(
      firestore: firestore,
      requestId: requestId,
      actorId: 'admin-one',
      actorName: 'Branch Admin',
      actorRole: 'admin',
      reason: 'Cash did not arrive',
      message: 'Courier did not reach the branch.',
      chatId: chatId,
      messageActorId: 'ADM-001',
    );
    final reported =
        (await firestore
                .collection(CashFloatService.collectionName)
                .doc(requestId)
                .get())
            .data()!;
    expect(reported['status'], 'reported');
    expect(reported['reportReason'], 'Cash did not arrive');
    expect(reported['reportMessage'], 'Courier did not reach the branch.');
    expect(
      (await firestore.collection('staff_cash_drawer').doc('branch-one').get())
          .exists,
      isFalse,
    );
    final reportReply =
        (await firestore
                .collection('messages')
                .doc(chatId)
                .collection('items')
                .get())
            .docs
            .last
            .data();
    expect(reportReply['type'], 'cash_float_update');
    expect(reportReply['senderId'], 'ADM-001');
    expect(reportReply['text'], contains('Cash did not arrive'));
  });

  test('shortfall report credits only the amount actually received', () async {
    final firestore = FakeFirebaseFirestore();
    await firestore.collection('staff_requests').doc('admin-one').set({
      'role': 'admin',
      'status': 'accepted',
      'adminId': 'ADM-001',
      'branchIds': ['branch-one'],
    });
    final requestId = await CashFloatService.createRequest(
      firestore: firestore,
      branchId: 'branch-one',
      branchName: 'Dagupan',
      senderId: 'Spr-001',
      senderName: 'Super Admin',
      amount: 1500,
      startingCash: true,
    );
    final request =
        (await firestore
                .collection(CashFloatService.collectionName)
                .doc(requestId)
                .get())
            .data()!;
    final chatId = (request['chatIds'] as List).single as String;

    await CashFloatService.reportNotReceived(
      firestore: firestore,
      requestId: requestId,
      actorId: 'admin-one',
      actorName: 'Branch Admin',
      actorRole: 'admin',
      reason: 'Amount is short',
      shortfallAmount: 200,
      message: 'Envelope was missing cash.',
      chatId: chatId,
    );

    final drawer =
        (await firestore
                .collection('staff_cash_drawer')
                .doc('branch-one')
                .get())
            .data()!;
    expect(drawer['balance'], 1300);
    expect(drawer['dailyOpeningCash'], 1300);
    final budget =
        (await firestore.collection('staff_budget').doc('branch-one').get())
            .data()!;
    expect(budget['allocatedBudget'], 1300);
    final reported =
        (await firestore
                .collection(CashFloatService.collectionName)
                .doc(requestId)
                .get())
            .data()!;
    expect(reported['status'], 'reported');
    expect(reported['shortfallAmount'], 200);
    expect(reported['receivedAmount'], 1300);
    final reply =
        (await firestore
                .collection('messages')
                .doc(chatId)
                .collection('items')
                .get())
            .docs
            .last
            .data();
    expect(reply['type'], 'cash_float_update');
    expect(reply['text'], contains('₱1,300.00'));
    expect(reply['text'], contains('₱200.00'));
  });
}
