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
        'loginAt': '2026-09-28T08:00:00',
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
}
