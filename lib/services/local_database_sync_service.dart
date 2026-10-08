import 'refund_value.dart';
import 'cash_drawer_service.dart';
import 'local_write_lock.dart';
import 'dart:async';
import 'dart:convert';
import 'sale_stock.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'collection_storage.dart';
import 'collection_storage_native.dart'
    if (dart.library.js_interop) 'collection_storage_web.dart';

class LocalDatabaseSyncService {
  LocalDatabaseSyncService._()
      : _firestore = FirebaseFirestore.instance,
        _storage = createCollectionStorage();

  LocalDatabaseSyncService.forDatabase(this._firestore, {CollectionStorage? storage})
      : _storage = storage ?? createCollectionStorage();

  static final LocalDatabaseSyncService _instance =
      LocalDatabaseSyncService._();

  factory LocalDatabaseSyncService() => _instance;

  final FirebaseFirestore _firestore;
  final CollectionStorage _storage;

  static const _keyPrefix = 'local_collection_v1_';
  final _completedSales =
      StreamController<List<Map<String, dynamic>>>.broadcast();
  final _collectionUpdates = StreamController<String>.broadcast();

  final _salesLock = LocalWriteLock();
  final _drawerLock = LocalWriteLock();
  final _inventoryLock = LocalWriteLock();

  /// A scoped query must not erase allocations belonging to other targets.
  /// In particular, an empty direct-staff query can arrive before branch lookup.
  Future<void> cacheStaffInventorySnapshot(
    Iterable<String> targets,
    Iterable<Map<String, dynamic>> incoming, {
    bool authoritative = true,
  }) => _inventoryLock.run(() async {
    if (targets.isEmpty) return;
    final current = await getCachedCollection('staff_inventory');
    final byId = <String, Map<String, dynamic>>{
      for (final row in current.where(
        (row) =>
            !authoritative || !targets.contains(row['staffId']?.toString()),
      ))
        '${row['_localDocId']}': row,
      for (final row in incoming) '${row['_localDocId']}': row,
    };
    await cacheCollectionDocs('staff_inventory', byId.values);
  });

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
      final raw = await _storage.read(_key(collection));
      // Callers add newly-created offline orders to this list, so it must be
      // mutable even when this device has not cached a sale yet.
      if (raw == null || raw.isEmpty) return <Map<String, dynamic>>[];
      final decoded = jsonDecode(raw);
      if (decoded is! List) throw const FormatException('Invalid offline collection');
      return decoded
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(_decode(item) as Map))
          .toList();
    } catch (e) {
      debugPrint('Unable to read local $collection cache: $e');
      rethrow;
    }
  }

  Future<void> cacheCollectionDocs(
    String collection,
    Iterable<Map<String, dynamic>> docs,
  ) async {
    try {
      var records = docs.map((doc) => Map<String, dynamic>.from(doc)).toList();
      if (collection == 'staff_inventory') {
        final receipts = await getCachedCollection('completed_sales');
        for (final receipt in receipts.where(
          (sale) => sale['stockSyncRequired'] == true,
        )) {
          final lines = (receipt['items'] as List? ?? [])
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .toList();
          records = records
              .map(
                (record) => applySaleStock(
                  record,
                  '${receipt['salesId']}',
                  lines
                      .where(
                        (line) =>
                            line['staffInventoryDocId'] ==
                            record['_localDocId'],
                      )
                      .toList(),
                ),
              )
              .toList();
        }
      }
      final encoded = jsonEncode(_encode(records));
      if (await _storage.read(_key(collection)) == encoded) return;
      await _storage.write(_key(collection), encoded);
      if (collection == 'completed_sales' && !_completedSales.isClosed) {
        _completedSales.add(records);
      }
      if (!_collectionUpdates.isClosed) _collectionUpdates.add(collection);
    } catch (e) {
      debugPrint('Unable to save local $collection cache: $e');
      rethrow;
    }
  }

  /// Keeps cloud/cache receipts available to the offline drawer after restart.
  Future<void> mergeCompletedSales(Iterable<Map<String, dynamic>> incoming) =>
      _salesLock.run(() async {
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
            '_localDocId':
                item['_localDocId'] ?? existing?['_localDocId'] ?? saleKey,
          };
        }
        await cacheCollectionDocs('completed_sales', merged.values);
      });

  /// Updates cached drawer details from Firestore without replacing a drawer
  /// value that was rebuilt locally from today's receipts.
  Future<List<Map<String, dynamic>>> mergeCashDrawerSnapshot(
    Iterable<Map<String, dynamic>> serverDrawers,
  ) => _drawerLock.run(() async {
    final cached = await getCachedCollection('staff_cash_drawer');
    final pending = await getCachedCollection('pending_cash_drawer_changes');
    final receipts = await getCachedCollection('completed_sales');
    final byId = {
      for (final row in cached) row['_localDocId']?.toString(): row,
    };
    for (final server in serverDrawers) {
      final id = server['_localDocId']?.toString();
      final applied = List<String>.from(
        server['appliedOfflineMutationIds'] as List? ?? [],
      );
      final row = CashDrawerService.forDay(server, DateTime.now(), receipts: receipts.where((receipt) => receipt['branchId'] == id));
      if (id != null && server['drawerDate'] != CashDrawerService.dayKey(DateTime.now())) {
        unawaited(CashDrawerService.ensureToday(_firestore, id).catchError((Object error) { debugPrint('Drawer reset deferred: $error'); }));
      }
      row['localReceiptIds'] = {
        ...List<String>.from(byId[id]?['localReceiptIds'] as List? ?? []),
        ...pending
            .where((movement) => movement['drawerId'] == id)
            .map((movement) => movement['receiptId']?.toString() ?? ''),
      }.where((id) => id.isNotEmpty).toList();
      for (final movement in pending) {
        if (CashDrawerService.dayKey(_asDate(movement['createdAt']) ?? DateTime.now()) != CashDrawerService.dayKey(DateTime.now()) || movement['drawerId'] != id ||
            applied.contains(movement['_localDocId']))
          continue;
        row['balance'] =
            ((row['balance'] as num?)?.toDouble() ?? 0) +
            ((movement['cashDelta'] as num?)?.toDouble() ?? 0);
        row['gcashBalance'] =
            ((row['gcashBalance'] as num?)?.toDouble() ?? 0) +
            ((movement['gcashDelta'] as num?)?.toDouble() ?? 0);
      }
      byId[id] = row;
    }
    final merged = byId.values.toList();
    await cacheCollectionDocs('staff_cash_drawer', merged);
    return merged;
  });

  Future<void> refreshCoreCollectionsFromFirebase() async {
    for (final collection in const ['sales_inventory', 'coffee_products']) {
      try {
        final snapshot = await _firestore
            .collection(collection)
            .get(const GetOptions(source: Source.server))
            .timeout(const Duration(seconds: 5));
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

  Future<void> rolloverCashDrawers() => _drawerLock.run(() async {
    final drawers = await getCachedCollection('staff_cash_drawer');
    final receipts = await getCachedCollection('completed_sales');
    var changed = false;
    for (var i = 0; i < drawers.length; i++) {
      final data = drawers[i];
      if (data['drawerDate'] == CashDrawerService.dayKey(DateTime.now())) continue;
      final id = '${data['_localDocId'] ?? data['id'] ?? ''}';
      drawers[i] = CashDrawerService.forDay(data, DateTime.now(), receipts: receipts.where((receipt) => receipt['branchId'] == id));
      changed = true;
      if (id.isNotEmpty) unawaited(CashDrawerService.ensureToday(_firestore, id).catchError((Object error) { debugPrint('Drawer reset deferred: $error'); }));
    }
    if (changed) await cacheCollectionDocs('staff_cash_drawer', drawers);
  });

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
      final drawerId =
          drawer['_localDocId']?.toString() ?? drawer['id']?.toString() ?? '';
      if (drawerId.isEmpty) continue;
      final opening =
          (drawer['dailyOpeningCash'] as num?)?.toDouble() ??
          (drawer['openingCash'] as num?)?.toDouble();
      // A drawer without an opening amount cannot be rebuilt safely.
      if (opening == null) continue;
      final seenReceiptIds = <String>{};
      var todayCashSales = 0.0;
      for (final receipt in receipts) {
        if (receipt['branchId']?.toString() != drawerId ||
            receipt['paymentMode']?.toString().toLowerCase() != 'cash' ||
            !_isToday(_asDate(receipt['timestamp'])))
          continue;
        final receiptId =
            receipt['salesId']?.toString() ??
            receipt['_localDocId']?.toString() ??
            '';
        if (receiptId.isEmpty || !seenReceiptIds.add(receiptId)) continue;
        todayCashSales +=
            (receipt['cashDrawerDelta'] as num?)?.toDouble() ??
            (receipt['total'] as num?)?.toDouble() ??
            0.0;
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
    DateTime? occurredAt,
  }) => _drawerLock.run(() async {
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
    final queue = await getCachedCollection('pending_cash_drawer_changes');
    final id = receiptId.isNotEmpty
        ? 'receipt-$receiptId'
        : _firestore.collection('staff_cash_drawer').doc().id;
    if ((drawer['appliedOfflineMutationIds'] as List? ?? []).contains(id))
      return;
    if (!queue.any((change) => change['_localDocId'] == id))
      queue.add({
        '_localDocId': id,
        'drawerId': drawerId,
        'cashDelta': cashDelta,
        'gcashDelta': gcashDelta,
        'staffId': staffId,
        'receiptId': receiptId,
        'gcashTransactionId': gcashTransactionId,
        'createdAt': occurredAt ?? DateTime.now(),
      });
    await cacheCollectionDocs('pending_cash_drawer_changes', queue);
    if ((drawer['localReceiptIds'] as List? ?? []).contains(receiptId) &&
        receiptId.isNotEmpty)
      return;
    final todayReceipts = await getCachedCollection('completed_sales');
    drawer.addAll(CashDrawerService.forDay(drawer, DateTime.now(), receipts: todayReceipts.where((receipt) => receipt['branchId'] == drawerId)));
    final movementDate = _asDate(queue.firstWhere((change) => change['_localDocId'] == id)['createdAt']) ?? DateTime.now();
    final sameDay = CashDrawerService.dayKey(movementDate) == CashDrawerService.dayKey(DateTime.now());
    drawer['_localDocId'] = drawerId;
    drawer['balance'] = ((drawer['balance'] as num?)?.toDouble() ?? 0) + (sameDay ? cashDelta : 0);
    drawer['gcashBalance'] = ((drawer['gcashBalance'] as num?)?.toDouble() ?? 0) + (sameDay ? gcashDelta : 0);
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
    unawaited(syncPendingCashDrawerChanges());
  });

  bool _syncingDrawer = false;
  Future<void> syncPendingCashDrawerChanges() async {
    if (_syncingDrawer) return;
    _syncingDrawer = true;
    try {
      final queue = await getCachedCollection('pending_cash_drawer_changes');
      for (final change in List<Map<String, dynamic>>.from(queue)) {
        final id = change['_localDocId']?.toString() ?? '';
        final drawerId = change['drawerId']?.toString() ?? '';
        if (id.isEmpty || drawerId.isEmpty) continue;
        try {
          final ref = _firestore.collection('staff_cash_drawer').doc(drawerId);
          await CashDrawerService.ensureToday(_firestore, drawerId);
          await _firestore.runTransaction((transaction) async {
            final snapshot = await transaction.get(ref);
            final applied = List<String>.from(
              snapshot.data()?['appliedOfflineMutationIds'] as List? ??
                  const [],
            );
            if (applied.contains(id)) return;
            final now = DateTime.now();
            final current = CashDrawerService.forDay(snapshot.data() ?? {}, now);
            final sameDay = CashDrawerService.dayKey(_asDate(change['createdAt']) ?? now) == CashDrawerService.dayKey(now);
            transaction.set(ref, {
              ...current,
              'balance': (current['balance'] as num? ?? 0) + (sameDay ? (change['cashDelta'] as num? ?? 0) : 0),
              'gcashBalance': (current['gcashBalance'] as num? ?? 0) + (sameDay ? (change['gcashDelta'] as num? ?? 0) : 0),
              'staffId': drawerId,
              'branchId': drawerId,
              'handledByStaffId': change['staffId'],
              if ((change['gcashTransactionId']?.toString() ?? '').isNotEmpty)
                'lastGcashTransactionId': change['gcashTransactionId'],
              'appliedOfflineMutationIds': [...applied, id],
              'updatedAt': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));
          });
          await _drawerLock.run(() async {
            final remaining = await getCachedCollection(
              'pending_cash_drawer_changes',
            );
            remaining.removeWhere(
              (item) => item['_localDocId']?.toString() == id,
            );
            await cacheCollectionDocs('pending_cash_drawer_changes', remaining);
          });
        } catch (_) {
          // Still offline or temporarily unavailable; leave the change queued.
          return;
        }
      }
    } finally {
      _syncingDrawer = false;
    }
  }

  Future<void> recordCompletedSale(Map<String, dynamic> payload) async {
    payload = refundValueRecord(payload);
    final now = DateTime.now();
    final salesId = payload['salesId']?.toString().trim();
    final docId = salesId?.isNotEmpty == true
        ? salesId!
        : _firestore.collection('completed_sales').doc().id;
    final local = {
      ...payload,
      '_localDocId': docId,
      'localOnly': true,
      'drawerSyncRequired': true,
    };
    await _salesLock.run(() async {
      final cached = await getCachedCollection('completed_sales');

      final index = cached.indexWhere((item) => item['_localDocId'] == docId);
      if (index >= 0) {
        cached[index] = local;
      } else {
        cached.insert(0, local);
      }
      await cacheCollectionDocs('completed_sales', cached);
    });

    await _ensureSaleDrawer(local);
    if (payload['stockSyncRequired'] == true) {
      final stock = await getCachedCollection('staff_inventory');
      await cacheCollectionDocs('staff_inventory', stock);
    }

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

  Future<void> updateReceiptPrintStatus({
    required String salesId,
    required String status,
    String? error,
  }) async {
    final updatedAt = DateTime.now();
    final localFields = <String, dynamic>{
      'receiptPrintStatus': status,
      'receiptPrintError': error,
      'receiptPrintUpdatedAt': updatedAt,
    };
    await _salesLock.run(() async {
      final cached = await getCachedCollection('completed_sales');
      final sale = cached.firstWhere(
        (item) => item['_localDocId'] == salesId || item['salesId'] == salesId,
        orElse: () => <String, dynamic>{},
      );
      if (sale.isEmpty) return;
      sale.addAll(localFields);
      await cacheCollectionDocs('completed_sales', cached);
    });
    try {
      await _firestore.collection('completed_sales').doc(salesId).set({
        'receiptPrintStatus': status,
        'receiptPrintError': error,
        'receiptPrintUpdatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (error) {
      debugPrint('Receipt print status remains local for $salesId: $error');
    }
  }

  Future<bool> ensureSaleSynced(
    String salesId, {
    Duration timeout = const Duration(seconds: 12),
  }) async {
    final stopwatch = Stopwatch()..start();
    while (stopwatch.elapsed < timeout) {
      final cached = await getCachedCollection('completed_sales');
      final sale = cached.firstWhere(
        (item) => item['_localDocId'] == salesId || item['salesId'] == salesId,
        orElse: () => <String, dynamic>{},
      );
      if (sale.isEmpty) return false;
      if (sale['localOnly'] != true) return true;
      await syncPendingSales();
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    return false;
  }

  final Set<String> _uploadingSales = {};
  Future<void> _uploadCompletedSale(
    String docId,
    Map<String, dynamic> payload,
  ) async {
    if (!_uploadingSales.add(docId)) return;
    try {
      final ref = _firestore.collection('completed_sales').doc(docId);
      if (payload['stockSyncRequired'] == true) {
        final lines = (payload['items'] as List? ?? [])
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList();
        final ids = lines
            .map((line) => '${line['staffInventoryDocId'] ?? ''}')
            .where((id) => id.isNotEmpty)
            .toSet();
        await _firestore.runTransaction((tx) async {
          final receipt = await tx.get(ref);
          if (receipt.data()?['stockApplied'] == true) return;
          final stock = <DocumentSnapshot<Map<String, dynamic>>>[];
          for (final id in ids) {
            stock.add(
              await tx.get(_firestore.collection('staff_inventory').doc(id)),
            );
          }
          for (final doc in stock) {
            if (!doc.exists)
              throw StateError(
                'Allocated inventory no longer exists: ${doc.id}',
              );
            final updated = applySaleStock(
              doc.data()!,
              docId,
              lines
                  .where((line) => line['staffInventoryDocId'] == doc.id)
                  .toList(),
            );
            tx.update(doc.reference, updated);
          }
          tx.set(ref, {
            ...payload,
            for (final key in const [
              'receiptPrintStatus',
              'receiptPrintError',
              'receiptPrintUpdatedAt',
            ])
              if (receipt.data()?.containsKey(key) == true)
                key: receipt.data()![key],
            'stockApplied': true,
            'stockSyncRequired': false,
          }, SetOptions(merge: true));
        });
      } else {
        await ref.set(payload, SetOptions(merge: true));
      }
      await _salesLock.run(() async {
        final cached = await getCachedCollection('completed_sales');
        for (final sale in cached) {
          if (sale['_localDocId'] == docId) {
            sale['localOnly'] = false;
            sale['stockSyncRequired'] = false;
          }
        }
        await cacheCollectionDocs('completed_sales', cached);
      });
    } catch (e) {
      debugPrint('Completed sale remains queued locally: $e');
    } finally {
      _uploadingSales.remove(docId);
    }
  }

  /// Re-sends receipts that were saved before the app closed while offline.
  /// Reusing the stable local ID makes this idempotent (no duplicate sale).
  Future<void> _ensureSaleDrawer(Map<String, dynamic> sale) async {
    final inventoryReplacement = sale['refundMethod'] == 'inventory';
    final cash =
        (sale['paymentMode'] ?? 'Cash').toString().toLowerCase() == 'cash';
    if (!inventoryReplacement) {
      await recordCashDrawerChange(
        drawerId: sale['branchId']?.toString() ?? '',
        cashDelta: cash
            ? (sale['cashDrawerDelta'] as num? ?? sale['total'] as num? ?? 0)
                  .toDouble()
            : 0,
        gcashDelta: cash ? 0 : (sale['total'] as num? ?? 0).toDouble(),
        staffId: sale['userId']?.toString() ?? '',
        receiptId: sale['salesId']?.toString() ?? '',
        gcashTransactionId: sale['gcashTransactionId']?.toString() ?? '',
        occurredAt: _asDate(sale['timestamp']),
      );
    }
    await _salesLock.run(() async {
      final latest = await getCachedCollection('completed_sales');
      for (final row in latest) {
        if (row['_localDocId'] == sale['_localDocId'])
          row['drawerSyncRequired'] = false;
      }
      await cacheCollectionDocs('completed_sales', latest);
    });
  }

  Future<void> syncPendingSales() async {
    final sales = await getCachedCollection('completed_sales');
    for (final sale in sales.where(
      (item) => item['drawerSyncRequired'] == true,
    )) {
      await _ensureSaleDrawer(sale);
    }
    for (final sale in sales.where((item) => item['localOnly'] == true)) {
      final id = sale['_localDocId']?.toString() ?? '';
      if (id.isEmpty) continue;
      final payload = Map<String, dynamic>.from(sale)
        ..remove('_localDocId')
        ..remove('localOnly')
        ..remove('drawerSyncRequired')
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
