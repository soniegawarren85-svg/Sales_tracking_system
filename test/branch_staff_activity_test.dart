import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:sales_tracking/widgets/branch_staff_activity_dialog.dart';

void main() {
  testWidgets('staff sees both concurrent sessions and only their account', (
    tester,
  ) async {
    final db = FakeFirebaseFirestore();
    for (final id in ['tablet', 'phone', 'other']) {
      await db.collection('staff_login_sessions').doc(id).set({
        'userId': id == 'other' ? 'other-user' : 'staff-user',
        'staffId': 'STF-001',
        'staffName': id,
        'branchId': 'branch',
        'loginAt': DateTime.now().toIso8601String(),
        'logoutAt': null,
        'ipAddress': '192.168.1.1',
      });
    }
    await tester.pumpWidget(
      MaterialApp(
        home: BranchStaffActivityDialog(
          branchId: '',
          branchName: '',
          userId: 'staff-user',
          firestore: db,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('tablet'), findsOneWidget);
    expect(find.text('phone'), findsOneWidget);
    expect(find.text('other'), findsNothing);
    expect(find.byTooltip('Close activity logs'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('empty session history does not fabricate previous logins', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: StaffSessionTable(sessions: [])),
      ),
    );
    expect(
      find.text('No recorded login sessions for this branch.'),
      findsOneWidget,
    );
  });

  testWidgets('branch logs include every assigned account and identify role', (
    tester,
  ) async {
    final db = FakeFirebaseFirestore();
    await db.collection('branches').doc('branch').set({
      'name': 'Branch',
      'staffIds': ['staff-user', 'admin-user'],
    });
    final now = DateTime.now();
    await db.collection('staff_login_sessions').doc('staff').set({
      'userId': 'staff-user',
      'staffId': 'STF-001',
      'staffName': 'Cashier One',
      'type': 'staff',
      'role': 'staff',
      'loginAt': Timestamp.fromDate(now),
    });
    await db.collection('staff_login_sessions').doc('admin').set({
      'userId': 'admin-user',
      'staffId': 'ADM-001',
      'staffName': 'Admin One',
      'type': 'admin',
      'role': 'admin',
      'loginAt': Timestamp.fromDate(now),
    });
    await db.collection('staff_login_sessions').doc('outsider').set({
      'userId': 'other-user',
      'staffName': 'Other Branch',
      'role': 'staff',
      'loginAt': Timestamp.fromDate(now),
    });

    await tester.pumpWidget(
      MaterialApp(
        home: BranchStaffActivityDialog(
          branchId: 'branch',
          branchName: 'Branch',
          firestore: db,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Cashier One'), findsOneWidget);
    expect(find.text('Admin One'), findsOneWidget);
    expect(find.text('Staff'), findsNWidgets(2));
    expect(find.text('Admin'), findsOneWidget);
    expect(find.text('Other Branch'), findsNothing);

    await tester.enterText(find.byType(TextField).first, 'admin');
    await tester.pumpAndSettle();
    expect(find.text('Admin One'), findsOneWidget);
    expect(find.text('Cashier One'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
