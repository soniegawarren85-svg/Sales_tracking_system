import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sales_tracking/services/branch_report_data.dart';
import 'package:sales_tracking/widgets/inventory_report.dart';

void main() {
  testWidgets('inventory report summarizes products and movement metrics', (
    tester,
  ) async {
    final data = BranchReportData({
      'branches': const [],
      'sales_inventory': [
        {
          '_id': 'cookies',
          'name': 'Cookies',
          'items': [
            {
              'id': 'cookie',
              'name': 'Chocolate cookie',
              'stock': 5,
              'costPrice': 10,
              'price': 20,
            },
          ],
        },
        {
          '_id': 'bundle',
          'name': 'Cookie bundle',
          'isBundle': true,
          'bundleCount': 2,
          'costPrice': 30,
          'price': 50,
        },
      ],
      'coffee_products': [
        {'_id': 'latte', 'name': 'Latte', 'basePrice': 100},
      ],
      'coffee_addons': [
        {'_id': 'cream', 'name': 'Chewy cream', 'price': 15},
      ],
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InventoryReportDialog(branchId: null, data: Stream.value(data)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Total Products'), findsOneWidget);
    expect(find.text('Total Bundles'), findsOneWidget);
    expect(find.text('Total Beverages'), findsOneWidget);
    expect(find.text('Total Inventory Cost'), findsOneWidget);
    expect(find.text('Total Inventory Value'), findsOneWidget);
    expect(find.text('Stock movement'), findsOneWidget);
    expect(find.text('Stock Received'), findsOneWidget);
    expect(find.text('Damaged Items'), findsOneWidget);
    expect(find.text('Save Excel'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('branch report excludes inventory from other branches', (
    tester,
  ) async {
    final now = DateTime.now();
    final data = BranchReportData({
      'branches': [
        {'_id': 'dagupan', 'name': 'SM Dagupan'},
        {'_id': 'manila', 'name': 'Manila'},
      ],
      'sales_inventory': [
        {
          '_id': 'dagupan-category',
          'name': 'Dagupan category',
          'items': [
            {
              'id': 'dagupan-cookie',
              'name': 'Dagupan cookie',
              'stock': 4,
              'startingStock': 4,
              'assignedStartingStock': 4,
              'costPrice': 10,
              'price': 20,
            },
          ],
        },
        {
          '_id': 'manila-category',
          'name': 'Manila category',
          'items': [
            {
              'id': 'manila-cookie',
              'name': 'Manila cookie',
              'stock': 9,
              'startingStock': 9,
              'assignedStartingStock': 9,
              'costPrice': 10,
              'price': 20,
            },
          ],
        },
      ],
      'staff_inventory': [
        {
          '_id': 'dagupan-allocation',
          'staffId': 'dagupan',
          'sourceInventoryId': 'dagupan-category',
          'name': 'Dagupan category',
          'assignedAt': now,
          'items': [
            {
              'id': 'dagupan-cookie',
              'name': 'Dagupan cookie',
              'stock': 4,
              'startingStock': 4,
              'assignedStartingStock': 4,
              'costPrice': 10,
              'price': 20,
            },
          ],
        },
        {
          '_id': 'manila-allocation',
          'staffId': 'manila',
          'sourceInventoryId': 'manila-category',
          'name': 'Manila category',
          'assignedAt': now,
          'items': [
            {
              'id': 'manila-cookie',
              'name': 'Manila cookie',
              'stock': 9,
              'startingStock': 9,
              'assignedStartingStock': 9,
              'costPrice': 10,
              'price': 20,
            },
          ],
        },
      ],
    });
    final today = DateUtils.dateOnly(now);
    expect(data.currentInventory('dagupan', today), hasLength(1));
    expect(data.currentInventory('manila', today), hasLength(1));
    expect(
      data
          .items('dagupan', today, today.add(const Duration(days: 1)))
          .map((item) => item['name']),
      contains('Dagupan cookie'),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InventoryReportDialog(
            branchId: 'dagupan',
            data: Stream.value(data),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -900));
    await tester.pumpAndSettle();

    expect(find.text('SM Dagupan'), findsWidgets);
    expect(find.text('Dagupan cookie'), findsWidgets);
    expect(find.text('Manila cookie'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
