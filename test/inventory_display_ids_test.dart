import 'package:flutter_test/flutter_test.dart';
import 'package:sales_tracking/services/inventory_display_ids.dart';

void main() {
  test(
    'allocation variant remains matched after the catalog price changes',
    () {
      final allocated = {
        'id': 'variant-1',
        'name': 'Pistachio Dubai Chewy',
        'price': 100,
      };
      final updatedCatalog = {
        'id': 'variant-1',
        'name': 'Pistachio Dubai Chewy',
        'price': 120,
      };

      expect(inventoryVariantsMatch(updatedCatalog, allocated), isTrue);
    },
  );

  test('allocation display uses latest catalog metadata by source item ID', () {
    final aligned = alignInventoryDisplayIds(
      {
        'items': [
          {
            'id': 'allocated-row',
            'sourceItemId': 'catalog-variant',
            'name': 'Pistachio Dubai Chewy',
            'price': 100,
            'imageUrl': 'old.jpg',
            'stock': 14,
          },
        ],
      },
      {
        'items': [
          {
            'id': 'catalog-variant',
            'name': 'Pistachio Dubai Chewy',
            'price': 120,
            'imageUrl': 'latest.jpg',
          },
        ],
      },
    );
    final item = (aligned['items'] as List).single as Map;
    expect(item['price'], 120);
    expect(item['imageUrl'], 'latest.jpg');
    expect(item['stock'], 14);
  });

  test('legacy allocation without matching IDs refreshes by old name', () {
    final aligned = alignInventoryDisplayIds(
      {
        'items': [
          {
            'id': 'legacy-allocation-row',
            'name': 'Pistachio Dubai Chewy',
            'price': 100,
            'stock': 14,
          },
        ],
      },
      {
        'items': [
          {
            'id': 'catalog-variant',
            'name': 'Pistachio Dubai Chewy',
            'price': 140,
          },
        ],
      },
    );
    final item = (aligned['items'] as List).single as Map;
    expect(item['price'], 140);
    expect(item['stock'], 14);
  });

  test('branch overrides remain in effect when catalog metadata changes', () {
    final aligned = alignInventoryDisplayIds(
      {
        'items': [
          {
            'id': 'catalog-variant',
            'name': 'Branch Pistachio',
            'branchNameOverride': 'Branch Pistachio',
            'price': 150,
            'branchPriceOverride': 150,
            'stock': 4,
          },
        ],
      },
      {
        'items': [
          {
            'id': 'catalog-variant',
            'name': 'Pistachio Dubai Chewy',
            'price': 120,
          },
        ],
      },
    );
    final item = (aligned['items'] as List).single as Map;
    expect(item['name'], 'Branch Pistachio');
    expect(item['price'], 150);
    expect(item['stock'], 4);
  });

  test('legacy variants match by normalized name without IDs', () {
    expect(
      inventoryVariantsMatch(
        {'name': '  Pistachio Dubai Chewy ', 'price': 99},
        {'name': 'pistachio dubai chewy', 'price': 100},
      ),
      isTrue,
    );
  });

  test('different legacy variants do not match', () {
    expect(
      inventoryVariantsMatch(
        {'name': 'Pistachio Dubai Chewy'},
        {'name': 'Chocolate Cookie'},
      ),
      isFalse,
    );
  });
}
