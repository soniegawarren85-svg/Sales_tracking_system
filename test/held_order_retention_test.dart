import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sales_tracking/services/collection_storage.dart';
import 'package:sales_tracking/services/held_order_store.dart';
import 'package:sales_tracking/services/local_database_sync_service.dart';
import 'package:sales_tracking/widgets/held_order_card.dart';

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

  test('offline held orders persist locally and remain pending', () async {
    final database = FakeFirebaseFirestore();
    final storage = _MemoryCollectionStorage();
    final local = LocalDatabaseSyncService.forDatabase(
      database,
      storage: storage,
    );
    final offlineStore = HeldOrderStore.forDatabase(
      database,
      local,
      syncEnabled: false,
    );

    for (var index = 0; index < 12; index++) {
      await offlineStore.hold('staff-1', {
        'items': [
          {'name': 'Item $index', 'quantity': 1},
        ],
      });
    }

    final restartedStore = HeldOrderStore.forDatabase(
      database,
      LocalDatabaseSyncService.forDatabase(database, storage: storage),
      syncEnabled: false,
    );
    final held = await restartedStore.list('staff-1');

    expect(held, hasLength(12));
    expect(held.every((order) => order.data()['_pendingSync'] == true), isTrue);
    final pendingCard = HeldOrderCard(
      data: held.first.data(),
      hasNetwork: false,
      onVoid: () {},
      onRestore: () {},
    );
    expect(pendingCard.syncLabel, 'Saved offline');
  });

  test(
    'online sync and authoritative reconcile retain 12 held orders',
    () async {
      final database = FakeFirebaseFirestore();
      final local = LocalDatabaseSyncService.forDatabase(
        database,
        storage: _MemoryCollectionStorage(),
      );
      final store = HeldOrderStore.forDatabase(database, local);

      await local.cacheCollectionDocs('pending_orders', [
        for (var index = 0; index < 12; index++)
          {
            '_localDocId': 'order-$index',
            'userId': 'staff-1',
            'status': 'held',
            'createdAt': Timestamp.now(),
            '_pendingSync': true,
            '_revision': 1,
            'items': [
              {'name': 'Item $index', 'quantity': 1},
            ],
            'events': [
              {'action': 'held', 'createdAt': Timestamp.now(), 'revision': 1},
            ],
          },
      ]);

      await store.sync('staff-1');
      final synced = await store.list('staff-1');
      expect(synced, hasLength(12));
      expect(
        synced.every((order) => order.data()['_pendingSync'] == false),
        isTrue,
      );
      expect(
        (await database.collection('pending_orders').get()).docs,
        hasLength(12),
      );

      await store.merge('staff-1', [HeldOrder('order-0', synced.first.data())]);

      expect(await store.list('staff-1'), hasLength(12));
      expect(
        HeldOrderCard(
          data: synced.first.data(),
          hasNetwork: true,
          onVoid: () {},
          onRestore: () {},
        ).syncLabel,
        'Synced',
      );
    },
  );

  test('pending online status remains distinct from offline and synced', () {
    HeldOrderCard card(bool pending, bool online) => HeldOrderCard(
      data: {'_pendingSync': pending},
      hasNetwork: online,
      onVoid: () {},
      onRestore: () {},
    );

    expect(card(true, true).syncLabel, 'Sync pending');
    expect(card(true, false).syncLabel, 'Saved offline');
    expect(card(false, true).syncLabel, 'Synced');
  });
}
