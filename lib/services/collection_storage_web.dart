import 'package:idb_shim/idb_browser.dart';
import 'collection_storage.dart';
import 'indexed_db_collection_storage.dart';

final CollectionStorage _storage = IndexedDbCollectionStorage(idbFactoryNative);
CollectionStorage createCollectionStorage() => _storage;
