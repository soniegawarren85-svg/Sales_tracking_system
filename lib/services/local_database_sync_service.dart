import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

class LocalDatabaseSyncService {
  LocalDatabaseSyncService._();

  static final LocalDatabaseSyncService _instance =
      LocalDatabaseSyncService._();

  factory LocalDatabaseSyncService() => _instance;

  static const Duration syncInterval = Duration(minutes: 10);

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  Timer? _timer;
  Database? _db;
  bool _started = false;
  bool _syncing = false;
  bool _refreshingCoreCache = false;
  final StreamController<List<Map<String, dynamic>>> _localSalesController =
      StreamController<List<Map<String, dynamic>>>.broadcast();

  void start() {
    if (_started) return;
    _started = true;

    unawaited(_publishLocalSales());
    unawaited(refreshCoreCollectionsFromFirebase());
    _timer = Timer.periodic(syncInterval, (_) {
      unawaited(syncPendingSales());
      unawaited(refreshCoreCollectionsFromFirebase());
    });
  }

  Future<List<Map<String, dynamic>>> getCachedCollection(
    String collection,
  ) async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      final rows = prefs.getStringList(_webCacheKey(collection)) ?? const [];
      return rows.map<Map<String, dynamic>>((row) {
        return Map<String, dynamic>.from(
          _fromJsonSafe(jsonDecode(row) as Map<String, dynamic>) as Map,
        );
      }).toList();
    }

    final db = await _database;
    final rows = await db.query(
      'cached_collection_docs',
      where: 'collection = ?',
      whereArgs: [collection],
      orderBy: 'updated_at DESC',
    );
    return rows.map<Map<String, dynamic>>((row) {
      final data = Map<String, dynamic>.from(
        _fromJsonSafe(
              jsonDecode(row['payload_json'] as String) as Map<String, dynamic>,
            )
            as Map,
      );
      data['_localDocId'] = row['doc_id']?.toString() ?? '';
      return data;
    }).toList();
  }

  Future<void> cacheCollectionDocs(
    String collection,
    Iterable<Map<String, dynamic>> docs,
  ) async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      final existing = <String, Map<String, dynamic>>{};
      for (final row
          in prefs.getStringList(_webCacheKey(collection)) ??
              const <String>[]) {
        final data = Map<String, dynamic>.from(
          _fromJsonSafe(jsonDecode(row) as Map<String, dynamic>) as Map,
        );
        final id = data['_localDocId']?.toString() ?? data['id']?.toString();
        if ((id ?? '').trim().isNotEmpty) existing[id!] = data;
      }
      for (final doc in docs) {
        final docId = doc['_localDocId']?.toString() ?? doc['id']?.toString();
        if ((docId ?? '').trim().isEmpty) continue;
        existing[docId!] = Map<String, dynamic>.from(doc);
      }
      final encoded = existing.values
          .map((doc) => jsonEncode(_toJsonSafe(doc)))
          .toList();
      await prefs.setStringList(_webCacheKey(collection), encoded);
      return;
    }

    final db = await _database;
    final batch = db.batch();
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final doc in docs) {
      final docId = doc['_localDocId']?.toString() ?? doc['id']?.toString();
      if ((docId ?? '').trim().isEmpty) continue;
      final payload = Map<String, dynamic>.from(doc)..remove('_localDocId');
      batch.insert('cached_collection_docs', {
        'collection': collection,
        'doc_id': docId,
        'payload_json': jsonEncode(_toJsonSafe(payload)),
        'updated_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  String _webCacheKey(String collection) =>
      'sales_tracking_cached_collection_$collection';

  Future<void> refreshCoreCollectionsFromFirebase() async {
    if (_refreshingCoreCache) return;
    _refreshingCoreCache = true;
    try {
      for (final collection in const [
        'staff_inventory',
        'sales_inventory',
        'staff_cash_drawer',
        'staff_requests',
        'branches',
        'completed_sales',
      ]) {
        final snapshot = await _firestore
            .collection(collection)
            .limit(1000)
            .get();
        await cacheCollectionDocs(
          collection,
          snapshot.docs.map((doc) => {...doc.data(), '_localDocId': doc.id}),
        );
      }
    } catch (e) {
      debugPrint('Core local cache refresh failed: $e');
    } finally {
      _refreshingCoreCache = false;
    }
  }

  Stream<List<Map<String, dynamic>>> watchLocalCompletedSales() {
    unawaited(_publishLocalSales());
    return _localSalesController.stream;
  }

  Future<void> recordCompletedSale(Map<String, dynamic> payload) async {
    final db = await _database;
    final now = DateTime.now();
    final localId = payload['localId']?.toString().trim().isNotEmpty == true
        ? payload['localId'].toString()
        : 'local-${now.microsecondsSinceEpoch}';
    final localPayload = <String, dynamic>{
      ...payload,
      'localId': localId,
      'localOnly': true,
      'timestamp': now.toIso8601String(),
      'createdAtLocal': now.toIso8601String(),
    };

    await db.insert('pending_completed_sales', {
      'local_id': localId,
      'payload_json': jsonEncode(_toJsonSafe(localPayload)),
      'created_at': now.millisecondsSinceEpoch,
      'synced': 0,
    }, conflictAlgorithm: ConflictAlgorithm.replace);

    await _publishLocalSales();
  }

  Future<void> syncPendingSales() async {
    if (_syncing) return;
    _syncing = true;
    try {
      final db = await _database;
      final rows = await db.query(
        'pending_completed_sales',
        where: 'synced = ?',
        whereArgs: [0],
        orderBy: 'created_at ASC',
      );

      for (final row in rows) {
        final id = row['id'] as int;
        final payload = _fromJsonSafe(
          jsonDecode(row['payload_json'] as String) as Map<String, dynamic>,
        );
        payload.remove('localOnly');
        payload['syncedFromLocal'] = true;
        payload['syncedAt'] = FieldValue.serverTimestamp();
        payload['timestamp'] = FieldValue.serverTimestamp();

        await _firestore.collection('completed_sales').add(payload);
        await db.update(
          'pending_completed_sales',
          {'synced': 1, 'synced_at': DateTime.now().millisecondsSinceEpoch},
          where: 'id = ?',
          whereArgs: [id],
        );
      }

      await _publishLocalSales();
    } catch (e) {
      debugPrint('Local completed sales sync failed: $e');
    } finally {
      _syncing = false;
    }
  }

  Future<Database> get _database async {
    final existing = _db;
    if (existing != null) return existing;

    final dbPath = await getDatabasesPath();
    final db = await openDatabase(
      p.join(dbPath, 'sales_tracking_local.db'),
      version: 2,
      onCreate: (database, version) async {
        await database.execute('''
          CREATE TABLE pending_completed_sales (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            local_id TEXT NOT NULL UNIQUE,
            payload_json TEXT NOT NULL,
            created_at INTEGER NOT NULL,
            synced INTEGER NOT NULL DEFAULT 0,
            synced_at INTEGER
          )
        ''');
        await database.execute('''
          CREATE TABLE cached_collection_docs (
            collection TEXT NOT NULL,
            doc_id TEXT NOT NULL,
            payload_json TEXT NOT NULL,
            updated_at INTEGER NOT NULL,
            PRIMARY KEY (collection, doc_id)
          )
        ''');
      },
      onUpgrade: (database, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await database.execute('''
            CREATE TABLE IF NOT EXISTS cached_collection_docs (
              collection TEXT NOT NULL,
              doc_id TEXT NOT NULL,
              payload_json TEXT NOT NULL,
              updated_at INTEGER NOT NULL,
              PRIMARY KEY (collection, doc_id)
            )
          ''');
        }
      },
    );
    _db = db;
    return db;
  }

  Future<void> _publishLocalSales() async {
    if (_localSalesController.isClosed) return;
    try {
      final db = await _database;
      final rows = await db.query(
        'pending_completed_sales',
        where: 'synced = ?',
        whereArgs: [0],
        orderBy: 'created_at DESC',
      );
      final sales = rows.map<Map<String, dynamic>>((row) {
        final payload = Map<String, dynamic>.from(
          _fromJsonSafe(
                jsonDecode(row['payload_json'] as String)
                    as Map<String, dynamic>,
              )
              as Map,
        );
        final createdAt = DateTime.fromMillisecondsSinceEpoch(
          row['created_at'] as int,
        );
        payload['timestamp'] = Timestamp.fromDate(createdAt);
        payload['localOnly'] = true;
        return payload;
      }).toList();
      _localSalesController.add(sales);
    } catch (e) {
      debugPrint('Local sales publish failed: $e');
    }
  }

  dynamic _toJsonSafe(dynamic value) {
    if (value is Timestamp)
      return {'__timestamp': value.toDate().toIso8601String()};
    if (value is DateTime) return {'__datetime': value.toIso8601String()};
    if (value is FieldValue) return {'__fieldValue': 'serverTimestamp'};
    if (value is Map) {
      return value.map(
        (key, entry) => MapEntry(key.toString(), _toJsonSafe(entry)),
      );
    }
    if (value is Iterable) return value.map(_toJsonSafe).toList();
    return value;
  }

  dynamic _fromJsonSafe(dynamic value) {
    if (value is Map<String, dynamic>) {
      if (value.containsKey('__timestamp')) {
        return Timestamp.fromDate(
          DateTime.parse(value['__timestamp'] as String),
        );
      }
      if (value.containsKey('__datetime')) {
        return DateTime.parse(value['__datetime'] as String);
      }
      if (value['__fieldValue'] == 'serverTimestamp') {
        return FieldValue.serverTimestamp();
      }
      return value.map((key, entry) => MapEntry(key, _fromJsonSafe(entry)));
    }
    if (value is List) return value.map(_fromJsonSafe).toList();
    return value;
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
    _started = false;
    unawaited(_localSalesController.close());
  }
}
