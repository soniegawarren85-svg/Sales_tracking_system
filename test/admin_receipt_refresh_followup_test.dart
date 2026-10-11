import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sales_tracking/services/branch_report_data.dart';
import 'package:sales_tracking/services/branch_report_csv.dart';
import 'package:sales_tracking/widgets/branch_receipts_dialog.dart';
import 'package:sales_tracking/widgets/daily_sales_report.dart';
import 'package:sales_tracking/widgets/report_sales_timeline.dart';
import 'package:sales_tracking/widgets/staff_deactivation_dialog.dart';
import 'package:sales_tracking/widgets/top_edge_refresh.dart';

void main() {
  test(
    'payment searches are exact and VAT and discount totals include money',
    () {
      final sales = <Map<String, dynamic>>[
        {'paymentMode': 'Cash', 'total': 90, 'discount': 10},
        {'paymentMode': 'GCash', 'total': 112, 'tax': 12},
        {'paymentMethod': 'Cash', 'total': 56, 'tax': 6},
      ];
      final cash = sales.where((s) => receiptMatchesSearch(s, 'cash')).toList();
      expect(cash.length, 2);
      expect(receiptSearchSummary(cash, 'cash'), contains('146.00'));
      final vat = sales.where((s) => receiptMatchesSearch(s, 'VAT')).toList();
      expect(vat.length, 2);
      expect(receiptSearchSummary(vat, 'VAT'), contains('168.00'));
      expect(receiptSearchSummary(vat, 'VAT'), contains('18.00'));
      final discounted = sales
          .where((s) => receiptMatchesSearch(s, 'discounted'))
          .toList();
      expect(discounted.length, 1);
      expect(receiptSearchSummary(discounted, 'discounted'), contains('10.00'));
      expect(receiptSearchCategory('Cookie'), isNull);
    },
  );

  testWidgets('tablet refresh starts at top and keeps page content visible', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1100, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var refreshes = 0;
    final completion = Completer<void>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TopEdgeRefresh(
            onRefresh: () {
              refreshes++;
              return completion.future;
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: const [
                Text('Branch Sales'),
                Text('Loaded inventory'),
                SizedBox(height: 140),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.dragFrom(const Offset(500, 65), const Offset(0, 420));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(refreshes, 1);
    expect(find.text('Branch Sales').hitTestable(), findsOneWidget);
    expect(find.text('Loaded inventory').hitTestable(), findsOneWidget);
    completion.complete();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('report financial cards reconcile with branch details', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final now = DateTime.now();
    final data = BranchReportData({
      'branches': [
        {'_id': 'b', 'name': 'SM Dagupan'},
      ],
      'completed_sales': [
        {
          '_id': 'sale',
          'branchId': 'b',
          'timestamp': now,
          'total': 100,
          'items': [
            {
              'itemId': 'CO-001',
              'name': 'Cookie',
              'quantity': 2,
              'price': 50,
              'costPrice': 20,
            },
          ],
        },
      ],
      'stock_adjustments': [
        {'branchId': 'b', 'createdAt': now, 'quantity': 1, 'lossAmount': 20},
      ],
    });
    final start = DateUtils.dateOnly(now);
    final csv = utf8.decode(
      branchReportCsv(data, start, start.add(const Duration(days: 1))),
    );
    expect(csv, contains('"Total loss","20.00"'));
    await tester.pumpWidget(
      MaterialApp(home: DailySalesReport(data: Stream.value(data))),
    );
    await tester.pumpAndSettle();
    expect(find.text('Average sale'), findsNothing);
    for (final entry in {
      'Total cost': '40.00',
      'Total profit': '60.00',
      'Total loss': '20.00',
    }.entries) {
      final card = find
          .ancestor(of: find.text(entry.key), matching: find.byType(Card))
          .first;
      await tester.ensureVisible(card);
      expect(
        find.descendant(of: card, matching: find.text('\u20B1${entry.value}')),
        findsOneWidget,
      );
      await tester.tap(
        find.descendant(of: card, matching: find.text('View details')),
      );
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(Dialog),
          matching: find.text('SM Dagupan'),
        ),
        findsOneWidget,
      );
      await tester.tap(find.byTooltip('Close details'));
      await tester.pumpAndSettle();
    }
    await tester.scrollUntilVisible(
      find.text('Save CSV file'),
      400,
      scrollable: find
          .descendant(
            of: find.byType(ListView).first,
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.text('Print report'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'report analytics hide refunds when all branches disable refunds',
    (tester) async {
      final start = DateUtils.dateOnly(DateTime.now());
      final data = BranchReportData({
        'branches': [
          {'_id': 'b', 'name': 'SM Dagupan'},
        ],
        'admin_settings': [
          {
            '_id': 'transactions',
            'branchSettings': {
              'b': {'allowRefunds': false},
            },
          },
        ],
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ReportSalesTimeline(
                data: data,
                start: start,
                end: start.add(const Duration(days: 1)),
                period: 'Day',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Sales & reductions'), findsOneWidget);
      expect(find.textContaining('Refund'), findsNothing);
      expect(find.text('Reduced'), findsOneWidget);
    },
  );

  testWidgets('preset deactivation reason needs no typed reason', (
    tester,
  ) async {
    String? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              child: const Text('Open'),
              onPressed: () async {
                result = await showDialog<String>(
                  context: context,
                  builder: (_) => const StaffDeactivationDialog(name: 'Ana'),
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Resigned').last);
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    await tester.tap(find.widgetWithText(FilledButton, 'Deactivate'));
    await tester.pumpAndSettle();
    expect(result, 'Resigned');
  });
}
