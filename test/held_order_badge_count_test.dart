import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sales_tracking/services/collection_storage.dart';
import 'package:sales_tracking/services/held_order_store.dart';
import 'package:sales_tracking/services/local_database_sync_service.dart';

class _MemoryCollectionStorage implements CollectionStorage {
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

  test('pending order list and badge count exclude closed orders', () async {
    final database = FakeFirebaseFirestore();
    final local = LocalDatabaseSyncService.forDatabase(
      database,
      storage: _MemoryCollectionStorage(),
    );
    final store = HeldOrderStore.forDatabase(
      database,
      local,
      syncEnabled: false,
    );

    await local.cacheCollectionDocs('pending_orders', [
      {'_localDocId': 'held', 'userId': 'staff-1', 'status': 'held'},
      {'_localDocId': 'legacy', 'userId': 'staff-1'},
      {'_localDocId': 'voided', 'userId': 'staff-1', 'status': 'voided'},
      {'_localDocId': 'restored', 'userId': 'staff-1', 'status': 'restored'},
      {'_localDocId': 'expired', 'userId': 'staff-1', 'status': 'expired'},
      {'_localDocId': 'other-staff', 'userId': 'staff-2', 'status': 'held'},
    ]);

    final activeOrders = await store.list('staff-1');
    expect(activeOrders.map((order) => order.id).toSet(), {'held', 'legacy'});

    await store.consume('staff-1', 'held', 'voided');
    final updatedOrders = await store.list('staff-1');
    expect(updatedOrders.map((order) => order.id).toSet(), {'legacy'});
  });
}
