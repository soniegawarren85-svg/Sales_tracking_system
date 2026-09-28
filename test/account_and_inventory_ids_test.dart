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
