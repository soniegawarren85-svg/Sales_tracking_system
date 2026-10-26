import 'package:cloud_firestore/cloud_firestore.dart';
import 'inventory_display_ids.dart';

Future<void> updateBranchInventoryItem({
  required FirebaseFirestore firestore,
  required String branchId,
  required Map<String, dynamic> item,
  required String name,
  required double price,
  int? stock,
  Map<String, double>? sizePrices,
  DateTime? expirationDate,
  bool updateExpirationDate = false,
}) async {
  final sourceId = '${item['sourceInventoryId'] ?? ''}';
  final itemId = '${item['id'] ?? ''}';
  final query = firestore.collection('staff_inventory');
  final snapshots = await Future.wait([
    query.where('staffId', isEqualTo: branchId).get(),
    query.where('branchId', isEqualTo: branchId).get(),
  ]);
  final documents = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{
    for (final snapshot in snapshots)
      for (final document in snapshot.docs) document.id: document,
  }.values.toList();
  final candidates =
      <
        ({
          DocumentReference<Map<String, dynamic>> ref,
          int? index,
          Map<String, dynamic> value,
        })
      >[];

  for (final document in documents) {
    final allocation = document.data();
    if (allocation['isDeleted'] == true ||
        allocation['isVoided'] == true ||
        (sourceId.isNotEmpty &&
            '${allocation['sourceInventoryId'] ?? ''}' != sourceId)) {
      continue;
    }
    final singleItem =
        allocation['isBundle'] == true ||
        allocation['isCoffee'] == true ||
        allocation['isAddon'] == true;
    if (singleItem) {
      if (inventoryDisplayId(allocation) == itemId) {
        candidates.add((
          ref: document.reference,
          index: null,
          value: allocation,
        ));
      }
      continue;
    }
    final variants = allocation['items'] as List? ?? [];
    for (var index = 0; index < variants.length; index++) {
      final raw = variants[index];
      if (raw is! Map) continue;
      final variant = Map<String, dynamic>.from(raw);
      if (inventoryDisplayId(variant) == itemId) {
        candidates.add((ref: document.reference, index: index, value: variant));
      }
    }
  }

  if (candidates.isEmpty) {
    throw StateError(
      'This item is no longer allocated to the selected branch.',
    );
  }
  await firestore.runTransaction((transaction) async {
    final references = {
      for (final candidate in candidates) candidate.ref.path: candidate.ref,
    };
    final latest = <String, Map<String, dynamic>>{};
    final snapshots = await Future.wait(references.values.map(transaction.get));
    for (final snapshot in snapshots) {
      if (!snapshot.exists) {
        throw StateError('This item is no longer allocated to the branch.');
      }
      latest[snapshot.reference.path] = snapshot.data() ?? {};
    }
    final currentItems = candidates.map((candidate) {
      final allocation = latest[candidate.ref.path]!;
      return candidate.index == null
          ? allocation
          : Map<String, dynamic>.from(
              (allocation['items'] as List? ?? [])[candidate.index!] as Map,
            );
    }).toList();
    for (var index = 0; index < candidates.length; index++) {
      if (inventoryDisplayId(currentItems[index]) != itemId) {
        throw StateError('This item changed while it was being edited.');
      }
      if (stock != null &&
          currentItems[index]['isBundle'] == true &&
          (currentItems[index]['bundleInstances'] as List? ?? []).isNotEmpty) {
        throw StateError('Bundle stock is managed by its allocated batches.');
      }
    }
    final quantities = currentItems
        .map(
          (currentItem) =>
              int.tryParse(
                '${currentItem['stock'] ?? currentItem['startingStock'] ?? currentItem['bundleCount'] ?? 0}',
              ) ??
              0,
        )
        .toList();
    if (stock != null) {
      final currentTotal = quantities.fold<int>(
        0,
        (total, value) => total + value,
      );
      if (stock >= currentTotal) {
        quantities[0] += stock - currentTotal;
      } else {
        var reduction = currentTotal - stock;
        for (
          var index = 0;
          index < quantities.length && reduction > 0;
          index++
        ) {
          final removed = quantities[index] < reduction
              ? quantities[index]
              : reduction;
          quantities[index] -= removed;
          reduction -= removed;
        }
      }
    }
    final updatedAllocations = <String, Map<String, dynamic>>{
      for (final entry in latest.entries)
        entry.key: Map<String, dynamic>.from(entry.value),
    };
    for (var index = 0; index < candidates.length; index++) {
      final candidate = candidates[index];
      final allocation = updatedAllocations[candidate.ref.path]!;
      final currentItem = currentItems[index];
      final updatedItem = {
        ...Map<String, dynamic>.from(currentItem),
        'name': name,
        'price': price,
        'branchNameOverride': name,
        'branchPriceOverride': price,
        if (sizePrices != null) 'branchSizePriceOverrides': sizePrices,
        if (updateExpirationDate)
          'expirationDate': expirationDate == null
              ? null
              : Timestamp.fromDate(expirationDate),
        if (stock != null) ...{
          if (candidate.index == null && currentItem['isBundle'] == true)
            'bundleCount': quantities[index]
          else
            'stock': quantities[index],
        },
      };
      if (candidate.index == null) {
        updatedAllocations[candidate.ref.path] = updatedItem;
      } else {
        final variants = (allocation['items'] as List? ?? [])
            .map((raw) => raw is Map ? Map<String, dynamic>.from(raw) : raw)
            .toList();
        if (candidate.index! >= variants.length ||
            variants[candidate.index!] is! Map) {
          throw StateError('This item changed while it was being edited.');
        }
        variants[candidate.index!] = updatedItem;
        allocation['items'] = variants;
      }
    }
    for (final entry in updatedAllocations.entries) {
      transaction.set(
        references[entry.key]!,
        entry.value,
        SetOptions(merge: true),
      );
    }
  });
}
