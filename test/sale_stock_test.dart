import 'package:flutter_test/flutter_test.dart';
import 'package:sales_tracking/services/sale_stock.dart';

void main() {
  test(
    'bundle stock combines allocations and allocates a sale oldest first',
    () {
      final lines = bundleSaleLines({
        'name': 'Bundle Cakes',
        'bundleInventorySources': [
          {
            'staffInventoryDocId': 'new-batch',
            'stock': 5,
            'instances': [
              for (var i = 1; i <= 5; i++)
                {
                  'id': 'new-$i',
                  'status': 'available',
                  'assignedAt': DateTime(2026, 10, 16),
                },
            ],
          },
          {
            'staffInventoryDocId': 'old-batch',
            'stock': 2,
            'instances': [
              for (var i = 1; i <= 2; i++)
                {
                  'id': 'old-$i',
                  'status': 'available',
                  'assignedAt': DateTime(2026, 10, 15),
                },
            ],
          },
        ],
      }, 7);

      expect(lines, hasLength(2));
      expect(lines.map((line) => line['quantity']).reduce((a, b) => a + b), 7);
      expect(lines.first['staffInventoryDocId'], 'old-batch');
      expect(lines.first['bundleInstanceIds'], ['old-1', 'old-2']);
    },
  );

  test('sale marks only selected bundle instances sold', () {
    final updated = applySaleStock(
      {
        'isBundle': true,
        'bundleCount': 2,
        'bundleInstances': [
          {'id': 'first', 'status': 'available'},
          {'id': 'second', 'status': 'available'},
        ],
      },
      'sale-1',
      [
        {
          'quantity': 1,
          'bundleInstanceIds': ['second'],
        },
      ],
    );

    expect(updated['bundleCount'], 1);
    expect((updated['bundleInstances'] as List).map((row) => row['status']), [
      'available',
      'sold',
    ]);
  });
}
