import 'package:flutter_test/flutter_test.dart';
import 'package:sales_tracking/services/bundle_stock_service.dart';

void main() {
  test('bundle expiration uses available batch snapshots only', () {
    final expiry = bundleExpirationDateLabel({
      'bundleCount': 1,
      'items': [
        {'name': 'Current recipe', 'expirationDate': '2027-01-01'},
      ],
      'bundleInstances': [
        {
          'id': 'available',
          'status': 'available',
          'items': [
            {'name': 'Cookie', 'expirationDate': '2026-12-31'},
          ],
        },
        {
          'id': 'reduced',
          'status': 'reduced',
          'items': [
            {'name': 'Cookie', 'expirationDate': '2026-10-01'},
          ],
        },
        {
          'id': 'sold',
          'status': 'sold',
          'items': [
            {'name': 'Cookie', 'expirationDate': '2026-09-01'},
          ],
        },
      ],
    }, now: DateTime(2026, 10, 16));

    expect(expiry, '2026-12-31');
  });

  test('bundle with no available batches has no expiration label', () {
    expect(
      bundleExpirationDateLabel({
        'bundleCount': 0,
        'items': [
          {'name': 'Cookie', 'expirationDate': '2026-12-31'},
        ],
        'bundleInstances': [
          {
            'id': 'reduced',
            'status': 'reduced',
            'items': [
              {'name': 'Cookie', 'expirationDate': '2026-10-01'},
            ],
          },
        ],
      }, now: DateTime(2026, 10, 16)),
      '--',
    );
  });

  test(
    'bundle allocation version ignores batch-specific ingredient expiry',
    () {
      final first = {
        'name': 'Bundle Cakes',
        'price': 350,
        'costPrice': 150,
        'items': [
          {
            'sourceInventoryId': 'cake',
            'variantId': 'chocolate',
            'name': 'Chocolate cake',
            'quantity': 2,
            'expirationDate': '2026-12-31',
          },
        ],
      };
      final second = {
        ...first,
        'items': [
          {
            'sourceInventoryId': 'cake',
            'variantId': 'chocolate',
            'name': 'Chocolate cake',
            'quantity': 2,
            'expirationDate': '2027-01-31',
          },
        ],
      };
      final revised = {
        ...second,
        'items': [
          {
            'sourceInventoryId': 'cake',
            'variantId': 'chocolate',
            'name': 'Chocolate cake',
            'quantity': 3,
            'expirationDate': '2027-01-31',
          },
        ],
      };

      expect(
        bundleAllocationVersionKey(first),
        bundleAllocationVersionKey(second),
      );
      expect(
        bundleAllocationVersionKey(first),
        isNot(bundleAllocationVersionKey(revised)),
      );
    },
  );

  test(
    'staff inventory grouping combines allocation versions of one bundle',
    () {
      expect(
        bundleInventoryGroupKey({
          'bundleId': 'BND-001',
          'sourceInventoryId': 'old-source',
          'bundleVersionId': 'old-recipe',
          'name': 'Bundle Cakes',
        }),
        bundleInventoryGroupKey({
          'bundleId': 'BND-001',
          'sourceInventoryId': 'new-source',
          'bundleVersionId': 'new-recipe',
          'name': 'Bundle Cakes',
        }),
      );
    },
  );
}
