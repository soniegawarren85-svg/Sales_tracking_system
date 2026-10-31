import 'package:flutter_test/flutter_test.dart';
import 'package:sales_tracking/services/inventory_void_service.dart';
import 'package:sales_tracking/widgets/admin_catalog.dart';

void main() {
  test('voided category, bundle, and beverage entries leave the catalog', () {
    final products = <Map<String, dynamic>>[
      {
        'id': 'category',
        'name': 'Pastries',
        'items': [
          {'id': 'sold-out', 'name': 'Cookie', 'stock': 0},
          {'id': 'other', 'name': 'Brownie', 'stock': 4},
        ],
      },
      {
        'id': 'bundle',
        'name': 'Cookie bundle',
        'isBundle': true,
        'bundleCount': 1,
        'items': <Map<String, dynamic>>[],
      },
    ];
    final coffees = <Map<String, dynamic>>[
      {'id': 'coffee', 'name': 'Latte'},
    ];

    expect(
      adminCatalogEntries(
        products,
        coffees,
        now: DateTime(2026, 1, 1),
      ).map((entry) => entry.name),
      containsAll(['Cookie', 'Brownie', 'Cookie bundle', 'Latte']),
    );

    products[0]['items'] = [
      {'id': 'sold-out', 'name': 'Cookie', 'stock': 0, 'isVoided': true},
      {'id': 'other', 'name': 'Brownie', 'stock': 4},
    ];
    products[1]['isDeleted'] = true;
    coffees[0]['isDeleted'] = true;

    expect(
      adminCatalogEntries(
        products,
        coffees,
        now: DateTime(2026, 1, 1),
      ).map((entry) => entry.name),
      ['Brownie'],
    );
  });

  test(
    'allocation cleanup matches variant IDs without removing same-name items',
    () {
      final remaining = removeAllocatedCatalogVariant(
        [
          {'id': 'variant-a', 'name': 'Cookie', 'stock': 0},
          {'variantId': 'variant-b', 'name': 'Cookie', 'stock': 3},
          {'id': 'other', 'name': 'Brownie'},
        ],
        {'id': 'variant-a', 'name': 'Cookie'},
      );

      expect(remaining, [
        {'variantId': 'variant-b', 'name': 'Cookie', 'stock': 3},
        {'id': 'other', 'name': 'Brownie'},
      ]);
    },
  );

  test('ambiguous legacy names are preserved during allocation cleanup', () {
    final allocated = [
      {'name': 'Cookie'},
      {'name': 'Cookie'},
    ];

    expect(
      removeAllocatedCatalogVariant(allocated, {'name': 'Cookie'}),
      allocated,
    );
  });
}
