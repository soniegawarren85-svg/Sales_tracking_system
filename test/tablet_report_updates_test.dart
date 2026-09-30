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
    await tester.tap(find.widgetWithText(ChoiceChip, 'Discount'));
    await tester.pumpAndSettle();
    expect(find.text('2 receipts'), findsOneWidget);
    expect(find.text('CASH-DISCOUNT'), findsOneWidget);
    expect(find.text('GCASH-DISCOUNT'), findsOneWidget);
    expect(find.text('REGULAR'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final width in [390.0, 1100.0]) {
    testWidgets(
      'sales filters stay fixed and average uses sold units at $width',
      (tester) async {
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
                {'name': 'Cookie', 'quantity': 3},
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
          of: find.text('Average sale'),
          matching: find.byType(Card),
        );
        expect(
          find.descendant(of: card, matching: find.text('₱200.00')),
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
      },
    );
  }
}
