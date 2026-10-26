import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sales_tracking/services/cash_float_service.dart';

void main() {
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

    await CashFloatService.receive(
      firestore: firestore,
      requestId: requestId,
      actorId: 'staff-one',
      actorName: 'Branch Staff',
      actorRole: 'staff',
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
      amount: 300,
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
    expect(topUpDrawer['balance'], 2300);
    expect(topUpDrawer['dailyOpeningCash'], 2000);
    final budget =
        (await firestore.collection('staff_budget').doc('branch-one').get())
            .data()!;
    expect(budget['allocatedBudget'], 2300);
  });

  test('not-received report records reason without crediting drawer', () async {
    final firestore = FakeFirebaseFirestore();
    await firestore.collection('staff_requests').doc('admin-one').set({
      'role': 'admin',
      'status': 'accepted',
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
    final pending =
        (await firestore
                .collection(CashFloatService.collectionName)
                .doc(requestId)
                .get())
            .data()!;
    expect(pending['recipientRole'], 'admin');

    await CashFloatService.reportNotReceived(
      firestore: firestore,
      requestId: requestId,
      actorId: 'admin-one',
      actorName: 'Branch Admin',
      actorRole: 'admin',
      reason: 'Cash did not arrive',
      message: 'Courier did not reach the branch.',
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
  });
}
