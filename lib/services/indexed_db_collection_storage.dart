import 'package:idb_shim/idb.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'collection_storage.dart';
import 'local_write_lock.dart';

/// Large offline collections must not share localStorage's small preferences
/// quota. Legacy data is removed only after an IndexedDB transaction commits.
class IndexedDbCollectionStorage implements CollectionStorage {
  IndexedDbCollectionStorage(this.factory);

  final IdbFactory factory;
  final _lock = LocalWriteLock();
  Database? _database;
  static const _store = 'collections';

  Future<Database> _open() async => _database ??= await factory.open(
    'sales_tracking_offline_v2',
    version: 1,
    onUpgradeNeeded: (event) => event.database.createObjectStore(_store),
  );

  Future<void> _put(Database db, String key, String value) async {
    final transaction = db.transaction(_store, idbModeReadWrite);
    await transaction.objectStore(_store).put(value, key);
    await transaction.completed;
  }

  Future<void> _removeLegacy(String key) async {
    // A failed cleanup must not invalidate a successfully committed record.
    try {
      await (await SharedPreferences.getInstance()).remove(key);
    } catch (_) {}
  }

  @override
  Future<String?> read(String key) => _lock.run(() async {
    final db = await _open();
    final transaction = db.transaction(_store, idbModeReadOnly);
    final value = await transaction.objectStore(_store).getObject(key);
    await transaction.completed;
    if (value != null) return value as String;
    final legacy = (await SharedPreferences.getInstance()).getString(key);
    if (legacy != null) {
      await _put(db, key, legacy);
      await _removeLegacy(key);
    }
    return legacy;
  });

  @override
  Future<void> write(String key, String value) => _lock.run(() async {
    await _put(await _open(), key, value);
    await _removeLegacy(key);
  });
}
