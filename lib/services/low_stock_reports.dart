import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'activity_log.dart';
import 'session_actor.dart';
import 'super_admin.dart';
import 'bundle_stock_service.dart';
import 'branch_identity.dart';

Future<void> markStaffInventoryLowStock({
  required FirebaseFirestore firestore,
  required List<Map<String, dynamic>> items,
  required List<String> branchIds,
  required String staffId,
  required String staffName,
  String staffPublicId = '',
}) async {
  if (items.isEmpty) return;
  if (items.length > 450) {
    throw StateError('Select fewer than 451 items at a time.');
  }
  final branchAdminExists = await branchHasActiveAdmin(
    firestore: firestore,
    branchIds: branchIds,
  );
  final branchNames = <String>[];
  final branchCodes = <String>[];
  if (!branchAdminExists) {
    for (final branchId in branchIds) {
      final branch = await firestore.collection('branches').doc(branchId).get();
      final data = branch.data();
      final name = '${data?['name'] ?? ''}'.trim();
      if (name.isNotEmpty) branchNames.add(name);
      final code = '${data?['branchCode'] ?? data?['publicId'] ?? ''}'.trim();
      branchCodes.add(code.isEmpty ? publicBranchCode(branchId) : code);
    }
  }
  final allocationRefs = <DocumentReference<Map<String, dynamic>>>[];
  final markedItems = <Map<String, dynamic>>[];
  for (final item in items) {
    final docId = '${item['staffInventoryDocId'] ?? ''}'.trim();
    if (docId.isEmpty) {
      throw StateError(
        'Unable to identify ${item['name'] ?? 'an item'} in branch inventory.',
      );
    }
    allocationRefs.add(firestore.collection('staff_inventory').doc(docId));
    markedItems.add({
      'name': item['name'] ?? '',
      'type': item['type'] ?? '',
      'id': item['id'] ?? '',
      'staffInventoryDocId': docId,
    });
  }

  await firestore.runTransaction((transaction) async {
    final allocations = <DocumentSnapshot<Map<String, dynamic>>>[];
    for (final ref in allocationRefs) {
      allocations.add(await transaction.get(ref));
    }
    for (var index = 0; index < allocations.length; index++) {
      final data = allocations[index].data() ?? const <String, dynamic>{};
      if (data['isLowStock'] == true ||
          data['staffLowStockPendingAdmin'] == true) {
        throw StateError(
          '${markedItems[index]['name']} is already marked low stock.',
        );
      }
    }
    for (var index = 0; index < allocationRefs.length; index++) {
      transaction.set(allocationRefs[index], {
        'isLowStock': !branchAdminExists,
        'staffLowStockPendingAdmin': branchAdminExists,
        'lowStockReportStatus': branchAdminExists
            ? 'pending_admin'
            : 'reported',
        'lowStockMarkedAt': FieldValue.serverTimestamp(),
        'lowStockMarkedBy': staffId,
        'lowStockMarkedByName': staffName,
        'lowStockItemName': markedItems[index]['name'],
        'lowStockItemType': markedItems[index]['type'],
        if (!branchAdminExists)
          'lowStockReportedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
    if (branchAdminExists) {
      final notification = firestore.collection('admin_notifications').doc();
      transaction.set(notification, {
        'type': 'staff_low_stock',
        'title': 'Staff reported low stock',
        'message':
            '$staffName marked ${markedItems.length} beverage/add-on item(s) as low stock.',
        'staffId': staffId,
        'staffName': staffName,
        'branchIds': branchIds,
        'items': markedItems,
        'isRead': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } else {
      _writeLowStockConversation(
        transaction: transaction,
        firestore: firestore,
        senderId: staffId,
        senderName: staffName,
        senderPublicId: staffPublicId,
        branchId: branchCodes.firstOrNull ?? '',
        branchName: branchNames.join(', '),
        items: markedItems,
        type: 'staff_low_stock_report',
      );
    }
  });

  await ActivityLog.record(
    'low_stock_marked',
    '$staffName marked ${markedItems.length} beverage/add-on item(s) as low stock.',
    database: firestore,
    branchIds: branchIds.toSet(),
    details: {'items': markedItems},
  );
}

Future<bool> branchHasActiveAdmin({
  required FirebaseFirestore firestore,
  required List<String> branchIds,
}) async {
  if (branchIds.isEmpty) return false;
  final branches = await Future.wait(
    branchIds.map((id) => firestore.collection('branches').doc(id).get()),
  );
  final memberIds = <String>{};
  for (final branch in branches) {
    final data = branch.data();
    if (data == null || data['isVoided'] == true) continue;
    memberIds.addAll(
      (data['staffIds'] as List? ?? const []).map((id) => '$id'),
    );
  }
  final requests = await firestore.collection('staff_requests').get();
  return requests.docs.any((doc) {
    final data = doc.data();
    final role = '${data['role'] ?? (data['adminId'] != null ? 'admin' : '')}'
        .trim()
        .toLowerCase();
    final status = '${data['status'] ?? ''}'.trim().toLowerCase();
    final accountIds = {
      doc.id,
      data['uid'],
      data['userId'],
      data['staffId'],
      data['adminId'],
    }.whereType<Object>().map((id) => '$id');
    final branchMembership =
        accountIds.any(memberIds.contains) ||
        (data['branchIds'] as List? ?? const []).any(
          (branchId) => branchIds.contains('$branchId'),
        );
    return branchMembership &&
        role == 'admin' &&
        (status == 'accepted' || status.isEmpty) &&
        data['isDeleted'] != true &&
        data['isVoided'] != true &&
        data['isDeactivated'] != true &&
        data['isSuspended'] != true;
  });
}

void _writeLowStockConversation({
  required Transaction transaction,
  required FirebaseFirestore firestore,
  required String senderId,
  required String senderName,
  required String senderPublicId,
  required String branchId,
  required String branchName,
  required List<Map<String, dynamic>> items,
  required String type,
}) {
  final recipientId = SuperAdmin.id;
  final participantIds = [senderId, recipientId]..sort();
  final chatId = participantIds.join('_');
  final chatRef = firestore.collection('messages').doc(chatId);
  final messageRef = chatRef.collection('items').doc();
  final itemLines = items
      .map((item) => '• ${item['type']}: ${item['name']} (${item['id']})')
      .join('\n');
  final text =
      'Low stock report — ${branchName.isEmpty ? branchId : branchName}\n'
      'Branch ID: $branchId\n'
      'Submitted by: $senderName • ID: ${senderPublicId.trim().isEmpty ? senderId : senderPublicId}\n'
      '$itemLines';
  transaction.set(chatRef, {
    'participantIds': participantIds,
    'participantNames': {senderId: senderName, recipientId: SuperAdmin.name},
    'participantPhotos': {senderId: '', recipientId: ''},
    'lastMessage': text,
    'lastMessageId': messageRef.id,
    'lastMessageSenderId': senderId,
    'lastMessageDeliveredAt': null,
    'lastMessageReadAt': null,
    'updatedAt': FieldValue.serverTimestamp(),
    'unreadBy': {senderId: 0, recipientId: FieldValue.increment(1)},
  }, SetOptions(merge: true));
  transaction.set(messageRef, {
    'senderId': senderId,
    'senderName': senderName,
    'senderPublicId': senderPublicId,
    'text': text,
    'type': type,
    'branchId': branchId,
    'branchName': branchName,
    'items': items,
    'createdAt': FieldValue.serverTimestamp(),
  });
}

Future<void> submitLowStockReportToSuperAdmin({
  required FirebaseFirestore firestore,
  required String adminId,
  required String adminName,
  required String branchId,
  required String branchName,
  required List<Map<String, dynamic>> items,
}) async {
  if (items.isEmpty) {
    throw StateError('Select at least one low-stock item to report.');
  }
  if (items.length > 450) {
    throw StateError('Select fewer than 451 items at a time.');
  }
  final senderId = adminId.trim();
  if (senderId.isEmpty ||
      senderId.toLowerCase() == SuperAdmin.id.toLowerCase()) {
    throw StateError('Unable to identify the signed-in branch admin.');
  }

  final branchSnapshot = await firestore
      .collection('branches')
      .doc(branchId)
      .get();
  final storedBranchCode =
      '${branchSnapshot.data()?['branchCode'] ?? branchSnapshot.data()?['publicId'] ?? ''}'
          .trim();
  final resolvedBranchId = storedBranchCode.isEmpty
      ? publicBranchCode(branchId)
      : storedBranchCode;
  final recipientId = SuperAdmin.id;
  final participantIds = [senderId, recipientId]..sort();
  final chatId = participantIds.join('_');
  final chatRef = firestore.collection('messages').doc(chatId);
  final messageRef = chatRef.collection('items').doc();
  final reportedItems = items
      .map(
        (item) => {
          'name': item['name'] ?? '',
          'type': item['type'] ?? '',
          'id': item['id'] ?? '',
          'categoryName': item['categoryName'] ?? item['type'] ?? '',
          'currentStock': item['remaining'] ?? item['stock'],
          if (item['requestedQuantity'] != null)
            'requestedQuantity': item['requestedQuantity'],
          'allocationId':
              item['allocationId'] ??
              item['staffInventoryDocId'] ??
              item['_id'] ??
              '',
          'allocationItemId': item['allocationItemId'] ?? '',
        },
      )
      .toList();
  final itemLines = reportedItems
      .map((item) {
        final requested = item['requestedQuantity'];
        final madeToOrder = ['Beverages', 'Add-ons'].contains(item['type']);
        return '• ${item['categoryName']}: ${item['name']} (${item['id']})'
            ' — Current: ${item['currentStock'] ?? 'N/A'}'
            ' — Request: ${madeToOrder ? 'Made to order' : requested ?? 'Not specified'}';
      })
      .join('\n');
  final text =
      'Low stock report — $branchName\n'
      'Branch ID: $resolvedBranchId\n'
      'Submitted by: $adminName • ID: $senderId\n'
      '$itemLines';
  final allocationRefsById =
      <String, DocumentReference<Map<String, dynamic>>>{};
  for (final item in reportedItems) {
    final allocationId = '${item['allocationId'] ?? ''}'.trim();
    if (allocationId.isEmpty) {
      throw StateError(
        'Unable to identify ${item['name'] ?? 'an item'} in branch inventory.',
      );
    }
    allocationRefsById.putIfAbsent(
      allocationId,
      () => firestore.collection('staff_inventory').doc(allocationId),
    );
  }
  final allocationRefs = allocationRefsById.values.toList();
  final validationError = await firestore.runTransaction<String?>((
    transaction,
  ) async {
    final allocations = <DocumentSnapshot<Map<String, dynamic>>>[];
    for (final ref in allocationRefs) {
      allocations.add(await transaction.get(ref));
    }
    final allocationById = {
      for (var index = 0; index < allocationRefs.length; index++)
        allocationRefs[index].id: allocations[index].data(),
    };
    for (var index = 0; index < reportedItems.length; index++) {
      final item = reportedItems[index];
      final selectedItem = items[index];
      final allocation = allocationById['${item['allocationId']}'];
      final legacyStaffMark =
          allocation?['lowStockReportStatus'] == null &&
          allocation?['isLowStock'] == true &&
          allocation?['lowStockMarkedBy'] != null;
      final pendingAdminReport =
          allocation?['staffLowStockPendingAdmin'] == true ||
          allocation?['lowStockReportStatus'] == 'pending_admin';
      final currentlyLow =
          selectedItem['autoLowStock'] == true &&
          inventoryLowStock(
            selectedItem['remaining'],
            type: '${selectedItem['type'] ?? ''}',
          );
      if (allocation == null) {
        return '${item['name'] ?? 'This item'} could not be found in branch inventory.';
      }
      if (allocation['lowStockReportStatus'] == 'reported' ||
          allocation['lowStockReportStatus'] == 'requested') {
        return '${item['name'] ?? 'This item'} has already been requested.';
      }
      if ((!pendingAdminReport && !legacyStaffMark && !currentlyLow)) {
        final itemName = '${item['name'] ?? 'This item'}';
        return '$itemName is no longer waiting for an Admin report.';
      }
    }
    for (final ref in allocationRefs) {
      transaction.set(ref, {
        'isLowStock': true,
        'staffLowStockPendingAdmin': false,
        'lowStockReportStatus': 'reported',
        'lowStockReportedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
    transaction.set(chatRef, {
      'participantIds': participantIds,
      'participantNames': {senderId: adminName, recipientId: SuperAdmin.name},
      'participantPhotos': {senderId: '', recipientId: ''},
      'lastMessage': text,
      'lastMessageId': messageRef.id,
      'lastMessageSenderId': senderId,
      'lastMessageDeliveredAt': null,
      'lastMessageReadAt': null,
      'updatedAt': FieldValue.serverTimestamp(),
      'unreadBy': {senderId: 0, recipientId: FieldValue.increment(1)},
    }, SetOptions(merge: true));
    transaction.set(messageRef, {
      'senderId': senderId,
      'senderName': adminName,
      'senderPublicId': senderId,
      'text': text,
      'type': 'low_stock_report',
      'branchId': resolvedBranchId,
      'branchName': branchName,
      'items': reportedItems,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return null;
  });
  if (validationError != null) throw StateError(validationError);

  await ActivityLog.record(
    'low_stock_report_submitted',
    '$adminName sent a low-stock report for $branchName to Super Admin.',
    database: firestore,
    branchId: branchId,
    details: {'items': reportedItems},
  );
}

Future<({String id, String name})> currentBranchAdmin({
  required FirebaseFirestore firestore,
}) async {
  final prefs = await SharedPreferences.getInstance();
  final actor = await resolveSessionActor(
    firestore,
    admin: true,
    preferences: prefs,
  );
  final id = (prefs.getString('adminId') ?? actor.publicId).trim();
  return (id: id.isEmpty ? actor.id : id, name: actor.name);
}
