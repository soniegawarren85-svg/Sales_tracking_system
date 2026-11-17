import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sales_tracking/widgets/allocation_checklist.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets('staff pending view includes older unaccepted allocations only', (
    tester,
  ) async {
    final db = FakeFirebaseFirestore();
    for (final status in ['pending', 'Received']) {
      await db.collection('allocation_checklist').add({
        'staffId': 'branch',
        'status': status,
        'name': '$status delivery',
        'createdAt': Timestamp.fromDate(
          DateTime.now().subtract(const Duration(days: 2)),
        ),
      });
    }
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AllocationChecklistButton(
            scopeIds: const ['branch'],
            database: db,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Checklist'));
    await tester.pumpAndSettle();
    expect(find.textContaining('pending delivery'), findsOneWidget);
    expect(find.textContaining('Received delivery'), findsNothing);
    expect(find.byTooltip('Filter by date range'), findsNothing);
    expect(find.textContaining('pending delivery'), findsOneWidget);
    expect(find.textContaining('Received delivery'), findsNothing);
    expect(find.text('Confirm Received'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'staff checklist action buttons stay beside each other on mobile',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final db = FakeFirebaseFirestore();
      await db.collection('allocation_checklist').add({
        'staffId': 'branch',
        'status': 'pending',
        'name': 'Bundle Cakes',
        'isBundle': true,
        'bundleCount': 2,
        'createdAt': Timestamp.now(),
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AllocationChecklistButton(
              scopeIds: const ['branch'],
              database: db,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Checklist'));
      await tester.pumpAndSettle();
      final reportButton = tester.getRect(find.text('Report Issue'));
      final confirmButton = tester.getRect(find.text('Confirm Received'));

      expect(reportButton.center.dy, closeTo(confirmButton.center.dy, 1));
      expect(reportButton.right, lessThan(confirmButton.left));
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('staff completed checklist dates by actual receive timestamp', (
    tester,
  ) async {
    final db = FakeFirebaseFirestore();
    final now = DateTime.now();
    await db.doc('allocation_checklist/received-yesterday').set({
      'kind': 'incoming',
      'staffId': 'branch',
      'status': 'Received',
      'name': 'Yesterday allocation',
      'createdAt': Timestamp.fromDate(now.subtract(const Duration(days: 1))),
      'assignedAt': Timestamp.fromDate(now.subtract(const Duration(days: 1))),
      'confirmedAt': Timestamp.fromDate(now),
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AllocationChecklistButton(
            scopeIds: const ['branch'],
            database: db,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Checklist'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Complete Items'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Yesterday allocation'), findsOneWidget);
    expect(find.textContaining('Received:'), findsOneWidget);
    await tester.tap(find.byTooltip('Filter by date range'));
    await tester.pumpAndSettle();
    expect(find.byType(DateRangePickerDialog), findsOneWidget);
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Assigned:'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('staff checklist and returns share a row on tablet', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(768, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AllocationChecklistButton(
            scopeIds: const ['branch'],
            database: FakeFirebaseFirestore(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final checklist = tester.getRect(find.text('Checklist'));
    final returns = tester.getRect(find.text('Returns'));
    expect(checklist.center.dy, closeTo(returns.center.dy, 1));
    expect(checklist.right, lessThan(returns.left));
    expect(tester.takeException(), isNull);
  });
  testWidgets('older returns remain visible and batch acceptance spans dates', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'lastRole': 'admin',
      'lastUserId': 'admin',
    });
    final db = FakeFirebaseFirestore();
    await db.doc('staff_requests/admin').set({
      'role': 'admin',
      'firstName': 'Ana',
    });
    for (var day = 1; day <= 2; day++) {
      await db.doc('allocation_checklist/old$day').set({
        'kind': 'return',
        'status': 'Awaiting Admin Confirmation',
        'name': 'Cookie',
        'quantity': 1,
        'staffId': 'branch',
        'createdAt': Timestamp.fromDate(
          DateTime.now().subtract(Duration(days: day)),
        ),
      });
    }
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AllocationChecklistButton(
            scopeIds: const [],
            isAdmin: true,
            database: db,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Returns'));
    await tester.pumpAndSettle();
    expect(find.text('Pending Returned'), findsOneWidget);
    expect(find.byTooltip('Filter by date range'), findsOneWidget);
    for (var index = 0; index < 2; index++) {
      if (find.text('Accept').evaluate().isEmpty) {
        await tester.tap(find.textContaining('branch').first);
        await tester.pumpAndSettle();
      }
      await tester.ensureVisible(find.text('Accept'));
      await tester.tap(find.text('Accept'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Proceed'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
    }
    for (var day = 1; day <= 2; day++) {
      expect(
        (await db.doc('allocation_checklist/old$day').get()).data()!['status'],
        'Return Completed',
      );
    }
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'admin return date filter applies to pending and completed tabs',
    (tester) async {
      final db = FakeFirebaseFirestore();
      final today = DateUtils.dateOnly(DateTime.now());
      await db.doc('allocation_checklist/recent').set({
        'kind': 'return',
        'status': 'Awaiting Admin Confirmation',
        'name': 'Pistachio',
        'quantity': 2,
        'branchName': 'Recent Branch',
        'staffId': 'recent',
        'createdAt': Timestamp.fromDate(today.add(const Duration(hours: 10))),
      });
      await db.doc('allocation_checklist/older').set({
        'kind': 'return',
        'status': 'Awaiting Admin Confirmation',
        'name': 'Og Cookies',
        'quantity': 1,
        'branchName': 'Older Branch',
        'staffId': 'older',
        'createdAt': Timestamp.fromDate(
          today.subtract(const Duration(days: 10)),
        ),
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AllocationChecklistButton(
              scopeIds: const [],
              isAdmin: true,
              database: db,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Returns'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Recent Branch'), findsOneWidget);
      expect(find.textContaining('Older Branch'), findsOneWidget);

      await tester.tap(find.byTooltip('Filter by date range'));
      await tester.pumpAndSettle();
      tester
          .state<NavigatorState>(find.byType(Navigator).last)
          .pop(DateTimeRange(start: today, end: today));
      await tester.pumpAndSettle();
      expect(find.textContaining('Recent Branch'), findsOneWidget);
      expect(find.textContaining('Older Branch'), findsNothing);

      await tester.tap(find.text('Completed Return'));
      await tester.pumpAndSettle();
      expect(find.text('No matching return batches.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('admin accepts return and sees success after Proceed', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'lastRole': 'admin',
      'lastUserId': 'emergency-admin',
      'adminId': 'ADM-0001',
    });
    final db = FakeFirebaseFirestore();
    await db.doc('staff_requests/account').set({
      'adminId': 'ADM-0001',
      'role': 'admin',
      'firstName': 'Ana',
      'lastName': 'Cruz',
    });
    await db.doc('allocation_checklist/returned').set({
      'kind': 'return',
      'createdAt': Timestamp.fromDate(DateUtils.dateOnly(DateTime.now())),
      'status': 'Awaiting Admin Confirmation',
      'name': 'Cookie',
      'quantity': 2,
      'staffId': 'branch',
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AllocationChecklistButton(
            scopeIds: const [],
            isAdmin: true,
            database: db,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Returns'));
    await tester.pumpAndSettle();
    expect(find.text('Pending Returned'), findsOneWidget);
    await tester.tap(find.textContaining('branch').first);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Accept'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Accept'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Proceed'));
    await tester.pumpAndSettle();
    expect(find.text('Return accepted'), findsOneWidget);
    expect(find.textContaining('accepted successfully'), findsOneWidget);
    final saved = (await db.doc('allocation_checklist/returned').get()).data()!;
    expect(saved['status'], 'Return Completed');
    expect(saved['confirmedByName'], 'Ana Cruz');
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.text('Accept'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('Super Admin reports return issue and completes with details', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({
      'lastRole': 'super_admin',
      'lastUserId': 'super-admin',
      'superAdminId': 'Spr-001',
    });
    final db = FakeFirebaseFirestore();
    await db.doc('allocation_checklist/returned').set({
      'kind': 'return',
      'createdAt': Timestamp.fromDate(DateTime(2026, 11, 16, 21, 0)),
      'status': 'Awaiting Super Admin Confirmation',
      'name': 'Cheese Cakes',
      'quantity': 15,
      'staffId': 'branch',
      'branchId': 'branch',
      'batchId': 'batch',
      'submittedBy': 'admin',
      'submittedByName': 'Jomalyn',
    });
    await db.doc('allocation_checklist/returned-49').set({
      'kind': 'return',
      'createdAt': Timestamp.fromDate(DateTime(2026, 11, 16, 21, 0)),
      'status': 'Awaiting Super Admin Confirmation',
      'name': 'Cheese Cakes',
      'quantity': 49,
      'staffId': 'branch',
      'branchId': 'branch',
      'batchId': 'batch',
      'submittedBy': 'admin',
      'submittedByName': 'Jomalyn',
    });
    await db.doc('allocation_checklist/returned-1').set({
      'kind': 'return',
      'createdAt': Timestamp.fromDate(DateTime(2026, 11, 16, 21, 0)),
      'status': 'Awaiting Super Admin Confirmation',
      'name': 'Red Velvet',
      'quantity': 1,
      'staffId': 'branch',
      'branchId': 'branch',
      'batchId': 'batch',
      'submittedBy': 'admin',
      'submittedByName': 'Jomalyn',
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AllocationChecklistButton(
            scopeIds: const [],
            isAdmin: true,
            isSuperAdmin: true,
            database: db,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Returns'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(ExpansionTile).first);
    await tester.pumpAndSettle();
    expect(find.text('Return records • 3 items'), findsOneWidget);
    expect(find.text('Reject'), findsNothing);
    await tester.ensureVisible(find.text('Report Issue'));
    await tester.pump();
    await tester.tap(find.text('Report Issue'));
    await tester.pump();
    expect(find.text('Report issue with return'), findsOneWidget);
    await tester.tap(find.byType(DropdownButtonFormField<String>).last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Damaged').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.enterText(find.byType(TextFormField).first, '1');
    await tester.enterText(
      find.byType(TextFormField).last,
      'Packaging was open.',
    );
    await tester.tap(
      find.widgetWithText(OutlinedButton, 'Add this item report'),
    );
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.byType(DropdownButtonFormField<String>).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Cheese Cakes · Qty 49').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byType(DropdownButtonFormField<String>).last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Extra').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.enterText(find.byType(TextFormField).first, '10');
    await tester.enterText(find.byType(TextFormField).last, 'Ten are damaged.');
    await tester.tap(
      find.widgetWithText(OutlinedButton, 'Add this item report'),
    );
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.byType(DropdownButtonFormField<String>).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Red Velvet · Qty 1').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byType(DropdownButtonFormField<String>).last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Damaged').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.enterText(find.byType(TextFormField).first, '1');
    await tester.enterText(find.byType(TextFormField).last, 'One missing.');
    await tester.tap(
      find.widgetWithText(OutlinedButton, 'Add this item report'),
    );
    await tester.pump(const Duration(milliseconds: 300));

    await tester.ensureVisible(
      find.widgetWithText(FilledButton, 'Submit all reports'),
    );
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Submit all reports'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(find.text('Issue reported'), findsOneWidget);

    final saved = (await db.doc('allocation_checklist/returned').get()).data()!;
    expect(saved['status'], 'Return Completed');
    expect(saved['superAdminIssueType'], 'Damaged');
    expect(saved['superAdminIssueQuantity'], 1);
    expect(saved['superAdminIssueComment'], 'Packaging was open.');
    expect(saved['declineReason'], isNull);
    final saved49 = (await db.doc('allocation_checklist/returned-49').get())
        .data()!;
    expect(saved49['status'], 'Return Completed');
    expect(saved49['superAdminIssueType'], 'Extra');
    expect(saved49['superAdminIssueQuantity'], 10);
    expect(saved49['superAdminIssueComment'], 'Ten are damaged.');
    final saved1 = (await db.doc('allocation_checklist/returned-1').get())
        .data()!;
    expect(saved1['status'], 'Return Completed');
    expect(saved1['superAdminIssueType'], 'Damaged');
    expect(saved1['superAdminIssueQuantity'], 1);
    expect(saved1['superAdminIssueComment'], 'One missing.');
    expect(
      (await db.doc('activity_logs/return_issue_returned').get())
          .data()?['action'],
      'return_issue_reported',
    );
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Completed'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('branch').first);
    await tester.pumpAndSettle();
    expect(find.textContaining('Done · Issue reported'), findsOneWidget);
    expect(find.text('Issue reported'), findsNWidgets(3));
    expect(find.textContaining('Damaged · 1 of 15 returned'), findsOneWidget);
    expect(find.textContaining('Packaging was open.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  for (final width in [360.0, 768.0]) {
    testWidgets('admin checklist at $width watches returns across branches', (
      tester,
    ) async {
      final db = FakeFirebaseFirestore();
      await db.doc('allocation_checklist/return').set({
        'kind': 'return',
        'createdAt': Timestamp.fromDate(DateUtils.dateOnly(DateTime.now())),
        'status': 'Awaiting Admin Confirmation',
        'name': 'Damaged cookie',
        'quantity': 2,
        'staffId': 'branch',
      });
      await db.doc('allocation_checklist/incoming').set({
        'status': 'Awaiting Confirmation',
        'name': 'Delivery',
        'staffId': 'branch',
      });
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AllocationChecklistButton(
              scopeIds: const [],
              isAdmin: true,
              database: db,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Returns'));
      await tester.pumpAndSettle();
      expect(find.text('Confirm Received'), findsNothing);
      expect(find.text('Pending Returned'), findsOneWidget);
      expect(find.text('Completed Return'), findsOneWidget);
      expect(find.text('Incoming Items'), findsNothing);
      expect(find.textContaining('Pending Confirmation'), findsNothing);
      expect(find.textContaining('Review returned items'), findsOneWidget);
      expect(find.textContaining('Waiting Admin Confirmation'), findsNothing);
      expect(find.text('Accept'), findsNothing);
      await tester.tap(find.text('branch'));
      await tester.pumpAndSettle();
      expect(find.text('Accept'), findsOneWidget);
      expect(find.text('Report Issue'), findsOneWidget);
      expect(
        tester.getCenter(find.text('View')).dy,
        greaterThan(tester.getCenter(find.text('branch')).dy),
      );
      expect(tester.getCenter(find.text('View')).dx, greaterThan(0));
      await tester.ensureVisible(
        find.widgetWithText(OutlinedButton, 'Report Issue'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Report Issue'));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('Submit report'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('A reason is required'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('View'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('View'));
      await tester.pumpAndSettle();
      final details = find.ancestor(
        of: find.text('Returned items'),
        matching: find.byType(Dialog),
      );
      expect(
        find.descendant(of: details, matching: find.text('Accept')),
        findsNothing,
      );
      expect(
        find.descendant(of: details, matching: find.text('Report Issue')),
        findsNothing,
      );
      await db.doc('allocation_checklist/return').update({
        'status': 'Return Completed',
      });
      await tester.pumpAndSettle();
      expect(find.text('Pending Returned'), findsOneWidget);
      expect(find.text('Accept'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('Close returned items'));
      await tester.pumpAndSettle();
      expect(find.text('Accept'), findsNothing);
      await tester.tap(find.byTooltip('Close checklist'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Returns'), findsOneWidget);
    });
  }

  testWidgets(
    'branch checklist records a separate reason and quantity per item',
    (tester) async {
      final db = FakeFirebaseFirestore();
      for (final row in [
        {
          'staffId': 'branch',
          'status': 'pending',
          'name': 'Cookies',
          'targetDocId': 'target',
          'items': [
            {'id': 'chocolate', 'name': 'Chocolate', 'stock': 3},
            {'id': 'red-velvet', 'name': 'Red Velvet', 'stock': 2},
          ],
        },
        {
          'staffId': 'branch',
          'status': 'pending',
          'name': 'Latte',
          'isCoffee': true,
        },
        {'staffId': 'other', 'status': 'pending', 'name': 'Other branch'},
        {'staffId': 'branch', 'status': 'accepted', 'name': 'Old delivery'},
      ]) {
        await db.collection('allocation_checklist').add({
          ...row,
          'createdAt': Timestamp.fromDate(DateUtils.dateOnly(DateTime.now())),
        });
      }
      await db.doc('staff_requests/staff-one').set({
        'role': 'staff',
        'status': 'accepted',
        'staffId': 'STF-001',
        'firstName': 'Test',
        'lastName': 'Staff',
        'branchIds': ['branch'],
      });
      await db.doc('staff_inventory/target').set({
        'staffId': 'branch',
        'items': [
          {'id': 'chocolate', 'name': 'Chocolate', 'stock': 0},
          {'id': 'red-velvet', 'name': 'Red Velvet', 'stock': 0},
        ],
      });
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString('lastRole', 'staff');
      await preferences.setString('lastUserId', 'staff-one');
      await tester.binding.setSurfaceSize(const Size(420, 780));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AllocationChecklistButton(
              scopeIds: const ['branch'],
              database: db,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Checklist'), findsOneWidget);
      expect(find.text('Returns'), findsOneWidget);
      await tester.tap(find.text('Checklist'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Chocolate'), findsOneWidget);
      expect(find.text('Other branch'), findsNothing);
      expect(find.text('All items'), findsNothing);
      expect(find.text('Bundle'), findsNothing);
      await tester.enterText(find.byType(TextField).first, 'Chocolate');
      await tester.pumpAndSettle();
      expect(find.text('Chocolate — 3'), findsOneWidget);
      await tester.ensureVisible(find.text('Confirm Received'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm Received'));
      await tester.pumpAndSettle();
      expect(find.text('Receive allocated items?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Confirm Received'), findsOneWidget);
      await tester.ensureVisible(find.text('Report Issue'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Report Issue'));
      await tester.pumpAndSettle();
      expect(find.byType(CheckboxListTile), findsNothing);
      expect(find.text('Add this item report'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField).first, '1');
      await tester.enterText(find.byType(TextFormField).last, 'One missing.');
      await tester.tap(find.text('Add this item report'));
      await tester.pumpAndSettle();
      expect(find.text('Reports added: 1'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('incoming-item-chocolate-0')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Red Velvet · Qty 2').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<String>).last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Damaged').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).first, '1');
      await tester.enterText(find.byType(TextFormField).last, 'Sira ang box.');
      await tester.tap(find.text('Add this item report'));
      await tester.pumpAndSettle();
      expect(find.text('Reports added: 2'), findsOneWidget);
      await tester.tap(find.text('Submit all reports'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final received =
          (await db.doc('staff_inventory/target').get()).data()!['items']
              as List;
      expect(received[0]['stock'], 2);
      expect(received[1]['stock'], 1);
      final deliveryDoc =
          (await db
                  .collection('allocation_checklist')
                  .where('name', isEqualTo: 'Cookies')
                  .get())
              .docs
              .single;
      final savedChecklist = deliveryDoc.data();
      final reports = savedChecklist['issueReports'] as List;
      expect(reports[0]['issueType'], 'Missing');
      expect(reports[0]['comment'], 'One missing.');
      expect(reports[1]['issueType'], 'Damaged');
      expect(reports[1]['comment'], 'Sira ang box.');
      final returnRecord =
          (await db
                  .doc(
                    'allocation_checklist/${deliveryDoc.id}_issue_return_red-velvet',
                  )
                  .get())
              .data()!;
      expect(returnRecord['quantity'], 1);
      expect(returnRecord['returnReason'], 'Sira ang box.');
      await tester.tap(find.text('Complete Items'));
      await tester.pumpAndSettle();
      expect(find.text('Received inventory details'), findsOneWidget);
      expect(find.text('REPORTED'), findsNWidgets(2));
      expect(find.text('−1 Missing'), findsOneWidget);
      expect(find.text('−1 Damaged'), findsOneWidget);
      expect(find.text('Allocated'), findsNWidgets(2));
      expect(find.text('Received'), findsNWidgets(2));
      expect(find.text('One missing.'), findsOneWidget);
      expect(find.text('Sira ang box.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
