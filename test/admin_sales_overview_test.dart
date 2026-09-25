import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:sales_tracking/widgets/admin_recent_sales.dart';
import 'package:sales_tracking/widgets/admin_sales_overview.dart';

void main() {
  test(
    'Today totals exclude older receipts and tomorrow, retaining local midnight',
    () {
      final today = DateTime(2026, 9, 25);
      final records = <Map<String, dynamic>>[
        {
          'total': 14938.20,
          'timestamp': Timestamp.fromDate(DateTime(2026, 9, 24, 23, 59)),
        },
        {'total': 100, 'timestamp': Timestamp.fromDate(today)},
        {
          'total': 200,
          'timestamp': Timestamp.fromDate(DateTime(2026, 9, 25, 23, 59, 59)),
        },
        {'total': 500, 'timestamp': Timestamp.fromDate(DateTime(2026, 9, 26))},
        {'total': 900},
      ];
      final sales = salesForDay(records, today);
      expect(sales.map((sale) => sale['total']), [100, 200]);
      final emptyToday = salesForDay([records.first], today);
      expect(emptyToday, isEmpty);
      expect(
        emptyToday.fold<double>(
          0,
          (total, sale) => total + saleNumber(sale['total']),
        ),
        0,
      );
      expect(
        salesForDay(
          records,
          DateTime(2026, 9, 26),
        ).map((sale) => sale['total']),
        [500],
      );
    },
  );
  test('Sales overview excludes refund, void and cancelled receipts', () {
    final sales = completedReceipts([
      {
        'salesId': 'S-1',
        'total': 250,
        'items': [
          {'quantity': 3},
          {'quantity': 2},
        ],
      },
      {'salesId': 'R-1', 'type': 'refund', 'total': -50},
      {'salesId': 'S-2', 'status': 'voided', 'total': 100},
      {'salesId': 'S-3', 'isVoided': true, 'total': 200},
      {'salesId': 'S-4', 'status': 'cancelled', 'total': 300},
      {'salesId': 'S-5', 'fullyRefunded': true, 'total': 100},
      {'salesId': 'S-6', 'isDeleted': true, 'total': 100},
      {
        'salesId': 'S-7',
        'total': '150.50',
        'items': [
          {'quantity': '1'},
        ],
      },
    ]);
    expect(sales, hasLength(2));
    expect(
      sales.fold<double>(0, (total, sale) => total + saleNumber(sale['total'])),
      400.5,
    );
    expect(
      sales
          .expand(saleItems)
          .fold<double>(
            0,
            (total, item) => total + saleNumber(item['quantity']),
          ),
      6,
    );
  });
}
