import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sales_tracking/services/branch_report_data.dart';
import 'package:sales_tracking/services/refund_value.dart';
import 'package:sales_tracking/widgets/report_item_history.dart';

void main() {
  test(
    'legacy inventory refund value counts in losses without changing cash',
    () {
      final day = DateTime(2026, 10, 6);
      final record = <String, dynamic>{
        'branchId': 'b',
        'type': 'refund',
        'refundMethod': 'inventory',
        'paymentMode': 'Inventory replacement',
        'timestamp': day,
        'total': 0,
        'subtotal': 0,
        'replacementValue': 89,
      };
      final normalized = refundValueRecord(record);
      expect(normalized['total'], -89);
      expect(normalized['subtotal'], -89);
      expect(normalized['cashDrawerDelta'], 0);
      expect(record['total'], 0);
      final totals = BranchReportData({
        'completed_sales': [record],
      }).totals('b', day, day.add(const Duration(days: 1)));
      expect(totals['Refunds'], 89);
      expect(totals['Closing cash drawer'], 0);
    },
  );

  test('quantity cannot exceed remaining sold items or contain fractions', () {
    expect(refundQuantityError('1', 1), isNull);
    for (final value in ['2', '3', '0', '-1', '1.5', '']) {
      expect(refundQuantityError(value, 1), isNotNull);
    }
    expect(refundQuantityError('1', 0), isNotNull);
  });

  for (final bundle in [false, true]) {
    test(
      '${bundle ? 'bundle' : 'item'} history keeps chronological running balances',
      () {
        final day = DateTime(2026, 10, 6);
        Map<String, dynamic> item(int qty) => {
          'id': 'CO-001',
          'publicId': 'CO-001',
          'name': 'Cookie',
          'isBundle': bundle,
          'quantity': qty,
          'price': 89,
        };
        final data = BranchReportData({
          'staff_inventory_history': [
            for (final entry in [(8, 100), (12, 50), (16, 50)])
              {
                'staffId': 'b',
                'createdAt': DateTime(2026, 10, 6, entry.$1),
                'items': [item(entry.$2)],
              },
          ],
          'completed_sales': [
            for (final entry in [(10, 30), (14, 40), (18, 20)])
              {
                'branchId': 'b',
                'timestamp': DateTime(2026, 10, 6, entry.$1),
                'items': [item(entry.$2)],
              },
          ],
        });
        final row = data
            .items('b', day, day.add(const Duration(days: 1)))
            .single;
        expect(row['allocated'], 200);
        expect(row['sold'], 90);
        final history = (row['history'] as List).cast<Map>();
        expect(history.map((event) => event['balance']), [
          100,
          70,
          120,
          80,
          130,
          110,
        ]);
        expect(history.first['activity'], 'Starting Allocation');
        expect(history[2]['activity'], 'Additional Allocation');
      },
    );
  }

  test('additional five keeps saved starting allocation at 105', () {
    final day = DateTime(2026, 10, 6);
    final data = BranchReportData({
      'staff_inventory': [
        {
          'staffId': 'b',
          'assignedAt': day,
          'items': [
            {
              'id': 'CO-001',
              'name': 'Cookie',
              'stock': 75,
              'assignedStartingStock': 105,
            },
          ],
        },
      ],
      'staff_inventory_history': [
        {
          'staffId': 'b',
          'createdAt': DateTime(2026, 10, 6, 12),
          'items': [
            {'id': 'CO-001', 'name': 'Cookie', 'quantity': 5},
          ],
        },
      ],
      'completed_sales': [
        {
          'branchId': 'b',
          'timestamp': DateTime(2026, 10, 6, 10),
          'items': [
            {'itemId': 'CO-001', 'name': 'Cookie', 'quantity': 30},
          ],
        },
      ],
    });
    final row = data.items('b', day, day.add(const Duration(days: 1))).single;
    expect(row['allocated'], 105);
    expect((row['history'] as List).map((e) => e['balance']), [100, 70, 75]);
  });

  testWidgets('beverage history shows actual price and sales per size', (
    tester,
  ) async {
    final day = DateTime(2026, 10, 6);
    final data = BranchReportData({
      'completed_sales': [
        for (final entry in [('Small', 2, 50), ('Large', 3, 80)])
          {
            'branchId': 'b',
            'timestamp': day,
            'items': [
              {
                'publicId': 'BEV-001',
                'name': 'Coffee',
                'isCoffee': true,
                'coffeeSize': entry.$1,
                'quantity': entry.$2,
                'price': entry.$3,
              },
            ],
          },
      ],
    });
    final row = data.items('b', day, day.add(const Duration(days: 1))).single;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReportItemHistory(item: row, period: 'Today'),
        ),
      ),
    );
    expect(find.text('Small'), findsOneWidget);
    expect(find.text('Large'), findsOneWidget);
    expect(find.text('₱100.00'), findsOneWidget);
    expect(find.text('₱240.00'), findsOneWidget);
    expect(find.byTooltip('Close history'), findsOneWidget);
    expect(find.text('Balance'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
