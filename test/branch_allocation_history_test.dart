import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sales_tracking/widgets/branch_allocation_history.dart';

void main() {
  testWidgets('history defaults to today and uses a single-day picker', (
    tester,
  ) async {
    final db = FakeFirebaseFirestore();
    await db.doc('allocation_checklist/old').set({
      'staffId': 'branch',
      'status': 'Received',
      'createdAt': Timestamp.fromDate(
        DateTime.now().subtract(const Duration(days: 1)),
      ),
      'items': [
        {'name': 'Cookie', 'stock': 5},
      ],
    });
    await tester.pumpWidget(
      MaterialApp(
        home: AllocationHistoryDialog(branchId: 'branch', database: db),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('No matching allocations.'), findsOneWidget);
    expect(find.byType(InputChip), findsNothing);
    await tester.tap(find.byTooltip('Filter by date'));
    await tester.pumpAndSettle();
    expect(find.byType(DatePickerDialog), findsOneWidget);
    await tester.tap(find.byTooltip('Switch to input'));
    await tester.pumpAndSettle();
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    await tester.enterText(
      find.byType(TextField).last,
      '${yesterday.month}/${yesterday.day}/${yesterday.year}',
    );
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.text('Qty: 5 allocated units'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('legacy quantities show names, total and populated details', (
    tester,
  ) async {
    final db = FakeFirebaseFirestore();
    await db.doc('staff_requests/profile').set({
      'adminId': 'ADM-0001',
      'firstName': 'Ana',
      'lastName': 'Cruz',
    });
    await db.doc('branches/branch').set({'branchCode': 'BR-001'});
    await db.doc('sales_inventory/cookies').set({
      'name': 'Cookies',
      'items': [
        {'id': 'choc', 'name': 'Chocolate cookie', 'stock': 99},
        {'id': 'oat', 'name': 'Oat cookie', 'stock': 88},
      ],
    });
    await db.doc('sales_inventory/bundle').set({
      'name': 'Cookie box',
      'isBundle': true,
    });
    await db.doc('staff_inventory_history/legacy').set({
      'staffId': 'branch',
      'staffName': 'Sm dagupan',
      'type': 'assignment',
      'createdAt': Timestamp.now(),
      'assignedBy': 'ADM-0001',
      'quantities': {'cookies::0': 5, 'cookies::oat': 3, 'bundle::bundle': 2},
    });
    await tester.pumpWidget(
      MaterialApp(
        home: AllocationHistoryDialog(branchId: 'branch', database: db),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Allocated by: Ana Cruz'), findsOneWidget);
    expect(find.text('Admin ID: ADM-0001'), findsOneWidget);
    expect(find.text('Branch: Sm dagupan'), findsOneWidget);
    expect(find.text('Branch ID: BR-001'), findsOneWidget);
    expect(find.text('Qty: 10 allocated units'), findsOneWidget);
    final receivedBadge = find.ancestor(
      of: find.text('Received'),
      matching: find.byType(Chip),
    );
    expect(
      tester.getTopRight(receivedBadge).dx,
      closeTo(tester.getTopRight(find.byType(Card).first).dx - 18, 4),
    );
    expect(find.text('Pending'), findsNothing);
    final dialogBody = find.descendant(
      of: find.byType(Dialog),
      matching: find.byWidgetPredicate(
        (widget) => widget is SizedBox && widget.width == 680,
      ),
    );
    expect(tester.getSize(dialogBody).width, lessThanOrEqualTo(680));
    await tester.tap(find.text('View Items'));
    await tester.pumpAndSettle();
    expect(find.text('Categories (2)'), findsOneWidget);
    expect(find.text('Chocolate cookie'), findsOneWidget);
    expect(find.text('Item ID: choc'), findsOneWidget);
    expect(find.text('Qty: 5'), findsOneWidget);
    expect(find.text('Oat cookie'), findsOneWidget);
    await tester.tap(find.text('Bundle (1)'));
    await tester.pumpAndSettle();
    expect(find.text('Cookie box'), findsOneWidget);
    expect(find.text('Qty: 2'), findsOneWidget);
    await tester.tap(find.byTooltip('Close').last);
    await tester.pumpAndSettle();
    await db.doc('staff_inventory_history/new').set({
      'staffId': 'branch',
      'type': 'assignment',
      'createdAt': Timestamp.now(),
      'quantities': {'cookies::0': 7},
    });
    await tester.pumpAndSettle();
    expect(find.text('Qty: 7 allocated units'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  test(
    'delivery totals count bundle units once and preserve partial receipt',
    () {
      final groups = groupAllocations([
        {
          '_id': 'a',
          'deliveryId': 'delivery',
          'status': 'Received',
          'items': [
            {'name': 'Cookie', 'stock': 5},
          ],
        },
        {
          '_id': 'b',
          'deliveryId': 'delivery',
          'status': 'pending',
          'createdAt': Timestamp.now(),
          'isBundle': true,
          'bundleCount': 2,
          'items': [
            {'name': 'Cookie', 'quantity': 6},
          ],
        },
        {
          '_id': 'c',
          'deliveryId': 'delivery',
          'status': 'Received',
          'isCoffee': true,
          'name': 'Latte',
        },
      ]);
      expect(groups, hasLength(1));
      expect(groups.single['_quantity'], 7);
      expect(groups.single['_catalogCount'], 1);
      expect(groups.single['_complete'], false);
      expect(groups.single['_items'], hasLength(3));
    },
  );

  testWidgets('reported allocation shows issue badge and report details', (
    tester,
  ) async {
    final db = FakeFirebaseFirestore();
    await db.doc('allocation_checklist/reported').set({
      'staffId': 'branch',
      'status': 'Issue Reported',
      'name': 'Cookies',
      'issueReason': 'Five units arrived damaged',
      'reportedBy': 'staff-1',
      'reportedByName': 'Mia Staff',
      'reportedAt': Timestamp.now(),
      'createdAt': Timestamp.now(),
    });
    await tester.pumpWidget(
      MaterialApp(
        home: AllocationHistoryDialog(
          branchId: 'branch',
          database: db,
          pendingOnly: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Pending'), findsWidgets);
    expect(find.text('Issue Reported'), findsOneWidget);
    expect(find.text('View Items'), findsOneWidget);
    expect(
      tester.getCenter(find.text('View Items')).dx,
      greaterThan(tester.getCenter(find.text('View issue report')).dx),
    );
    await tester.tap(find.text('View issue report'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Five units arrived damaged'), findsOneWidget);
    expect(find.text('Reported by: Mia Staff'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'history filters records and opens searchable allocated details',
    (tester) async {
      final db = FakeFirebaseFirestore();
      await db.doc('staff_requests/admin').set({
        'firstName': 'Ana',
        'lastName': 'Cruz',
      });
      await db.doc('allocation_checklist/received').set({
        'staffId': 'branch',
        'staffName': 'Main',
        'allocatedBy': 'admin',
        'status': 'Received',
        'createdAt': Timestamp.now(),
        'items': [
          {'name': 'Cookie', 'stock': 5, 'price': 89},
        ],
      });
      await db.doc('staff_inventory_history/duplicate').set({
        'staffId': 'branch',
        'type': 'assignment',
        'createdAt': Timestamp.now(),
        'allocationId': 'received',
      });
      await db.doc('allocation_checklist/pending').set({
        'staffId': 'branch',
        'staffName': 'Other',
        'createdAt': Timestamp.now(),
        'status': 'pending',
        'items': [
          {'name': 'Cake', 'stock': 2},
        ],
      });
      await tester.pumpWidget(
        MaterialApp(
          home: AllocationHistoryDialog(branchId: 'branch', database: db),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Allocated by: Ana Cruz'), findsOneWidget);
      expect(find.text('Qty: 5 allocated units'), findsOneWidget);
      expect(find.text('View Items'), findsOneWidget);
      await tester.tap(find.text('View Items'));
      await tester.pumpAndSettle();
      expect(find.text('Cookie'), findsOneWidget);
      await tester.enterText(find.byType(TextField).last, 'missing');
      await tester.pumpAndSettle();
      expect(find.text('Cookie'), findsNothing);
      await tester.tap(find.byTooltip('Close').last);
      await tester.pumpAndSettle();
      await tester.pumpWidget(
        MaterialApp(
          home: AllocationHistoryDialog(
            key: const ValueKey('pending'),
            branchId: 'branch',
            database: db,
            pendingOnly: true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Branch: Other'), findsOneWidget);
      expect(find.text('Branch: Main'), findsNothing);
      await tester.enterText(find.byType(TextField), 'missing');
      await tester.pumpAndSettle();
      expect(find.text('No matching allocations.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
