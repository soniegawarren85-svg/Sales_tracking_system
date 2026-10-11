import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sales_tracking/services/branch_report_data.dart';
import 'package:sales_tracking/services/checklist_status.dart';
import 'package:sales_tracking/widgets/allocation_checklist.dart';
import 'package:sales_tracking/widgets/branch_allocation_table.dart';
import 'package:sales_tracking/widgets/branch_report_dialog.dart';
import 'package:sales_tracking/widgets/report_item_history.dart';
import 'package:sales_tracking/widgets/return_batch_cards.dart';
import 'package:sales_tracking/widgets/staff_performance_panel.dart';

void main() {
  test('current inventory excludes archived, deleted and expired history', () {
    final today = DateUtils.dateOnly(DateTime.now());
    Map<String, dynamic> item(
      String id, {
      bool deleted = false,
      DateTime? expiry,
    }) => {
      'id': id,
      'publicId': id,
      'name': id,
      'price': 50,
      'costPrice': 25,
      'quantity': 10,
      'stock': 10,
      'startingStock': 10,
      'isDeleted': deleted,
      if (expiry != null) 'expirationDate': expiry.toIso8601String(),
    };
    final active = item('active');
    final deleted = item('deleted', deleted: true);
    final expired = item(
      'expired',
      expiry: today.subtract(const Duration(days: 1)),
    );
    final removed = item('removed');
    final data = BranchReportData({
      'sales_inventory': [
        {
          '_id': 'cat',
          'items': [active, deleted, expired],
          'removedItems': [removed],
        },
      ],
      'staff_inventory': [
        {
          '_id': 'a',
          'staffId': 'b',
          'sourceInventoryId': 'cat',
          'assignedAt': today.subtract(const Duration(days: 2)),
          'items': [
            active,
            {...deleted, 'isDeleted': false},
            expired,
            removed,
          ],
        },
      ],
      'staff_inventory_history': [
        {
          'staffId': 'b',
          'createdAt': today,
          'items': [removed, deleted, expired],
        },
      ],
    });
    expect(data.currentInventory('b', today).map((r) => r['name']), ['active']);
    expect(
      data
          .items('b', today, today.add(const Duration(days: 1)))
          .any((r) => r['name'] == 'removed'),
      isTrue,
    );
  });

  testWidgets(
    'branch table orders dates, totals stock investment and size prices',
    (tester) async {
      final today = DateTime.now();
      final row = <String, dynamic>{
        'id': 'CO-1',
        'name': 'Cookie',
        'type': 'Categories',
        'allocationDate': today,
        'starting': 50,
        'added': 50,
        'remaining': 80,
        'costPrice': 25,
        'profit': 500,
        'sold': 20,
        'sales': 1000,
        'price': 50,
      };
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BranchAllocationTable(
              rows: [row],
              beverages: false,
              actions: (_) => const Icon(Icons.history),
            ),
          ),
        ),
      );
      final table = tester.widget<DataTable>(find.byType(DataTable));
      expect((table.columns[1].label as Text).data, 'Allocation date');
      final total = table.rows.last.cells
          .map((c) => (c.child as Text).data)
          .toList();
      expect(
        total,
        containsAll([
          'Total',
          '50',
          '80',
          '₱2500.00',
          '₱500.00',
          '20',
          '₱1000.00',
        ]),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BranchAllocationTable(
              rows: [
                {
                  ...row,
                  'type': 'Beverages',
                  'sizes': [
                    {'name': 'Small', 'priceDelta': 60},
                    {'name': 'Medium', 'priceDelta': 80},
                    {'name': 'Large', 'priceDelta': 100},
                  ],
                },
              ],
              beverages: true,
              actions: (_) => const SizedBox(),
            ),
          ),
        ),
      );
      expect(find.text('Starting allocation'), findsNothing);
      expect(find.text('Remaining allocation'), findsNothing);
      expect(find.text('₱60.00'), findsOneWidget);
      expect(find.text('₱80.00'), findsOneWidget);
      expect(find.text('₱100.00'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('history opening quantity has no plus and table fills dialog', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReportItemHistory(
            item: {
              'name': 'Cookie',
              'history': [
                {
                  'time': DateTime.now(),
                  'activity': 'Opening balance',
                  'qty': 200,
                  'balance': 200,
                },
                {
                  'time': DateTime.now(),
                  'activity': 'Additional Allocation',
                  'qty': 50,
                  'balance': 250,
                },
              ],
            },
            period: 'Today',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('+200'), findsNothing);
    expect(find.text('200'), findsNWidgets(2));
    expect(find.text('+50'), findsOneWidget);
    expect(find.text('Clear'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'pending returns ignore range; completed returns use acceptance date',
    (tester) async {
      final db = FakeFirebaseFirestore();
      final today = DateUtils.dateOnly(DateTime.now());
      final old = today.subtract(const Duration(days: 8));
      for (final entry in [
        ('pending', ChecklistStatus.awaitingAdmin, old, null),
        ('completed-today', ChecklistStatus.completed, old, today),
        ('completed-old', ChecklistStatus.completed, today, old),
      ]) {
        await db.collection('allocation_checklist').doc(entry.$1).set({
          'kind': 'return',
          'name': entry.$1,
          'status': entry.$2,
          'createdAt': Timestamp.fromDate(entry.$3),
          if (entry.$4 != null) 'confirmedAt': Timestamp.fromDate(entry.$4!),
          'quantity': 2,
          'staffId': 'b',
          'branchId': 'b',
          'branchName': 'Dagupan',
          'submittedByName': 'Cashier',
          'submittedByStaffId': 'STF-1',
        });
      }
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AllocationChecklistButton(
              scopeIds: const [],
              database: db,
              isAdmin: true,
            ),
          ),
        ),
      );
      await tester.tap(find.byTooltip('Returns'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('View pending returns'), findsNothing);
      expect(
        tester
            .widget<ReturnBatchList>(find.byType(ReturnBatchList))
            .docs
            .map((d) => d.id),
        ['pending'],
      );
      await tester.tap(find.text('Completed Return'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ReturnBatchList>(find.byType(ReturnBatchList))
            .docs
            .map((d) => d.id),
        ['completed-today'],
      );
      expect(find.text('Completed returns: 1 • 2 items'), findsOneWidget);
      await tester.tap(find.byTooltip('Filter by date range'));
      await tester.pumpAndSettle();
      expect(find.byType(DateRangePickerDialog), findsOneWidget);
      tester
          .state<NavigatorState>(find.byType(Navigator).last)
          .pop(
            DateTimeRange(start: old, end: old.add(const Duration(days: 1))),
          );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ReturnBatchList>(find.byType(ReturnBatchList))
            .docs
            .map((d) => d.id),
        ['completed-old'],
      );
      await tester.tap(find.text('Returned Items'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ReturnBatchList>(find.byType(ReturnBatchList))
            .docs
            .map((d) => d.id),
        ['pending'],
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('staff range and search show identity, item IDs and discount', (
    tester,
  ) async {
    final db = FakeFirebaseFirestore();
    final today = DateUtils.dateOnly(DateTime.now());
    final yesterday = today.subtract(const Duration(days: 1));
    await db.doc('branches/b').set({
      'name': 'Dagupan',
      'staffIds': ['u'],
    });
    await db.doc('staff_requests/u').set({
      'firstName': 'Ana',
      'lastName': 'Cruz',
      'staffId': 'STF-1',
      'uid': 'u',
    });
    for (final day in [today, yesterday]) {
      await db.collection('completed_sales').add({
        'branchId': 'b',
        'userId': 'u',
        'timestamp': Timestamp.fromDate(day),
        'total': 40,
        'staffName': 'Ana Cruz',
        'staffPublicId': 'STF-1',
        'discount': 10,
        'discountType': 'Senior',
        'tax': 4.8,
        'taxRate': .12,
        'taxClassification': 'vat',
        'items': [
          {'publicId': 'CO-1', 'name': 'Cookie', 'price': 50, 'quantity': 1},
        ],
      });
    }
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StaffPerformancePanel(branchId: 'b', firestore: db),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('1 orders • 1 items sold • ₱40.00'), findsOneWidget);
    await tester.tap(find.byTooltip('Filter performance by date range'));
    await tester.pumpAndSettle();
    tester
        .state<NavigatorState>(find.byType(Navigator).last)
        .pop(DateTimeRange(start: yesterday, end: today));
    await tester.pumpAndSettle();
    expect(find.text('2 orders • 2 items sold • ₱80.00'), findsOneWidget);
    expect(find.text('Cashier: Ana Cruz'), findsWidgets);
    expect(find.text('Cashier ID: STF-1'), findsWidgets);
    expect(find.text('VAT (12%): ₱4.80'), findsWidgets);
    expect(find.textContaining('CO-1 • Cookie'), findsWidgets);
    expect(find.textContaining('Discount'), findsWidgets);
    await tester.enterText(find.byType(TextField), 'missing-item');
    await tester.pumpAndSettle();
    expect(find.text('0 orders • 0 items sold • ₱0.00'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('disabled branch refunds disappear from analytics controls', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BranchReportDialog(
            branchId: 'b',
            reportData: Future.value(
              BranchReportData({
                'admin_settings': [
                  {
                    '_id': 'transactions',
                    'branchSettings': {
                      'b': {'allowRefunds': false},
                    },
                  },
                ],
              }),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Sales analytics'),
      250,
      scrollable: find
          .descendant(
            of: find.byType(ListView).first,
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.widgetWithText(ActionChip, 'Refund'), findsNothing);
    expect(find.textContaining('Total Refund:'), findsNothing);
    expect(find.widgetWithText(ActionChip, 'Reduce'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
