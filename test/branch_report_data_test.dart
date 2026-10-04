import 'package:flutter_test/flutter_test.dart';
import 'package:sales_tracking/services/branch_report_data.dart';
import 'package:sales_tracking/widgets/admin_sales_overview.dart';

void main() {
  test(
    'item sales total uses recorded quantity and price, excluding refunds',
    () {
      final data = BranchReportData({
        'completed_sales': [
          {
            'branchId': 'b',
            'timestamp': '2026-10-04T10:00:00',
            'status': 'completed',
            'items': [
              {'id': 'cookie', 'name': 'Cookie', 'quantity': 2, 'price': 89},
            ],
          },
          {
            'branchId': 'b',
            'timestamp': '2026-10-04T11:00:00',
            'type': 'refund',
            'items': [
              {'id': 'cookie', 'name': 'Cookie', 'quantity': 1, 'price': 89},
            ],
          },
        ],
      });
      final item = data
          .items('b', DateTime(2026, 10, 4), DateTime(2026, 10, 5))
          .single;
      expect(item['sold'], 2);
      expect(item['sales'], 178);
      expect(item['refund'], 1);
    },
  );
  test('saved assignment details survive removal of inventory documents', () {
    final data = BranchReportData({
      'staff_inventory_history': [
        {
          'staffId': 'b',
          'createdAt': '2026-09-01',
          'items': [
            {
              'id': 'old',
              'publicId': 'CO-003',
              'name': 'Cookie',
              'quantity': 10,
              'price': 50,
            },
          ],
          'quantities': {'cookies::old': 10},
        },
      ],
    });
    final items = data.items('b', DateTime(2026, 9, 1), DateTime(2026, 9, 2));
    expect(items, hasLength(1));
    expect(items.single['name'], 'Cookie');
    expect(items.single['allocated'], 10);
    expect(items.single['price'], 50);
  });
  test(
    'today uses configured 1200 instead of stale submitted 1000 and excludes GCash',
    () {
      final now = DateTime.now();
      final range = branchReportRange(now, 'Day');
      final data = BranchReportData({
        'staff_cash_drawer': [
          {'_id': 'b', 'dailyOpeningCash': 1200},
        ],
        'daily_reports': [
          {'branchId': 'b', 'reportDate': now, 'openingCash': 1000},
        ],
        'budget_history': [
          {
            'staffId': 'b',
            'createdAt': now.subtract(const Duration(days: 2)),
            'type': 'set_daily_cash_drawer',
            'amount': 1000,
          },
        ],
        'completed_sales': [
          {
            'branchId': 'b',
            'timestamp': now,
            'total': 300,
            'paymentMode': 'Cash',
          },
          {
            'branchId': 'b',
            'timestamp': now,
            'total': 500,
            'paymentMode': 'GCash',
          },
          {
            'branchId': 'b',
            'timestamp': now,
            'total': -50,
            'paymentMode': 'Cash',
            'type': 'refund',
          },
        ],
        'stock_adjustments': [
          {'branchId': 'b', 'createdAt': now, 'quantity': 2, 'lossAmount': 100},
        ],
      });
      final totals = data.totals('b', range.$1, range.$2);
      expect(totals['Starting fund'], 1200);
      expect(totals['Closing cash drawer'], 1450);
      expect(totals['Total revenue'], 800);
      expect(totals['Refunds'], 50);
      expect(totals['Reduce'], 100);
    },
  );

  test(
    'archived allocations and sales resolve to current inventory display codes',
    () {
      final data = BranchReportData({
        'sales_inventory': [
          {
            '_id': 'cookies',
            'items': [
              {'id': 'VAR-old', 'publicId': 'CO-003', 'name': 'Cookie'},
            ],
          },
        ],
        'staff_inventory': [
          {
            'staffId': 'b',
            'sourceInventoryId': 'cookies',
            'assignedAt': '2026-09-01',
            'isDeleted': true,
            'items': [
              {
                'id': 'VAR-old',
                'name': 'Cookie',
                'stock': 0,
                'expirationDate': '2026-09-02',
              },
            ],
          },
        ],
        'staff_inventory_history': [
          {
            'staffId': 'b',
            'createdAt': '2026-09-01',
            'quantities': {'cookies::VAR-old': 10},
          },
        ],
        'completed_sales': [
          {
            'branchId': 'b',
            'timestamp': '2026-09-01T12:00:00',
            'total': 100,
            'items': [
              {
                'itemId': 'VAR-old',
                'name': 'Cookies',
                'variant': 'Cookie',
                'quantity': 2,
              },
            ],
          },
        ],
      });
      final items = data.items('b', DateTime(2026, 9, 1), DateTime(2026, 9, 2));
      expect(items, hasLength(1));
      expect(items.single['id'], 'CO-003');
      expect(items.single['allocated'], 10);
      expect(items.single['sold'], 2);
      expect(items.single['status'], 'Recorded');
    },
  );

  test('month range includes its final day and excludes following month', () {
    final range = branchReportRange(DateTime(2026, 9, 12), 'Month');
    expect(reportInRange('2026-09-30T23:59:59', range.$1, range.$2), isTrue);
    expect(reportInRange('2026-10-01', range.$1, range.$2), isFalse);
    final week = branchReportRange(DateTime(2026, 9, 27), 'Week');
    expect(week.$1, DateTime(2026, 9, 21));
    expect(week.$2, DateTime(2026, 9, 28));
  });
}
