import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sales_tracking/services/branch_report_data.dart';
import 'package:sales_tracking/services/branch_report_csv.dart';
import 'package:sales_tracking/widgets/branch_report_dialog.dart';

void main() {
  final day = DateUtils.dateOnly(DateTime.now());
  final end = day.add(const Duration(days: 1));
  BranchReportData fixture({bool sales = false}) {
    Map<String, dynamic> item(String id, String name, {bool expired = false}) =>
        {
          'id': id,
          'publicId': id,
          'name': name,
          'price': 89,
          'costPrice': 50,
          'stock': 42,
          'startingStock': 42,
          'quantity': 42,
          'expirationDate':
              (expired
                      ? day.subtract(const Duration(days: 1))
                      : day.add(const Duration(days: 30)))
                  .toIso8601String(),
        };
    final active = item('CO-005', 'Og Cookies');
    final expired = item('CO-012', 'Expired cookie', expired: true);
    final removed = item('CO-010', 'Removed cookie');
    return BranchReportData({
      'branches': [
        {'_id': 'b', 'name': 'SM Dagupan'},
      ],
      'sales_inventory': [
        {
          '_id': 'cat',
          'items': [active, expired],
          'removedItems': [removed],
        },
      ],
      'staff_inventory': [
        {
          '_id': 'allocation',
          'staffId': 'b',
          'sourceInventoryId': 'cat',
          'assignedAt': day.subtract(const Duration(days: 2)),
          'items': [
            {...active, 'costPrice': 0},
            expired,
            removed,
          ],
        },
      ],
      'completed_sales': sales
          ? [
              {
                '_id': 'sale',
                'salesId': 'S-001',
                'branchId': 'b',
                'timestamp': day.add(const Duration(hours: 11)),
                'total': 99.68,
                'subtotal': 89,
                'tax': 10.68,
                'paymentMode': 'Cash',
                'items': [
                  {
                    'itemId': 'CO-010',
                    'name': 'Removed cookie',
                    'quantity': 1,
                    'price': 89,
                    'costPrice': 20,
                  },
                ],
              },
              {
                '_id': 'other',
                'branchId': 'other',
                'timestamp': day,
                'tax': 500,
              },
              {
                '_id': 'voided',
                'branchId': 'b',
                'timestamp': day,
                'tax': 500,
                'isVoided': true,
              },
              {
                '_id': 'yesterday',
                'branchId': 'b',
                'timestamp': day.subtract(const Duration(days: 1)),
                'tax': 500,
              },
            ]
          : [],
    });
  }

  test('current allocation costs use catalog costs even with no sales', () {
    final data = fixture();
    final items = data.currentAllocatedItems('b', day, end, now: day);
    expect(items.length, 1);
    expect(items.single['id'], 'CO-005');
    expect(items.single['costPrice'], 50);
    expect(items.single['allocationCost'], 2100);
    expect(
      data.allocationReportTotals('b', day, end, now: day)['Total cost'],
      2100,
    );
    // Cost of sales is kept separate from the cost of allocated inventory.
    expect(data.totals('b', day, end)['Total cost'], 0);
  });

  test(
    'tax uses recorded transactions and CSV separates current stock from historical sales',
    () {
      final data = fixture(sales: true);
      expect(
        data.totals('b', day, end)['Total VAT / tax'],
        closeTo(10.68, .001),
      );
      expect(data.totals('b', day, end)['Total net sales'], closeTo(89, .001));
      final removedCookie = data
          .items('b', day, end)
          .singleWhere((item) => item['name'] == 'Removed cookie');
      expect(removedCookie['profit'], closeTo(79.68, .001));
      expect(removedCookie['vatAmount'], closeTo(10.68, .001));
      expect(removedCookie['netProfit'], closeTo(69, .001));
      expect(
        data.profitForSales(data.sales('b', day, end)),
        closeTo(removedCookie['profit'], .001),
      );
      final csv = utf8.decode(
        branchReportCsv(data, day, end, branchId: 'b', now: day),
      );
      for (final section in [
        '1. SALES SUMMARY',
        '2. CURRENT ALLOCATED ITEMS',
        '3. SALES ANALYTICS',
        '4. BEST-SELLING ITEMS',
        '5. RECEIPT RECORDS',
        '6. RECEIPT ITEM DETAILS',
      ]) {
        expect(csv, contains(section));
      }
      final allocations = csv
          .split('2. CURRENT ALLOCATED ITEMS')[1]
          .split('3. SALES ANALYTICS')[0];
      expect(allocations, contains('Og Cookies'));
      expect(allocations, isNot(contains('Expired cookie')));
      expect(allocations, isNot(contains('Removed cookie')));
      expect(allocations, contains('Total cost: 2100.00'));
      expect(csv, contains('"Total VAT / tax","10.68"'));
      expect(csv, contains('"Total net sales","89.00"'));
      final analytics = csv
          .split('3. SALES ANALYTICS')[1]
          .split('4. BEST-SELLING ITEMS')[0];
      expect(analytics, contains('11:00","1.0","1.0","99.68","89.00","10.68"'));
      expect(
        analytics,
        contains('"TOTAL","1.0","1.0","99.68","89.00","10.68"'),
      );
      expect(csvCell('-25.00'), '"-25.00"');
      final ranking = csv
          .split('4. BEST-SELLING ITEMS')[1]
          .split('5. RECEIPT RECORDS')[0];
      expect(ranking, contains('Removed cookie'));
      expect(csv, contains('"Sales","Sold items"'));
      expect(csv, contains('S-001'));
    },
  );

  testWidgets(
    'allocation table has adjacent sales and sold, current costs and footer cost',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BranchReportDialog(
              branchId: 'b',
              branchName: 'SM Dagupan',
              reportData: Future.value(fixture()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final scroll = find
          .descendant(
            of: find.byType(ListView).first,
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.scrollUntilVisible(
        find.text('Allocated items'),
        300,
        scrollable: scroll,
      );
      await tester.pumpAndSettle();
      final table = tester.widget<DataTable>(find.byType(DataTable).first);
      final headings = table.columns
          .map((column) => (column.label as Text).data)
          .toList();
      expect(headings[headings.indexOf('Sales') + 1], 'Sold items');
      expect(headings[headings.indexOf('Total profit') + 1], 'Net profit');
      expect(headings, isNot(contains('Total cost')));
      expect(find.text('Expired cookie'), findsNothing);
      expect(find.text('Removed cookie'), findsNothing);
      expect(find.textContaining('Total cost: '), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
