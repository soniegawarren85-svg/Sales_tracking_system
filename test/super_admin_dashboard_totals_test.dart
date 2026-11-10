import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sales_tracking/Super_admin_pages/dashboard_totals.dart';
import 'package:sales_tracking/services/branch_report_data.dart';

void main() {
  test('Super Admin staff total counts every active cashier account once', () {
    final accounts = [
      {
        '_id': 'cashier-1',
        'role': 'staff',
        'status': 'accepted',
        'staffId': 'STF-001',
      },
      {
        '_id': 'cashier-1',
        'role': 'cashier',
        'status': 'accepted',
        'staffId': 'STF-001',
      },
      {
        '_id': 'cashier-2',
        'role': 'staff',
        'status': 'Accepted',
        'staffId': 'STF-002',
      },
      {
        '_id': 'admin-1',
        'role': 'admin',
        'status': 'accepted',
        'adminId': 'ADM-001',
      },
      {
        '_id': 'inactive-cashier',
        'role': 'staff',
        'status': 'deactivated',
        'staffId': 'STF-003',
      },
    ];

    expect(superAdminCashierCount(accounts), 2);
  });

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
        'staff_inventory_history': [
          {
            'staffId': 'branch-a',
            'createdAt': Timestamp.fromDate(DateTime(2026, 10, 17, 10)),
            'items': [
              {'id': 'cookie-1', 'name': 'Cookie', 'quantity': 7},
              {'id': 'cookie-2', 'name': 'Brownie', 'quantity': 2},
            ],
          },
          {
            'staffId': 'branch-b',
            'createdAt': Timestamp.fromDate(DateTime(2026, 10, 17, 10)),
            'items': [
              {'id': 'other-item', 'name': 'Other', 'quantity': 300},
            ],
          },
        ],
      });

      expect(currentAllocatedQuantity(report, DateTime(2026, 10, 17)), 9);
    },
  );

  test('daily allocated total excludes non-assignment history records', () {
    final history = [
      {
        'staffId': 'branch-a',
        'type': 'assignment',
        'items': [
          {'quantity': 4},
          {'quantity': 3},
        ],
      },
      {
        'staffId': 'branch-a',
        'type': 'unbundle',
        'items': [
          {'quantity': 20},
        ],
      },
      {
        'staffId': 'branch-b',
        'type': 'assignment',
        'quantities': {'item': 100},
      },
      {
        'staffId': 'branch-a',
        'quantities': {'legacy-item': 2},
      },
    ];

    expect(allocatedQuantityFromHistory(history, {'branch-a'}), 9);
  });
}
