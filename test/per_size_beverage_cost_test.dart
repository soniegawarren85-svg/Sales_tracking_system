import 'package:flutter_test/flutter_test.dart';
import 'package:sales_tracking/services/bundle_stock_service.dart';

void main() {
  test('coffee size cost prefers its own cost then matching root size', () {
    expect(
      coffeeSizeCostPrice(
        size: {'name': 'Small', 'costPrice': 12},
        data: {'costPrice': 5},
        rootData: {
          'costPrice': 3,
          'sizes': [
            {'name': 'Small', 'costPrice': 10},
          ],
        },
      ),
      12,
    );
    expect(
      coffeeSizeCostPrice(
        size: {'name': 'Small'},
        data: {'costPrice': 5},
        rootData: {
          'costPrice': 3,
          'sizes': [
            {'name': 'Small', 'costPrice': 10},
          ],
        },
      ),
      10,
    );
  });

  test('legacy coffee records fall back to their shared cost', () {
    expect(
      coffeeSizeCostPrice(
        size: {'name': 'Large'},
        data: {'costPrice': 7},
        rootData: {'costPrice': 4},
      ),
      7,
    );
    expect(
      coffeeSizeCostPrice(
        size: {'name': 'Large'},
        data: {},
        rootData: {'costPrice': 4},
      ),
      4,
    );
  });

  test('bundle beverage options retain each size cost', () {
    final sizes = bundleBeverageSizes('coffee-1', {
      'name': 'Latte',
      'basePrice': 100,
      'costPrice': 20,
      'sizes': [
        {'name': 'Small', 'priceDelta': 0, 'costPrice': 15},
        {'name': 'Large', 'priceDelta': 25, 'costPrice': 28},
      ],
    });

    expect(sizes.map((size) => size['costPrice']), [15, 28]);
    expect(sizes.map((size) => size['price']), [100, 125]);
  });
}
