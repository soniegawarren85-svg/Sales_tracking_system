import 'package:flutter_test/flutter_test.dart';
import 'package:sales_tracking/services/staff_addon_inventory.dart';

void main() {
  test('standalone branch add-ons appear alongside beverage options', () {
    final addons = mergeStaffAddonOptions(
      beverageOptions: [
        {'id': 'catalog-cream', 'name': 'Cream'},
      ],
      allocatedAddons: [
        {'id': 'CHEWY-1', 'name': 'Chewy', 'sourceDocId': 'branch_addon_chewy'},
      ],
    );

    expect(addons.map((addon) => addon['name']), ['Chewy', 'Cream']);
    expect(addons.first['staffInventoryDocId'], 'branch_addon_chewy');
  });

  test('allocated add-on record takes precedence over its catalog option', () {
    final addons = mergeStaffAddonOptions(
      beverageOptions: [
        {'id': 'catalog-chewy', 'name': 'Chewy', 'priceDelta': 10},
      ],
      allocatedAddons: [
        {
          'id': 'CHEWY-1',
          'name': 'Chewy',
          'priceDelta': 15,
          'sourceDocId': 'branch_addon_chewy',
        },
      ],
    );

    expect(addons, hasLength(1));
    expect(addons.single['id'], 'CHEWY-1');
    expect(addons.single['priceDelta'], 15);
  });
}
