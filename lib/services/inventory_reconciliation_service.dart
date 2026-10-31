import 'package:cloud_firestore/cloud_firestore.dart';
import 'bundle_stock_service.dart';
import 'branch_permissions.dart';

String ingredientIdentity(Map item) =>
    '${item['sourceCollection'] ?? 'sales_inventory'}::${item['sourceInventoryId'] ?? ''}::${item['variantId'] ?? item['itemId'] ?? item['id'] ?? item['name']}';

bool physicalIngredient(Map item) =>
    item['sourceCollection'] != 'coffee_products' &&
    item['sourceCollection'] != 'coffee_addons' &&
    item['isCoffee'] != true &&
    item['isAddon'] != true;

bool sameReconciliationIngredient(Map left, Map right) {
  if ((left['sourceCollection'] ?? 'sales_inventory') !=
          (right['sourceCollection'] ?? 'sales_inventory') ||
      '${left['sourceInventoryId'] ?? ''}' !=
          '${right['sourceInventoryId'] ?? ''}')
    return false;
  Set<String> aliases(Map item) => [
    item['variantId'],
    item['itemId'],
    item['id'],
    item['publicId'],
  ].map((value) => '${value ?? ''}'.trim()).where((v) => v.isNotEmpty).toSet();
  final a = aliases(left);
  final b = aliases(right);
  if (a.isNotEmpty && b.isNotEmpty) return a.intersection(b).isNotEmpty;
  final name = '${left['name'] ?? ''}'.trim().toLowerCase();
  return name.isNotEmpty &&
      name == '${right['name'] ?? ''}'.trim().toLowerCase();
}

/// Allocation snapshots are the source of truth, including ingredient expiries.
/// Requests reserve instances immediately; approval and rejection are idempotent.
class InventoryReconciliationService {
  InventoryReconciliationService(this.db);
  final FirebaseFirestore db;

  // Return domain validation errors across the web transaction bridge as data.
  // All validation must finish before scheduling any transaction writes.
  Future<void> _validatedTransaction(
    Future<void> Function(Transaction) operation,
  ) async {
    final error = await db.runTransaction<String?>((tx) async {
      try {
        await operation(tx);
        return null;
      } on StateError catch (error) {
        return error.message;
      }
    });
    if (error != null) throw StateError(error);
  }

  Future<void> submit({
    required String requestId,
    required String allocationId,
    required List<String> instanceIds,
    required String action,
    required String actorId,
    required String actorName,
    required List<String> scopeIds,
    String? targetAllocationId,
  }) async {
    if (actorId.isEmpty ||
        instanceIds.isEmpty ||
        instanceIds.toSet().length != instanceIds.length ||
        !['convert', 'unbundle'].contains(action)) {
      throw ArgumentError('Select bundles and a reconciliation reason.');
    }
    final request = db.collection('inventory_reconciliations').doc(requestId);
    final source = db.collection('staff_inventory').doc(allocationId);
    await _validatedTransaction((tx) async {
      if ((await tx.get(request)).exists) return;
      final data = (await tx.get(source)).data();
      if (data == null ||
          data['isBundle'] != true ||
          data['isDeleted'] == true ||
          !scopeIds.contains(data['staffId'])) {
        throw StateError('This bundle is outside your active allocation.');
      }
      Map<String, dynamic>? target;
      if (action == 'convert') {
        if (targetAllocationId == null || targetAllocationId == allocationId) {
          throw StateError('Choose a newer allocated bundle version.');
        }
        target = (await tx.get(
          db.collection('staff_inventory').doc(targetAllocationId),
        )).data();
        if (target == null ||
            target['isBundle'] != true ||
            target['isDeleted'] == true ||
            target['staffId'] != data['staffId'] ||
            bundleInventoryGroupKey(target) != bundleInventoryGroupKey(data)) {
          throw StateError(
            'The updated bundle must already be allocated to this branch.',
          );
        }
        if (availableReconciliationInstances(
          target,
          targetAllocationId,
        ).isEmpty) {
          throw StateError(
            'The updated bundle has no available stock at this branch.',
          );
        }
      }
      final instances = reconciliationInstances(data, allocationId);
      final selected = instances
          .where((i) => instanceIds.contains('${i['id']}'))
          .toList();
      if (selected.length != instanceIds.length ||
          selected.any((i) => !bundleInstanceAvailable(i, data)) ||
          bundleQuantity(data['bundleCount']) < selected.length) {
        throw StateError('Selected stock changed. Reopen the batch and retry.');
      }
      // Validate conservation before reserving any stock.
      final output = reconcileBundleContents(selected, target);
      _validateLooseSources(output);
      for (final instance in selected) {
        instance['status'] = 'reconciliation_pending';
        instance['reconciliationId'] = requestId;
      }
      tx.update(source, {
        'bundleInstances': instances,
        'bundleCount': bundleQuantity(data['bundleCount']) - selected.length,
      });
      tx.set(request, {
        'status': 'pending',
        'action': action,
        'allocationId': allocationId,
        'instanceIds': instanceIds,
        'targetAllocationId': targetAllocationId,
        'targetSnapshot': target == null
            ? null
            : {
                for (final key in [
                  'name',
                  'items',
                  'price',
                  'costPrice',
                  'sourceInventoryId',
                  'bundleId',
                  'publicId',
                  'imageUrl',
                ])
                  if (target.containsKey(key)) key: target[key],
              },
        'name': data['name'],
        'staffId': data['staffId'],
        'branchName':
            data['branchName'] ?? data['staffName'] ?? data['staffId'],
        'submittedBy': actorId,
        'submittedByName': actorName,
        'quantity': selected.length,
        'preview': output,
        'createdAt': FieldValue.serverTimestamp(),
      });
      tx.set(
        db.collection('admin_notifications').doc('bundle_action_$requestId'),
        {
          'title': action == 'unbundle'
              ? 'Bundle unbundle request'
              : 'Bundle update request',
          'message':
              '$actorName requested to ${action == 'unbundle' ? 'unbundle' : 'convert'} ${selected.length} bundle(s) from ${data['name'] ?? 'Bundle'} at ${data['branchName'] ?? data['staffId']}.',
          'type': 'inventory_reconciliation',
          'category': 'Inventory',
          'requestId': requestId,
          'allocationId': allocationId,
          'branchId': data['staffId'],
          'staffId': actorId,
          'isRead': false,
          'toastShown': false,
          'createdAt': FieldValue.serverTimestamp(),
        },
      );
    });
  }

  Future<void> decide(
    String id, {
    required bool approve,
    required String actorId,
    String reason = '',
  }) async {
    if (actorId.isEmpty) throw ArgumentError('Sign in as administrator.');
    await BranchPermissions.require(
      'adminAllowReconciliationApproval',
      database: db,
    );
    final request = db.collection('inventory_reconciliations').doc(id);
    await _validatedTransaction((tx) async {
      final pending = (await tx.get(request)).data();
      if (pending == null || pending['status'] != 'pending') return;
      final source = db
          .collection('staff_inventory')
          .doc('${pending['allocationId']}');
      final data = (await tx.get(source)).data();
      if (data == null) throw StateError('Original allocation is missing.');
      final targetRef = pending['action'] == 'convert'
          ? db
                .collection('staff_inventory')
                .doc('${pending['targetAllocationId']}')
          : null;
      final targetCurrent = targetRef == null
          ? null
          : (await tx.get(targetRef)).data();
      if (approve &&
          pending['action'] == 'convert' &&
          (targetCurrent == null ||
              targetCurrent['isDeleted'] == true ||
              targetCurrent['isBundle'] != true)) {
        throw StateError('Updated bundle allocation is no longer available.');
      }
      final instances = reconciliationInstances(data, source.id);
      final selected = instances
          .where(
            (i) =>
                i['reconciliationId'] == id &&
                i['status'] == 'reconciliation_pending',
          )
          .toList();
      if (selected.length != bundleQuantity(pending['quantity'])) {
        throw StateError('Reserved stock changed. Review this request.');
      }
      final target = pending['targetSnapshot'] is Map
          ? Map<String, dynamic>.from(pending['targetSnapshot'])
          : null;
      if (approve &&
          selected.any(
            (i) =>
                bundleExpired(i, DateTime.now()) ||
                bundleRows(
                  i['items'],
                ).any((item) => bundleExpired(item, DateTime.now())),
          )) {
        throw StateError(
          'Reserved items have expired. Reject this request and return them.',
        );
      }
      final output = approve ? reconcileBundleContents(selected, target) : null;
      if (output != null) _validateLooseSources(output);
      for (final instance in selected) {
        instance['status'] = approve ? 'reconciled' : 'available';
        instance.remove('reconciliationId');
      }
      tx.update(source, {
        'bundleInstances': instances,
        if (!approve)
          'bundleCount': bundleQuantity(data['bundleCount']) + selected.length,
      });
      if (output != null) {
        final loose = bundleRows(output['loose']);
        // Separate documents retain original source IDs and each expiry lot.
        for (var i = 0; i < loose.length; i++) {
          final item = loose[i];
          final count = bundleQuantity(item['quantity']);
          if (count <= 0) continue;
          final sourceId = '${item['sourceInventoryId'] ?? ''}';
          tx.set(
            db.collection('staff_inventory').doc('reconcile_${id}_item_$i'),
            {
              'staffId': data['staffId'],
              'staffName': data['staffName'] ?? '',
              'sourceInventoryId': sourceId,
              'name': item['parentName'] ?? 'Unbundled items',
              'isBundle': false,
              'isDeleted': false,
              'origin': 'unbundle',
              'reconciliationId': id,
              'assignedAt': FieldValue.serverTimestamp(),
              'items': [
                {
                  ...item,
                  'id': item['variantId'] ?? item['itemId'] ?? item['id'],
                  'stock': count,
                  'startingStock': count,
                  'assignedStartingStock': count,
                  'origin': 'unbundle',
                  'unbundledQuantity': count,
                },
              ],
            },
          );
        }
        final converted = bundleRows(output['bundles']);
        if (target != null && targetRef != null && targetCurrent != null) {
          final assignedAt = Timestamp.now();
          final targetInstances = reconciliationInstances(
            targetCurrent,
            targetRef.id,
          );
          final convertedInstances = [
            for (var i = 0; i < converted.length; i++)
              {
                ...converted[i],
                'id': '$id-converted-$i',
                'status': 'available',
                'batchId':
                    'conversion_${id}_${selected[i]['batchId'] ?? source.id}',
                'originBatchId':
                    selected[i]['batchId'] ?? pending['allocationId'],
                'origin': 'conversion',
                'reconciliationId': id,
                'fifoAt': selected[i]['fifoAt'] ?? selected[i]['assignedAt'],
                'assignedAt': assignedAt,
                'price': target['price'],
                'costPrice': target['costPrice'],
              },
          ];
          tx.update(targetRef, {
            'bundleInstances': [...targetInstances, ...convertedInstances],
            'bundleCount':
                bundleQuantity(targetCurrent['bundleCount']) +
                convertedInstances.length,
            'assignedStartingStock':
                bundleQuantity(
                  targetCurrent['assignedStartingStock'] ??
                      targetCurrent['bundleCount'],
                ) +
                convertedInstances.length,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
      }
      tx.update(request, {
        'status': approve ? 'approved' : 'rejected',
        'reviewedBy': actorId,
        'reviewReason': reason.trim(),
        'reviewedAt': FieldValue.serverTimestamp(),
      });
      tx.set(db.collection('activity_logs').doc('reconciliation_$id'), {
        'action': approve
            ? 'reconciliation_approved'
            : 'reconciliation_rejected',
        'description':
            '${approve ? 'Approved' : 'Rejected'} bundle reconciliation: ${pending['name']}',
        'actorId': actorId,
        'actorName': actorId,
        'actorPublicId': actorId,
        'actorRole': actorId == 'Spr-001' ? 'super_admin' : 'admin',
        'branchIds': [pending['staffId']],
        'createdAt': FieldValue.serverTimestamp(),
      });
    });
  }
}

void _validateLooseSources(Map<String, dynamic> output) {
  for (final item in bundleRows(output['loose'])) {
    if ('${item['sourceInventoryId'] ?? ''}'.trim().isEmpty) {
      throw StateError(
        'Ingredient source is missing for ${item['name']}. Repair the legacy bundle first.',
      );
    }
  }
}

List<Map<String, dynamic>> reconciliationInstances(Map data, String id) {
  final instances = bundleRows(data['bundleInstances']);
  if (instances.isNotEmpty) return instances;
  return [
    for (var i = 0; i < bundleQuantity(data['bundleCount']); i++)
      {
        'id': '$id-legacy-$i',
        'status': 'available',
        'items': bundleRows(data['items']),
        'price': data['price'],
        'costPrice': data['costPrice'],
        'expirationDate': data['expirationDate'] ?? '',
      },
  ];
}

List<Map<String, dynamic>> availableReconciliationInstances(
  Map data,
  String id, {
  DateTime? now,
}) => reconciliationInstances(data, id)
    .where((instance) => bundleInstanceAvailable(instance, data, now: now))
    .toList();

/// Convert each physical bundle independently, conserving quantities and expiry.
/// Made-to-order beverages/add-ons do not produce inventory when unbundled.
Map<String, dynamic> reconcileBundleContents(
  List<Map<String, dynamic>> instances,
  Map<String, dynamic>? target,
) {
  final loose = <Map<String, dynamic>>[];
  final bundles = <Map<String, dynamic>>[];
  final recipe = target == null
      ? <Map<String, dynamic>>[]
      : bundleRows(target['items']);
  if (target != null && recipe.isEmpty)
    throw StateError('Updated bundle has no recipe.');
  for (final instance in instances) {
    final available = bundleRows(
      instance['items'],
    ).where(physicalIngredient).map((i) => {...i}).toList();
    final used = <Map<String, dynamic>>[];
    for (final ingredient in recipe) {
      var needed = bundleQuantity(ingredient['quantity']);
      if (needed <= 0) throw StateError('Invalid updated recipe quantity.');
      if (!physicalIngredient(ingredient)) {
        used.add({...ingredient});
        continue;
      }
      for (final old in available.where(
        (i) => sameReconciliationIngredient(i, ingredient),
      )) {
        final stock = bundleQuantity(old['quantity']);
        final take = stock < needed ? stock : needed;
        if (take <= 0) continue;
        used.add({...old, 'quantity': take, 'remaining': take});
        old['quantity'] = stock - take;
        old['remaining'] = stock - take;
        needed -= take;
      }
      if (needed > 0)
        throw StateError(
          'Not enough ${ingredient['name']} to convert this batch. Unbundle it instead.',
        );
    }
    loose.addAll(available.where((i) => bundleQuantity(i['quantity']) > 0));
    if (target != null) {
      final expiries =
          used
              .where(physicalIngredient)
              .map((i) => '${i['expirationDate'] ?? ''}')
              .where((s) => s.isNotEmpty)
              .toList()
            ..sort();
      bundles.add({
        'items': used,
        'expirationDate':
            expiries.firstOrNull ?? instance['expirationDate'] ?? '',
      });
    }
  }
  return {'loose': loose, 'bundles': bundles};
}
