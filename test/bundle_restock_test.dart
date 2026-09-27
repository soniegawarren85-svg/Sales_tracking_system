import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sales_tracking/services/bundle_stock_service.dart';
import 'dart:convert';

void main() {
  Future<FakeFirebaseFirestore> fixture({
    int stock = 20,
    String expiry = '2099-12-31',
  }) async {
    final db = FakeFirebaseFirestore();
    await db.collection('sales_inventory').doc('category').set({
      'name': 'Cookies',
      'items': [
        {'id': 'v', 'name': 'Cookie', 'stock': stock, 'expirationDate': expiry},
      ],
    });
    await db.collection('sales_inventory').doc('bundle').set({
      'name': 'Bundle',
      'isBundle': true,
      'bundleId': 'BND-1',
      'bundleCount': 1,
      'items': [
        {
          'sourceInventoryId': 'category',
          'variantId': 'v',
          'name': 'Cookie',
          'quantity': 2,
          'expirationDate': '2020-01-01',
        },
      ],
      'bundleInstances': [
        {'id': 'old', 'status': 'available', 'expirationDate': '2020-01-01'},
      ],
    });
    return db;
  }

  test(
    'restock reserves ingredients and preserves expired batch separately',
    () async {
      final db = await fixture();
      await BundleStockService(db).restock('bundle', 3, {'price': 200});
      final bundle =
          (await db.collection('sales_inventory').doc('bundle').get()).data()!;
      final category =
          (await db.collection('sales_inventory').doc('category').get())
              .data()!;
      expect(bundleRows(category['items']).single['stock'], 14);
      expect(bundle['bundleCount'], 4);
      expect(availableBundleStock(bundle), 3);
      expect(
        bundleRows(bundle['bundleInstances']).first['expirationDate'],
        '2020-01-01',
      );
      expect(
        bundleRows(
          bundle['bundleInstances'],
        ).map((row) => row['id']).toSet().length,
        4,
      );
    },
  );
  test('insufficient ingredients does not change either document', () async {
    final db = await fixture(stock: 1);
    await expectLater(
      BundleStockService(db).restock('bundle', 2, {'price': 200}),
      throwsStateError,
    );
    expect(
      (await db.collection('sales_inventory').doc('bundle').get())
          .data()!['bundleCount'],
      1,
    );
    expect(
      bundleRows(
        (await db.collection('sales_inventory').doc('category').get())
            .data()!['items'],
      ).single['stock'],
      1,
    );
  });
  test('expired ingredients cannot create new stock', () async {
    final db = await fixture(expiry: '2020-01-01');
    await expectLater(
      BundleStockService(db).restock('bundle', 1, {}),
      throwsStateError,
    );
  });
  test(
    'restock does not duplicate ingredient pictures into every instance',
    () async {
      final db = await fixture(stock: 40);
      final photo = 'data:image/jpeg;base64,${List.filled(120000, 'a').join()}';
      await db.collection('sales_inventory').doc('category').update({
        'items': [
          {
            'id': 'v',
            'name': 'Red Velvet',
            'publicId': 'CO-006',
            'stock': 40,
            'expirationDate': '2099-12-31',
            'imageUrl': photo,
          },
        ],
      });
      await BundleStockService(db).restock('bundle', 10, {});
      final data = (await db.collection('sales_inventory').doc('bundle').get())
          .data()!;
      final fresh = bundleRows(data['bundleInstances']).last;
      expect(bundleRows(fresh['items']).single['name'], 'Red Velvet');
      expect(bundleRows(fresh['items']).single['imageUrl'], isNull);
      expect(bundleRows(data['items']).single['name'], 'Red Velvet');
      expect(
        jsonEncode(data, toEncodable: (value) => '$value').length,
        lessThan(50000),
      );
    },
  );
  test(
    'explicit replacement reserves the selected current ingredient',
    () async {
      final db = await fixture();
      await db.collection('sales_inventory').doc('new').set({
        'name': 'Cookies',
        'items': [
          {
            'id': 'red',
            'name': 'Red Velvet',
            'stock': 50,
            'expirationDate': '2099-10-01',
          },
        ],
      });
      await BundleStockService(db).restock(
        'bundle',
        2,
        {},
        ingredients: [
          {'sourceInventoryId': 'new', 'variantId': 'red', 'quantity': 3},
        ],
      );
      expect(
        bundleRows(
          (await db.collection('sales_inventory').doc('new').get())
              .data()!['items'],
        ).single['stock'],
        44,
      );
      expect(
        bundleRows(
          (await db.collection('sales_inventory').doc('category').get())
              .data()!['items'],
        ).single['stock'],
        20,
      );
    },
  );
  test('expiry is inclusive and batch dates override older recipe dates', () {
    final day = DateTime(2026, 9, 27);
    final bundle = {
      'items': [
        {'expirationDate': '2020-01-01'},
      ],
      'bundleInstances': [
        {'status': 'available', 'expirationDate': '2026-09-27'},
        {'status': 'sold', 'expirationDate': '2026-09-28'},
        {'status': 'available', 'expirationDate': '2026-09-26'},
      ],
    };
    expect(availableBundleStock(bundle, now: day), 1);
  });
}
