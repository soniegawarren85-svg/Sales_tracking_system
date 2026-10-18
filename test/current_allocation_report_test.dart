import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sales_tracking/services/branch_report_data.dart';
import 'package:sales_tracking/services/branch_report_csv.dart';
import 'package:sales_tracking/services/branch_report_excel.dart';
import 'package:sales_tracking/services/number_format.dart';
import 'package:sales_tracking/widgets/branch_allocation_table.dart';
import 'package:sales_tracking/widgets/branch_report_dialog.dart';
import 'package:xml/xml.dart';

void main() {
  test('money display groups thousands and preserves two decimals', () {
    expect(formatMoney(1200), '₱1,200.00');
    expect(formatMoney(1200.5), '₱1,200.50');
  });

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

  test('report total cost excludes unsold allocated inventory', () {
    final data = fixture();
    final items = data.currentAllocatedItems('b', day, end, now: day);
    expect(items.length, 1);
    expect(items.single['id'], 'CO-005');
    expect(items.single['costPrice'], 50);
    expect(items.single['allocationCost'], 2100);
    expect(
      data.allocationReportTotals('b', day, end, now: day)['Total cost'],
      0,
    );
    expect(data.totals('b', day, end)['Total cost'], 0);
  });

  test(
    'current bundle report shows one live row and current starting count',
    () {
      final day = DateUtils.dateOnly(DateTime.now());
      final end = day.add(const Duration(days: 1));
      final data = BranchReportData({
        'sales_inventory': [
          {
            '_id': 'bundle-source',
            'isBundle': true,
            'publicId': 'BND-001',
            'name': 'Bundle Cakes',
            'price': 200,
            'items': <Map<String, dynamic>>[],
          },
        ],
        'staff_inventory': [
          for (final entry in [
            ('old-version', 3, 2),
            ('returned-version', 0, 5),
            ('current-version', 6, 1),
          ])
            {
              '_id': entry.$1,
              'staffId': 'b',
              'sourceInventoryId': 'bundle-source',
              'isBundle': true,
              'bundleId': 'BND-001',
              'publicId': 'BND-001',
              'name': 'Bundle Cakes',
              'price': entry.$1 == 'current-version' ? 200 : 350,
              'bundleCount': entry.$2,
              'assignedStartingStock': entry.$2 + entry.$3,
              'assignedAt': day,
              'bundleInstances': [
                for (var index = 0; index < entry.$2; index++)
                  {
                    'id': '${entry.$1}-$index',
                    'number': index + 1,
                    'status': 'available',
                    'assignedAt': day,
                    'items': <Map<String, dynamic>>[],
                  },
                for (var index = 0; index < entry.$3; index++)
                  {
                    'id': '${entry.$1}-returned-$index',
                    'number': entry.$2 + index + 1,
                    'status': 'returned',
                    'assignedAt': day,
                    'items': <Map<String, dynamic>>[],
                  },
              ],
            },
        ],
      });

      final rows = data.currentAllocatedItems('b', day, end, now: day);

      expect(rows, hasLength(1));
      expect(rows.single['id'], 'BND-001');
      expect(rows.single['remaining'], 9);
      expect(rows.single['starting'], 9);
      expect(rows.single['price'], 200);
    },
  );

  test('unbundled stock is aggregated with its unbundle history', () {
    final data = BranchReportData({
      'sales_inventory': [
        {
          '_id': 'category-source',
          'items': [
            {
              'id': 'CA-001',
              'publicId': 'CA-001',
              'name': 'Cake',
              'stock': 0,
              'price': 100,
            },
          ],
        },
      ],
      'staff_inventory': [
        {
          '_id': 'original-allocation',
          'staffId': 'b',
          'sourceInventoryId': 'category-source',
          'assignedAt': day,
          'items': [
            {
              'id': 'CA-001',
              'publicId': 'CA-001',
              'name': 'Cake',
              'stock': 0,
              'assignedStartingStock': 5,
              'price': 100,
            },
          ],
        },
        for (var index = 0; index < 2; index++)
          {
            '_id': 'unbundle-$index',
            'staffId': 'b',
            'sourceInventoryId': 'category-source',
            'origin': 'unbundle',
            'assignedAt': day,
            'items': [
              {
                'id': 'CA-001',
                'publicId': 'CA-001',
                'name': 'Cake',
                'stock': 2,
                'startingStock': 2,
                'assignedStartingStock': 2,
                'price': 100,
              },
            ],
          },
      ],
    });

    final rows = data.currentInventory('b', day);
    final history = data.items('b', day, end);

    expect(rows, hasLength(1));
    expect(rows.single['id'], 'CA-001');
    expect(rows.single['remaining'], 4);
    final events = history.single['history'] as List<Map<String, dynamic>>;
    final unbundles = events.where((event) => event['activity'] == 'Unbundle');
    expect(unbundles, hasLength(2));
    expect(unbundles.map((event) => event['qty']), everyElement(2));
  });

  test('branch table cost is cost price multiplied by sold quantity', () {
    expect(
      branchStockCost({
        'costPrice': 50,
        'sold': 1,
        'starting': 100,
        'added': 5,
      }),
      50,
    );
    expect(
      branchStockCost({
        'costPrice': 50,
        'sold': 3,
        'starting': 100,
        'added': 5,
      }),
      150,
    );
    expect(branchStockCost({'costPrice': 50, 'sold': 0, 'starting': 100}), 0);
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
      expect(data.totals('b', day, end)['Total cost'], 20);
      expect(
        data.allocationReportTotals('b', day, end, now: day)['Total cost'],
        20,
      );
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
      expect(
        allocations,
        contains(
          '"Total cost","Cost price x sold items; unsold inventory contributes 0."',
        ),
      );
      expect(
        allocations,
        contains(
          '"TOTAL","","","","","42.0","0.0","42.0","0.00","0.0","0.00","0.00","0.00",""',
        ),
      );
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

  test('Excel report styles totals, uses sold costs, date cells and chart', () {
    final data = fixture();
    final rows = branchReportRows(data, day, end, branchId: 'b', now: day);
    final allocationHeaderIndex = rows.indexWhere(
      (row) => row.firstOrNull == 'ID',
    );
    final allocationHeaders = rows[allocationHeaderIndex];
    final totalRow = rows.firstWhere((row) => row.firstOrNull == 'TOTAL');
    expect(totalRow[allocationHeaders.indexOf('Total cost')], '0.00');
    expect(allocationHeaders, contains('Net profit'));

    final workbook = ZipDecoder().decodeBytes(
      branchReportExcel(data, day, end, branchId: 'b', now: day),
    );
    for (final file in workbook.files.where(
      (file) => file.name.endsWith('.xml') || file.name.endsWith('.rels'),
    )) {
      XmlDocument.parse(utf8.decode(file.content as List<int>));
    }
    final sheetFile = workbook.findFile('xl/worksheets/sheet1.xml');
    final stylesFile = workbook.findFile('xl/styles.xml');
    final chartFile = workbook.findFile('xl/charts/chart1.xml');
    expect(sheetFile, isNotNull);
    expect(stylesFile, isNotNull);
    expect(chartFile, isNotNull);

    final sheet = utf8.decode(sheetFile!.content as List<int>);
    final styles = utf8.decode(stylesFile!.content as List<int>);
    final chart = utf8.decode(chartFile!.content as List<int>);
    expect(sheet, contains('CO-005'));
    expect(sheet, contains('s="4"'));
    expect(sheet, contains('s="5"'));
    expect(sheet, contains('s="6"><v>'));
    expect(styles, contains('dd/mm/yyyy'));
    expect(chart, contains('<c:barDir val="bar"/>'));
    expect(chart, contains('Net sales'));
  });

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
      final categoryWrap = find
          .ancestor(of: find.text('Categories'), matching: find.byType(Wrap))
          .first;
      final categoryChoices = tester
          .widgetList<ChoiceChip>(
            find.descendant(
              of: categoryWrap,
              matching: find.byType(ChoiceChip),
            ),
          )
          .map((chip) => (chip.label as Text).data)
          .toList();
      expect(categoryChoices, ['Categories', 'Bundle', 'Beverages']);
      expect(
        tester
            .widget<ChoiceChip>(
              find
                  .ancestor(
                    of: find.text('Categories'),
                    matching: find.byType(ChoiceChip),
                  )
                  .first,
            )
            .selected,
        isTrue,
      );
      final table = tester.widget<DataTable>(find.byType(DataTable).first);
      final headings = table.columns
          .map((column) => (column.label as Text).data)
          .toList();
      expect(headings.indexOf('Cost price') + 1, headings.indexOf('Price'));
      expect(
        headings.indexOf('Price') + 1,
        headings.indexOf('Starting allocated'),
      );
      expect(headings[headings.indexOf('Sales') + 1], 'Sold items');
      expect(headings[headings.indexOf('Total profit') + 1], 'Net profit');
      expect(headings[headings.indexOf('Net profit') + 1], 'Total cost');
      expect(headings.last, 'Action');
      expect(find.text('Expired cookie'), findsNothing);
      expect(find.text('Removed cookie'), findsNothing);
      expect(find.text('₱2,100.00'), findsNothing);
      expect(find.text('₱0.00'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );
}
