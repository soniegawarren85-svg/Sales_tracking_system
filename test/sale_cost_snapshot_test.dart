import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sales_tracking/services/collection_storage.dart';
import 'package:sales_tracking/services/local_database_sync_service.dart';
import 'package:sales_tracking/services/bundle_stock_service.dart';

class _Storage implements CollectionStorage {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'offline receipts preserve sale-time costs across catalog updates',
    () async {
      final db = FakeFirebaseFirestore();
      final service = LocalDatabaseSyncService.forDatabase(
        db,
        storage: _Storage(),
      );
      Future<void> catalog(int cost) =>
          service.cacheCollectionDocs('sales_inventory', [
            {
              '_localDocId': 'cat',
              'items': [
                {
                  'id': 'cookie',
                  'publicId': 'CO-1',
                  'name': 'Cookie',
                  'costPrice': cost,
                },
              ],
            },
          ]);
      Future<void> sell(String id) => service.recordCompletedSale({
        'salesId': id,
        'timestamp': DateTime.now(),
        'paymentMode': 'GCash',
        'total': 50,
        'items': [
          {
            'sourceInventoryId': 'cat',
            'itemId': 'cookie',
            'name': 'Cookie',
            'price': 50,
            'quantity': 1,
          },
        ],
      });
      await catalog(25);
      await sell('first');
      await catalog(35);
      await sell('second');
      final records = await service.getCachedCollection('completed_sales');
      expect(
        (records.firstWhere((r) => r['salesId'] == 'first')['items'] as List)
            .single['costPrice'],
        25,
      );
      expect(
        (records.firstWhere((r) => r['salesId'] == 'second')['items'] as List)
            .single['costPrice'],
        35,
      );
    },
  );
  test(
    'bundle cost sums current ingredient cost times recipe quantity',
    () async {
      final db = FakeFirebaseFirestore();
      await db.collection('sales_inventory').doc('cat').set({
        'name': 'Cookies',
        'items': [
          {
            'id': 'cookie',
            'name': 'Cookie',
            'costPrice': 25,
            'stock': 100,
            'expirationDate': '2099-12-31',
          },
        ],
      });
      await db.collection('coffee_products').doc('coffee').set({
        'name': 'Coffee',
        'costPrice': 15,
        'sizes': [
          {'name': 'Small', 'priceDelta': 50},
        ],
      });
      await BundleStockService(db).restock(
        'bundle',
        2,
        {'name': 'Mixed', 'price': 150},
        newBundle: {'isBundle': true, 'bundleCount': 0},
        ingredients: [
          {'sourceInventoryId': 'cat', 'variantId': 'cookie', 'quantity': 2},
          {
            'sourceInventoryId': 'coffee',
            'sourceCollection': 'coffee_products',
            'coffeeSize': 'Small',
            'quantity': 1,
          },
        ],
      );
      final bundle =
          (await db.collection('sales_inventory').doc('bundle').get()).data()!;
      expect(bundle['costPrice'], 65);
      expect(bundle['bundleCount'], 2);
    },
  );
}
