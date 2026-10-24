import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'local_database_sync_service.dart';
import 'local_write_lock.dart';

class HeldOrder {
  HeldOrder(this.id, this.value);
  final String id;
  final Map<String, dynamic> value;
  Map<String, dynamic> data() => value;
}

/// Holds are durable on this device before any network request starts.
class HeldOrderStore {
  HeldOrderStore.forDatabase(this.db, this.local, {this.syncEnabled = true});
  static final instance = HeldOrderStore.forDatabase(FirebaseFirestore.instance, LocalDatabaseSyncService());
  final FirebaseFirestore db;
  final LocalDatabaseSyncService local;
  final bool syncEnabled;
  final _lock = LocalWriteLock();
  bool _syncing = false;

  Future<List<HeldOrder>> list(String userId, {bool includeClosed = false}) async {
    final rows = await local.getCachedCollection('pending_orders');
    final result = rows.where((row) => row['userId'] == userId &&
      (includeClosed || (row['status'] ?? 'held') == 'held'))
      .map((row) => HeldOrder('${row['_localDocId']}', row)).toList();
    result.sort((a,b) => ((b.value['createdAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0)
      .compareTo((a.value['createdAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0));
    return result;
  }

  Future<void> merge(String userId, List<HeldOrder> incoming, {required bool authoritative}) => _lock.run(() async {
    final rows = await local.getCachedCollection('pending_orders');
    final byId = {for(final row in rows) '${row['_localDocId']}': row};
    final remoteIds = incoming.map((row) => row.id).toSet();
    if (authoritative) {
      for (final row in byId.values) {
        if (row['userId'] == userId && row['_pendingSync'] != true && !remoteIds.contains(row['_localDocId'])) {
          row['status'] = 'removed';
        }
      }
    }
    for(final order in incoming) {
      if (order.value['userId'] != userId || byId[order.id]?['_pendingSync'] == true) continue;
      byId[order.id] = {...order.value, '_localDocId': order.id};
    }
    await local.cacheCollectionDocs('pending_orders', byId.values);
  });

  Stream<List<HeldOrder>> watch(String userId) {
    late StreamController<List<HeldOrder>> controller;
    StreamSubscription? cloud, cache;
    Timer? retry;
    Future<void> emit() async {
      try { final rows = await list(userId); if(!controller.isClosed) controller.add(rows); }
      catch(error, stack) { if(!controller.isClosed) controller.addError(error, stack); }
    }
    controller = StreamController<List<HeldOrder>>(onListen: () {
      cache = local.collectionUpdates.where((name) => name == 'pending_orders').listen((_) => emit());
      unawaited(emit());
      if (syncEnabled) {
        cloud = db.collection('pending_orders').where('userId', isEqualTo: userId).snapshots(includeMetadataChanges: true).listen((snapshot) async {
          try {
            await merge(userId, snapshot.docs.map((doc) => HeldOrder(doc.id, doc.data())).toList(),
              authoritative: !snapshot.metadata.isFromCache && !snapshot.metadata.hasPendingWrites);
            unawaited(sync(userId));
          } catch(error) { debugPrint('Held-order cache: $error'); }
        }, onError: (Object error) { debugPrint('Held orders offline: $error'); });
        retry = Timer.periodic(const Duration(seconds: 10), (_) => sync(userId));
        unawaited(sync(userId));
      }
    }, onCancel: () async {
      retry?.cancel(); await cloud?.cancel(); await cache?.cancel();
    });
    return controller.stream;
  }

  Future<String> hold(String userId, Map<String, dynamic> payload) async {
    final id = db.collection('pending_orders').doc().id;
    await _lock.run(() async {
      final rows = await local.getCachedCollection('pending_orders');
      final now = Timestamp.now();
      rows.add({...payload, '_localDocId': id, 'userId': userId, 'status': 'held', 'createdAt': now,
        '_pendingSync': true, '_revision': 1,
        'events': [{'action': 'held', 'createdAt': now, 'revision': 1}],
      });
      await local.cacheCollectionDocs('pending_orders', rows);
    });
    unawaited(sync(userId));
    return id;
  }

  Future<void> consume(String userId, String id, String action) async {
    if (!['restored','voided','expired'].contains(action)) throw ArgumentError('Invalid hold action');
    await _lock.run(() async {
      final rows = await local.getCachedCollection('pending_orders');
      final row = rows.where((row) => row['_localDocId'] == id && row['userId'] == userId).firstOrNull;
      if (row == null || (row['status'] ?? 'held') != 'held') throw StateError('This held order is already closed.');
      final revision = (row['_revision'] as num? ?? 0).toInt() + 1;
      row.addAll({'status': action, '_pendingSync': true, '_revision': revision,
        'events': [...(row['events'] as List? ?? []), {'action': action, 'createdAt': Timestamp.now(), 'revision': revision}]});
      await local.cacheCollectionDocs('pending_orders', rows);
    });
    unawaited(sync(userId));
  }

  Future<List<HeldOrder>> history(String userId) async {
    final orders = await list(userId, includeClosed: true);
    final result = <HeldOrder>[];
    for(final order in orders) {
      for(final event in (order.value['events'] as List? ?? []).whereType<Map>()) {
        result.add(HeldOrder(order.id, {...Map<String,dynamic>.from(event), 'items': order.value['items'], 'orderId': order.id}));
      }
    }
    result.sort((a,b) => ((b.value['createdAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0)
      .compareTo((a.value['createdAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0));
    return result;
  }

  Future<void> sync(String userId) async {
    if (!syncEnabled || _syncing) return;
    _syncing = true;
    try {
      final pending = (await list(userId, includeClosed: true)).where((row) => row.value['_pendingSync'] == true).toList();
      for(final order in pending) {
        final revision = order.value['_revision'];
        final payload = Map<String,dynamic>.from(order.value)..remove('_localDocId')..remove('_pendingSync');
        final batch = db.batch();
        batch.set(db.collection('pending_orders').doc(order.id), payload);
        for(final event in (payload['events'] as List? ?? []).whereType<Map>()) {
          batch.set(db.collection('pending_order_history').doc('${order.id}_${event['revision']}'), {
            ...Map<String,dynamic>.from(event), 'orderId': order.id, 'userId': userId, 'items': payload['items'],
          });
        }
        await batch.commit().timeout(const Duration(seconds: 6));
        await _lock.run(() async {
          final rows = await local.getCachedCollection('pending_orders');
          final row = rows.where((row) => row['_localDocId'] == order.id).firstOrNull;
          if(row != null && row['_revision'] == revision) row['_pendingSync'] = false;
          await local.cacheCollectionDocs('pending_orders', rows);
        });
      }
    } catch(error) { debugPrint('Held orders waiting to sync: $error'); }
    finally { _syncing = false; }
  }
}
