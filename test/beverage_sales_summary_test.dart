import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sales_tracking/services/beverage_sales_summary.dart';

void main() {
  group('beverageSalesToday', () {
    final now = DateTime(2026, 10, 22, 19, 0);

    test('counts only today sales from assigned branches', () {
      final total = beverageSalesToday(
        now: now,
        branchIds: {'branch-a'},
        coffeeId: 'CF-001',
        coffeeName: 'Latte',
        publicId: 'CF-001',
        sales: [
          {
            'branchId': 'branch-a',
            'timestamp': DateTime(2026, 10, 22, 8),
            'status': 'completed',
            'items': [
              {'isCoffee': true, 'coffeeId': 'CF-001', 'quantity': 3},
            ],
          },
          {
            'branchId': 'branch-a',
            'timestamp': Timestamp.fromDate(DateTime(2026, 10, 21, 23, 59)),
            'status': 'completed',
            'items': [
              {'isCoffee': true, 'coffeeId': 'CF-001', 'quantity': 20},
            ],
          },
          {
            'branchId': 'branch-b',
            'timestamp': DateTime(2026, 10, 22, 9),
            'status': 'completed',
            'items': [
              {'isCoffee': true, 'coffeeId': 'CF-001', 'quantity': 100},
            ],
          },
          {
            'branchId': 'branch-a',
            'timestamp': DateTime(2026, 10, 22, 10),
            'status': 'completed',
            'items': [
              {'isCoffee': true, 'coffeeId': 'CF-002', 'quantity': 50},
            ],
          },
        ],
      );

      expect(total, 3);
    });

    test(
      'subtracts same-day refunds and never shows a negative sold count',
      () {
        final sales = [
          {
            'branchId': 'branch-a',
            'timestamp': DateTime(2026, 10, 22, 10),
            'status': 'completed',
            'items': [
              {'isCoffee': true, 'coffeeId': 'CF-001', 'quantity': 2},
            ],
          },
          {
            'branchId': 'branch-a',
            'timestamp': DateTime(2026, 10, 22, 11),
            'type': 'refund',
            'status': 'refund',
            'items': [
              {'isCoffee': true, 'coffeeId': 'CF-001', 'quantity': 5},
            ],
          },
        ];

        expect(
          beverageSalesToday(
            sales: sales,
            now: now,
            branchIds: {'branch-a'},
            coffeeId: 'CF-001',
            coffeeName: 'Latte',
            publicId: 'CF-001',
          ),
          0,
        );
      },
    );
  });

  test('size price uses its actual selling price and avoids false zero', () {
    expect(
      beverageSizeSellingPrice({
        'price': 105,
        'basePrice': 0,
        'sizePriceDelta': 105,
      }),
      105,
    );
    expect(
      beverageSizeSellingPrice({'basePrice': 100, 'sizePriceDelta': 20}),
      120,
    );
    expect(beverageSizeSellingPrice({'price': 0}), 0);
  });
}
