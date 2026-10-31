import 'dart:convert';
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'bundle_stock_service.dart';
import 'local_write_lock.dart';
import 'number_format.dart';

bool stockReductionMatchesItem(
  Map<String, dynamic> item, {
  required String itemId,
  required String itemName,
  required String variant,
}) {
  String normalized(dynamic value) => '${value ?? ''}'.trim().toLowerCase();

  final normalizedName = normalized(itemName);
  final normalizedVariant = normalized(variant);
  final nameMatches =
      normalizedName.isEmpty || normalized(item['name']) == normalizedName;
  final itemIds = [
    item['id'],
    item['itemId'],
    item['variantId'],
    item['sourceItemId'],
    item['publicId'],
    item['itemPublicId'],
  ].map((value) => '${value ?? ''}'.trim());
  final idMatches = itemId.trim().isNotEmpty && itemIds.contains(itemId.trim());
  final itemVariants = [
    item['variant'],
    item['size'],
    item['coffeeSize'],
  ].map(normalized).where((value) => value.isNotEmpty).toSet();
  final variantMatches =
      normalizedVariant.isEmpty ||
      itemVariants.contains(normalizedVariant) ||
      (idMatches && itemVariants.isEmpty);

  if ((!nameMatches && !idMatches) || !variantMatches) return false;
  if (idMatches) return true;
  return normalizedName.isNotEmpty;
}

bool beverageStockMatchesSize(Map<String, dynamic> item, String size) {
  final normalizedSize = size.trim().toLowerCase();
  if (normalizedSize.isEmpty) return false;
  final explicitSize = [
    item['coffeeSize'],
    item['variant'],
    item['size'],
  ].map((value) => '${value ?? ''}'.trim().toLowerCase());
  if (explicitSize.any((value) => value == normalizedSize)) return true;

  final name = '${item['name'] ?? ''}'.trim().toLowerCase();
  return name == normalizedSize ||
      name.endsWith(' - $normalizedSize') ||
      name.endsWith(' ($normalizedSize)');
}

class StockReductionResult {
  const StockReductionResult({
    required this.items,
    required this.previousStock,
    required this.newStock,
    required this.unitPrice,
  });

  final List<Map<String, dynamic>> items;
  final int previousStock;
  final int newStock;
  final double unitPrice;
}

class StockReductionDocumentsResult {
  const StockReductionDocumentsResult({
    required this.itemsByDocument,
    required this.previousStock,
    required this.newStock,
    required this.unitPrice,
  });

  final Map<String, List<Map<String, dynamic>>> itemsByDocument;
  final int previousStock;
  final int newStock;
  final double unitPrice;
}

StockReductionResult reduceMatchingInventoryRows({
  required Iterable<dynamic> rows,
  required String itemId,
  required String itemName,
  required String variant,
  required int quantity,
  required bool beverage,
  double fallbackUnitPrice = 0,
}) {
  int number(dynamic value) =>
      value is num ? value.toInt() : int.tryParse('$value') ?? 0;
  double price(dynamic value) {
    if (value is num) return value.toDouble();
    final normalized = '$value'.replaceAll(RegExp(r'[^0-9.-]'), '');
    return double.tryParse(normalized) ?? 0;
  }

  bool matches(Map<String, dynamic> item) => beverage
      ? beverageStockMatchesSize(item, variant)
      : stockReductionMatchesItem(
          item,
          itemId: itemId,
          itemName: itemName,
          variant: variant,
        );

  final items = rows
      .whereType<Map>()
      .map((item) => Map<String, dynamic>.from(item))
      .toList();
  final matchingIndices = [
    for (var index = 0; index < items.length; index++)
      if (matches(items[index])) index,
  ];
  final previousStock = matchingIndices.fold<int>(0, (total, index) {
    final item = items[index];
    return total +
        number(
          item['stock'] ??
              item['startingStock'] ??
              item['assignedStartingStock'],
        );
  });
  if (quantity <= 0 || quantity > previousStock) {
    throw StateError(
      'Only $previousStock ${itemName.toLowerCase()} item(s) remain.',
    );
  }

  var remaining = quantity;
  var lossAmount = 0.0;
  for (final index in matchingIndices) {
    if (remaining == 0) break;
    final item = items[index];
    final hasStock = item['stock'] != null;
    final current = number(
      item['stock'] ?? item['startingStock'] ?? item['assignedStartingStock'],
    );
    final reduced = current < remaining ? current : remaining;
    if (reduced <= 0) continue;
    final itemPrice = price(item['price']);
    final unitPrice = beverage && fallbackUnitPrice > 0
        ? fallbackUnitPrice
        : itemPrice > 0
        ? itemPrice
        : fallbackUnitPrice;
    lossAmount += unitPrice * reduced;
    final newStock = current - reduced;
    items[index] = {
      ...item,
      'stock': newStock,
      'reducedQuantity': number(item['reducedQuantity']) + reduced,
      if (!hasStock) 'startingStock': newStock,
    };
    remaining -= reduced;
  }

  return StockReductionResult(
    items: items,
    previousStock: previousStock,
    newStock: previousStock - quantity,
    unitPrice: lossAmount / quantity,
  );
}

StockReductionDocumentsResult reduceMatchingInventoryDocuments({
  required Map<String, Map<String, dynamic>> documents,
  required String itemId,
  required String itemName,
  required String variant,
  required int quantity,
  required bool beverage,
  double fallbackUnitPrice = 0,
}) {
  final rows = <Map<String, dynamic>>[];
  final rowCounts = <String, int>{};
  for (final entry in documents.entries) {
    final field = entry.value['items'] is List ? 'items' : 'sizes';
    final documentRows = (entry.value[field] as List? ?? const [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
    rowCounts[entry.key] = documentRows.length;
    rows.addAll(documentRows);
  }

  final result = reduceMatchingInventoryRows(
    rows: rows,
    itemId: itemId,
    itemName: itemName,
    variant: variant,
    quantity: quantity,
    beverage: beverage,
    fallbackUnitPrice: fallbackUnitPrice,
  );
  var offset = 0;
  final itemsByDocument = <String, List<Map<String, dynamic>>>{};
  for (final entry in documents.entries) {
    final count = rowCounts[entry.key]!;
    itemsByDocument[entry.key] = result.items.skip(offset).take(count).toList();
    offset += count;
  }
  return StockReductionDocumentsResult(
    itemsByDocument: itemsByDocument,
    previousStock: result.previousStock,
    newStock: result.newStock,
    unitPrice: result.unitPrice,
  );
}

class OfflineStockReductionService {
  static const _queueKey = 'pending_offline_stock_reductions';
  static final _changes = StreamController<void>.broadcast();
  static final _queueLock = LocalWriteLock();
  static bool _syncing = false;

  Stream<void> get changes => _changes.stream;
  bool get isSyncing => _syncing;

  Future<List<Map<String, dynamic>>> pending() async {
    final preferences = await SharedPreferences.getInstance();
    final encoded = preferences.getString(_queueKey);
    if (encoded == null || encoded.isEmpty) return [];
    final decoded = jsonDecode(encoded);
    if (decoded is! List) {
      throw const FormatException('Invalid offline stock reduction queue.');
    }
    return decoded
        .whereType<Map>()
        .map((entry) => Map<String, dynamic>.from(entry))
        .toList();
  }

  Future<void> enqueue(Map<String, dynamic> reduction) async {
    await _queueLock.run(() async {
      final queue = await pending();
      if (queue.any((item) => item['id'] == reduction['id'])) return;
      queue.add({
        ...Map<String, dynamic>.from(reduction),
        'queuedAt': reduction['queuedAt'] ?? DateTime.now().toIso8601String(),
      });
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(_queueKey, jsonEncode(queue));
      if (!_changes.isClosed) _changes.add(null);
    });
  }

  Map<String, dynamic> applyPendingToInventory(
    Map<String, dynamic> inventory,
    String inventoryId,
    Iterable<Map<String, dynamic>> reductions,
  ) {
    final field = inventory['items'] is List ? 'items' : 'sizes';
    final items = (inventory[field] as List? ?? const [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
    var changed = false;
    for (final reduction in reductions.where(
      (entry) => entry['inventoryId'] == inventoryId,
    )) {
      final itemId = '${reduction['itemId'] ?? ''}';
      final quantity = int.tryParse('${reduction['quantity'] ?? 0}') ?? 0;
      try {
        final result = reduceMatchingInventoryRows(
          rows: items,
          itemId: itemId,
          itemName: '${reduction['itemName'] ?? ''}',
          variant: '${reduction['variant'] ?? ''}',
          quantity: quantity,
          beverage: reduction['type'] == 'coffee_void',
          fallbackUnitPrice: price(reduction['unitPrice']),
        );
        items
          ..clear()
          ..addAll(result.items);
        changed = true;
      } on StateError catch (error) {
        debugPrint(
          'Pending stock reduction ${reduction['id']} cannot be overlaid: $error',
        );
      }
    }
    return changed ? {...inventory, field: items} : inventory;
  }

  List<Map<String, dynamic>> applyPendingToInventoryDocuments(
    Iterable<Map<String, dynamic>> documents,
    Iterable<Map<String, dynamic>> reductions,
  ) {
    final result = documents
        .map((document) => Map<String, dynamic>.from(document))
        .toList();
    for (final reduction in reductions) {
      final inventoryId = '${reduction['inventoryId'] ?? ''}';
      final sourceId = '${reduction['sourceInventoryId'] ?? ''}'.trim();
      final primaryIndex = result.indexWhere(
        (document) =>
            '${document['_localDocId'] ?? document['id'] ?? ''}' == inventoryId,
      );
      if (primaryIndex < 0) continue;
      final primary = result[primaryIndex];
      final staffId = '${primary['staffId'] ?? ''}'.trim();
      final targetIndices = [
        for (var index = 0; index < result.length; index++)
          if (index == primaryIndex ||
              (sourceId.isNotEmpty &&
                  staffId.isNotEmpty &&
                  result[index]['staffId'] == staffId &&
                  result[index]['sourceInventoryId'] == sourceId))
            index,
      ];
      if (reduction['type'] == 'refund_inventory_replacement') {
        for (final operation
            in (reduction['operations'] as List? ?? const [])
                .whereType<Map>()) {
          final index = result.indexWhere(
            (document) =>
                '${document['_localDocId'] ?? document['id'] ?? ''}' ==
                '${operation['docId'] ?? ''}',
          );
          if (index < 0) continue;
          final document = result[index];
          final kind = '${operation['kind'] ?? ''}';
          final quantity = int.tryParse('${operation['quantity'] ?? 0}') ?? 0;
          if (kind == 'Bundle') {
            final ids = (operation['bundleInstanceIds'] as List? ?? const [])
                .map((id) => '$id')
                .toSet();
            final instances = (document['bundleInstances'] as List? ?? const [])
                .whereType<Map>()
                .map((instance) => Map<String, dynamic>.from(instance))
                .toList();
            var reduced = 0;
            for (
              var instanceIndex = 0;
              instanceIndex < instances.length;
              instanceIndex++
            ) {
              if (!ids.contains('${instances[instanceIndex]['id'] ?? ''}') ||
                  !bundleInstanceAvailable(
                    instances[instanceIndex],
                    document,
                  )) {
                continue;
              }
              instances[instanceIndex] = {
                ...instances[instanceIndex],
                'status': 'replacement',
              };
              reduced++;
            }
            if (reduced > 0) {
              final stock =
                  int.tryParse('${document['bundleCount'] ?? 0}') ?? reduced;
              result[index] = {
                ...document,
                'bundleInstances': instances,
                'bundleCount': stock > reduced ? stock - reduced : 0,
              };
            }
          } else {
            final field = kind == 'Beverages' ? 'sizes' : 'items';
            try {
              final updated = reduceMatchingInventoryRows(
                rows: (document[field] as List? ?? const []),
                itemId: '${operation['itemId'] ?? ''}',
                itemName: '${operation['itemName'] ?? ''}',
                variant: '${operation['variant'] ?? ''}',
                quantity: quantity,
                beverage: kind == 'Beverages',
              );
              result[index] = {...document, field: updated.items};
            } on StateError catch (error) {
              debugPrint(
                'Pending refund replacement ${reduction['id']} cannot be shown: $error',
              );
            }
          }
        }
        continue;
      }
      if (reduction['type'] == 'bundle_instance_adjustment') {
        final ids = (reduction['bundleInstanceIds'] as List? ?? const [])
            .map((id) => '$id')
            .toSet();
        for (final index in targetIndices) {
          final bundle = result[index];
          final instances = (bundle['bundleInstances'] as List? ?? const [])
              .whereType<Map>()
              .map((entry) => Map<String, dynamic>.from(entry))
              .toList();
          var reduced = 0;
          for (
            var instanceIndex = 0;
            instanceIndex < instances.length;
            instanceIndex++
          ) {
            final id = '${instances[instanceIndex]['id'] ?? ''}';
            if (ids.contains(id) &&
                bundleInstanceAvailable(instances[instanceIndex], bundle)) {
              instances[instanceIndex] = {
                ...instances[instanceIndex],
                'status': 'reduced',
              };
              reduced++;
            }
          }
          if (reduced == 0) continue;
          final bundleStock =
              int.tryParse('${bundle['bundleCount'] ?? 0}') ?? 0;
          result[index] = {
            ...bundle,
            'bundleInstances': instances,
            'bundleCount': bundleStock > reduced ? bundleStock - reduced : 0,
          };
          break;
        }
        continue;
      }

      final documentsById = <String, Map<String, dynamic>>{
        for (final index in targetIndices)
          '${result[index]['_localDocId'] ?? result[index]['id'] ?? ''}':
              result[index],
      };
      final itemId = '${reduction['itemId'] ?? ''}';
      final itemName = '${reduction['itemName'] ?? ''}';
      final variant = '${reduction['variant'] ?? ''}';
      final quantity = int.tryParse('${reduction['quantity'] ?? 0}') ?? 0;
      try {
        final update = reduceMatchingInventoryDocuments(
          documents: documentsById,
          itemId: itemId,
          itemName: itemName,
          variant: variant,
          quantity: quantity,
          beverage: reduction['type'] == 'coffee_void',
          fallbackUnitPrice: price(reduction['unitPrice']),
        );
        for (final index in targetIndices) {
          final id =
              '${result[index]['_localDocId'] ?? result[index]['id'] ?? ''}';
          final items = update.itemsByDocument[id];
          if (items == null) continue;
          final field = result[index]['items'] is List ? 'items' : 'sizes';
          result[index] = {...result[index], field: items};
        }
      } on StateError catch (error) {
        debugPrint(
          'Pending reduction ${reduction['id']} cannot be shown in inventory: $error',
        );
      }
    }
    return result;
  }

  double price(dynamic value) =>
      value is num ? value.toDouble() : double.tryParse('$value') ?? 0;

  Future<void> sync(FirebaseFirestore database) async {
    if (_syncing) return;
    _syncing = true;
    if (!_changes.isClosed) _changes.add(null);
    try {
      final queue = await pending();
      for (final reduction in queue) {
        try {
          await _apply(database, reduction);
          await _queueLock.run(() async {
            final latest = await pending();
            latest.removeWhere((item) => item['id'] == reduction['id']);
            final preferences = await SharedPreferences.getInstance();
            await preferences.setString(_queueKey, jsonEncode(latest));
            if (!_changes.isClosed) _changes.add(null);
          });
        } on FirebaseException catch (error) {
          if (_isConnectionError(error.code)) return;
          debugPrint(
            'Offline stock reduction ${reduction['id']} could not sync: $error',
          );
          await _recordSyncError(reduction, error.message ?? error.code);
        } on StateError catch (error) {
          debugPrint(
            'Offline stock reduction ${reduction['id']} needs review: ${error.message}',
          );
          await _recordSyncError(reduction, error.message);
        }
      }
    } finally {
      _syncing = false;
      if (!_changes.isClosed) _changes.add(null);
    }
  }

  bool _isConnectionError(String code) => const {
    'unavailable',
    'deadline-exceeded',
    'network-request-failed',
  }.contains(code);

  Future<void> _recordSyncError(
    Map<String, dynamic> reduction,
    String message,
  ) async {
    await _queueLock.run(() async {
      final queue = await pending();
      final index = queue.indexWhere((item) => item['id'] == reduction['id']);
      if (index < 0 || queue[index]['syncError'] == message) return;
      queue[index] = {...queue[index], 'syncError': message};
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(_queueKey, jsonEncode(queue));
      if (!_changes.isClosed) _changes.add(null);
    });
  }

  Future<void> _apply(
    FirebaseFirestore database,
    Map<String, dynamic> reduction,
  ) async {
    final inventoryRef = database
        .collection('staff_inventory')
        .doc('${reduction['inventoryId']}');
    final adjustmentRef = database
        .collection('stock_adjustments')
        .doc('${reduction['id']}');
    final notificationRef = database
        .collection('admin_notifications')
        .doc('offline_stock_${reduction['id']}');
    final initialSnapshot = await inventoryRef.get();
    final initialData = initialSnapshot.data();
    if (initialData == null || initialData['isDeleted'] == true) {
      throw StateError('The source inventory allocation no longer exists.');
    }
    final initialStaffId = '${initialData['staffId'] ?? ''}'.trim();
    final initialSourceInventoryId =
        '${initialData['sourceInventoryId'] ?? reduction['sourceInventoryId'] ?? ''}'
            .trim();
    final allocationRefs = <String, DocumentReference<Map<String, dynamic>>>{
      inventoryRef.id: inventoryRef,
    };
    if (initialStaffId.isNotEmpty && initialSourceInventoryId.isNotEmpty) {
      final allocations = await database
          .collection('staff_inventory')
          .where('staffId', isEqualTo: initialStaffId)
          .get();
      for (final allocation in allocations.docs) {
        if (allocation.data()['sourceInventoryId'] ==
            initialSourceInventoryId) {
          allocationRefs[allocation.id] = allocation.reference;
        }
      }
    }
    for (final operation
        in (reduction['operations'] as List? ?? const []).whereType<Map>()) {
      final docId = '${operation['docId'] ?? ''}'.trim();
      if (docId.isNotEmpty) {
        allocationRefs[docId] = database
            .collection('staff_inventory')
            .doc(docId);
      }
    }
    await database.runTransaction<void>((transaction) async {
      final adjustmentSnapshot = await transaction.get(adjustmentRef);
      if (adjustmentSnapshot.exists) return;
      final snapshots = await Future.wait(
        allocationRefs.values.map(transaction.get),
      );
      final snapshotsById = {
        for (final snapshot in snapshots) snapshot.id: snapshot,
      };
      final inventorySnapshot = snapshotsById[inventoryRef.id];
      final data = inventorySnapshot?.data();
      if (data == null || data['isDeleted'] == true) {
        throw StateError('The source inventory allocation no longer exists.');
      }
      if (reduction['type'] == 'refund_inventory_replacement') {
        final updatedById = <String, Map<String, dynamic>>{
          for (final entry in snapshotsById.entries)
            if (entry.value.data() != null)
              entry.key: Map<String, dynamic>.from(entry.value.data()!),
        };
        for (final operation
            in (reduction['operations'] as List? ?? const [])
                .whereType<Map>()) {
          final docId = '${operation['docId'] ?? ''}';
          final updated = updatedById[docId];
          if (updated == null || updated['isDeleted'] == true) {
            throw StateError('A replacement item is no longer available.');
          }
          final quantity = int.tryParse('${operation['quantity'] ?? 0}') ?? 0;
          if ('${operation['kind'] ?? ''}' == 'Bundle') {
            final ids = (operation['bundleInstanceIds'] as List? ?? const [])
                .map((id) => '$id')
                .toSet();
            final instances = (updated['bundleInstances'] as List? ?? const [])
                .whereType<Map>()
                .map((instance) => Map<String, dynamic>.from(instance))
                .toList();
            var marked = 0;
            for (var index = 0; index < instances.length; index++) {
              if (!ids.contains('${instances[index]['id'] ?? ''}') ||
                  !bundleInstanceAvailable(instances[index], updated)) {
                continue;
              }
              instances[index] = {
                ...instances[index],
                'status': 'replacement',
                'replacementAt': FieldValue.serverTimestamp(),
              };
              marked++;
            }
            if (marked != quantity) {
              throw StateError('Not enough bundle stock for replacement.');
            }
            final stock =
                int.tryParse('${updated['bundleCount'] ?? marked}') ?? marked;
            updated['bundleCount'] = stock > marked ? stock - marked : 0;
            updated['bundleInstances'] = instances;
          } else {
            final beverage = '${operation['kind'] ?? ''}' == 'Beverages';
            final field = beverage ? 'sizes' : 'items';
            final result = reduceMatchingInventoryRows(
              rows: (updated[field] as List? ?? const []),
              itemId: '${operation['itemId'] ?? ''}',
              itemName: '${operation['itemName'] ?? ''}',
              variant: '${operation['variant'] ?? ''}',
              quantity: quantity,
              beverage: beverage,
            );
            updated[field] = result.items;
          }
        }
        for (final entry in updatedById.entries) {
          transaction
              .update(database.collection('staff_inventory').doc(entry.key), {
                if (entry.value['bundleInstances'] is List)
                  'bundleInstances': entry.value['bundleInstances'],
                if (entry.value.containsKey('bundleCount'))
                  'bundleCount': entry.value['bundleCount'],
                if (entry.value['items'] is List) 'items': entry.value['items'],
                if (entry.value['sizes'] is List) 'sizes': entry.value['sizes'],
                'updatedAt': FieldValue.serverTimestamp(),
              });
        }
        transaction.set(adjustmentRef, {
          'type': 'refund_replacement',
          'userId': reduction['userId'],
          'staffId': reduction['staffId'],
          'quantity': (reduction['operations'] as List? ?? const [])
              .whereType<Map>()
              .fold<int>(
                0,
                (total, operation) =>
                    total +
                    (int.tryParse('${operation['quantity'] ?? 0}') ?? 0),
              ),
          'operations': reduction['operations'],
          'reason': reduction['reason'] ?? 'Refund replacement',
          'createdAt': FieldValue.serverTimestamp(),
        });
        transaction.set(notificationRef, {
          'title': 'Refund replacement synced',
          'message': 'Offline inventory replacement synced successfully.',
          'category': 'Refund',
          'type': 'refund_replacement',
          'staffId': reduction['staffId'],
          'isRead': false,
          'createdAt': FieldValue.serverTimestamp(),
        });
        return;
      }
      if (reduction['type'] == 'bundle_instance_adjustment') {
        final ids = (reduction['bundleInstanceIds'] as List? ?? const [])
            .map((id) => '$id')
            .toSet();
        final instances = (data['bundleInstances'] as List? ?? const [])
            .whereType<Map>()
            .map((instance) => Map<String, dynamic>.from(instance))
            .toList();
        var reduced = 0;
        for (var index = 0; index < instances.length; index++) {
          final instance = instances[index];
          if (!ids.contains('${instance['id'] ?? ''}') ||
              !bundleInstanceAvailable(instance, data)) {
            continue;
          }
          instances[index] = {
            ...instance,
            'status': 'reduced',
            'reductionReason': reduction['reason'],
            'reductionComment': reduction['comment'] ?? '',
            'reducedAt': FieldValue.serverTimestamp(),
          };
          reduced++;
        }
        if (reduced != ids.length) {
          throw StateError('One selected bundle ID is no longer available.');
        }
        final currentStock =
            int.tryParse('${data['bundleCount'] ?? 0}') ?? reduced;
        final newStock = currentStock > reduced ? currentStock - reduced : 0;
        transaction.update(inventoryRef, {
          'bundleInstances': instances,
          'bundleCount': newStock,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        transaction.set(adjustmentRef, {
          'type': 'bundle_stock_adjustment',
          'userId': reduction['staffId'],
          'staffId': reduction['staffId'],
          'branchId': data['staffId'],
          'branchName': data['branchName'] ?? data['staffName'] ?? '',
          'isBundle': true,
          'bundleId': reduction['bundleId'] ?? data['bundleId'] ?? '',
          'itemDisplayId': reduction['itemDisplayId'] ?? '',
          'categoryId': reduction['inventoryId'],
          'categoryName': reduction['categoryName'] ?? data['name'] ?? 'Bundle',
          'itemName': reduction['categoryName'] ?? data['name'] ?? 'Bundle',
          'bundlePrice': price(reduction['unitPrice']),
          'bundleInstanceIds': ids.toList(),
          'bundleDisplayIds': reduction['bundleDisplayIds'] ?? ids.toList(),
          'quantity': reduced,
          'previousStock': currentStock,
          'newStock': newStock,
          'reason': reduction['reason'],
          'comment': reduction['comment'] ?? '',
          'offline': true,
          'syncStatus': 'synced',
          'offlineCreatedAt': reduction['queuedAt'],
          'createdAt': FieldValue.serverTimestamp(),
        });
        transaction.set(notificationRef, {
          'title': 'Bundle stock reduced',
          'message':
              '${reduction['staffName'] ?? 'Staff'} reduced $reduced bundle(s) from ${reduction['categoryName'] ?? data['name'] ?? 'Bundle'}.',
          'category': 'Stock',
          'type': 'stock_adjustment',
          'itemName': reduction['categoryName'] ?? data['name'] ?? 'Bundle',
          'quantity': reduced,
          'staffId': reduction['staffId'],
          'staffName': reduction['staffName'] ?? 'Staff',
          'isRead': false,
          'createdAt': FieldValue.serverTimestamp(),
        });
        return;
      }
      final itemId = '${reduction['itemId'] ?? ''}';
      final itemName = '${reduction['itemName'] ?? ''}';
      final variant = '${reduction['variant'] ?? ''}';
      final isBeverage = reduction['type'] == 'coffee_void';
      int number(dynamic value) =>
          value is num ? value.toInt() : int.tryParse('$value') ?? 0;
      final reductionQuantity = number(reduction['quantity']);
      final staffId = '${data['staffId'] ?? ''}'.trim();
      final sourceInventoryId =
          '${data['sourceInventoryId'] ?? reduction['sourceInventoryId'] ?? ''}'
              .trim();
      final allocationDocuments = <String, Map<String, dynamic>>{};
      for (final entry in snapshotsById.entries) {
        final allocationData = entry.value.data();
        if (allocationData == null || allocationData['isDeleted'] == true) {
          continue;
        }
        final sameScope =
            entry.key == inventoryRef.id ||
            (staffId.isNotEmpty &&
                sourceInventoryId.isNotEmpty &&
                allocationData['staffId'] == staffId &&
                allocationData['sourceInventoryId'] == sourceInventoryId);
        if (sameScope) allocationDocuments[entry.key] = allocationData;
      }
      final result = reduceMatchingInventoryDocuments(
        documents: allocationDocuments,
        itemId: itemId,
        itemName: itemName,
        variant: variant,
        quantity: reductionQuantity,
        beverage: isBeverage,
        fallbackUnitPrice: price(reduction['unitPrice']),
      );
      final previousStock = result.previousStock;
      final newStock = result.newStock;
      final lossAmount = result.unitPrice * reductionQuantity;
      final quantity = number(reduction['quantity']);
      final staffName = '${reduction['staffName'] ?? 'Staff'}';
      final categoryName = '${reduction['categoryName'] ?? 'Inventory'}';
      final comment = '${reduction['comment'] ?? ''}';
      for (final entry in result.itemsByDocument.entries) {
        final field = allocationDocuments[entry.key]?['items'] is List
            ? 'items'
            : 'sizes';
        transaction.update(
          database.collection('staff_inventory').doc(entry.key),
          {field: entry.value},
        );
      }
      transaction.set(adjustmentRef, {
        'type':
            reduction['adjustmentType'] ??
            (isBeverage ? 'coffee_void' : 'stock_adjustment'),
        if (isBeverage) 'coffeeId': reduction['coffeeId'] ?? '',
        if (isBeverage) 'isCoffee': true,
        if (isBeverage) 'coffeeSize': variant,
        'userId': reduction['staffId'],
        'staffId': reduction['staffId'],
        'branchId': data['staffId'],
        'branchName': data['branchName'] ?? data['staffName'] ?? '',
        'isBundle': data['isBundle'] == true,
        'categoryName': categoryName,
        'categoryId': reduction['inventoryId'],
        if (sourceInventoryId.isNotEmpty)
          'sourceInventoryId': sourceInventoryId,
        'itemId': itemId,
        'itemName': itemName,
        'variant': variant,
        'quantity': quantity,
        'unitPrice': lossAmount / quantity,
        'lossAmount': lossAmount,
        'previousStock': previousStock,
        'newStock': newStock,
        'reason': reduction['reason'],
        'comment': comment,
        'offline': true,
        'syncStatus': 'synced',
        'offlineCreatedAt': reduction['queuedAt'],
        'createdAt': FieldValue.serverTimestamp(),
      });
      transaction.set(notificationRef, {
        'title': 'Stock reduced',
        'message':
            '$staffName reduced $quantity x $itemName from $previousStock to $newStock. Expected sales decreased by ${formatMoney(lossAmount)}.',
        'category': 'Stock',
        'type': 'stock_adjustment',
        'itemName': itemName,
        'variant': variant,
        'quantity': quantity,
        'reductionAmount': lossAmount,
        'categoryName': categoryName,
        'staffId': reduction['staffId'],
        'staffName': staffName,
        'isRead': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
    });
  }
}
