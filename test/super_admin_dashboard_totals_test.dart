import 'package:flutter_test/flutter_test.dart';
import 'package:sales_tracking/Super_admin_pages/dashboard_totals.dart';
import 'package:sales_tracking/services/branch_report_data.dart';

void main() {
  test(
    'allocated total uses active remaining stock, not old starting totals',
    () {
      final report = BranchReportData({
        'branches': [
          {'_id': 'branch-a'},
          {'_id': 'branch-b', 'isVoided': true},
        ],
        'staff_inventory': [
          {
            '_id': 'allocation-a',
            'staffId': 'branch-a',
            'items': [
              {
                'id': 'cookie-1',
                'name': 'Cookie',
                'stock': 7,
                'assignedStartingStock': 449,
              },
              {
                'id': 'cookie-2',
                'name': 'Brownie',
                'stock': 2,
                'assignedStartingStock': 50,
              },
            ],
          },
          {
            '_id': 'returned-allocation',
            'staffId': 'branch-a',
            'isDeleted': true,
            'items': [
              {'id': 'old-item', 'name': 'Returned item', 'stock': 500},
            ],
          },
          {
            '_id': 'other-branch-allocation',
            'staffId': 'branch-b',
            'items': [
              {'id': 'other-item', 'name': 'Other', 'stock': 300},
            ],
          },
        ],
        'sales_inventory': [],
        'coffee_products': [],
        'coffee_addons': [],
        'completed_sales': [],
        'stock_adjustments': [],
        'staff_inventory_history': [],
      });

      expect(currentAllocatedQuantity(report, DateTime(2026, 10, 17)), 9);
    },
  );
}
