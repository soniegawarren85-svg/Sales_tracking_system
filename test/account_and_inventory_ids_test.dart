import 'package:flutter_test/flutter_test.dart';
import 'package:sales_tracking/services/account_username.dart';
import 'package:sales_tracking/services/inventory_display_ids.dart';

void main() {
  test('admin and staff login accept only three-digit account IDs', () {
    for (final value in ['ADM-001', 'adm-002', 'STF-001']) {
      expect(isValidAccountLoginUsername(value), isTrue);
    }
    for (final value in ['ADM-0001', 'ADM-01', 'STF-0001', 'ADM-OO1']) {
      expect(isValidAccountLoginUsername(value), isFalse);
    }
    expect(accountUsernameAliases('ADM-001'), contains('ADM-0001'));
  });
  test('staff login requires exactly three numeric digits', () {
    expect(isValidStaffLoginUsername('STF-001'), isTrue);
    expect(isValidStaffLoginUsername(' stf-001 '), isTrue);
    for (final value in ['STF-0001', 'STF-01', 'STF-OO1', 'STF-1']) {
      expect(isValidStaffLoginUsername(value), isFalse);
    }
  });
  test('displayed usernames match legacy stored IDs', () {
    expect(normalizeAccountUsername('stf-001'), 'STF-001');
    expect(normalizeAccountUsername('STF-0001'), 'STF-001');
    expect(normalizeAccountUsername('adm-0001'), 'ADM-0001');
    expect(normalizeAccountUsername('ADM-001'), 'ADM-0001');
    expect(normalizeAccountUsername('STF–002'), 'STF-002');
    expect(
      normalizeAccountUsername('STF-002'),
      isNot(normalizeAccountUsername('STF-001')),
    );
    expect(
      accountUsernameAliases('stf-001'),
      containsAll(['STF-001', 'STF-0001', 'stf-001', 'stf-0001']),
    );
  });
  test('stale allocation category identity follows its active catalog', () {
    expect(
      inventoryCategoryIdentity(
        {'name': 'Cakes', 'categoryId': 'CAT-003'},
        catalog: {'name': 'Cakes', 'publicId': 'CAT-018'},
      ),
      inventoryCategoryIdentity({'name': 'Cakes', 'categoryId': 'CAT-018'}),
    );
  });
  test('latest same-name catalog category wins over older public ID', () {
    final old = {
      'name': 'Cakes',
      'publicId': 'CAT-003',
      'timestamp': DateTime(2026, 11, 10),
    };
    final current = {
      'name': 'Cakes',
      'publicId': 'CAT-018',
      'timestamp': DateTime(2026, 11, 14),
    };
    expect(inventoryCatalogIsNewer(current, old), isTrue);
    expect(inventoryCatalogIsNewer(old, current), isFalse);
    expect(
      inventoryCategoryIdentity(current),
      inventoryCategoryIdentity({'name': 'Cakes', 'publicId': 'CAT-018'}),
    );
  });
  test(
    'legacy category item allocations combine by current catalog identity',
    () {
      final merged = aggregateInventoryAllocationItems([
        {
          'id': 'legacy-item',
          'name': 'Pistachio',
          'publicId': 'PISTACHIO',
          'stock': 2,
        },
        {
          'id': 'current-item',
          'name': 'New Cake',
          'publicId': 'NEW-CAKE',
          'stock': 1,
        },
        {
          'id': 'another-item',
          'name': 'Biscoff',
          'publicId': 'BISCOFF',
          'stock': 3,
        },
      ]);

      expect(merged, hasLength(3));
      expect(
        merged.fold<int>(0, (total, item) => total + (item['stock'] as int)),
        6,
      );
    },
  );
  test(
    'allocation shows central item codes without changing stock references',
    () {
      final allocation = {
        'sourceInventoryId': 'root',
        'stock': 5,
        'items': [
          {'id': 'legacy-item', 'stock': 3, 'name': 'Cookie'},
        ],
      };
      final source = {
        'publicId': 'CAT-001',
        'stock': 100,
        'items': [
          {'id': 'legacy-item', 'publicId': 'CO-004', 'stock': 90},
        ],
      };
      final aligned = alignInventoryDisplayIds(allocation, source);
      final item = (aligned['items'] as List).first as Map<String, dynamic>;
      expect(inventoryDisplayId(item), 'CO-004');
      expect(item['id'], 'legacy-item');
      expect(item['stock'], 3);
      expect(aligned['stock'], 5);
      expect(aligned['sourceInventoryId'], 'root');
    },
  );
  test(
    'allocation inventory prices follow the matching current catalog variant',
    () {
      final aligned = alignInventoryDisplayIds(
        {
          'items': [
            {
              'id': 'shared-category-id',
              'name': 'Cookie',
              'variant': 'Pistachio',
              'price': 100,
              'stock': 17,
            },
          ],
        },
        {
          'items': [
            {
              'id': 'shared-category-id',
              'name': 'Cookie',
              'variant': 'Chocolate',
              'price': 99,
            },
            {
              'id': 'shared-category-id',
              'name': 'Cookie',
              'variant': 'Pistachio',
              'price': 120,
            },
          ],
        },
      );

      final item = (aligned['items'] as List).single as Map<String, dynamic>;
      expect(item['price'], 120);
      expect(item['stock'], 17);
    },
  );
  test('shared catalog ID cannot match a different inventory variant', () {
    expect(
      inventoryVariantsMatch(
        {'id': 'shared', 'name': 'Cookie', 'variant': 'Chocolate'},
        {'id': 'shared', 'name': 'Cookie', 'variant': 'Pistachio'},
      ),
      isFalse,
    );
  });
  test('beverages and bundles use the same public code as admin', () {
    expect(
      inventoryDisplayId({'publicId': 'CF-002', 'coffeeId': '2026715-002'}),
      'CF-002',
    );
    expect(
      inventoryDisplayId({'publicId': 'BND-003', 'bundleId': 'legacy'}),
      'BND-003',
    );
  });
}
