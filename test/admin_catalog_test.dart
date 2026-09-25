import 'package:flutter_test/flutter_test.dart';
import 'package:sales_tracking/widgets/admin_catalog.dart';

void main() {
  final today = DateTime(2026, 9, 24);
  final category = <String, dynamic>{
    'id': 'category-doc',
    'categoryId': 'CAT-001',
    'name': 'Cookies',
    'imageUrl': 'category.jpg',
    'items': [
      {
        'id': 'VAR-001',
        'name': 'Pistachio',
        'startingStock': 20,
        'stock': 7,
        'imageUrl': 'pistachio.jpg',
      },
      {'id': 'VAR-002', 'name': 'Chocolate', 'startingStock': 0},
      {
        'id': 'VAR-003',
        'name': 'Expired',
        'startingStock': 30,
        'expirationDate': '2026-09-23',
      },
      {
        'id': 'VAR-004',
        'name': 'Removed',
        'startingStock': 40,
        'isDeleted': true,
      },
    ],
  };

  test('Inventory lists individual item IDs and current stock', () {
    final entries = adminCatalogEntries([category], [], now: today);
    expect(entries.map((entry) => entry.id), ['VAR-001', 'VAR-002']);
    expect(entries.first.stock, 7);
    expect(entries.last.available, isFalse);
    // Editing a visible item must not discard expired or voided siblings.
    expect(entries.first.source['items'], hasLength(4));
    expect(entries.first.details['id'], 'VAR-001');
    // A category's cover photo must not replace this item's own picture.
    expect(entries.first.images, ['pistachio.jpg']);
    expect(entries.last.images, isEmpty);
  });

  test('Home groups active variants and includes their carousel images', () {
    final entry = adminCatalogEntries(
      [category],
      [],
      gallery: true,
      now: today,
    ).single;
    expect(entry.name, 'Cookies');
    expect(entry.id, 'CAT-001');
    expect(entry.stock, 7);
    expect(entry.images, ['category.jpg', 'pistachio.jpg']);
  });

  test('Bundle stock excludes sold and reduced instances', () {
    final entry = adminCatalogEntries(
      [
        {
          'id': 'bundle-doc',
          'bundleId': '',
          'isBundle': true,
          'bundleCount': 99,
          'bundleInstances': [
            {'status': 'available'},
            {'status': 'sold'},
            {'status': 'reduced'},
          ],
        },
      ],
      [],
      now: today,
    ).single;
    expect(entry.id, 'bundle-doc');
    expect(entry.stock, 1);
  });

  test('Coffee uses existing IDs and does not invent stock quantities', () {
    final entries = adminCatalogEntries([], [
      {'id': 'coffee-doc', 'coffeeId': 'COF-001', 'name': 'Latte'},
      {'id': 'removed-coffee', 'isDeleted': true},
      {'id': 'unavailable-coffee', 'name': 'Mocha', 'isAvailable': false},
    ], now: today);
    expect(entries.length, 2);
    expect(entries.first.id, 'COF-001');
    expect(entries.first.stock, isNull);
    expect(entries.last.available, isFalse);
  });
}
