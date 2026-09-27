import 'package:flutter_test/flutter_test.dart';
import 'package:idb_shim/idb_client_memory.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sales_tracking/services/indexed_db_collection_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const key = 'local_collection_v1_staff_inventory';

  test(
    'migrates existing records and preserves them when storage is reopened',
    () async {
      SharedPreferences.setMockInitialValues({key: '[{"stock":12}]'});
      final factory = newIdbFactoryMemory();
      final store = IndexedDbCollectionStorage(factory);
      expect(await store.read(key), '[{"stock":12}]');
      expect((await SharedPreferences.getInstance()).containsKey(key), isFalse);
      expect(
        await IndexedDbCollectionStorage(factory).read(key),
        '[{"stock":12}]',
      );
    },
  );

  test(
    'large inventory and pending receipts do not use preferences quota',
    () async {
      SharedPreferences.setMockInitialValues({});
      final factory = newIdbFactoryMemory();
      final store = IndexedDbCollectionStorage(factory);
      final inventory = 'x' * (8 * 1024 * 1024);
      const receiptsKey = 'local_collection_v1_completed_sales';
      await store.write(key, inventory);
      await store.write(
        receiptsKey,
        '[{"salesId":"offline-1","localOnly":true}]',
      );
      final reopened = IndexedDbCollectionStorage(factory);
      expect(await reopened.read(key), inventory);
      expect(await reopened.read(receiptsKey), contains('offline-1'));
      expect((await SharedPreferences.getInstance()).getKeys(), isEmpty);
    },
  );

  test('concurrent migration and update keep the latest inventory', () async {
    SharedPreferences.setMockInitialValues({key: 'old'});
    final store = IndexedDbCollectionStorage(newIdbFactoryMemory());
    await Future.wait([store.read(key), store.write(key, 'new')]);
    expect(await store.read(key), 'new');
  });
}
