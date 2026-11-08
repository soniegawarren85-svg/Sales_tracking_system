import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'bundle_stock_service.dart';

/// Moves expired physical stock out of the sellable branch quantity and opens
/// a return record for the branch admin. Deterministic document IDs make the
/// sweep safe to retry whenever inventory refreshes.
class StaffExpiryService {
  StaffExpiryService(this.db);
  final FirebaseFirestore db;

  DateTime? _date(dynamic value) {
    if (value is Timestamp) return DateUtils.dateOnly(value.toDate());
    if (value is DateTime) return DateUtils.dateOnly(value);
    final parsed = DateTime.tryParse('$value');
    return parsed == null ? null : DateUtils.dateOnly(parsed);
  }

  Future<void> process(
    Iterable<Map<String, dynamic>> allocations,
    Set<String> scopeIds,
  ) async {
    final today = DateUtils.dateOnly(DateTime.now());
    for (final allocation in allocations) {
      final allocationId = '${allocation['_localDocId'] ?? ''}';
      final branchId = '${allocation['staffId'] ?? ''}';
      if (allocationId.isEmpty ||
          !scopeIds.contains(branchId) ||
          allocation['isDeleted'] == true ||
          allocation['isCoffee'] == true ||
          allocation['isAddon'] == true) {
        continue;
      }
      if (allocation['isBundle'] == true) {
        final instances = (allocation['bundleInstances'] as List? ?? const [])
            .whereType<Map>()
            .map((instance) => Map<String, dynamic>.from(instance))
            .toList();
        for (final instance in instances) {
          final status = '${instance['status'] ?? 'available'}'.toLowerCase();
          if (status != 'available' ||
              !_bundleInstanceExpired(instance, today)) {
            continue;
          }
          await _processBundleInstance(
            allocationId: allocationId,
            branchId: branchId,
            allocation: allocation,
            instance: instance,
          );
        }
        continue;
      }
      final items = (allocation['items'] as List? ?? const [])
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
      for (var index = 0; index < items.length; index++) {
        final item = items[index];
        final expiry = _date(item['expirationDate'] ?? item['expiryDate']);
        final stock =
            int.tryParse('${item['stock'] ?? item['startingStock'] ?? 0}') ?? 0;
        if (expiry == null || expiry.isAfter(today) || stock <= 0) continue;
        await _processItem(
          allocationId: allocationId,
          branchId: branchId,
          item: item,
          itemIndex: index,
          expiry: expiry,
        );
      }
    }
  }

  bool _bundleInstanceExpired(Map<String, dynamic> instance, DateTime today) {
    if (bundleExpired(instance, today)) return true;
    return bundleRows(
      instance['items'],
    ).any((item) => bundleExpired(item, today));
  }

  Future<void> _processBundleInstance({
    required String allocationId,
    required String branchId,
    required Map<String, dynamic> allocation,
    required Map<String, dynamic> instance,
  }) async {
    final bundleName = '${allocation['name'] ?? 'Bundle'}';
    final bundleId = '${instance['id'] ?? ''}'.replaceAll(
      RegExp(r'[^A-Za-z0-9_-]'),
      '_',
    );
    if (bundleId.isEmpty) return;
    final source = db.collection('staff_inventory').doc(allocationId);
    final returnRef = db
        .collection('allocation_checklist')
        .doc('expired_bundle_${allocationId}_$bundleId');
    final adjustmentRef = db
        .collection('stock_adjustments')
        .doc('expired_bundle_${allocationId}_$bundleId');
    final notificationRef = db
        .collection('admin_notifications')
        .doc('expired_bundle_return_${allocationId}_$bundleId');
    await db.runTransaction((tx) async {
      final currentSnapshot = await tx.get(source);
      final returnSnapshot = await tx.get(returnRef);
      if (!currentSnapshot.exists || returnSnapshot.exists) return;
      final current = currentSnapshot.data() ?? <String, dynamic>{};
      final instances = (current['bundleInstances'] as List? ?? const [])
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();
      final index = instances.indexWhere(
        (row) => '${row['id'] ?? ''}' == '${instance['id']}',
      );
      final currentCount = int.tryParse('${current['bundleCount'] ?? 0}') ?? 0;
      if (index < 0 ||
          currentCount <= 0 ||
          '${instances[index]['status'] ?? 'available'}'.toLowerCase() !=
              'available' ||
          !_bundleInstanceExpired(
            instances[index],
            DateUtils.dateOnly(DateTime.now()),
          )) {
        return;
      }
      instances[index] = {
        ...instances[index],
        'status': 'return_pending',
        'expired': true,
        'returnId': returnRef.id,
      };
      final branchName =
          '${current['branchName'] ?? current['staffName'] ?? branchId}';
      tx.update(source, {
        'bundleInstances': instances,
        'bundleCount': currentCount - 1,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      tx.set(returnRef, {
        'kind': 'return',
        'status': 'Awaiting Admin Confirmation',
        'staffId': branchId,
        'branchId': branchId,
        'staffName': current['staffName'] ?? branchName,
        'branchName': branchName,
        'name': bundleName,
        'itemName': bundleName,
        'expirationDate':
            instances[index]['expirationDate'] ??
            bundleRows(instances[index]['items'])
                .map((item) => item['expirationDate'])
                .where((value) => value != null)
                .firstOrNull,
        'quantity': 1,
        'returnQuantity': 1,
        'reason': 'Expired item',
        'returnReason': 'Expired item',
        'returnSourceCollection': 'staff_inventory',
        'returnSourceId': allocationId,
        'bundleInstanceId': instances[index]['id'],
        'isBundle': true,
        'isExpiredInventory': true,
        'sourceItem': instances[index],
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      tx.set(adjustmentRef, {
        'type': 'expired',
        'staffId': branchId,
        'userId': branchId,
        'staffName': current['staffName'] ?? branchName,
        'branchId': branchId,
        'branchName': branchName,
        'categoryId': current['sourceInventoryId'] ?? allocationId,
        'allocationId': allocationId,
        'itemId': instances[index]['id'],
        'itemName': bundleName,
        'quantity': 1,
        'reason': 'Expired bundle item',
        'createdAt': FieldValue.serverTimestamp(),
      });
      tx.set(notificationRef, {
        'title': 'Expired bundle awaiting return',
        'message':
            '$bundleName expired at $branchName and was sent to Admin for return review.',
        'type': 'allocation_return',
        'category': 'Inventory',
        'requestId': returnRef.id,
        'branchId': branchId,
        'staffId': branchId,
        'staffName': current['staffName'] ?? branchName,
        'isRead': false,
        'toastShown': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> _processItem({
    required String allocationId,
    required String branchId,
    required Map<String, dynamic> item,
    required int itemIndex,
    required DateTime expiry,
  }) async {
    final variant =
        '${item['id'] ?? item['variantId'] ?? item['name'] ?? itemIndex}'
            .replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    final key =
        '${allocationId}_${variant}_${expiry.toIso8601String().split('T').first}'
            .replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    final source = db.collection('staff_inventory').doc(allocationId);
    final returnRef = db.collection('allocation_checklist').doc('expired_$key');
    final adjustmentRef = db
        .collection('stock_adjustments')
        .doc('expired_$key');
    final notificationRef = db
        .collection('admin_notifications')
        .doc('expired_return_$key');

    await db.runTransaction((tx) async {
      final currentSnapshot = await tx.get(source);
      final returnSnapshot = await tx.get(returnRef);
      if (!currentSnapshot.exists || returnSnapshot.exists) return;
      final current = currentSnapshot.data() ?? <String, dynamic>{};
      final currentItems = (current['items'] as List? ?? const [])
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();
      final currentIndex = currentItems.indexWhere((row) {
        final id = '${item['id'] ?? item['variantId'] ?? ''}';
        if (id.isNotEmpty && '${row['id'] ?? row['variantId'] ?? ''}' == id) {
          return true;
        }
        return '${row['name'] ?? ''}' == '${item['name'] ?? ''}' &&
            '${row['expirationDate'] ?? row['expiryDate'] ?? ''}' ==
                '${item['expirationDate'] ?? item['expiryDate'] ?? ''}';
      });
      if (currentIndex < 0) return;
      final currentItem = currentItems[currentIndex];
      final latestStock =
          int.tryParse(
            '${currentItem['stock'] ?? currentItem['startingStock'] ?? 0}',
          ) ??
          0;
      final latestExpiry = _date(
        currentItem['expirationDate'] ?? currentItem['expiryDate'],
      );
      if (latestStock <= 0 ||
          latestExpiry == null ||
          latestExpiry.isAfter(DateUtils.dateOnly(DateTime.now()))) {
        return;
      }
      currentItems[currentIndex] = {
        ...currentItem,
        'stock': 0,
        'expiredQuantity': latestStock,
        'expiryReturnId': returnRef.id,
      };
      tx.update(source, {
        'items': currentItems,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      final itemName = '${currentItem['name'] ?? 'Item'}';
      final branchName =
          '${current['branchName'] ?? current['staffName'] ?? branchId}';
      final sourceInventoryId = '${current['sourceInventoryId'] ?? ''}';
      tx.set(returnRef, {
        'kind': 'return',
        'status': 'Awaiting Admin Confirmation',
        'staffId': branchId,
        'branchId': branchId,
        'staffName': current['staffName'] ?? branchName,
        'branchName': branchName,
        'name': itemName,
        'itemName': itemName,
        'quantity': latestStock,
        'returnQuantity': latestStock,
        'reason': 'Expired item',
        'returnReason': 'Expired item',
        'returnSourceCollection': 'staff_inventory',
        'returnSourceId': allocationId,
        'returnLineKey': currentItem['id'] ?? currentItem['name'],
        'sourceInventoryId': sourceInventoryId,
        'sourceItem': currentItem,
        'expirationDate': latestExpiry.toIso8601String(),
        'isExpiredInventory': true,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      tx.set(adjustmentRef, {
        'type': 'expired',
        'staffId': branchId,
        'userId': branchId,
        'staffName': current['staffName'] ?? branchName,
        'branchId': branchId,
        'branchName': branchName,
        'categoryId': sourceInventoryId,
        'allocationId': allocationId,
        'itemId': currentItem['id'] ?? currentItem['variantId'],
        'itemName': itemName,
        'quantity': latestStock,
        'reason': 'Expired item',
        'expirationDate': latestExpiry.toIso8601String(),
        'sourceInventoryId': sourceInventoryId,
        'createdAt': FieldValue.serverTimestamp(),
      });
      tx.set(notificationRef, {
        'title': 'Expired inventory awaiting return',
        'message':
            '$latestStock $itemName expired at $branchName and was moved out of sellable inventory for return review.',
        'type': 'allocation_return',
        'category': 'Inventory',
        'requestId': returnRef.id,
        'branchId': branchId,
        'staffId': branchId,
        'staffName': current['staffName'] ?? branchName,
        'isRead': false,
        'toastShown': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
    });
  }
}
