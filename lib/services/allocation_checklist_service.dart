import 'package:cloud_firestore/cloud_firestore.dart';
import 'checklist_status.dart';

class AllocationChecklistService {
  final FirebaseFirestore db;
  AllocationChecklistService(this.db);

  static int quantity(dynamic value) => num.tryParse('$value')?.toInt() ?? 0;
  static List<Map<String, dynamic>> rows(dynamic value) =>
      (value is List ? value : const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
  static String type(Map<String, dynamic> data) =>
      data['isCoffee'] == true || data['isAddon'] == true
      ? 'Beverages'
      : data['isBundle'] == true
      ? 'Bundle'
      : 'Categories';

  Future<bool> report(
    String id, {
    required bool admin,
    required String actorId,
    required String actorName,
    required String reason,
    required List<String> scopeIds,
  }) async {
    if (actorId.isEmpty || reason.trim().isEmpty) {
      throw ArgumentError('A signed-in user and reason are required.');
    }
    return db.runTransaction((tx) async {
      final ref = db.collection('allocation_checklist').doc(id);
      final data = (await tx.get(ref)).data();
      if (data == null || !ChecklistStatus.pending(data, admin: admin))
        return false;
      if (!admin && !scopeIds.contains(data['staffId'])) {
        throw StateError('This delivery is outside your assigned branch.');
      }
      final status = admin
          ? ChecklistStatus.discrepancy
          : ChecklistStatus.issue;
      tx.update(ref, {
        'status': status,
        'issueReason': reason.trim(),
        'reportedBy': actorId,
        'reportedByName': actorName,
        'reportedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      tx.update(ref, {
        'reports.${ref.collection('events').doc().id}': {
          'status': status,
          'reason': reason.trim(),
          'actorId': actorId,
          'actorName': actorName,
          'createdAt': FieldValue.serverTimestamp(),
        },
      });
      return true;
    });
  }

  /// Reserve stock, or claim already deducted refund/reduction quantities.
  /// The caller reuses requestId on retry, including after a lost response.
  Future<bool> submitReturn({
    required String requestId,
    required String sourceCollection,
    required String sourceId,
    required String lineKey,
    required int count,
    required String reason,
    required String actorId,
    required String actorName,
    required List<String> scopeIds,
    required String branchId,
    required String branchName,
  }) async {
    if (requestId.isEmpty ||
        actorId.isEmpty ||
        count <= 0 ||
        reason.trim().isEmpty ||
        !scopeIds.contains(branchId) ||
        ![
          'staff_inventory',
          'completed_sales',
          'stock_adjustments',
        ].contains(sourceCollection)) {
      throw ArgumentError(
        'Select an assigned branch, item, positive quantity, and reason.',
      );
    }
    return db.runTransaction((tx) async {
      final ref = db.collection('allocation_checklist').doc(requestId);
      if ((await tx.get(ref)).exists) return false;
      final source = db.collection(sourceCollection).doc(sourceId);
      final data = (await tx.get(source)).data();
      if (data == null || data['isDeleted'] == true)
        throw StateError('Source is no longer available.');
      final fromStock = sourceCollection == 'staff_inventory';
      final owner = fromStock
          ? data['staffId']
          : data['userId'] ?? data['staffId'];
      if (!scopeIds.contains(owner) &&
          owner != actorId &&
          !scopeIds.contains(data['branchId'])) {
        throw StateError('This item is outside your assigned scope.');
      }
      var savedBranch =
          data['branchId'] ?? (fromStock ? data['staffId'] : null);
      if (sourceCollection == 'stock_adjustments' &&
          savedBranch == null &&
          '${data['categoryId'] ?? ''}'.isNotEmpty) {
        final originalStock = (await tx.get(
          db.collection('staff_inventory').doc('${data['categoryId']}'),
        )).data();
        savedBranch = originalStock?['staffId'];
      }
      if (savedBranch != null &&
          savedBranch != actorId &&
          savedBranch != branchId) {
        throw StateError('Choose the original branch for this item.');
      }
      Map<String, dynamic> item;
      int available;
      final changes = <String, dynamic>{
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (fromStock) {
        if (data['isCoffee'] == true || data['isAddon'] == true) {
          throw StateError(
            'Catalog permissions are not physical stock. Use a recorded refund or reduction.',
          );
        }
        if (data['isBundle'] == true) {
          item = data;
          final instances = rows(data['bundleInstances']);
          final eligible = instances
              .where(
                (row) =>
                    (row['status'] ?? 'available') == 'available' &&
                    row['isDeleted'] != true &&
                    row['isVoided'] != true,
              )
              .toList();
          available = quantity(data['bundleCount']);
          if (instances.isNotEmpty && eligible.length < available)
            available = eligible.length;
          if (count > available)
            throw StateError('Only $available bundles remain.');
          for (final row in eligible.take(count)) {
            row['status'] = 'return_pending';
            row['returnId'] = requestId;
          }
          changes['bundleInstances'] = instances;
          changes['bundleCount'] = quantity(data['bundleCount']) - count;
        } else {
          final items = rows(data['items']);
          final index = items.indexWhere(
            (row) => '${row['id'] ?? row['name']}' == lineKey,
          );
          if (index < 0) throw StateError('Item is no longer available.');
          item = items[index];
          available = quantity(item['stock'] ?? item['startingStock']);
          if (count > available)
            throw StateError('Only $available items remain.');
          items[index] = {...item, 'stock': available - count};
          changes['items'] = items;
        }
      } else {
        if (sourceCollection == 'completed_sales') {
          if ('${data['type'] ?? data['status']}'.toLowerCase() != 'refund') {
            throw StateError('Select a recorded refund.');
          }
          final items = rows(data['items']);
          final index = int.tryParse(lineKey) ?? -1;
          if (index < 0 || index >= items.length)
            throw StateError('Refund item not found.');
          item = items[index];
        } else {
          if (data['type'] == 'addon_void') {
            throw StateError('Voided catalog access is not a physical return.');
          }
          item = {...data, 'name': data['itemName'] ?? data['categoryName']};
        }
        final claimed = Map<String, dynamic>.from(
          data['checklistReturnedQuantities'] as Map? ?? {},
        );
        available = quantity(item['quantity']) - quantity(claimed[lineKey]);
        if (count > available)
          throw StateError('Only $available unsubmitted items remain.');
        claimed[lineKey] = quantity(claimed[lineKey]) + count;
        changes['checklistReturnedQuantities'] = claimed;
      }
      tx.update(source, changes);
      tx.set(ref, {
        'schemaVersion': 2,
        'kind': 'return',
        'status': ChecklistStatus.awaitingAdmin,
        'staffId': branchId,
        'branchId': branchId,
        'branchName': branchName,
        'staffName': actorName,
        'submittedBy': actorId,
        'submittedByName': actorName,
        'name': item['flavor'] ?? item['variant'] ?? item['name'] ?? 'Item',
        'quantity': count,
        'reason': reason.trim(),
        'originalReason':
            item['refundReason'] ??
            data['reason'] ??
            data['refundReason'] ??
            reason.trim(),
        'sourceItem': item,
        'sourceDate': data['timestamp'] ?? data['createdAt'],
        'sourceStaffName': data['staffName'] ?? data['staffFullName'],
        'sourceReceiptId': data['salesId'] ?? data['receiptId'],
        'unitPrice': item['price'] ?? item['unitPrice'] ?? data['unitPrice'],
        'returnSourceCollection': sourceCollection,
        'returnSourceId': sourceId,
        'returnLineKey': lineKey,
        'isBundle': data['isBundle'] == true,
        'isCoffee': item['isCoffee'] == true || data['isCoffee'] == true,
        'sourceInventoryId':
            data['sourceInventoryId'] ??
            item['sourceInventoryId'] ??
            data['categoryId'],
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return true;
    });
  }

  /// Receiving a return records custody, not saleability (e.g. damaged stock).
  Future<bool> confirmReturn(
    String id, {
    required String actorId,
    required String actorName,
  }) async {
    if (actorId.isEmpty)
      throw ArgumentError('Sign in before confirming a return.');
    return db.runTransaction((tx) async {
      final ref = db.collection('allocation_checklist').doc(id);
      final data = (await tx.get(ref)).data();
      if (data == null || !ChecklistStatus.returnOpen(data)) return false;
      if (data['returnSourceCollection'] == 'staff_inventory' &&
          data['isBundle'] == true) {
        final source = db
            .collection('staff_inventory')
            .doc('${data['returnSourceId']}');
        final stock = (await tx.get(source)).data();
        if (stock != null) {
          final instances = rows(stock['bundleInstances']);
          for (final instance in instances) {
            if (instance['returnId'] == id) instance['status'] = 'returned';
          }
          tx.update(source, {
            'bundleInstances': instances,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
      }
      tx.update(ref, {
        'status': ChecklistStatus.completed,
        'confirmedBy': actorId,
        'confirmedByName': actorName,
        'confirmedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return true;
    });
  }

  /// A batch decision changes custody status only. Refunded/reduced stock is
  /// never made saleable again when an admin declines its physical return.
  Future<int> decideReturns(
    List<String> ids, {
    required bool accept,
    required String actorId,
    required String actorName,
    String reason = '',
  }) async {
    if (actorId.trim().isEmpty) throw ArgumentError('Please sign in again.');
    if (!accept && reason.trim().isEmpty)
      throw ArgumentError('A decline reason is required.');
    final unique = ids.toSet().toList();
    if (unique.isEmpty || unique.length > 200)
      throw ArgumentError('Select 1 to 200 return records.');
    return db.runTransaction(
      (tx) async {
        final records = await Future.wait(
          unique.map(
            (id) => tx.get(db.collection('allocation_checklist').doc(id)),
          ),
        );
        final pending = records
            .where(
              (doc) => doc.exists && ChecklistStatus.returnOpen(doc.data()!),
            )
            .toList();
        final bundleSources = pending
            .where(
              (doc) =>
                  doc.data()?['returnSourceCollection'] == 'staff_inventory' &&
                  doc.data()?['isBundle'] == true,
            )
            .map((doc) => '${doc.data()?['returnSourceId']}')
            .toSet();
        final stocks = await Future.wait(
          bundleSources.map(
            (id) => tx.get(db.collection('staff_inventory').doc(id)),
          ),
        );
        if (accept) {
          final acceptedIds = pending.map((doc) => doc.id).toSet();
          for (final stock in stocks) {
            if (!stock.exists) continue;
            final instances = rows(stock.data()?['bundleInstances']);
            for (final instance in instances) {
              if (acceptedIds.contains(instance['returnId']))
                instance['status'] = 'returned';
            }
            tx.update(stock.reference, {
              'bundleInstances': instances,
              'updatedAt': FieldValue.serverTimestamp(),
            });
          }
        }
        for (final doc in pending) {
          tx.update(doc.reference, {
            'status': accept
                ? ChecklistStatus.completed
                : ChecklistStatus.returnDeclined,
            if (accept) ...{
              'confirmedBy': actorId,
              'confirmedByName': actorName,
              'confirmedAt': FieldValue.serverTimestamp(),
            } else ...{
              'declinedBy': actorId,
              'declinedByName': actorName,
              'declinedAt': FieldValue.serverTimestamp(),
              'declineReason': reason.trim(),
            },
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
        return pending.length;
      },
      timeout: const Duration(seconds: 15),
      maxAttempts: 2,
    );
  }

  Future<bool> decide(
    String id, {
    required bool accept,
    required String staffId,
    String reason = '',
    String actorName = '',
    List<String>? scopeIds,
  }) async {
    if (!accept && reason.trim().isEmpty)
      throw ArgumentError('Please enter a decline reason.');
    return db.runTransaction<bool>((tx) async {
      final ref = db.collection('allocation_checklist').doc(id);
      final snap = await tx.get(ref);
      final pending = snap.data();
      if (pending == null || !ChecklistStatus.incomingOpen(pending))
        return false;
      if (staffId.isEmpty ||
          (scopeIds != null && !scopeIds.contains(pending['staffId']))) {
        throw StateError('This delivery is outside your assigned branch.');
      }
      final destination = accept
          ? db.collection('staff_inventory').doc('${pending['targetDocId']}')
          : db
                .collection(
                  '${pending['sourceCollection'] ?? 'sales_inventory'}',
                )
                .doc('${pending['sourceInventoryId']}');
      final target = await tx.get(destination);
      final current = target.data() ?? <String, dynamic>{};
      final bundle = pending['isBundle'] == true;
      final beverage = type(pending) == 'Beverages';
      if (!accept && !target.exists)
        throw StateError(
          'Source inventory is missing. Ask the administrator to restore it before declining.',
        );
      final incoming = rows(pending['items']);
      final payload = Map<String, dynamic>.from(pending)
        ..remove('targetDocId')
        ..remove('status')
        ..remove('deliveryId')
        ..remove('reports')
        ..remove('issueReason')
        ..remove('reportedBy')
        ..remove('reportedByName')
        ..remove('reportedAt');
      final result = <String, dynamic>{
        if (accept) ...payload,
        ...current,
        if (accept) 'isDeleted': false,
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (bundle) {
        result['bundleCount'] =
            quantity(current['bundleCount']) + quantity(pending['bundleCount']);
        result['bundleInstances'] = [
          ...rows(current['bundleInstances']),
          ...rows(pending['bundleInstances']),
        ];
        if (accept)
          result['assignedStartingStock'] =
              quantity(
                current['assignedStartingStock'] ?? current['bundleCount'],
              ) +
              quantity(pending['bundleCount']);
      } else if (!beverage) {
        final items = rows(current['items']);
        for (final item in incoming) {
          final index = items.indexWhere(
            (old) => (item['id']?.toString().isNotEmpty ?? false)
                ? old['id'] == item['id']
                : old['name'] == item['name'],
          );
          final count = quantity(item['stock'] ?? item['startingStock']);
          if (index < 0) {
            items.add({...item, 'stock': count});
          } else {
            final old = items[index];
            items[index] = {
              ...old,
              'stock': quantity(old['stock'] ?? old['startingStock']) + count,
              if (accept)
                'startingStock': quantity(old['startingStock']) + count,
              if (accept)
                'assignedStartingStock':
                    quantity(
                      old['assignedStartingStock'] ?? old['startingStock'],
                    ) +
                    count,
            };
          }
        }
        result['items'] = items;
      } else if (accept) {
        result.addAll(payload);
      }
      if (accept) {
        result['assignedAt'] = FieldValue.serverTimestamp();
        result['updatedAt'] = FieldValue.serverTimestamp();
      }
      // Beverages/add-ons are catalog permissions; no physical stock was reserved.
      if (accept || !beverage)
        tx.set(destination, result, SetOptions(merge: true));
      tx.update(ref, {
        'status': accept ? ChecklistStatus.received : 'declined',
        if (accept) 'confirmedBy': staffId,
        if (accept) 'confirmedByName': actorName,
        if (accept) 'confirmedAt': FieldValue.serverTimestamp(),
        'reason': reason.trim(),
        'decidedBy': staffId,
        'decidedAt': FieldValue.serverTimestamp(),
      });
      if (accept) {
        tx.set(db.collection('staff_inventory_history').doc('accepted_$id'), {
          'staffId': pending['staffId'],
          'staffName': pending['staffName'],
          'type': 'assignment',
          'allocationId': id,
          'createdAt': FieldValue.serverTimestamp(),
          'items': bundle || beverage
              ? [
                  {
                    ...payload,
                    'quantity': bundle ? quantity(pending['bundleCount']) : 1,
                  },
                ]
              : incoming
                    .map(
                      (item) => {
                        ...item,
                        'sourceInventoryId': pending['sourceInventoryId'],
                        'quantity': quantity(item['stock']),
                      },
                    )
                    .toList(),
        });
      } else {
        tx.set(
          db.collection('admin_notifications').doc('allocation_declined_$id'),
          {
            'title': 'Allocation declined',
            'message':
                '${pending['staffName'] ?? 'Branch'} declined ${pending['name'] ?? 'items'}. Reason: ${reason.trim()}',
            'type': 'allocation_declined',
            'category': 'Inventory',
            'allocationId': id,
            'branchId': pending['staffId'],
            'staffId': staffId,
            'reason': reason.trim(),
            'isRead': false,
            'toastShown': false,
            'createdAt': FieldValue.serverTimestamp(),
          },
        );
      }
      return true;
    });
  }
}
