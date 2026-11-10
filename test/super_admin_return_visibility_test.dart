import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sales_tracking/services/checklist_status.dart';
import 'package:sales_tracking/widgets/allocation_checklist.dart';

void main() {
  testWidgets('Super Admin sees returns forwarded by a branch Admin', (
    tester,
  ) async {
    final db = FakeFirebaseFirestore();
    await db.collection('allocation_checklist').doc('return-1').set({
      'status': 'awaiting_super_admin',
      'forwardedBy': 'admin-1',
      'forwardedByName': 'Branch Admin',
      'forwardedAt': Timestamp.now(),
      'createdAt': Timestamp.now(),
      'branchId': 'branch-1',
      'branchName': 'Lingayen',
      'name': 'Pistachio Dubai Chewyy',
      'quantity': 2,
      'submittedByName': 'Branch Cashier',
    });
    await db.collection('allocation_checklist').doc('return-2').set({
      'kind': 'return_record',
      'status': 'Awaiting Admin Confirmation',
      'forwardedBy': 'admin-1',
      'forwardedByName': 'Branch Admin',
      'forwardedAt': Timestamp.now(),
      'createdAt': Timestamp.now(),
      'branchId': 'branch-1',
      'branchName': 'Lingayen',
      'name': 'Dubai Brownie',
      'quantity': 1,
      'submittedByName': 'Branch Cashier',
    });
    final returnData =
        (await db.collection('allocation_checklist').doc('return-1').get())
            .data()!;
    expect(ChecklistStatus.isReturnRecord(returnData), isTrue);
    expect(ChecklistStatus.returnPendingForSuperAdmin(returnData), isTrue);
    final legacyForwarded =
        (await db.collection('allocation_checklist').doc('return-2').get())
            .data()!;
    expect(ChecklistStatus.returnPendingForSuperAdmin(legacyForwarded), isTrue);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AllocationChecklistButton(
            scopeIds: const [],
            database: db,
            isAdmin: true,
            isSuperAdmin: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Returns'));
    await tester.pumpAndSettle();

    expect(
      find.text('Confirm returns submitted by branch admins'),
      findsOneWidget,
    );
    expect(find.text('Lingayen'), findsOneWidget);
    await tester.tap(find.text('Lingayen'));
    await tester.pumpAndSettle();

    expect(find.text('Pistachio Dubai Chewyy'), findsOneWidget);
    expect(find.text('Dubai Brownie'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
