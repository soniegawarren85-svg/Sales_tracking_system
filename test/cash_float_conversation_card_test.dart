import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sales_tracking/widgets/cash_float_conversation_card.dart';

void main() {
  testWidgets('branch cash float message offers receive and report actions', (
    tester,
  ) async {
    final firestore = FakeFirebaseFirestore();
    await firestore.collection('cash_float_requests').doc('request-1').set({
      'branchName': 'Dagupan',
      'amount': 1500,
      'requestType': 'starting',
      'status': 'pending',
      'recipientRole': 'admin',
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: CashFloatConversationCard(
              requestId: 'request-1',
              chatId: 'Spr-001_ADM-001',
              role: 'admin',
              firestore: firestore,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Cash float'), findsOneWidget);
    expect(find.text('Dagupan · Starting cash'), findsOneWidget);
    expect(find.text('₱1,500.00'), findsOneWidget);
    expect(find.text('Receive'), findsOneWidget);
    expect(find.text('Report'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Super Admin sees the status but not branch response actions', (
    tester,
  ) async {
    final firestore = FakeFirebaseFirestore();
    await firestore.collection('cash_float_requests').doc('request-2').set({
      'branchName': 'Dagupan',
      'amount': 1300,
      'requestType': 'starting',
      'status': 'reported',
      'recipientRole': 'admin',
      'reportReason': 'Amount is short',
      'shortfallAmount': 200,
      'receivedAmount': 1300,
      'reportedByName': 'Branch Admin',
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: CashFloatConversationCard(
              requestId: 'request-2',
              chatId: 'Spr-001_ADM-001',
              role: 'super_admin',
              firestore: firestore,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Shortfall'), findsOneWidget);
    expect(find.textContaining('₱200.00'), findsOneWidget);
    expect(find.text('₱1,300.00'), findsOneWidget);
    expect(
      find.textContaining('added to the branch cash drawer'),
      findsOneWidget,
    );
    expect(find.text('Receive'), findsNothing);
    expect(find.text('Report'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cash float card reflows without overflow at mobile width', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final firestore = FakeFirebaseFirestore();
    await firestore.collection('cash_float_requests').doc('request-3').set({
      'branchName': 'Dagupan Main Branch',
      'amount': 1500,
      'requestType': 'starting',
      'status': 'pending',
      'recipientRole': 'admin',
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SafeArea(
            child: ListView(
              children: [
                CashFloatConversationCard(
                  requestId: 'request-3',
                  chatId: 'Spr-001_ADM-001',
                  role: 'admin',
                  firestore: firestore,
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Receive'), findsOneWidget);
    expect(find.text('Report'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('admin can submit a cash float report without dialog errors', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'lastRole': 'admin',
      'lastUserId': 'admin-one',
    });
    final firestore = FakeFirebaseFirestore();
    await firestore.collection('staff_requests').doc('admin-one').set({
      'role': 'admin',
      'status': 'accepted',
      'adminId': 'ADM-001',
    });
    await firestore
        .collection('cash_float_requests')
        .doc('request-report')
        .set({
          'branchId': 'branch-one',
          'branchName': 'Dagupan',
          'amount': 500,
          'requestType': 'additional',
          'status': 'pending',
          'recipientRole': 'admin',
          'senderId': 'super-admin',
          'senderName': 'Super Admin',
        });
    await firestore.collection('messages').doc('ADM-001_super-admin').set({
      'participantIds': ['ADM-001', 'super-admin'],
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CashFloatConversationCard(
            requestId: 'request-report',
            chatId: 'ADM-001_super-admin',
            role: 'admin',
            firestore: firestore,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Report'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Send report'));
    await tester.pumpAndSettle();

    final request =
        (await firestore
                .collection('cash_float_requests')
                .doc('request-report')
                .get())
            .data();
    expect(request?['status'], 'reported');
    expect(request?['reportReason'], 'Cash did not arrive');
    expect(tester.takeException(), isNull);
  });
}
