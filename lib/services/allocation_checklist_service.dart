import 'branch_permissions.dart';
import 'inventory_reconciliation_service.dart';
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
      data['isAddon'] == true ||
          data['sourceCollection']?.toString() == 'coffee_addons'
      ? 'Beverages Add-ons'
      : data['isCoffee'] == true
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
      if (data == null || !ChecklistStatus.pending(data, admin: admin)) {
        return false;
      }
      if (!admin && !scopeIds.contains(data['staffId'])) {
        throw StateError('This delivery is outside your assigned branch.');
      }
      final status = admin
          ? ChecklistStatus.discrepancy
          : ChecklistStatus.issue;
      final eventId = ref.collection('events').doc().id;
      tx.update(ref, {
        'status': status,
        'issueReason': reason.trim(),
        'reportedBy': actorId,
        'reportedByName': actorName,
        'reportedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'reports.$eventId': {
          'status': status,
          'reason': reason.trim(),
          'actorId': actorId,
          'actorName': actorName,
          'createdAt': FieldValue.serverTimestamp(),
        },
      });
      if (admin && data['kind'] == 'return') {
        final branchId = '${data['branchId'] ?? data['staffId']}';
        tx.set(
          db.collection('activity_logs').doc('return_report_${id}_$eventId'),
          {
            'action': 'return_issue_reported',
            'description':
                '$actorName reported an issue with the return of ${data['name'] ?? 'item'}.',
            'actorId': actorId,
            'actorName': actorName,
            'actorRole': 'admin',
            'branchIds': [branchId],
            'details': {
              'returnId': id,
              'itemName': data['name'] ?? 'Item',
              'quantity': data['quantity'] ?? 0,
              'reason': reason.trim(),
            },
            'createdAt': FieldValue.serverTimestamp(),
          },
        );
      }
      if (!admin) {
        tx.set(db.collection('admin_notifications').doc('allocation_issue_$id'), {
          'title': 'Allocation issue reported',
          'message':
              '${data['staffName'] ?? 'Branch'} reported an issue with ${data['name'] ?? 'allocated items'}: ${reason.trim()}',
          'type': 'allocation_issue',
          'category': 'Inventory',
          'allocationId': id,
          'branchId': data['staffId'],
          'staffId': actorId,
          'staffName': data['staffName'] ?? data['branchName'] ?? 'Branch',
          'reportedByName': actorName,
          'reportedByRole': admin ? 'admin' : 'staff',
          'reason': reason.trim(),
          'isRead': false,
          'toastShown': false,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
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
    List<String>? instanceIds,
  }) async {
    await BranchPermissions.require(
      'allowReturns',
      database: db,
      branchId: branchId,
    );
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
      if (data == null || data['isDeleted'] == true) {
        throw StateError('Source is no longer available.');
      }
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
          final instances = reconciliationInstances(data, sourceId);
          final eligible = instances
              .where(
                (row) =>
                    (row['status'] ?? 'available') == 'available' &&
                    (instanceIds == null ||
                        instanceIds.contains('${row['id']}')) &&
                    row['isDeleted'] != true &&
                    row['isVoided'] != true,
              )
              .toList();
          available = quantity(data['bundleCount']);
          if (instances.isNotEmpty && eligible.length < available) {
            available = eligible.length;
          }
          if (count > available) {
            throw StateError('Only $available bundles remain.');
          }
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
          if (count > available) {
            throw StateError('Only $available items remain.');
          }
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
          if (index < 0 || index >= items.length) {
            throw StateError('Refund item not found.');
          }
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
        if (count > available) {
          throw StateError('Only $available unsubmitted items remain.');
        }
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
      tx.set(
        db.collection('admin_notifications').doc('return_request_$requestId'),
        {
          'title': 'Inventory return request',
          'message':
              '$actorName submitted ${count} ${item['name'] ?? 'item'} return(s) from $branchName for approval.',
          'type': 'allocation_return',
          'category': 'Inventory',
          'requestId': requestId,
          'branchId': branchId,
          'staffId': actorId,
          'isRead': false,
          'toastShown': false,
          'createdAt': FieldValue.serverTimestamp(),
        },
      );
      return true;
    });
  }

  Future<int> forwardReturns(
    List<String> ids, {
    required String actorId,
    required String actorName,
    required List<String> scopeIds,
  }) async {
    await BranchPermissions.require('allowReturns', database: db);
    final unique = ids.toSet().toList();
    if (actorId.trim().isEmpty || unique.isEmpty || unique.length > 200) {
      throw ArgumentError('Select 1 to 200 pending returns.');
    }
    return db.runTransaction((tx) async {
      final docs = await Future.wait(
        unique.map(
          (id) => tx.get(db.collection('allocation_checklist').doc(id)),
        ),
      );
      final pending = docs.where((doc) {
        final data = doc.data();
        return data != null && ChecklistStatus.returnPendingForAdmin(data);
      }).toList();
      if (pending.any(
        (doc) => !scopeIds.contains(
          '${doc.data()?['branchId'] ?? doc.data()?['staffId']}',
        ),
      )) {
        throw StateError('A selected return is outside your assigned branch.');
      }
      for (final doc in pending) {
        final data = doc.data()!;
        final branchId = '${data['branchId'] ?? data['staffId']}';
        tx.update(doc.reference, {
          'status': ChecklistStatus.awaitingSuperAdmin,
          'forwardedBy': actorId,
          'forwardedByName': actorName,
          'forwardedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
        tx.set(db.collection('activity_logs').doc('return_forward_${doc.id}'), {
          'action': 'return_forwarded',
          'description':
              '$actorName submitted ${data['quantity'] ?? 0} ${data['name'] ?? 'item'} return(s) for Super Admin review.',
          'actorId': actorId,
          'actorName': actorName,
          'actorRole': 'admin',
          'branchIds': [branchId],
          'details': {
            'returnId': doc.id,
            'itemName': data['name'] ?? 'Item',
            'quantity': data['quantity'] ?? 0,
          },
          'createdAt': FieldValue.serverTimestamp(),
        });
        tx.set(
          db.collection('admin_notifications').doc('return_forward_${doc.id}'),
          {
            'title': 'Branch return submitted',
            'message':
                '$actorName submitted ${doc.data()?['quantity'] ?? 1} ${doc.data()?['name'] ?? 'item'} return(s) from ${doc.data()?['branchName'] ?? 'a branch'} for Super Admin review.',
            'type': 'allocation_return',
            'category': 'Inventory',
            'requestId': doc.id,
            'branchId': branchId,
            'isRead': false,
            'toastShown': false,
            'createdAt': FieldValue.serverTimestamp(),
          },
        );
      }
      return pending.length;
    });
  }

  /// Receiving a return records custody, not saleability (e.g. damaged stock).
  Future<bool> confirmReturn(
    String id, {
    required String actorId,
    required String actorName,
  }) async {
    await BranchPermissions.require('adminAllowReturnApproval', database: db);
    if (actorId.isEmpty) {
      throw ArgumentError('Sign in before confirming a return.');
    }
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
      tx.set(db.collection('activity_logs').doc('return_$id'), {
        'action': 'return_approved',
        'description': 'Approved inventory return',
        'actorId': actorId,
        'actorName': actorName,
        'actorPublicId': actorId,
        'actorRole': actorId == 'Spr-001' ? 'super_admin' : 'admin',
        'branchIds': [data['branchId'] ?? data['staffId']],
        'details': {
          'item': data['name'] ?? data['itemName'] ?? 'Inventory item',
          'quantity': data['quantity'] ?? data['returnQuantity'] ?? 1,
          'returnId': id,
          'reason': data['returnReason'] ?? data['reason'] ?? '',
          'branch': data['branchName'] ?? data['staffName'] ?? '',
        },
        'createdAt': FieldValue.serverTimestamp(),
      });
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
    await BranchPermissions.require('adminAllowReturnApproval', database: db);
    if (actorId.trim().isEmpty) throw ArgumentError('Please sign in again.');
    if (!accept && reason.trim().isEmpty) {
      throw ArgumentError('A decline reason is required.');
    }
    final unique = ids.toSet().toList();
    if (unique.isEmpty || unique.length > 200) {
      throw ArgumentError('Select 1 to 200 return records.');
    }
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
              if (acceptedIds.contains(instance['returnId'])) {
                instance['status'] = 'returned';
              }
            }
            tx.update(stock.reference, {
              'bundleInstances': instances,
              'updatedAt': FieldValue.serverTimestamp(),
            });
          }
        }
        for (final doc in pending) {
          tx.set(db.collection('activity_logs').doc('return_${doc.id}'), {
            'action': accept ? 'return_approved' : 'return_rejected',
            'description': accept
                ? 'Approved inventory return'
                : 'Rejected inventory return',
            'actorId': actorId,
            'actorName': actorName,
            'actorRole': 'admin',
            'actorPublicId': actorId,
            'branchIds': [doc.data()?['branchId'] ?? doc.data()?['staffId']],
            'details': {
              'item':
                  doc.data()?['name'] ??
                  doc.data()?['itemName'] ??
                  'Inventory item',
              'quantity':
                  doc.data()?['quantity'] ?? doc.data()?['returnQuantity'] ?? 1,
              'returnId': doc.id,
              'reason': accept
                  ? (doc.data()?['returnReason'] ?? '')
                  : reason.trim(),
              'branch':
                  doc.data()?['branchName'] ?? doc.data()?['staffName'] ?? '',
            },
            'createdAt': FieldValue.serverTimestamp(),
          });
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

  Future<bool> reportReturnIssue({
    required String id,
    required String actorId,
    required String actorName,
    required String issueType,
    required int issueQuantity,
    String comment = '',
  }) async =>
      await reportReturnIssues(
        actorId: actorId,
        actorName: actorName,
        reports: [
          {
            'returnId': id,
            'issueType': issueType,
            'issueQuantity': issueQuantity,
            'comment': comment,
          },
        ],
      ) ==
      1;

  Future<int> reportReturnIssues({
    required String actorId,
    required String actorName,
    required List<Map<String, dynamic>> reports,
  }) async {
    await BranchPermissions.require('adminAllowReturnApproval', database: db);
    const issueTypes = {'Missing', 'Extra', 'Incorrect', 'Damaged', 'Others'};
    if (actorId.trim().isEmpty || reports.isEmpty || reports.length > 200) {
      throw ArgumentError('Choose up to 200 return issue reports.');
    }
    final reportIds = <String>{};
    for (final report in reports) {
      final id = '${report['returnId'] ?? ''}'.trim();
      final issueType = '${report['issueType'] ?? ''}';
      final issueQuantity = quantity(report['issueQuantity']);
      if (id.isEmpty ||
          !reportIds.add(id) ||
          !issueTypes.contains(issueType) ||
          issueQuantity <= 0) {
        throw ArgumentError('Choose an issue and enter a valid quantity.');
      }
    }

    return db.runTransaction<int>((tx) async {
      final records =
          <
            ({
              DocumentReference<Map<String, dynamic>> ref,
              Map<String, dynamic> data,
              int returnedQuantity,
            })
          >[];
      for (final report in reports) {
        final ref = db
            .collection('allocation_checklist')
            .doc('${report['returnId']}');
        final data = (await tx.get(ref)).data();
        if (data == null || !ChecklistStatus.returnOpen(data)) return 0;
        final returnedQuantity = quantity(
          data['quantity'] ?? data['returnQuantity'] ?? 1,
        );
        if (quantity(report['issueQuantity']) > returnedQuantity) {
          throw ArgumentError(
            'Issue quantity cannot exceed the returned quantity ($returnedQuantity).',
          );
        }
        records.add((ref: ref, data: data, returnedQuantity: returnedQuantity));
      }

      final now = FieldValue.serverTimestamp();
      for (var index = 0; index < reports.length; index++) {
        final report = reports[index];
        final record = records[index];
        final id = '${report['returnId']}';
        final issueType = '${report['issueType']}';
        final issueQuantity = quantity(report['issueQuantity']);
        final comment = '${report['comment'] ?? ''}'.trim();
        tx.update(record.ref, {
          'status': ChecklistStatus.completed,
          'confirmedBy': actorId,
          'confirmedByName': actorName,
          'confirmedAt': now,
          'superAdminIssueType': issueType,
          'superAdminIssueQuantity': issueQuantity,
          'superAdminIssueComment': comment,
          'superAdminReportedBy': actorId,
          'superAdminReportedByName': actorName,
          'superAdminReportedAt': now,
          'updatedAt': now,
        });
        tx.set(db.collection('activity_logs').doc('return_issue_$id'), {
          'action': 'return_issue_reported',
          'description':
              '$actorName reported $issueType on ${record.data['name'] ?? 'returned item'} and completed the return review.',
          'actorId': actorId,
          'actorName': actorName,
          'actorRole': 'super_admin',
          'branchIds': [record.data['branchId'] ?? record.data['staffId']],
          'details': {
            'returnId': id,
            'itemName':
                record.data['name'] ??
                record.data['itemName'] ??
                'Inventory item',
            'returnedQuantity': record.returnedQuantity,
            'issueType': issueType,
            'issueQuantity': issueQuantity,
            'comment': comment,
          },
          'createdAt': now,
        });
      }
      return reports.length;
    });
  }

  Future<bool> decide(
    String id, {
    required bool accept,
    required String staffId,
    String reason = '',
    String? issueType,
    int issueQuantity = 0,
    String issueItemId = '',
    String issueItemName = '',
    List<Map<String, dynamic>> issueReports = const [],
    String actorName = '',
    String actorPublicId = '',
    String actorRole = '',
    List<String>? scopeIds,
  }) async {
    await BranchPermissions.require('allowChecklist', database: db);
    if (!accept && reason.trim().isEmpty) {
      throw ArgumentError('Please enter a decline reason.');
    }
    const quantityIssues = {
      'Missing',
      'Extra',
      'Incorrect',
      'Damaged',
      'Not received',
      'Others',
    };
    final selectedIssues = issueReports.isNotEmpty
        ? issueReports
        : issueType == null
        ? const <Map<String, dynamic>>[]
        : [
            {
              'itemId': issueItemId,
              'itemName': issueItemName,
              'quantity': issueQuantity,
            },
          ];
    String reportType(Map<String, dynamic> issue) =>
        '${issue['issueType'] ?? issueType ?? ''}';
    final hasIssues = selectedIssues.isNotEmpty;
    if (hasIssues &&
        (!accept ||
            selectedIssues.any(
              (issue) =>
                  !quantityIssues.contains(reportType(issue)) ||
                  quantity(issue['quantity']) <= 0,
            ))) {
      throw ArgumentError('Choose a valid issue and positive quantity.');
    }
    final savedIssueReason = issueReports.isEmpty
        ? issueType ?? reason.trim()
        : selectedIssues
              .map(
                (issue) =>
                    '${reportType(issue)} - ${quantity(issue['quantity'])}',
              )
              .join('; ');
    return db.runTransaction<bool>((tx) async {
      final ref = db.collection('allocation_checklist').doc(id);
      final snap = await tx.get(ref);
      final pending = snap.data();
      if (pending == null || !ChecklistStatus.incomingOpen(pending)) {
        return false;
      }
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
      final beverage = type(pending).startsWith('Beverages');
      final incoming = rows(pending['items']);
      if (bundle && selectedIssues.length > 1) {
        throw ArgumentError('A bundle issue can only be reported once.');
      }
      final issueIndexes = <int>[];
      final issueBaseQuantities = <int>[];
      final seenIssueIndexes = <int>{};
      for (final issue in selectedIssues) {
        final itemId = '${issue['itemId'] ?? ''}';
        final itemName = '${issue['itemName'] ?? ''}';
        final itemIndex = !hasIssues || bundle
            ? -1
            : incoming.indexWhere(
                (item) => itemId.isNotEmpty
                    ? '${item['id'] ?? ''}' == itemId
                    : '${item['name'] ?? ''}' == itemName,
              );
        if (hasIssues && !bundle && itemIndex < 0) {
          throw ArgumentError('Select an item from this allocation.');
        }
        if (itemIndex >= 0 && !seenIssueIndexes.add(itemIndex)) {
          throw ArgumentError('Report each item only once.');
        }
        final baseQuantity = !hasIssues
            ? 0
            : bundle
            ? quantity(pending['bundleCount'])
            : quantity(
                incoming[itemIndex]['stock'] ??
                    incoming[itemIndex]['startingStock'],
              );
        final requestedQuantity = quantity(issue['quantity']);
        if (hasIssues &&
            reportType(issue) != 'Extra' &&
            requestedQuantity > baseQuantity) {
          throw ArgumentError(
            'Issue quantity cannot exceed the allocated quantity.',
          );
        }
        issueIndexes.add(itemIndex);
        issueBaseQuantities.add(baseQuantity);
      }
      if (hasIssues && beverage) {
        throw ArgumentError(
          'Beverage allocations do not track physical stock.',
        );
      }
      final issueBaseQuantity = issueBaseQuantities.firstOrNull ?? 0;
      if (!accept && !target.exists) {
        throw StateError(
          'Source inventory is missing. Ask the administrator to restore it before declining.',
        );
      }
      final resolvedIncoming = incoming
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
      if (hasIssues && !bundle) {
        for (var index = 0; index < selectedIssues.length; index++) {
          final item = resolvedIncoming[issueIndexes[index]];
          final reportedQuantity = quantity(selectedIssues[index]['quantity']);
          final itemIssueType = reportType(selectedIssues[index]);
          if (itemIssueType == 'Others') continue;
          final oldQuantity = quantity(item['stock'] ?? item['startingStock']);
          final adjustedQuantity = itemIssueType == 'Extra'
              ? oldQuantity + reportedQuantity
              : oldQuantity - reportedQuantity;
          item['stock'] = adjustedQuantity;
          item['startingStock'] = adjustedQuantity;
          item['assignedStartingStock'] = adjustedQuantity;
        }
      }
      final bundleIssueType = selectedIssues.isEmpty
          ? ''
          : reportType(selectedIssues.first);
      final resolvedBundleCount = !hasIssues
          ? quantity(pending['bundleCount'])
          : bundleIssueType == 'Extra'
          ? issueBaseQuantity + quantity(selectedIssues.first['quantity'])
          : bundleIssueType == 'Others'
          ? issueBaseQuantity
          : issueBaseQuantity - quantity(selectedIssues.first['quantity']);
      final fullyMissing =
          hasIssues &&
          selectedIssues.every((issue) => reportType(issue) == 'Missing') &&
          selectedIssues.every(
            (issue) =>
                quantity(issue['quantity']) >=
                issueBaseQuantities[selectedIssues.indexOf(issue)],
          ) &&
          (bundle ||
              resolvedIncoming.every(
                (item) => quantity(item['stock'] ?? item['startingStock']) == 0,
              ));
      final payload = Map<String, dynamic>.from(pending)
        ..remove('targetDocId')
        ..remove('status')
        ..remove('deliveryId')
        ..remove('reports')
        ..remove('issueReason')
        ..remove('reportedBy')
        ..remove('reportedByName')
        ..remove('reportedAt');
      // Carry the root category identity through to branch inventory. The
      // cashier uses this ID to join allocated stock to the source category.
      payload['categoryId'] =
          pending['categoryId'] ??
          pending['sourceInventoryId'] ??
          pending['sourceCategoryId'];
      final result = <String, dynamic>{
        if (accept) ...payload,
        ...current,
        if (accept) 'isDeleted': fullyMissing,
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (bundle) {
        final instances = rows(pending['bundleInstances'])
            .map(
              (instance) => {
                ...instance,
                'batchId': instance['batchId'] ?? pending['deliveryId'] ?? id,
              },
            )
            .toList();
        if (hasIssues && instances.length != issueBaseQuantity) {
          throw StateError(
            'Bundle instance records do not match the allocated quantity. Ask the administrator to review this allocation.',
          );
        }
        if (bundleIssueType == 'Extra') {
          if (instances.isEmpty) {
            throw StateError(
              'Bundle details are unavailable. Ask the administrator to review this allocation.',
            );
          }
          final template = Map<String, dynamic>.from(instances.first);
          for (
            var index = 0;
            index < quantity(selectedIssues.first['quantity']);
            index++
          ) {
            instances.add({
              ...template,
              'id': db.collection('allocation_checklist').doc().id,
              'status': 'available',
              'batchId': pending['deliveryId'] ?? id,
              'extraReported': true,
            });
          }
        } else if (hasIssues &&
            bundleIssueType != 'Others' &&
            quantity(selectedIssues.first['quantity']) > 0) {
          final reportedQuantity = quantity(selectedIssues.first['quantity']);
          instances.removeRange(
            instances.length - reportedQuantity,
            instances.length,
          );
        }
        result['bundleInstances'] = [
          ...rows(current['bundleInstances']),
          ...instances,
        ];
        result['bundleCount'] =
            quantity(current['bundleCount']) + resolvedBundleCount;
        if (accept) {
          result['assignedStartingStock'] =
              quantity(
                current['assignedStartingStock'] ?? current['bundleCount'],
              ) +
              resolvedBundleCount;
        }
      } else if (!beverage) {
        final items = rows(current['items']);
        for (final item in resolvedIncoming) {
          final index = items.indexWhere(
            (old) => (item['id']?.toString().isNotEmpty ?? false)
                ? old['id'] == item['id']
                : old['name'] == item['name'],
          );
          final count = quantity(item['stock'] ?? item['startingStock']);
          if (count == 0) continue;
          if (index < 0) {
            items.add({
              ...item,
              'stock': count,
              if (accept) 'startingStock': count,
              if (accept) 'assignedStartingStock': count,
            });
          } else {
            final old = items[index];
            items[index] = {
              ...old,
              'stock': quantity(old['stock'] ?? old['startingStock']) + count,
              if (accept)
                'startingStock':
                    quantity(old['startingStock'] ?? old['stock']) + count,
              if (accept)
                'assignedStartingStock':
                    quantity(
                      old['assignedStartingStock'] ??
                          old['startingStock'] ??
                          old['stock'],
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
        result.addAll({
          'isLowStock': false,
          'staffLowStockPendingAdmin': false,
          'lowStockReportStatus': FieldValue.delete(),
          'lowStockMarkedAt': FieldValue.delete(),
          'lowStockMarkedBy': FieldValue.delete(),
          'lowStockMarkedByName': FieldValue.delete(),
          'lowStockReportedAt': FieldValue.delete(),
        });
        result['assignedAt'] = FieldValue.serverTimestamp();
        result['updatedAt'] = FieldValue.serverTimestamp();
      }
      // An entirely unreceived allocation is held for review instead of being
      // added to branch stock. Mixed reports still receive their unaffected
      // quantities.
      final onlyNotReceived =
          hasIssues &&
          selectedIssues.every((issue) => reportType(issue) == 'Not received');
      if (!(accept && onlyNotReceived) && (accept || !beverage)) {
        tx.set(destination, result, SetOptions(merge: true));
      }
      final firstIssue = selectedIssues.firstOrNull;
      final firstIssueType = firstIssue == null ? '' : reportType(firstIssue);
      final firstIssueQuantity = firstIssue == null
          ? 0
          : quantity(firstIssue['quantity']);
      int receivedQuantity(Map<String, dynamic> issue, int allocated) {
        final type = reportType(issue);
        final issueQuantity = quantity(issue['quantity']);
        if (type == 'Extra') return allocated + issueQuantity;
        if (type == 'Others') return allocated;
        return allocated - issueQuantity;
      }

      final issueDetails = selectedIssues
          .where((issue) => '${issue['comment'] ?? ''}'.trim().isNotEmpty)
          .map(
            (issue) =>
                '${issue['itemName'] ?? 'Item'}: ${'${issue['comment']}'.trim()}',
          )
          .join('; ');
      tx.update(ref, {
        'status': accept ? ChecklistStatus.received : 'declined',
        if (accept && !bundle) 'items': resolvedIncoming,
        if (accept && bundle) ...{
          'bundleCount': resolvedBundleCount,
          'bundleInstances': result['bundleInstances'],
        },
        if (accept) 'confirmedBy': staffId,
        if (accept) 'confirmedByName': actorName,
        if (accept && actorPublicId.isNotEmpty)
          'confirmedByPublicId': actorPublicId,
        if (accept && actorRole.isNotEmpty)
          'confirmedByRole': actorRole == 'staff' ? 'Cashier' : 'Admin',
        if (accept) 'confirmedAt': FieldValue.serverTimestamp(),
        if (hasIssues) ...{
          'issueType': firstIssueType,
          'issueQuantity': firstIssueQuantity,
          'issueItemId': firstIssue?['itemId'] ?? issueItemId,
          'issueItemName': firstIssue?['itemName'] ?? issueItemName,
          'issueAllocatedQuantity': issueBaseQuantity,
          'issueReceivedQuantity': receivedQuantity(
            firstIssue!,
            issueBaseQuantity,
          ),
          'issueReports': [
            for (var index = 0; index < selectedIssues.length; index++)
              {
                ...selectedIssues[index],
                'issueType': reportType(selectedIssues[index]),
                'allocatedQuantity': issueBaseQuantities[index],
                'receivedQuantity': receivedQuantity(
                  selectedIssues[index],
                  issueBaseQuantities[index],
                ),
              },
          ],
          'issueReason': selectedIssues
              .map(
                (issue) =>
                    '${reportType(issue)} - ${quantity(issue['quantity'])}',
              )
              .join('; '),
          'issueDetails': issueDetails.isEmpty ? reason.trim() : issueDetails,
          'reportedBy': staffId,
          'reportedByName': actorName,
          'reportedAt': FieldValue.serverTimestamp(),
        },
        'reason': savedIssueReason,
        'decidedBy': staffId,
        'decidedAt': FieldValue.serverTimestamp(),
      });
      if (accept) {
        tx.set(db.collection('staff_inventory_history').doc('accepted_$id'), {
          'staffId': pending['staffId'],
          'staffName': pending['staffName'],
          'type': 'assignment',
          'allocationId': id,
          'deliveryId': pending['deliveryId'],
          'allocatedBy': pending['allocatedBy'],
          'allocatedByName': pending['allocatedByName'],
          'allocatedByAdminId': pending['allocatedByAdminId'],
          'createdAt': FieldValue.serverTimestamp(),
          'issueType': hasIssues ? firstIssueType : null,
          'issueQuantity': !hasIssues ? null : firstIssueQuantity,
          'issueAllocatedQuantity': !hasIssues ? null : issueBaseQuantity,
          'issueReceivedQuantity': !hasIssues
              ? null
              : receivedQuantity(firstIssue!, issueBaseQuantity),
          if (hasIssues)
            'issueReports': [
              for (var index = 0; index < selectedIssues.length; index++)
                {
                  ...selectedIssues[index],
                  'issueType': reportType(selectedIssues[index]),
                  'allocatedQuantity': issueBaseQuantities[index],
                  'receivedQuantity': receivedQuantity(
                    selectedIssues[index],
                    issueBaseQuantities[index],
                  ),
                },
            ],
          'issueDetails': hasIssues ? issueDetails : null,
          'items': bundle || beverage
              ? [
                  {...payload, 'quantity': bundle ? resolvedBundleCount : 1},
                ]
              : resolvedIncoming
                    .where(
                      (item) =>
                          quantity(item['stock'] ?? item['startingStock']) > 0,
                    )
                    .map(
                      (item) => {
                        ...item,
                        'sourceInventoryId': pending['sourceInventoryId'],
                        'quantity': quantity(item['stock']),
                      },
                    )
                    .toList(),
        });
        if (hasIssues) {
          final issueDescriptions = selectedIssues
              .map(
                (issue) =>
                    '${issue['itemName'] ?? pending['name'] ?? 'Item'}: ${reportType(issue)} × ${quantity(issue['quantity'])}',
              )
              .toList();
          final issueDescription = issueDescriptions.join('; ');
          final eventId = ref.collection('events').doc().id;
          tx.update(ref, {
            'reports.$eventId': {
              'status': ChecklistStatus.received,
              'reason': issueDescription,
              'details': issueDetails,
              'actorId': staffId,
              'actorName': actorName,
              'createdAt': FieldValue.serverTimestamp(),
            },
          });
          tx.set(
            db.collection('admin_notifications').doc('allocation_issue_$id'),
            {
              'title': 'Allocation discrepancy reported',
              'message':
                  '${pending['staffName'] ?? 'Branch'} reported '
                  '$issueDescription. The received quantities are recorded in the completed checklist.',
              'type': 'allocation_issue',
              'category': 'Inventory',
              'allocationId': id,
              'branchId': pending['staffId'],
              'staffId': staffId,
              'staffName':
                  pending['staffName'] ?? pending['branchName'] ?? 'Branch',
              'reportedByName': actorName,
              'reportedByRole': actorRole,
              'issueType': firstIssueType,
              'issueQuantity': firstIssueQuantity,
              'issueItemName': firstIssue?['itemName'] ?? issueItemName,
              'issueReports': selectedIssues,
              'allocationStatus': ChecklistStatus.received,
              'reason': savedIssueReason,
              'details': issueDetails,
              'isRead': false,
              'toastShown': false,
              'createdAt': FieldValue.serverTimestamp(),
            },
          );
          for (var index = 0; index < selectedIssues.length; index++) {
            final issue = selectedIssues[index];
            final itemIssueType = reportType(issue);
            final itemName =
                '${issue['itemName'] ?? pending['name'] ?? 'Item'}';
            final itemId = '${issue['itemId'] ?? ''}';
            final reportedQuantity = quantity(issue['quantity']);
            final issueIndex = issueIndexes[index];
            if (itemIssueType == 'Not received') {
              final unreceivedInstances = bundle
                  ? rows(pending['bundleInstances'])
                        .skip(
                          rows(pending['bundleInstances']).length -
                              reportedQuantity,
                        )
                        .toList()
                  : const <Map<String, dynamic>>[];
              final reportId = issueReports.isEmpty
                  ? '${id}_not_received'
                  : '${id}_not_received_${itemId.isEmpty ? index : itemId}'
                        .replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
              tx.set(db.collection('allocation_checklist').doc(reportId), {
                'kind': 'not_received',
                'status': ChecklistStatus.notReceivedPending,
                'deliveryId': pending['deliveryId'] ?? id,
                'originalAllocationId': id,
                'staffId': pending['staffId'],
                'branchId': pending['staffId'],
                'staffName': pending['staffName'],
                'branchName': pending['branchName'] ?? pending['staffName'],
                'allocatedBy': pending['allocatedBy'],
                'allocatedByName': pending['allocatedByName'],
                'allocatedByAdminId': pending['allocatedByAdminId'],
                'sourceInventoryId': pending['sourceInventoryId'],
                'sourceCollection':
                    pending['sourceCollection'] ?? 'sales_inventory',
                'isBundle': bundle,
                'isCoffee': false,
                'isAddon': false,
                'name': itemName,
                'issueType': itemIssueType,
                'issueQuantity': reportedQuantity,
                'issueItemId': itemId,
                'issueItemName': itemName,
                'issueReason': '$itemIssueType - $reportedQuantity',
                if ('${issue['comment'] ?? ''}'.trim().isNotEmpty)
                  'issueDetails': '${issue['comment']}'.trim(),
                'reportedBy': staffId,
                'reportedByName': actorName,
                'reportedAt': FieldValue.serverTimestamp(),
                if (bundle) ...{
                  'bundleCount': reportedQuantity,
                  'bundleInstances': unreceivedInstances,
                } else
                  'items': [
                    {
                      ...incoming[issueIndex],
                      'stock': reportedQuantity,
                      'startingStock': reportedQuantity,
                    },
                  ],
                'createdAt': FieldValue.serverTimestamp(),
              });
            }
            if (itemIssueType == 'Damaged' || itemIssueType == 'Incorrect') {
              final safeItemId = itemId.isEmpty
                  ? index.toString()
                  : itemId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
              final returnId = issueReports.isEmpty
                  ? '${id}_issue_return'
                  : '${id}_issue_return_$safeItemId';
              tx.set(db.collection('allocation_checklist').doc(returnId), {
                'kind': 'return',
                'status': ChecklistStatus.awaitingAdmin,
                'staffId': pending['staffId'],
                'branchId': pending['staffId'],
                'staffName': pending['staffName'],
                'branchName': pending['branchName'] ?? pending['staffName'],
                'name': itemName,
                'itemName': itemName,
                'itemId': itemId,
                'quantity': reportedQuantity,
                'returnQuantity': reportedQuantity,
                'returnSourceCollection': 'allocation_checklist',
                'returnSourceId': id,
                'returnLineKey': itemId.isEmpty ? itemName : itemId,
                'returnReason': '${issue['comment'] ?? ''}'.trim().isEmpty
                    ? '$itemIssueType × $reportedQuantity'
                    : '${issue['comment']}'.trim(),
                'issueType': itemIssueType,
                'allocationId': id,
                'submittedBy': staffId,
                'submittedByName': actorName,
                'createdAt': FieldValue.serverTimestamp(),
                'updatedAt': FieldValue.serverTimestamp(),
              });
            }
          }
        }
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

  Future<bool> restoreNotReceived(
    String id, {
    required String actorId,
    required String actorName,
  }) => db.runTransaction<bool>((tx) async {
    final reportRef = db.collection('allocation_checklist').doc(id);
    final report = (await tx.get(reportRef)).data();
    if (report == null ||
        !ChecklistStatus.allocationNeedsSuperAdminReview(report)) {
      return false;
    }
    final sourceCollection =
        '${report['sourceCollection'] ?? 'sales_inventory'}';
    final sourceId = '${report['sourceInventoryId'] ?? ''}';
    if (sourceCollection != 'sales_inventory' || sourceId.isEmpty) {
      throw StateError('The original inventory item could not be found.');
    }
    final sourceRef = db.collection(sourceCollection).doc(sourceId);
    final source = (await tx.get(sourceRef)).data();
    if (source == null) {
      throw StateError('The original inventory item could not be found.');
    }
    if (report['isBundle'] == true) {
      final existing = rows(source['bundleInstances']);
      final restored = rows(report['bundleInstances']).map((instance) {
        final available = Map<String, dynamic>.from(instance)
          ..['status'] = 'available'
          ..remove('assignedAt')
          ..remove('batchId');
        return available;
      });
      tx.update(sourceRef, {
        'bundleCount':
            quantity(source['bundleCount']) +
            quantity(report['bundleCount'] ?? report['issueQuantity']),
        'bundleInstances': [...existing, ...restored],
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } else {
      final sourceItems = rows(source['items']);
      final reportedItems = rows(report['items']);
      if (reportedItems.isEmpty) {
        throw StateError('The unreceived item details are missing.');
      }
      for (final reported in reportedItems) {
        final reportedId = '${reported['id'] ?? ''}';
        final index = sourceItems.indexWhere(
          (item) => reportedId.isNotEmpty
              ? '${item['id'] ?? ''}' == reportedId
              : '${item['name'] ?? ''}' == '${reported['name'] ?? ''}',
        );
        if (index < 0) {
          throw StateError(
            'The original variant ${reported['name'] ?? ''} could not be found.',
          );
        }
        final sourceItem = sourceItems[index];
        final stock = quantity(
          sourceItem['stock'] ?? sourceItem['startingStock'],
        );
        final returned = quantity(
          reported['stock'] ?? reported['startingStock'],
        );
        sourceItems[index] = {...sourceItem, 'stock': stock + returned};
      }
      tx.update(sourceRef, {
        'items': sourceItems,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
    tx.update(reportRef, {
      'status': ChecklistStatus.notReceivedRestored,
      'stockRestoredAt': FieldValue.serverTimestamp(),
      'stockRestoredBy': actorId,
      'stockRestoredByName': actorName,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return true;
  });
}
