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

  test('selling all remaining category stock leaves it at zero', () {
    final updated = applySaleStock(
      {
        'items': [
          {'id': 'cake-1', 'stock': 3, 'startingStock': 10},
        ],
      },
      'sale-all',
      [
        {'itemId': 'cake-1', 'quantity': 3},
      ],
    );

    expect((updated['items'] as List).single['stock'], 0);
  });

  test('stale category sales never make stock negative', () {
    final updated = applySaleStock(
      {
        'items': [
          {'id': 'cake-1', 'stock': 2, 'startingStock': 10},
        ],
      },
      'sale-stale',
      [
        {'itemId': 'cake-1', 'quantity': 3},
      ],
    );

    expect((updated['items'] as List).single['stock'], 0);
  });

  test('selling every available bundle leaves zero and marks all sold', () {
    final updated = applySaleStock(
      {
        'isBundle': true,
        'bundleCount': 2,
        'bundleInstances': [
          {'id': 'first', 'status': 'available'},
          {'id': 'second', 'status': 'available'},
        ],
      },
      'sale-all-bundles',
      [
        {
          'quantity': 2,
          'bundleInstanceIds': ['first', 'second'],
        },
      ],
    );

    expect(updated['bundleCount'], 0);
    expect((updated['bundleInstances'] as List).map((row) => row['status']), [
      'sold',
      'sold',
    ]);
  });

  test('bundle sale uses remaining available units when allocation IDs stale', () {
    final updated = applySaleStock(
      {
        'isBundle': true,
        'bundleCount': 1,
        'bundleInstances': [
          {'id': 'current-instance', 'status': 'available'},
        ],
      },
      'sale-stale-allocation',
      [
        {
          'quantity': 1,
          'bundleInstanceIds': ['old-instance'],
        },
      ],
    );

    expect(updated['bundleCount'], 0);
    expect(
      (updated['bundleInstances'] as List).single['status'],
      'sold',
    );
  });
}
