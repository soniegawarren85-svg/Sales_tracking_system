import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sales_tracking/services/allocation_checklist_service.dart';
import 'package:sales_tracking/services/checklist_status.dart';
import 'package:sales_tracking/widgets/return_batch_cards.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  late FakeFirebaseFirestore db;
  late AllocationChecklistService service;
  setUp(() async {
    db = FakeFirebaseFirestore();
    service = AllocationChecklistService(db);
    for (var i = 0; i < 2; i++) {
      await db.doc('allocation_checklist/r$i').set({
        'kind': 'return',
        'status': ChecklistStatus.awaitingAdmin,
        'name': 'Cookie $i',
        'quantity': 1,
        'staffId': 'branch',
        'branchId': 'branch',
        'submittedBy': 'staff',
        'submittedByName': 'Staff Name',
        'submittedByStaffId': 'STF-001',
        'createdAt': Timestamp.fromDate(DateTime(2026, 10, 4, 17, 42)),
        'returnSourceCollection': 'stock_adjustments',
        'returnSourceId': 'reduce',
      });
    }
    await db.doc('stock_adjustments/reduce').set({
      'checklistReturnedQuantities': {'item': 2},
    });
    await db.doc('staff_inventory/stock').set({'stock': 8});
  });

  test(
    'decline requires reason, is terminal, and never restores refunded stock',
    () async {
      await expectLater(
        service.decideReturns(
          ['r0', 'r1'],
          accept: false,
          actorId: 'admin',
          actorName: 'Admin',
          reason: ' ',
        ),
        throwsArgumentError,
      );
      expect(
        (await db.doc('allocation_checklist/r0').get()).data()!['status'],
        ChecklistStatus.awaitingAdmin,
      );
      expect(
        await service.decideReturns(
          ['r0', 'r1'],
          accept: false,
          actorId: 'admin',
          actorName: 'Admin Name',
          reason: ' Items were not delivered. ',
        ),
        2,
      );
      for (var i = 0; i < 2; i++) {
        final data = (await db.doc('allocation_checklist/r$i').get()).data()!;
        expect(data['status'], ChecklistStatus.returnDeclined);
        expect(data['declineReason'], 'Items were not delivered.');
        expect(data['declinedByName'], 'Admin Name');
        expect(ChecklistStatus.returnOpen(data), false);
      }
      expect(
        await service.decideReturns(
          ['r0', 'r1'],
          accept: true,
          actorId: 'admin',
          actorName: 'Admin',
        ),
        0,
      );
      expect((await db.doc('staff_inventory/stock').get()).data()!['stock'], 8);
      expect(
        (await db.doc('stock_adjustments/reduce').get())
            .data()!['checklistReturnedQuantities'],
        {'item': 2},
      );
    },
  );

  test(
    'batch acceptance is idempotent and updates legacy bundle custody',
    () async {
      await db.doc('allocation_checklist/r1').update({
        'isBundle': true,
        'returnSourceCollection': 'staff_inventory',
        'returnSourceId': 'bundle',
      });
      await db.doc('staff_inventory/bundle').set({
        'bundleInstances': [
          {'returnId': 'r1', 'status': 'return_pending'},
          {'returnId': 'other', 'status': 'return_pending'},
        ],
      });
      expect(
        await service.decideReturns(
          ['r0', 'r1'],
          accept: true,
          actorId: 'admin',
          actorName: 'Admin',
        ),
        2,
      );
      expect(
        await service.decideReturns(
          ['r0', 'r1'],
          accept: true,
          actorId: 'admin',
          actorName: 'Admin',
        ),
        0,
      );
      expect(
        (await db.doc('allocation_checklist/r0').get()).data()!['confirmedAt'],
        isA<Timestamp>(),
      );
      final instances =
          (await db.doc('staff_inventory/bundle').get())
                  .data()!['bundleInstances']
              as List;
      expect(instances[0]['status'], 'returned');
      expect(instances[1]['status'], 'return_pending');
    },
  );

  testWidgets('return card uses the submitter identity, not branch metadata', (
    tester,
  ) async {
    final db = FakeFirebaseFirestore();
    await db.doc('staff_requests/admin-auth').set({
      'adminId': 'ADM-007',
      'firstName': 'Jomalyn',
      'lastName': 'Ignacio',
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReturnItemCard(
            data: {
              'name': 'Cheese Cakes',
              'quantity': 1,
              'itemDisplayId': 'CA-006',
              'submittedBy': 'admin-auth',
              'submittedByName': 'Jomalyn Ignacio',
              'sourceStaffName': 'Lingayen',
              'branchName': 'Lingayen',
            },
            db: db,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Staff: Jomalyn Ignacio'), findsOneWidget);
    expect(find.text('Staff ID: ADM-007'), findsOneWidget);
    expect(find.text('Branch: Lingayen'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('Super Admin issue report completes return with details', () async {
    final changed = await service.reportReturnIssue(
      id: 'r0',
      actorId: 'super-admin',
      actorName: 'Super Admin',
      issueType: 'Damaged',
      issueQuantity: 1,
      comment: 'Packaging was open.',
    );

    expect(changed, isTrue);
    final record = (await db.doc('allocation_checklist/r0').get()).data()!;
    expect(record['status'], ChecklistStatus.completed);
    expect(record['confirmedByName'], 'Super Admin');
    expect(record['superAdminIssueType'], 'Damaged');
    expect(record['superAdminIssueQuantity'], 1);
    expect(record['superAdminIssueComment'], 'Packaging was open.');
    expect(record['declineReason'], isNull);
    expect(
      (await db.doc('activity_logs/return_issue_r0').get()).data()?['action'],
      'return_issue_reported',
    );
    expect(
      await service.reportReturnIssue(
        id: 'r0',
        actorId: 'super-admin',
        actorName: 'Super Admin',
        issueType: 'Damaged',
        issueQuantity: 1,
      ),
      isFalse,
    );
  });

  test(
    'Super Admin can report different issues for multiple returned items',
    () async {
      await db.doc('allocation_checklist/r0').update({'quantity': 15});
      await db.doc('allocation_checklist/r1').update({'quantity': 49});

      expect(
        await service.reportReturnIssues(
          actorId: 'super-admin',
          actorName: 'Super Admin',
          reports: [
            {
              'returnId': 'r0',
              'issueType': 'Missing',
              'issueQuantity': 5,
              'comment': 'Five missing.',
            },
            {
              'returnId': 'r1',
              'issueType': 'Damaged',
              'issueQuantity': 10,
              'comment': 'Damaged packaging.',
            },
          ],
        ),
        2,
      );

      final first = (await db.doc('allocation_checklist/r0').get()).data()!;
      final second = (await db.doc('allocation_checklist/r1').get()).data()!;
      expect(first['superAdminIssueType'], 'Missing');
      expect(first['superAdminIssueQuantity'], 5);
      expect(first['superAdminIssueComment'], 'Five missing.');
      expect(first['status'], ChecklistStatus.completed);
      expect(second['superAdminIssueType'], 'Damaged');
      expect(second['superAdminIssueQuantity'], 10);
      expect(second['superAdminIssueComment'], 'Damaged packaging.');
      expect(second['status'], ChecklistStatus.completed);
      expect(
        (await db.doc('activity_logs/return_issue_r0').get())
            .data()?['details']['issueQuantity'],
        5,
      );
      expect(
        (await db.doc('activity_logs/return_issue_r1').get())
            .data()?['details']['issueQuantity'],
        10,
      );
    },
  );

  testWidgets('decision buttons show progress and prevent duplicate taps', (
    tester,
  ) async {
    final done = Completer<void>();
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReturnDecisionButtons(
            onDecision: (accept) async {
              calls++;
              await done.future;
            },
          ),
        ),
      ),
    );
    await tester.tap(find.text('Accept'));
    await tester.pumpAndSettle();
    expect(find.text('Accept returned items?'), findsOneWidget);
    expect(calls, 0);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(calls, 0);
    await tester.tap(find.text('Accept'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Proceed'));
    await tester.pump();
    expect(find.text('Processing...'), findsOneWidget);
    await tester.tap(find.text('Accept'));
    expect(calls, 1);
    done.complete();
    await tester.pumpAndSettle();
    expect(find.text('Processing...'), findsNothing);
  });

  for (final width in [360.0, 768.0]) {
    testWidgets(
      'staff sees accepted and declined marks with reason at $width',
      (tester) async {
        await tester.binding.setSurfaceSize(Size(width, 850));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: db.collection('allocation_checklist').snapshots(),
                builder: (context, snapshot) => ReturnBatchList(
                  docs: snapshot.data?.docs ?? [],
                  itemBuilder: (doc) => ReturnItemCard(data: doc.data()),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byIcon(Icons.hourglass_top_rounded), findsOneWidget);
        await service.decideReturns(
          ['r0', 'r1'],
          accept: true,
          actorId: 'admin',
          actorName: 'Admin',
        );
        await tester.pumpAndSettle();
        expect(find.text('Done · Return accepted'), findsOneWidget);
        final icon = tester.widget<Icon>(
          find.byIcon(Icons.check_circle_outline),
        );
        final header = tester.widget<Container>(
          find
              .ancestor(
                of: find.text('Done · Return accepted'),
                matching: find.byType(Container),
              )
              .first,
        );
        expect(icon.color, Colors.white);
        expect(header.color, Colors.green.shade700);
        // A later batch receives a different decision.
        await db.doc('allocation_checklist/r2').set({
          'kind': 'return',
          'status': ChecklistStatus.awaitingAdmin,
          'staffId': 'branch',
          'submittedBy': 'staff',
          'name': 'Bundle Cakes',
          'createdAt': Timestamp.fromDate(DateTime(2026, 10, 4, 18)),
        });
        await service.decideReturns(
          ['r2'],
          accept: false,
          actorId: 'admin',
          actorName: 'Admin',
          reason: 'Please deliver the physical items.',
        );
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text('View reason'),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.ensureVisible(
          find.widgetWithText(OutlinedButton, 'View reason'),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('View reason'));
        await tester.pumpAndSettle();
        expect(
          find.textContaining('Please deliver the physical items.'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
