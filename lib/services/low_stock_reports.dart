import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'activity_log.dart';
import 'session_actor.dart';
import 'super_admin.dart';

Future<void> markStaffInventoryLowStock({
  required FirebaseFirestore firestore,
  required List<Map<String, dynamic>> items,
  required List<String> branchIds,
  required String staffId,
  required String staffName,
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
  if (!branchAdminExists) {
    for (final branchId in branchIds) {
      final branch = await firestore.collection('branches').doc(branchId).get();
      final name = '${branch.data()?['name'] ?? ''}'.trim();
      if (name.isNotEmpty) branchNames.add(name);
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
        branchId: branchIds.firstOrNull ?? '',
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
      'Submitted by: $senderName\n'
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
          'allocationId': item['allocationId'] ?? '',
          'allocationItemId': item['allocationItemId'] ?? '',
        },
      )
      .toList();
  final itemLines = reportedItems
      .map((item) => '• ${item['type']}: ${item['name']} (${item['id']})')
      .join('\n');
  final text =
      'Low stock report — $branchName\n'
      'Submitted by: $adminName\n'
      '$itemLines';
  final allocationRefs = <DocumentReference<Map<String, dynamic>>>[];
  for (final item in reportedItems) {
    final allocationId = '${item['allocationId'] ?? ''}'.trim();
    if (allocationId.isEmpty) {
      throw StateError(
        'Unable to identify ${item['name'] ?? 'an item'} in branch inventory.',
      );
    }
    allocationRefs.add(
      firestore.collection('staff_inventory').doc(allocationId),
    );
  }
  await firestore.runTransaction((transaction) async {
    final allocations = <DocumentSnapshot<Map<String, dynamic>>>[];
    for (final ref in allocationRefs) {
      allocations.add(await transaction.get(ref));
    }
    for (var index = 0; index < allocations.length; index++) {
      final allocation = allocations[index].data();
      final item = reportedItems[index];
      final legacyStaffMark =
          allocation?['lowStockReportStatus'] == null &&
          allocation?['isLowStock'] == true &&
          allocation?['lowStockMarkedBy'] != null;
      if (allocation == null ||
          (allocation['staffLowStockPendingAdmin'] != true &&
              !legacyStaffMark)) {
        final itemName = '${item['name'] ?? 'This item'}';
        final alreadyReported =
            allocation?['lowStockReportStatus'] == 'reported';
        throw StateError(
          alreadyReported
              ? '$itemName is already reported.'
              : '$itemName is no longer waiting for an Admin report.',
        );
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
      'text': text,
      'type': 'low_stock_report',
      'branchId': branchId,
      'branchName': branchName,
      'items': reportedItems,
      'createdAt': FieldValue.serverTimestamp(),
    });
  });

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
