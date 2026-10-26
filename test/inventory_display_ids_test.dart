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
        'price': 99,
      };

      expect(inventoryVariantsMatch(updatedCatalog, allocated), isTrue);
    },
  );

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
