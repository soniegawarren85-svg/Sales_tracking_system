import 'package:flutter_test/flutter_test.dart';
import 'package:sales_tracking/widgets/staff_inventory_history.dart';

void main() {
  final today = DateTime(2026, 10, 6, 12);

  test(
    'category history combines only this staff member sales and reductions',
    () {
      final entries = staffInventoryHistoryEntries(
        staffId: 'staff-a',
        kind: 'categories',
        categoryId: 'category-1',
        categoryName: 'Cookies',
        itemIds: {'item-1'},
        itemNames: {'Cookie'},
        adjustments: [
          {
            'type': 'stock_adjustment',
            'staffId': 'staff-a',
            'categoryId': 'category-1',
            'itemId': 'item-1',
            'itemName': 'Cookie',
            'quantity': 2,
            'createdAt': today,
          },
        ],
        sales: [
          {
            'userId': 'staff-a',
            'timestamp': today,
            'items': [
              {
                'itemId': 'item-1',
                'name': 'Cookie',
                'quantity': 3,
                'price': 25,
              },
            ],
          },
          {
            'userId': 'staff-b',
            'timestamp': today,
            'items': [
              {'itemId': 'item-1', 'name': 'Cookie', 'quantity': 8},
            ],
          },
        ],
      );

      expect(entries.map((entry) => entry['activity']).toSet(), {
        'Reduce',
        'Sold',
      });
      expect(entries.map((entry) => entry['quantity']).toSet(), {2, 3});
    },
  );

  test('offline history shows the saved item name and offline status', () {
    final entries = staffInventoryHistoryEntries(
      staffId: 'staff-a',
      kind: 'categories',
      categoryId: 'category-1',
      categoryName: 'Cookies',
      itemIds: {'item-1'},
      itemNames: {'Cookie'},
      adjustments: const [],
      sales: const [],
      pendingOfflineReductions: [
        {
          'id': 'offline-reduction',
          'type': 'stock_adjustment',
          'staffId': 'staff-a',
          'inventoryId': 'category-1',
          'itemId': 'item-1',
          'itemName': 'Pistachio Cookie',
          'categoryName': 'Cookies',
          'quantity': 2,
          'queuedAt': today.toIso8601String(),
        },
      ],
    );

    expect(entries, hasLength(1));
    expect(entries.single['name'], 'Pistachio Cookie');
    expect(entries.single['offline'], isTrue);
    expect(entries.single['offlineStatus'], 'Saved offline');
  });

  test('synced offline adjustment remains marked as offline in history', () {
    final entries = staffInventoryHistoryEntries(
      staffId: 'staff-a',
      kind: 'categories',
      categoryId: 'category-1',
      categoryName: 'Cookies',
      itemIds: {'item-1'},
      itemNames: {'Cookie'},
      adjustments: [
        {
          'type': 'stock_adjustment',
          'staffId': 'staff-a',
          'categoryId': 'category-1',
          'itemId': 'item-1',
          'itemName': 'Pistachio Cookie',
          'quantity': 1,
          'offline': true,
          'syncStatus': 'synced',
          'createdAt': today,
        },
      ],
      sales: const [],
    );

    expect(entries.single['name'], 'Pistachio Cookie');
    expect(entries.single['offline'], isTrue);
    expect(entries.single['offlineStatus'], 'Saved offline');
  });

  test('bundle history is scoped to the selected allocated bundle', () {
    final entries = staffInventoryHistoryEntries(
      staffId: 'staff-a',
      kind: 'bundle',
      categoryId: 'bundle-instance-1',
      categoryName: 'Cake Bundle',
      itemIds: {'bundle-instance-1'},
      itemNames: {'Cake Bundle'},
      adjustments: [
        {
          'type': 'bundle_instance_adjustment',
          'staffId': 'staff-a',
          'categoryId': 'bundle-instance-1',
          'itemName': 'Cake Bundle',
          'quantity': 1,
          'createdAt': today,
        },
        {
          'type': 'bundle_instance_adjustment',
          'staffId': 'staff-a',
          'categoryId': 'bundle-instance-2',
          'itemName': 'Another Bundle',
          'quantity': 1,
          'createdAt': today,
        },
      ],
      sales: [
        {
          'userId': 'staff-a',
          'timestamp': today,
          'items': [
            {
              'isBundle': true,
              'sourceInventoryId': 'bundle-instance-1',
              'name': 'Cake Bundle',
              'quantity': 2,
            },
            {
              'isBundle': true,
              'sourceInventoryId': 'bundle-instance-2',
              'name': 'Another Bundle',
              'quantity': 4,
            },
          ],
        },
      ],
    );

    expect(entries.map((entry) => entry['activity']).toSet(), {
      'Reduce',
      'Sold',
    });
    expect(entries.map((entry) => entry['quantity']).toSet(), {1, 2});
  });

  test('beverage history includes coffee sales and voids', () {
    final entries = staffInventoryHistoryEntries(
      staffId: 'staff-a',
      kind: 'beverages',
      categoryId: 'coffee-category',
      categoryName: 'Coffee',
      itemIds: {'coffee-category', 'coffee-1'},
      itemNames: {'Coffee'},
      adjustments: [
        {
          'type': 'coffee_void',
          'staffId': 'staff-a',
          'categoryId': 'coffee-category',
          'coffeeId': 'coffee-1',
          'itemName': 'Coffee',
          'quantity': 1,
          'createdAt': today,
        },
      ],
      sales: [
        {
          'userId': 'staff-a',
          'timestamp': today,
          'items': [
            {
              'isCoffee': true,
              'coffeeId': 'coffee-1',
              'name': 'Coffee',
              'quantity': 3,
            },
          ],
        },
      ],
    );

    expect(entries.map((entry) => entry['activity']).toSet(), {
      'Reduce',
      'Sold',
    });
    expect(entries.map((entry) => entry['quantity']).toSet(), {1, 3});
  });

  test('add-on history counts servings for each sold beverage', () {
    final entries = staffInventoryHistoryEntries(
      staffId: 'staff-a',
      kind: 'addons',
      categoryId: '',
      categoryName: 'Beverages Add-ons',
      itemIds: {'AD-007'},
      itemNames: {'Extra Cream'},
      adjustments: const [],
      sales: [
        {
          'userId': 'staff-a',
          'timestamp': today,
          'items': [
            {
              'isCoffee': true,
              'name': 'Dubai Chewy Smoothie',
              'addonName': 'Extra Cream',
              'addonId': 'AD-007',
              'quantity': 3,
            },
          ],
        },
      ],
    );

    expect(entries, hasLength(1));
    expect(entries.single['activity'], 'Sold');
    expect(entries.single['name'], 'Extra Cream');
    expect(entries.single['quantity'], 3);
  });
}
