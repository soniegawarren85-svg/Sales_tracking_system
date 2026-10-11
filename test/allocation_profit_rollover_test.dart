import 'package:flutter_test/flutter_test.dart';
import 'dart:convert';
import 'package:sales_tracking/services/branch_report_csv.dart';
import 'package:sales_tracking/services/branch_report_data.dart';
import 'package:sales_tracking/widgets/branch_inventory_monitor.dart';

void main() {
  final day = DateTime(2025, 6, 10);
  Map<String, dynamic> item(int qty, {double cost = 25}) => {
    'id': 'cookie',
    'publicId': 'CO-001',
    'name': 'Cookie',
    'quantity': qty,
    'price': 50,
    'costPrice': cost,
  };
  BranchReportData fixture() => BranchReportData({
    'staff_inventory_history': [
      {
        'staffId': 'b',
        'createdAt': day.subtract(const Duration(days: 1)),
        'items': [item(100)],
      },
      {
        'staffId': 'b',
        'createdAt': day.add(const Duration(hours: 10)),
        'items': [item(50)],
      },
    ],
    'completed_sales': [
      {
        'branchId': 'b',
        'timestamp': day.subtract(const Duration(hours: 4)),
        'total': 2500,
        'items': [item(50)],
      },
      {
        'branchId': 'b',
        'timestamp': day.add(const Duration(hours: 12)),
        'total': 1000,
        'items': [item(20)],
      },
    ],
  });
  test('opening carries previous closing and additions are separate', () {
    final data = fixture();
    final today = data.items('b', day, day.add(const Duration(days: 1))).single;
    expect(today['starting'], 50);
    expect(today['added'], 50);
    expect(today['remaining'], 80);
    expect(today['totalCost'], 500);
    expect(today['profit'], 500);
    expect((today['history'] as List).first['time'], day);
    final tomorrow = data
        .items(
          'b',
          day.add(const Duration(days: 1)),
          day.add(const Duration(days: 2)),
        )
        .single;
    expect(tomorrow['starting'], 80);
    expect(tomorrow['remaining'], 80);
    expect(tomorrow['added'], 0);
    expect(tomorrow['sold'], 0);
  });
  test(
    'sale cost snapshot survives catalog edits; discounts reduce profit',
    () {
      final data = BranchReportData({
        'sales_inventory': [
          {
            '_id': 'cat',
            'items': [item(1, cost: 40)],
          },
        ],
        'completed_sales': [
          {
            'branchId': 'b',
            'timestamp': day,
            'total': 90,
            'discount': 10,
            'items': [item(2)],
          },
          {
            'branchId': 'b',
            'timestamp': day.add(const Duration(hours: 1)),
            'total': -20,
            'type': 'refund',
            'items': [item(1)],
          },
        ],
      });
      final totals = data.totals('b', day, day.add(const Duration(days: 1)));
      expect(totals['Total cost'], 50);
      expect(totals['Total profit'], 20);
      expect(
        data.items('b', day, day.add(const Duration(days: 1))).single['profit'],
        20,
      );
    },
  );
  test('expiry warning includes today through five days only', () {
    expect(inventoryNearExpiry(day, day), isTrue);
    expect(inventoryNearExpiry(day.add(const Duration(days: 5)), day), isTrue);
    expect(inventoryNearExpiry(day.add(const Duration(days: 6)), day), isFalse);
    expect(
      inventoryNearExpiry(day.subtract(const Duration(days: 1)), day),
      isFalse,
    );
  });
  test('CSV escapes names and exports selected-range profit totals', () {
    final data = fixture();
    data.collections['branches'] = [
      {'_id': 'b', 'name': 'SM, "Dagupan"'},
    ];
    final csv = utf8.decode(
      branchReportCsv(
        data,
        day,
        day.add(const Duration(days: 1)),
        branchId: 'b',
      ),
    );
    expect(
      branchReportCsv(
        data,
        day,
        day.add(const Duration(days: 1)),
        branchId: 'b',
      ).take(3),
      [239, 187, 191],
    );
    expect(csv, contains('"SM, ""Dagupan"""'));
    expect(csv, contains('"Total profit","500.00"'));
    expect(csvCell('=1+1'), '"\'=1+1"');
    expect(csvCell(-25), '"-25"');
  });
}
