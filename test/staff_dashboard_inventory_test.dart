import 'package:flutter_test/flutter_test.dart';
import 'package:sales_tracking/services/bundle_stock_service.dart';
import 'package:sales_tracking/services/inventory_display_ids.dart';
import 'package:sales_tracking/services/staff_dashboard_inventory.dart';

void main() {
  test(
    'sold-out bundle allocations stay visible and available total uses rows',
    () {
      final allocations = <Map<String, dynamic>>[
        {
          'bundleCount': 6,
          'bundleInstances': [
            {'id': 'batch-a-1', 'status': 'available'},
            {'id': 'batch-a-2', 'status': 'sold'},
          ],
        },
        {
          'bundleCount': 1,
          'bundleInstances': [
            {'id': 'batch-b-1', 'status': 'available'},
          ],
        },
        {
          'bundleCount': 0,
          'bundleInstances': [
            {'id': 'batch-c-1', 'status': 'sold'},
            {'id': 'batch-c-2', 'status': 'reduced'},
          ],
        },
      ];

      expect(allocations.where(staffBundleAllocationVisible), hasLength(3));
      expect(availableStaffBundleCount(allocations), 2);
      expect(availableBundleStock(allocations.last), 0);
    },
  );

  test('deleted and expired bundle allocations remain hidden', () {
    final today = DateTime(2026, 10, 31);
    expect(
      staffBundleAllocationVisible({'isDeleted': true}, now: today),
      isFalse,
    );
    expect(
      staffBundleAllocationVisible({
        'expirationDate': DateTime(2026, 10, 30),
        'bundleCount': 0,
      }, now: today),
      isFalse,
    );
  });

  test('category carousel uses one unique image per inventory item', () {
    final images = staffDashboardImageUrls({
      'imageUrl': 'category.jpg',
      'items': [
        {'publicId': 'cookie-1', 'imageUrl': 'cookie-1.jpg'},
        {
          'publicId': 'cookie-1',
          'imageUrl': 'cookie-1.jpg',
        }, // Expanded duplicate allocation record.
        {
          'publicId': 'cookie-2',
          'images': ['cookie-2.jpg', 'extra-cookie-2.jpg'],
        },
        {
          'publicId': 'cookie-3',
          'photos': ['cookie-3.jpg'],
        },
      ],
    });

    expect(images, ['cookie-1.jpg', 'cookie-2.jpg', 'cookie-3.jpg']);
  });

  test('category images remain a fallback when inventory items have none', () {
    expect(
      staffDashboardImageUrls({
        'images': ['category-1.jpg', 'category-2.jpg'],
        'items': [
          {'name': 'Cookie', 'imageUrl': ''},
        ],
      }),
      ['category-1.jpg', 'category-2.jpg'],
    );
  });

  test('dashboard uses the latest catalog image for allocated variants', () {
    final allocated = <String, dynamic>{
      'imageUrl': 'category.jpg',
      'items': [
        {
          'id': 'allocated-testt',
          'sourceItemId': 'catalog-testt',
          'name': 'Testt ulit',
          'stock': 5,
        },
      ],
    };
    final catalog = <String, dynamic>{
      'items': [
        {'id': 'catalog-testt', 'name': 'Testt ulit', 'imageUrl': 'testt.jpg'},
      ],
    };
    final aligned = alignInventoryDisplayIds(allocated, catalog);

    expect(staffDashboardImageUrls(aligned), ['testt.jpg']);
  });
}
