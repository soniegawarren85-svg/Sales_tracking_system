import 'package:cloud_firestore/cloud_firestore.dart';

import 'bundle_stock_service.dart';
import 'inventory_display_ids.dart';

Future<bool> voidBranchInventoryAllocation({
  required FirebaseFirestore firestore,
  required String allocationId,
  required String allocationItemId,
  String? branchId,
  Map<String, dynamic>? item,
  bool allowLowStock = false,
}) {
  if (branchId != null && branchId.isNotEmpty && item != null) {
    return _voidSoldOutBranchCopies(
      firestore: firestore,
      branchId: branchId,
      sourceAllocationId: allocationId,
      item: item,
      allowLowStock: allowLowStock,
    );
  }
  return firestore.runTransaction<bool>((transaction) async {
    final ref = firestore.collection('staff_inventory').doc(allocationId);
    final snapshot = await transaction.get(ref);
    final data = snapshot.data();
    if (data == null || data['isDeleted'] == true) return false;

    if (allocationItemId.isEmpty) {
      if (availableBundleStock(data) > 0) {
        throw StateError('This bundle is not sold out yet.');
      }
      transaction.update(ref, {
        'isDeleted': true,
        'voidedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return true;
    }

    final variants = (data['items'] as List? ?? [])
        .whereType<Map>()
        .map((variant) => Map<String, dynamic>.from(variant))
        .toList();
    final index = variants.indexWhere(
      (variant) =>
          '${variant['id'] ?? variant['itemId'] ?? ''}' == allocationItemId,
    );
    if (index < 0) return false;

    final stock =
        num.tryParse(
          '${variants[index]['stock'] ?? variants[index]['startingStock'] ?? 0}',
        )?.toInt() ??
        0;
    if (stock > 0) throw StateError('This item is not sold out yet.');

    final removed = variants.removeAt(index);
    transaction.update(ref, {
      'items': variants,
      'removedItems': FieldValue.arrayUnion([
        {
          ...removed,
          'removedAt': Timestamp.now(),
          'voidReason': 'Voided from branch inventory',
        },
      ]),
      'isDeleted': variants.isEmpty,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return true;
  });
}

Future<bool> _voidSoldOutBranchCopies({
  required FirebaseFirestore firestore,
  required String branchId,
  required String sourceAllocationId,
  required Map<String, dynamic> item,
  required bool allowLowStock,
}) async {
  final inventory = firestore.collection('staff_inventory');
  final snapshots = await Future.wait([
    inventory.where('staffId', isEqualTo: branchId).get(),
    inventory.where('branchId', isEqualTo: branchId).get(),
  ]);
  final documents = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{
    for (final snapshot in snapshots)
      for (final document in snapshot.docs) document.id: document,
  }.values.toList();

  bool sameSource(Map<String, dynamic> allocation) {
    final sourceId = '${item['sourceInventoryId'] ?? ''}'.trim();
    return sourceId.isEmpty ||
        '${allocation['sourceInventoryId'] ?? ''}'.trim() == sourceId;
  }

  final matchingDocs = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
  for (final document in documents) {
    final allocation = document.data();
    if (allocation['isDeleted'] == true ||
        allocation['isVoided'] == true ||
        !sameSource(allocation)) {
      continue;
    }
    final singleItem =
        allocation['isBundle'] == true ||
        allocation['isCoffee'] == true ||
        allocation['isAddon'] == true;
    final matches = singleItem
        ? inventoryVariantsMatch(item, allocation)
        : (allocation['items'] as List? ?? []).whereType<Map>().any(
            (variant) => inventoryVariantsMatch(item, variant),
          );
    if (matches) matchingDocs[document.id] = document;
  }

  if (!matchingDocs.containsKey(sourceAllocationId)) {
    return false;
  }

  return firestore.runTransaction<bool>((transaction) async {
    final latestSnapshots = await Future.wait(
      matchingDocs.values.map(
        (document) => transaction.get(document.reference),
      ),
    );
    var removedAny = false;

    for (final snapshot in latestSnapshots) {
      if (!snapshot.exists) continue;
      final allocation = snapshot.data();
      if (allocation == null ||
          allocation['isDeleted'] == true ||
          allocation['isVoided'] == true ||
          !sameSource(allocation)) {
        continue;
      }

      final singleItem =
          allocation['isBundle'] == true ||
          allocation['isCoffee'] == true ||
          allocation['isAddon'] == true;
      if (singleItem) {
        if (!inventoryVariantsMatch(item, allocation)) continue;
        final stock = allocation['isBundle'] == true
            ? availableBundleStock(allocation)
            : num.tryParse('${allocation['stock'] ?? 0}')?.toInt() ?? 0;
        final mayVoidMarkedLowStock =
            allowLowStock &&
            allocation['isLowStock'] == true &&
            (allocation['isCoffee'] == true || allocation['isAddon'] == true);
        if (stock > 0 && !mayVoidMarkedLowStock) {
          if (snapshot.id == sourceAllocationId) {
            throw StateError('This item is not sold out yet.');
          }
          continue;
        }
        transaction.update(snapshot.reference, {
          'isDeleted': true,
          'voidedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
        removedAny = true;
        continue;
      }

      final variants = (allocation['items'] as List? ?? [])
          .whereType<Map>()
          .map((variant) => Map<String, dynamic>.from(variant))
          .toList();
      final removed = <Map<String, dynamic>>[];
      variants.removeWhere((variant) {
        if (!inventoryVariantsMatch(item, variant)) return false;
        final stock =
            num.tryParse(
              '${variant['stock'] ?? variant['startingStock'] ?? 0}',
            )?.toInt() ??
            0;
        if (stock > 0) {
          if (snapshot.id == sourceAllocationId) {
            throw StateError('This item is not sold out yet.');
          }
          return false;
        }
        removed.add(variant);
        return true;
      });
      if (removed.isEmpty) continue;
      transaction.update(snapshot.reference, {
        'items': variants,
        'removedItems': FieldValue.arrayUnion([
          for (final variant in removed)
            {
              ...variant,
              'removedAt': Timestamp.now(),
              'voidReason': 'Voided from branch inventory',
            },
        ]),
        'isDeleted': variants.isEmpty,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      removedAny = true;
    }
    return removedAny;
  });
}
