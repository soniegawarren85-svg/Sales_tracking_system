import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sales_tracking/services/branch_report_data.dart';
import 'package:sales_tracking/widgets/branch_receipts_dialog.dart';
import 'package:sales_tracking/widgets/daily_sales_report.dart';

void main() {
  test('discount totals include only valid sales in the branch and day', () {
    final data = BranchReportData({
      'completed_sales': [
        for (final extra in <Map<String, dynamic>>[
          {'discount': 20},
          {'discount': 15, 'paymentMode': 'GCash'},
          {'discount': 100, 'status': 'refunded'},
          {'discount': 100, 'isVoided': true},
          {'discount': 100, 'branchId': 'other'},
          {'discount': 100, 'timestamp': '2026-09-29'},
        ])
          {'branchId': 'b', 'timestamp': '2026-09-30', 'total': 200, ...extra},
      ],
    });
    expect(
      data.totals(
        'b',
        DateTime(2026, 9, 30),
        DateTime(2026, 10),
      )['Total discount'],
      35,
    );
  });

  testWidgets('Discount receipts include cash and GCash discounted sales', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BranchReceiptsDialog(
            period: 'Today',
            sales: [
              {
                'salesId': 'CASH-DISCOUNT',
                'paymentMode': 'Cash',
                'discount': 20,
                'total': 80,
              },
              {
                'salesId': 'GCASH-DISCOUNT',
                'paymentMode': 'GCash',
                'discount': 10,
                'total': 90,
              },
              {'salesId': 'REGULAR', 'paymentMode': 'Cash', 'total': 100},
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Discounted');
    await tester.pumpAndSettle();
    expect(find.textContaining('Discounted: 2 transactions'), findsOneWidget);
    expect(find.text('CASH-DISCOUNT'), findsWidgets);
    await tester.drag(find.byType(ListView), const Offset(0, -700));
    await tester.pumpAndSettle();
    expect(find.text('GCASH-DISCOUNT'), findsWidgets);
    expect(find.text('REGULAR'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final width in [390.0, 1100.0]) {
    testWidgets('sales filters stay fixed and cost uses sold units at $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final data = BranchReportData({
        'branches': [
          {'_id': 'b', 'name': 'Branch'},
        ],
        'completed_sales': [
          {
            '_id': 'sale',
            'branchId': 'b',
            'timestamp': DateTime.now(),
            'total': 600,
            'items': [
              {'name': 'Cookie', 'quantity': 3, 'costPrice': 20},
            ],
          },
        ],
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: DailySalesReport(data: Stream.value(data))),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('report · All branches'), findsNothing);
      final card = find.ancestor(
        of: find.text('Total cost'),
        matching: find.byType(Card),
      );
      expect(
        find.descendant(of: card, matching: find.text('₱60.00')),
        findsOneWidget,
      );
      final chip = find.widgetWithText(ChoiceChip, 'Day');
      final date = find.byIcon(Icons.calendar_month).first;
      final chipPosition = tester.getTopLeft(chip);
      final datePosition = tester.getTopLeft(date);
      await tester.drag(find.byType(ListView).first, const Offset(0, -450));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(chip), chipPosition);
      expect(tester.getTopLeft(date), datePosition);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('admin daily report remains scoped to its assigned branch', (
    tester,
  ) async {
    final today = DateUtils.dateOnly(DateTime.now());
    final data = BranchReportData({
      'branches': [
        {'_id': 'assigned', 'name': 'Sm Dagupan'},
        {'_id': 'other', 'name': 'Other Branch'},
      ],
      'completed_sales': [
        {
          '_id': 'assigned-sale',
          'salesId': 'ASSIGNED-1',
          'branchId': 'assigned',
          'timestamp': today.add(const Duration(hours: 1)),
          'total': 125,
        },
        {
          '_id': 'other-sale',
          'salesId': 'OTHER-1',
          'branchId': 'other',
          'timestamp': today.add(const Duration(hours: 1)),
          'total': 900,
        },
        {
          '_id': 'assigned-refund',
          'salesId': 'R-ASSIGNED-1',
          'branchId': 'assigned',
          'type': 'refund',
          'timestamp': today.add(const Duration(hours: 2)),
          'total': -20,
        },
        {
          '_id': 'other-refund',
          'salesId': 'R-OTHER-1',
          'branchId': 'other',
          'type': 'refund',
          'timestamp': today.add(const Duration(hours: 2)),
          'total': -900,
        },
      ],
      'stock_adjustments': [
        {
          '_id': 'assigned-reduction',
          'branchId': 'assigned',
          'createdAt': today.add(const Duration(hours: 3)),
          'lossAmount': 5,
        },
        {
          '_id': 'other-reduction',
          'branchId': 'other',
          'createdAt': today.add(const Duration(hours: 3)),
          'lossAmount': 50,
        },
      ],
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DailySalesReport(
            data: Stream.value(data),
            branchId: 'assigned',
            branchName: 'Sm Dagupan',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Sales Reports · Sm Dagupan'), findsOneWidget);
    expect(find.text('All branches'), findsNothing);
    expect(find.text('Sales by branch'), findsNothing);
    expect(find.text('Custom'), findsNothing);
    expect(find.textContaining('₱125.00'), findsWidgets);
    expect(find.textContaining('₱900.00'), findsNothing);
    expect(find.textContaining('₱25.00'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.calendar_month).first);
    await tester.pumpAndSettle();
    expect(find.byType(DateRangePickerDialog), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
