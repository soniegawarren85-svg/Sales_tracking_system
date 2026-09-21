import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocalDatabaseSyncService {
  LocalDatabaseSyncService._();

  static final LocalDatabaseSyncService _instance =
      LocalDatabaseSyncService._();

  factory LocalDatabaseSyncService() => _instance;

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static const _keyPrefix = 'local_collection_v1_';
  final _completedSales =
      StreamController<List<Map<String, dynamic>>>.broadcast();
  final _collectionUpdates = StreamController<String>.broadcast();

  String _key(String collection) => '$_keyPrefix$collection';

  dynamic _encode(dynamic value) {
    if (value is Timestamp || value is DateTime) {
      final date = value is Timestamp ? value.toDate() : value;
      return {'__localType': 'timestamp', 'value': date.millisecondsSinceEpoch};
    }
    if (value is GeoPoint) {
      return {
        '__localType': 'geopoint',
        'lat': value.latitude,
        'lng': value.longitude,
      };
    }
    if (value is DocumentReference) return value.path;
    if (value is Map) {
      return value.map((key, item) => MapEntry(key.toString(), _encode(item)));
    }
    if (value is Iterable) return value.map(_encode).toList();
    return value;
  }

  dynamic _decode(dynamic value) {
    if (value is List) return value.map(_decode).toList();
    if (value is Map) {
      if (value['__localType'] == 'timestamp') {
        return Timestamp.fromMillisecondsSinceEpoch(
          (value['value'] as num).toInt(),
        );
      }
      if (value['__localType'] == 'geopoint') {
        return GeoPoint(
          (value['lat'] as num).toDouble(),
          (value['lng'] as num).toDouble(),
        );
      }
      return value.map((key, item) => MapEntry(key.toString(), _decode(item)));
    }
    return value;
  }

  Future<List<Map<String, dynamic>>> getCachedCollection(
    String collection,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key(collection));
      // Callers add newly-created offline orders to this list, so it must be
      // mutable even when this device has not cached a sale yet.
      if (raw == null || raw.isEmpty) return <Map<String, dynamic>>[];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <Map<String, dynamic>>[];
      return decoded
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(_decode(item) as Map))
          .toList();
    } catch (e) {
      debugPrint('Unable to read local $collection cache: $e');
      return <Map<String, dynamic>>[];
    }
  }

  Future<void> cacheCollectionDocs(
    String collection,
    Iterable<Map<String, dynamic>> docs,
  ) async {
    try {
      final records = docs
          .map((doc) => Map<String, dynamic>.from(doc))
          .toList();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key(collection), jsonEncode(_encode(records)));
      if (collection == 'completed_sales' && !_completedSales.isClosed) {
        _completedSales.add(records);
      }
      if (!_collectionUpdates.isClosed) _collectionUpdates.add(collection);
    } catch (e) {
      debugPrint('Unable to save local $collection cache: $e');
    }
  }

  /// Keeps cloud/cache receipts available to the offline drawer after restart.
  Future<void> mergeCompletedSales(
    Iterable<Map<String, dynamic>> incoming,
  ) async {
    final cached = await getCachedCollection('completed_sales');
    final merged = <String, Map<String, dynamic>>{};
    String key(Map<String, dynamic> sale, int fallback) =>
        sale['salesId']?.toString() ??
        sale['localId']?.toString() ??
        sale['_localDocId']?.toString() ??
        'unknown-$fallback';
    for (var i = 0; i < cached.length; i++) {
      merged[key(cached[i], i)] = cached[i];
    }
    var offset = cached.length;
    for (final sale in incoming) {
      final item = Map<String, dynamic>.from(sale);
      final saleKey = key(item, offset++);
      final existing = merged[saleKey];
      merged[saleKey] = {
        ...?existing,
        ...item,
        '_localDocId': item['_localDocId'] ?? existing?['_localDocId'] ?? saleKey,
      };
    }
    await cacheCollectionDocs('completed_sales', merged.values);
  }

  /// Updates cached drawer details from Firestore without replacing a drawer
  /// value that was rebuilt locally from today's receipts.
  Future<List<Map<String, dynamic>>> mergeCashDrawerSnapshot(
    Iterable<Map<String, dynamic>> serverDrawers,
  ) async {
    final cached = await getCachedCollection('staff_cash_drawer');
    final cachedById = {
      for (final drawer in cached)
        drawer['_localDocId']?.toString() ?? drawer['id']?.toString() ?? '':
            drawer,
    };
    final merged = <Map<String, dynamic>>[];
    for (final serverDrawer in serverDrawers) {
      final id = serverDrawer['_localDocId']?.toString() ?? '';
      final local = cachedById[id];
      final localDate = _asDate(local?['offlineReceiptBalanceDate']);
      final value = Map<String, dynamic>.from(serverDrawer);
      if (local != null && _isToday(localDate)) {
        value['balance'] = local['balance'];
        value['offlineReceiptBalanceDate'] = local['offlineReceiptBalanceDate'];
        value['localReceiptIds'] = local['localReceiptIds'];
      }
      merged.add(value);
    }
    await cacheCollectionDocs('staff_cash_drawer', merged);
    return merged;
  }

  Future<void> refreshCoreCollectionsFromFirebase() async {
    for (final collection in const ['sales_inventory']) {
      try {
        final snapshot = await _firestore
            .collection(collection)
            .limit(1000)
            .get(const GetOptions(source: Source.server));
        await cacheCollectionDocs(
          collection,
          snapshot.docs.map((doc) => {...doc.data(), '_localDocId': doc.id}),
        );
      } catch (_) {
        // Keep the last known snapshot when the device is offline.
      }
    }
  }

  Stream<List<Map<String, dynamic>>> watchLocalCompletedSales() {
    return (() async* {
      yield await getCachedCollection('completed_sales');
      yield* _completedSales.stream;
    })();
  }

  Stream<String> get collectionUpdates => _collectionUpdates.stream;

  DateTime? _asDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return DateTime.tryParse(value?.toString() ?? '');
  }

  bool _isToday(DateTime? value) {
    if (value == null) return false;
    final now = DateTime.now();
    return value.year == now.year &&
        value.month == now.month &&
        value.day == now.day;
  }

  /// Produces a stable offline display value: today's opening cash plus each
  /// unique completed cash receipt. It never uses the previous displayed
  /// balance, so repeated dashboard refreshes cannot inflate the total.
  Future<void> rebuildTodayCashDrawerFromReceipts() async {
    final drawers = await getCachedCollection('staff_cash_drawer');
    final receipts = await getCachedCollection('completed_sales');
    final queue = await getCachedCollection('pending_cash_drawer_changes');
    // Remove the temporary receipt-derived queue entries created by the old
    // incremental reconciliation. Normal checkout entries always include this
    // key, even when its GCash transaction ID is empty.
    final queuedCount = queue.length;
    queue.removeWhere(
      (change) =>
          (change['receiptId']?.toString() ?? '').isNotEmpty &&
          !change.containsKey('gcashTransactionId'),
    );
    final removedLegacyReconciliation = queue.length != queuedCount;
    var changed = false;
    for (var index = 0; index < drawers.length; index++) {
      final drawer = Map<String, dynamic>.from(drawers[index]);
      final drawerId = drawer['_localDocId']?.toString() ??
          drawer['id']?.toString() ?? '';
      if (drawerId.isEmpty) continue;
      final opening = (drawer['dailyOpeningCash'] as num?)?.toDouble() ??
          (drawer['openingCash'] as num?)?.toDouble();
      // A drawer without an opening amount cannot be rebuilt safely.
      if (opening == null) continue;
      final seenReceiptIds = <String>{};
      var todayCashSales = 0.0;
      for (final receipt in receipts) {
        if (receipt['branchId']?.toString() != drawerId ||
            receipt['paymentMode']?.toString().toLowerCase() != 'cash' ||
            !_isToday(_asDate(receipt['timestamp']))) continue;
        final receiptId = receipt['salesId']?.toString() ??
            receipt['_localDocId']?.toString() ?? '';
        if (receiptId.isEmpty || !seenReceiptIds.add(receiptId)) continue;
        todayCashSales += (receipt['cashDrawerDelta'] as num?)?.toDouble() ??
            (receipt['total'] as num?)?.toDouble() ?? 0.0;
      }
      final rebuilt = opening + todayCashSales;
      if ((drawer['balance'] as num?)?.toDouble() != rebuilt) {
        drawer['balance'] = rebuilt;
        drawer['offlineReceiptBalanceDate'] = DateTime.now();
        drawers[index] = drawer;
        changed = true;
      }
    }
    if (changed) await cacheCollectionDocs('staff_cash_drawer', drawers);
    if (removedLegacyReconciliation) {
      await cacheCollectionDocs('pending_cash_drawer_changes', queue);
    }
  }

  /// Rebuilds the local drawer from today's saved cash receipts. It is safe to
  /// call repeatedly: every receipt ID is recorded after it has been applied.
  Future<void> reconcileTodayCashReceipts() async {
    final drawers = await getCachedCollection('staff_cash_drawer');
    final receipts = await getCachedCollection('completed_sales');
    final queue = await getCachedCollection('pending_cash_drawer_changes');
    var changed = false;

    for (var index = 0; index < drawers.length; index++) {
      final drawer = Map<String, dynamic>.from(drawers[index]);
      final drawerId =
          drawer['_localDocId']?.toString() ?? drawer['id']?.toString() ?? '';
      if (drawerId.isEmpty) continue;

      final applied = List<String>.from(
        drawer['localReceiptIds'] as List? ?? const [],
      );
      // Old queued movements did not yet store the receipt ID. Mark the most
      // recent receipts as applied so updating this app does not count them again.
      if (!drawer.containsKey('localReceiptIds')) {
        final legacyCount = queue
            .where(
              (change) =>
                  change['drawerId']?.toString() == drawerId &&
                  (change['receiptId']?.toString() ?? '').isEmpty,
            )
            .length;
        final matching =
            receipts
                .where(
                  (receipt) =>
                      receipt['branchId']?.toString() == drawerId &&
                      receipt['paymentMode']?.toString().toLowerCase() ==
                          'cash' &&
                      _isToday(_asDate(receipt['timestamp'])),
                )
                .toList()
              ..sort(
                (a, b) => (_asDate(b['timestamp']) ?? DateTime(0)).compareTo(
                  _asDate(a['timestamp']) ?? DateTime(0),
                ),
              );
        applied.addAll(
          matching
              .take(legacyCount)
              .map(
                (receipt) =>
                    receipt['salesId']?.toString() ??
                    receipt['_localDocId']?.toString() ??
                    '',
              ),
        );
        changed = true;
      }

      for (final receipt in receipts) {
        final receiptId =
            receipt['salesId']?.toString() ??
            receipt['_localDocId']?.toString() ??
            '';
        if (receiptId.isEmpty || applied.contains(receiptId)) continue;
        if (receipt['branchId']?.toString() != drawerId ||
            receipt['paymentMode']?.toString().toLowerCase() != 'cash' ||
            !_isToday(_asDate(receipt['timestamp'])))
          continue;
        final delta =
            (receipt['cashDrawerDelta'] as num?)?.toDouble() ??
            (receipt['total'] as num?)?.toDouble() ??
            0.0;
        if (delta == 0) continue;
        drawer['balance'] =
            ((drawer['balance'] as num?)?.toDouble() ?? 0) + delta;
        applied.add(receiptId);
        queue.add({
          '_localDocId': _firestore.collection('staff_cash_drawer').doc().id,
          'drawerId': drawerId,
          'cashDelta': delta,
          'gcashDelta': 0.0,
          'staffId': receipt['userId']?.toString() ?? '',
          'receiptId': receiptId,
          'createdAt': DateTime.now(),
        });
        changed = true;
      }
      drawer['localReceiptIds'] = applied
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList();
      drawers[index] = drawer;
    }
    if (changed) {
      await cacheCollectionDocs('staff_cash_drawer', drawers);
      await cacheCollectionDocs('pending_cash_drawer_changes', queue);
      unawaited(syncPendingCashDrawerChanges());
    }
  }

  /// Saves a drawer movement first on this device.  The movement stays in a
  /// durable queue, so closing/reloading the app while offline cannot lose it.
  Future<void> recordCashDrawerChange({
    required String drawerId,
    required double cashDelta,
    required double gcashDelta,
    required String staffId,
    String receiptId = '',
    String gcashTransactionId = '',
  }) async {
    if (drawerId.trim().isEmpty) return;
    final drawers = await getCachedCollection('staff_cash_drawer');
    final index = drawers.indexWhere(
      (item) =>
          item['_localDocId']?.toString() == drawerId ||
          item['id']?.toString() == drawerId,
    );
    final drawer = index >= 0
        ? Map<String, dynamic>.from(drawers[index])
        : <String, dynamic>{'_localDocId': drawerId};
    drawer['_localDocId'] = drawerId;
    drawer['balance'] =
        ((drawer['balance'] as num?)?.toDouble() ?? 0) + cashDelta;
    drawer['gcashBalance'] =
        ((drawer['gcashBalance'] as num?)?.toDouble() ?? 0) + gcashDelta;
    drawer['staffId'] = drawerId;
    drawer['branchId'] = drawerId;
    drawer['handledByStaffId'] = staffId;
    drawer['updatedAt'] = DateTime.now();
    if (receiptId.isNotEmpty) {
      final applied = List<String>.from(
        drawer['localReceiptIds'] as List? ?? const [],
      );
      if (!applied.contains(receiptId)) applied.add(receiptId);
      drawer['localReceiptIds'] = applied;
    }
    if (gcashTransactionId.isNotEmpty) {
      drawer['lastGcashTransactionId'] = gcashTransactionId;
    }
    if (index >= 0) {
      drawers[index] = drawer;
    } else {
      drawers.add(drawer);
    }
    await cacheCollectionDocs('staff_cash_drawer', drawers);

    final queue = await getCachedCollection('pending_cash_drawer_changes');
    final id = _firestore.collection('staff_cash_drawer').doc().id;
    queue.add({
      '_localDocId': id,
      'drawerId': drawerId,
      'cashDelta': cashDelta,
      'gcashDelta': gcashDelta,
      'staffId': staffId,
      'receiptId': receiptId,
      'gcashTransactionId': gcashTransactionId,
      'createdAt': DateTime.now(),
    });
    await cacheCollectionDocs('pending_cash_drawer_changes', queue);
    unawaited(syncPendingCashDrawerChanges());
  }

  Future<void> syncPendingCashDrawerChanges() async {
    final queue = await getCachedCollection('pending_cash_drawer_changes');
    for (final change in List<Map<String, dynamic>>.from(queue)) {
      final id = change['_localDocId']?.toString() ?? '';
      final drawerId = change['drawerId']?.toString() ?? '';
      if (id.isEmpty || drawerId.isEmpty) continue;
      try {
        final ref = _firestore.collection('staff_cash_drawer').doc(drawerId);
        await _firestore.runTransaction((transaction) async {
          final snapshot = await transaction.get(ref);
          final applied = List<String>.from(
            snapshot.data()?['appliedOfflineMutationIds'] as List? ?? const [],
          );
          if (applied.contains(id)) return;
          transaction.set(ref, {
            'balance': FieldValue.increment(
              (change['cashDelta'] as num?)?.toDouble() ?? 0,
            ),
            'gcashBalance': FieldValue.increment(
              (change['gcashDelta'] as num?)?.toDouble() ?? 0,
            ),
            'staffId': drawerId,
            'branchId': drawerId,
            'handledByStaffId': change['staffId'],
            if ((change['gcashTransactionId']?.toString() ?? '').isNotEmpty)
              'lastGcashTransactionId': change['gcashTransactionId'],
            'appliedOfflineMutationIds': FieldValue.arrayUnion([id]),
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        });
        queue.removeWhere((item) => item['_localDocId']?.toString() == id);
        await cacheCollectionDocs('pending_cash_drawer_changes', queue);
      } catch (_) {
        // Still offline or temporarily unavailable; leave the change queued.
        return;
      }
    }
  }

  Future<void> recordCompletedSale(Map<String, dynamic> payload) async {
    final now = DateTime.now();
    final salesId = payload['salesId']?.toString().trim();
    final docId = salesId?.isNotEmpty == true
        ? salesId!
        : _firestore.collection('completed_sales').doc().id;
    final cached = await getCachedCollection('completed_sales');
    final local = {...payload, '_localDocId': docId, 'localOnly': true};
    final index = cached.indexWhere((item) => item['_localDocId'] == docId);
    if (index >= 0) {
      cached[index] = local;
    } else {
      cached.insert(0, local);
    }
    await cacheCollectionDocs('completed_sales', cached);

    final cloudPayload = Map<String, dynamic>.from(payload);
    cloudPayload.remove('localOnly');
    cloudPayload['localId'] = docId;
    cloudPayload['syncedAt'] = FieldValue.serverTimestamp();

    final timestamp = cloudPayload['timestamp'];
    if (timestamp is String) {
      final parsed = DateTime.tryParse(timestamp);
      cloudPayload['timestamp'] = parsed == null
          ? FieldValue.serverTimestamp()
          : Timestamp.fromDate(parsed);
    } else if (timestamp is DateTime) {
      cloudPayload['timestamp'] = Timestamp.fromDate(timestamp);
    } else if (timestamp is! Timestamp) {
      cloudPayload['timestamp'] = Timestamp.fromDate(now);
    }

    // Do not hold the order screen open for a network write. The local receipt
    // above is already durable; Firestore sends this queued write once online.
    unawaited(_uploadCompletedSale(docId, cloudPayload));
  }

  Future<void> _uploadCompletedSale(
    String docId,
    Map<String, dynamic> payload,
  ) async {
    try {
      await _firestore
          .collection('completed_sales')
          .doc(docId)
          .set(payload, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Completed sale remains queued locally: $e');
    }
  }

  /// Re-sends receipts that were saved before the app closed while offline.
  /// Reusing the stable local ID makes this idempotent (no duplicate sale).
  Future<void> syncPendingSales() async {
    final sales = await getCachedCollection('completed_sales');
    for (final sale in sales.where((item) => item['localOnly'] == true)) {
      final id = sale['_localDocId']?.toString() ?? '';
      if (id.isEmpty) continue;
      final payload = Map<String, dynamic>.from(sale)
        ..remove('_localDocId')
        ..remove('localOnly')
        ..remove('syncedAt');
      final timestamp = payload['timestamp'];
      if (timestamp is DateTime)
        payload['timestamp'] = Timestamp.fromDate(timestamp);
      unawaited(_uploadCompletedSale(id, payload));
    }
  }

  void dispose() {
    _completedSales.close();
    _collectionUpdates.close();
  }
}
