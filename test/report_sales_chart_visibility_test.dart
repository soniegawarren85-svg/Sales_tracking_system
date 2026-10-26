import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sales_tracking/services/branch_report_data.dart';
import 'package:sales_tracking/widgets/branch_analytics_bars.dart';
import 'package:sales_tracking/widgets/report_sales_timeline.dart';

void main() {
  testWidgets('daily sales with recorded transactions render visible bars', (
    tester,
  ) async {
    final start = DateUtils.dateOnly(DateTime.now());
    final data = BranchReportData({
      'branches': [
        {'_id': 'branch-a', 'name': 'Dagupan'},
      ],
      'admin_settings': [
        {
          '_id': 'transactions',
          'branchSettings': {
            'branch-a': {'allowRefunds': false},
          },
        },
      ],
      'completed_sales': [
        {
          '_id': 'sale-a',
          'branchId': 'branch-a',
          'timestamp': start.add(const Duration(hours: 10, minutes: 15)),
          'total': 564,
          'status': 'completed',
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

    final chart = tester.widget<BranchAnalyticsBars>(
      find.byType(BranchAnalyticsBars),
    );
    expect(chart.values[10], 564);
    expect(
      tester.getSize(find.byKey(const ValueKey('sales-report-bar-10'))).height,
      greaterThan(4),
    );
    expect(find.text('Sales: ₱564.00'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
