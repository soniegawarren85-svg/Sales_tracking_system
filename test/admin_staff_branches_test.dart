import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sales_tracking/widgets/admin_staff_branches.dart';

void main() {
  testWidgets('branch staff picker hides accounts assigned to other branches', (
    tester,
  ) async {
    final db = FakeFirebaseFirestore();
    await db.collection('branches').doc('dagupan').set({
      'name': 'SM Dagupan',
      'staffIds': ['assigned'],
      'staffNames': ['Assigned Cashier'],
    });
    await db.collection('staff_requests').doc('assigned').set({
      'uid': 'assigned',
      'role': 'staff',
      'status': 'accepted',
      'firstName': 'Current',
      'lastName': 'Cashier',
      'branchIds': ['dagupan'],
    });
    await db.collection('staff_requests').doc('available').set({
      'uid': 'available',
      'role': 'staff',
      'status': 'accepted',
      'firstName': 'Available',
      'lastName': 'Cashier',
      'branchIds': [],
    });
    await db.collection('staff_requests').doc('elsewhere').set({
      'uid': 'elsewhere',
      'role': 'staff',
      'status': 'accepted',
      'firstName': 'Other',
      'lastName': 'Branch',
      'branchIds': ['sm-dagupan'],
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: AdminStaffBranches(firestore: db)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Staff in SM Dagupan'));
    await tester.pumpAndSettle();

    expect(find.text('Current Cashier'), findsOneWidget);
    expect(find.text('Available Cashier'), findsOneWidget);
    expect(find.text('Other Branch'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
