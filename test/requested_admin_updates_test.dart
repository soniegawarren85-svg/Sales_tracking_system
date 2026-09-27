import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sales_tracking/services/branch_report_data.dart';
import 'package:sales_tracking/services/branch_report_schedule.dart';
import 'package:sales_tracking/services/report_current_allocations.dart';
import 'package:sales_tracking/widgets/daily_sales_report.dart';
import 'package:sales_tracking/widgets/branch_staff_activity_dialog.dart';
import 'package:sales_tracking/widgets/branch_analytics_bars.dart';
import 'package:sales_tracking/widgets/report_sales_timeline.dart';

void main() {
  test('allocated bundles count only available instances', () {
    final data = BranchReportData({
      'branches': [
        {'_id': 'b'},
      ],
      'staff_inventory': [
        {
          'staffId': 'b',
          'isBundle': true,
          'bundleCount': 30,
          'bundleInstances': [
            {'status': 'available'},
            {'status': 'sold'},
            {'status': 'reduced'},
            {'status': 'available', 'expirationDate': '2025-01-01'},
          ],
        },
      ],
    });
    expect(
      currentReportAllocations(data, DateTime(2026, 9, 27)).single['quantity'],
      1,
    );
  });
  test('first allocation is not counted twice as opening and addition', () {
    final day = DateTime(2026, 9, 27);
    final data = BranchReportData({
      'branches': [
        {'_id': 'b'},
      ],
      'staff_cash_drawer': [
        {'_id': 'b', 'dailyOpeningCash': 1200},
      ],
      'budget_history': [
        {
          'staffId': 'b',
          'type': 'allocation',
          'amount': 1200,
          'createdAt': day,
        },
      ],
    });
    expect(
      configuredReportCash(data, day, DateTime(2026, 9, 28), day)['b'],
      1200,
    );
  });
  testWidgets(
    'timeline includes late sales, refunds and reductions with branch filtering',
    (tester) async {
      final start = DateTime(2026, 9, 27);
      final data = BranchReportData({
        'branches': [
          {'_id': 'b', 'name': 'Dagupan'},
          {'_id': 'c', 'name': 'Other'},
        ],
        'completed_sales': [
          {
            'branchId': 'b',
            'timestamp': start.add(const Duration(hours: 20)),
            'total': 200,
          },
          {
            'branchId': 'c',
            'timestamp': start.add(const Duration(hours: 20)),
            'total': 300,
          },
          {
            'branchId': 'b',
            'timestamp': start.add(const Duration(hours: 21)),
            'total': -50,
            'type': 'refund',
          },
        ],
        'stock_adjustments': [
          {
            'branchId': 'b',
            'createdAt': start.add(const Duration(hours: 22)),
            'lossAmount': 25,
          },
        ],
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReportSalesTimeline(
              data: data,
              start: start,
              end: DateTime(2026, 9, 28),
              period: 'Day',
            ),
          ),
        ),
      );
      final bars = tester.widget<BranchAnalyticsBars>(
        find.byType(BranchAnalyticsBars),
      );
      expect(bars.labels.length, 24);
      expect(bars.values[20], 500);
      expect(bars.refunds![21], 50);
      expect(bars.reduced![22], 25);
      final dropdown = tester.widget<DropdownButton<String>>(
        find.byType(DropdownButton<String>),
      );
      dropdown.onChanged!('b');
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<BranchAnalyticsBars>(find.byType(BranchAnalyticsBars))
            .values[20],
        200,
      );
      expect(tester.takeException(), isNull);
    },
  );
  test('branch closing schedule uses editable hour and minute', () {
    final now = DateTime(2026, 9, 27, 19);
    expect(
      nextBranchClosingTime(now, closingMinutes: 1230),
      DateTime(2026, 9, 27, 20, 30),
    );
    expect(
      latestClosedBranchDay(now, closingMinutes: 1230),
      DateTime(2026, 9, 26),
    );
    expect(
      reportClosingAvailable(
        DateTime(2026, 9, 27),
        DateTime(2026, 9, 28),
        now,
        closingMinutes: 1230,
      ),
      false,
    );
  });
  test(
    'late cash orders and refunds update closing, GCash only updates revenue',
    () {
      final day = DateUtils.dateOnly(DateTime.now());
      final data = BranchReportData({
        'staff_cash_drawer': [
          {'_id': 'b', 'dailyOpeningCash': 1200},
        ],
        'daily_reports': [
          {'branchId': 'b', 'reportDate': day, 'closingCash': 1200},
        ],
        'completed_sales': [
          {
            'branchId': 'b',
            'timestamp': day.add(const Duration(hours: 20)),
            'paymentMode': 'Cash',
            'total': 200,
          },
          {
            'branchId': 'b',
            'timestamp': day.add(const Duration(hours: 21)),
            'paymentMode': 'GCash',
            'total': 300,
          },
          {
            'branchId': 'b',
            'timestamp': day.add(const Duration(hours: 23, minutes: 59)),
            'paymentMode': 'Cash',
            'type': 'refund',
            'total': -50,
          },
          {
            'branchId': 'b',
            'timestamp': day.add(const Duration(days: 1)),
            'paymentMode': 'Cash',
            'total': 900,
          },
        ],
      });
      final totals = data.totals('b', day, day.add(const Duration(days: 1)));
      expect(totals['Closing cash drawer'], 1350);
      expect(totals['Total revenue'], 500);
      expect(totals['Refunds'], 50);
    },
  );
  test(
    'current allocation count includes older available inventory and resolves addon IDs',
    () {
      final data = BranchReportData({
        'branches': [
          {'_id': 'b', 'name': 'Dagupan'},
        ],
        'coffee_addons': [
          {'_id': 'internal-addon', 'publicId': 'ADD-007', 'name': 'Cream'},
        ],
        'staff_inventory': [
          {
            'staffId': 'b',
            'assignedAt': '2026-01-01',
            'items': [
              {'id': 'CO-004', 'name': 'Cookie', 'stock': 57},
              {'id': 'expired', 'stock': 90, 'expirationDate': '2026-01-01'},
            ],
          },
          {
            'staffId': 'b',
            'isBundle': true,
            'publicId': 'BND-001',
            'bundleCount': 9,
          },
          {
            'staffId': 'b',
            'isAddon': true,
            'sourceInventoryId': 'internal-addon',
          },
          {
            'staffId': 'b',
            'isDeleted': true,
            'isBundle': true,
            'bundleCount': 100,
          },
        ],
      });
      final rows = currentReportAllocations(data, DateTime(2026, 9, 27));
      expect(
        rows.fold<double>(0, (sum, r) => sum + reportValue(r['quantity'])),
        66,
      );
      expect(rows.last['id'], 'ADD-007');
      expect(rows.last['remaining'], 'Made to order');
      expect(rows, hasLength(3));
    },
  );
  test(
    'cash includes carried opening and latest configured cash even without today history',
    () {
      final now = DateTime(2026, 9, 27, 20);
      final data = BranchReportData({
        'branches': [
          {'_id': 'a'},
          {'_id': 'b'},
        ],
        'staff_cash_drawer': [
          {'_id': 'a', 'dailyOpeningCash': 1200},
          {'_id': 'b', 'dailyOpeningCash': 500},
        ],
        'budget_history': [
          {
            'staffId': 'a',
            'type': 'set_daily_cash_drawer',
            'amount': 1000,
            'createdAt': '2026-09-26',
          },
          {
            'staffId': 'a',
            'type': 'allocation',
            'amount': 100,
            'createdAt': '2026-09-27T12:00:00',
          },
        ],
      });
      expect(
        configuredReportCash(
          data,
          DateTime(2026, 9, 27),
          DateTime(2026, 9, 28),
          now,
        ),
        {'a': 1300, 'b': 500},
      );
    },
  );
  testWidgets(
    'report allocation details open inline and are hidden initially',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final data = BranchReportData({
        'branches': [
          {'_id': 'b', 'name': 'Dagupan'},
        ],
        'staff_inventory': [
          {
            'staffId': 'b',
            'items': [
              {'id': 'CO-004', 'name': 'Cookie', 'stock': 57},
            ],
          },
        ],
      });
      await tester.pumpWidget(
        MaterialApp(home: DailySalesReport(data: Stream.value(data))),
      );
      await tester.pumpAndSettle();
      expect(find.text('Cookie'), findsNothing);
      expect(find.text('Sales by branch'), findsOneWidget);
      await tester.tap(find.text('View allocated'));
      await tester.pumpAndSettle();
      expect(find.text('Cookie'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('IP address appears in its own column', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: StaffSessionTable(
            sessions: [
              {
                'staffId': 'STF-001',
                'staffName': 'Jessica',
                'ipAddress': '192.168.1.5',
                'loginAt': '2026-09-27T10:00:00',
              },
            ],
          ),
        ),
      ),
    );
    expect(find.text('IP address'), findsOneWidget);
    expect(find.text('192.168.1.5'), findsOneWidget);
    expect(find.text('Staff ID'), findsOneWidget);
  });
}
