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
    expect(find.byType(DropdownButtonFormField<String>), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('admin staff section only shows assigned staff and branch', (
    tester,
  ) async {
    final db = FakeFirebaseFirestore();
    await db.collection('branches').doc('dagupan').set({
      'name': 'SM Dagupan',
      'staffIds': ['cashier', 'branch-admin'],
      'staffNames': ['Dagupan Cashier', 'Branch Admin'],
    });
    await db.collection('branches').doc('lingayen').set({
      'name': 'Lingayen',
      'staffIds': ['other-cashier'],
      'staffNames': ['Other Cashier'],
    });
    await db.collection('staff_requests').doc('cashier').set({
      'uid': 'cashier',
      'role': 'staff',
      'status': 'accepted',
      'firstName': 'Dagupan',
      'lastName': 'Cashier',
      'branchIds': ['dagupan'],
    });
    await db.collection('staff_requests').doc('branch-admin').set({
      'uid': 'branch-admin',
      'adminId': 'ADM-001',
      'role': 'admin',
      'status': 'accepted',
      'firstName': 'Branch',
      'lastName': 'Admin',
      'branchIds': ['dagupan'],
    });
    await db.collection('staff_requests').doc('other-cashier').set({
      'uid': 'other-cashier',
      'role': 'staff',
      'status': 'accepted',
      'firstName': 'Other',
      'lastName': 'Cashier',
      'branchIds': ['lingayen'],
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AdminStaffBranches(
            firestore: db,
            branchId: 'dagupan',
            allowAssignment: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Staff in SM Dagupan'), findsOneWidget);
    expect(find.text('Staff in Lingayen'), findsNothing);
    expect(find.text('1 assigned staff'), findsOneWidget);
    expect(find.text('View & assign staff'), findsNothing);
    await tester.tap(find.text('Staff in SM Dagupan'));
    await tester.pumpAndSettle();
    expect(find.text('Dagupan Cashier'), findsOneWidget);
    expect(find.text('Branch Admin'), findsNothing);
    expect(find.text('Other Cashier'), findsNothing);
    expect(find.byType(CheckboxListTile), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('super admin can filter assignment choices by role', (
    tester,
  ) async {
    final db = FakeFirebaseFirestore();
    await db.collection('branches').doc('dagupan').set({
      'name': 'SM Dagupan',
      'staffIds': <String>[],
      'staffNames': <String>[],
    });
    await db.collection('staff_requests').doc('cashier').set({
      'uid': 'cashier',
      'role': 'staff',
      'status': 'accepted',
      'firstName': 'Available',
      'lastName': 'Cashier',
      'branchIds': <String>[],
    });
    await db.collection('staff_requests').doc('admin').set({
      'uid': 'admin',
      'adminId': 'ADM-002',
      'status': 'accepted',
      'firstName': 'Available',
      'lastName': 'Admin',
      'branchIds': <String>[],
    });
    await db.collection('staff_requests').doc('legacy-admin-001').set({
      'uid': 'legacy-admin-001',
      'adminId': 'ADM-001',
      'role': 'admin',
      'firstName': 'Warren',
      'lastName': 'Admin',
      'branchIds': <String>[],
    });
    await db.collection('staff_requests').doc('pending-admin').set({
      'uid': 'pending-admin',
      'adminId': 'ADM-003',
      'role': 'admin',
      'status': 'pending',
      'firstName': 'Pending',
      'lastName': 'Admin',
      'branchIds': <String>[],
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AdminStaffBranches(firestore: db, includeAdmins: true),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Staff in SM Dagupan'));
    await tester.pumpAndSettle();

    expect(find.text('Available Cashier • Cashier'), findsOneWidget);
    expect(find.text('Available Admin • Admin'), findsNothing);
    expect(find.text('Select role to assign'), findsOneWidget);

    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Admin').last);
    await tester.pumpAndSettle();

    expect(find.text('Available Admin • Admin'), findsOneWidget);
    expect(find.text('Warren Admin • Admin'), findsOneWidget);
    expect(find.text('Pending Admin • Admin'), findsNothing);
    expect(find.text('Available Cashier • Cashier'), findsNothing);
    await tester.tap(find.text('Warren Admin • Admin'));
    await tester.pumpAndSettle();

    expect(
      (await db.collection('branches').doc('dagupan').get())
          .data()?['staffIds'],
      contains('legacy-admin-001'),
    );
    final warren =
        (await db.collection('staff_requests').doc('legacy-admin-001').get())
            .data()!;
    expect(warren['branchIds'], contains('dagupan'));
    expect(tester.takeException(), isNull);
  });
}
