import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sales_tracking/services/bundle_stock_service.dart';

void main() {
  Future<FakeFirebaseFirestore> fixture({int? drinkStock}) async {
    final db = FakeFirebaseFirestore();
    await db.collection('sales_inventory').doc('cat').set({
      'name': 'Cookies',
      'items': [
        {
          'id': 'cookie',
          'name': 'Cookie',
          'stock': 20,
          'price': 99,
          'expirationDate': '2099-12-31',
        },
      ],
    });
    await db.collection('coffee_products').doc('latte').set({
      'name': 'Latte',
      'basePrice': 100,
      if (drinkStock != null) 'stock': drinkStock,
      'sizes': [
        {'name': 'Small', 'priceDelta': 10},
        {'name': 'Large', 'priceDelta': 30},
      ],
    });
    return db;
  }

  final recipe = [
    {'sourceInventoryId': 'cat', 'variantId': 'cookie', 'quantity': 2},
    {
      'sourceInventoryId': 'latte',
      'sourceCollection': 'coffee_products',
      'coffeeSize': 'Small',
      'quantity': 1,
    },
  ];
  test(
    'create and restock mixed bundle preserves beverage size and total price',
    () async {
      final db = await fixture();
      final service = BundleStockService(db);
      await service.restock(
        'mixed',
        3,
        {},
        ingredients: recipe,
        newBundle: {
          'name': 'Cookie and latte',
          'isBundle': true,
          'bundleCount': 0,
        },
      );
      var data = (await db.collection('sales_inventory').doc('mixed').get())
          .data()!;
      expect(data['bundleCount'], 3);
      final drink = bundleRows(data['items']).last;
      expect(drink['name'], 'Latte (Small)');
      expect(drink['price'], 110);
      expect(drink['coffeeSize'], 'Small');
      expect(drink['sourceCollection'], 'coffee_products');
      expect(
        (await db.collection('coffee_products').doc('latte').get())
            .data()!
            .containsKey('stock'),
        false,
      );
      await service.restock('mixed', 2, {});
      data = (await db.collection('sales_inventory').doc('mixed').get())
          .data()!;
      expect(data['bundleCount'], 5);
      expect(
        bundleRows(
          (await db.collection('sales_inventory').doc('cat').get())
              .data()!['items'],
        ).single['stock'],
        10,
      );
    },
  );
  test(
    'sizes share tracked beverage stock and failed create reserves nothing',
    () async {
      final db = await fixture(drinkStock: 3);
      await expectLater(
        BundleStockService(db).restock(
          'mixed',
          2,
          {},
          newBundle: {'bundleCount': 0},
          ingredients: [
            ...recipe,
            {
              'sourceInventoryId': 'latte',
              'sourceCollection': 'coffee_products',
              'coffeeSize': 'Large',
              'quantity': 1,
            },
          ],
        ),
        throwsStateError,
      );
      expect(
        (await db.collection('sales_inventory').doc('mixed').get()).exists,
        false,
      );
      expect(
        bundleRows(
          (await db.collection('sales_inventory').doc('cat').get())
              .data()!['items'],
        ).single['stock'],
        20,
      );
      expect(
        (await db.collection('coffee_products').doc('latte').get())
            .data()!['stock'],
        3,
      );
      await BundleStockService(db).restock(
        'mixed',
        2,
        {},
        newBundle: {'bundleCount': 0},
        ingredients: recipe,
      );
      expect(
        (await db.collection('coffee_products').doc('latte').get())
            .data()!['stock'],
        1,
      );
    },
  );
  test(
    'deleted unavailable and removed beverage sizes cannot be bundled',
    () async {
      final db = await fixture();
      await db.collection('coffee_products').doc('latte').update({
        'isAvailable': false,
      });
      await expectLater(
        BundleStockService(db).restock(
          'mixed',
          1,
          {},
          newBundle: {'bundleCount': 0},
          ingredients: recipe,
        ),
        throwsStateError,
      );
      expect(
        bundleBeverageSizes('latte', {
          'isDeleted': true,
          'sizes': [
            {'name': 'Small'},
          ],
        }),
        isEmpty,
      );
    },
  );
}
