import 'package:cloud_firestore/cloud_firestore.dart';

import 'cash_drawer_service.dart';
import 'number_format.dart';

class CashFloatService {
  CashFloatService._();

  static const collectionName = 'cash_float_requests';

  static Future<String> createRequest({
    required FirebaseFirestore firestore,
    required String branchId,
    required String branchName,
    required String senderId,
    required String senderName,
    required double amount,
    required bool startingCash,
  }) async {
    if (amount <= 0 || !amount.isFinite) {
      throw ArgumentError.value(
        amount,
        'amount',
        'Must be positive and finite.',
      );
    }
    final profiles = await Future.wait([
      firestore
          .collection('staff_requests')
          .where('branchIds', arrayContains: branchId)
          .get(),
      firestore
          .collection('staff_requests')
          .where('branchId', isEqualTo: branchId)
          .get(),
    ]);
    final branchAccounts = {
      for (final doc in profiles.expand((profile) => profile.docs)) doc.id: doc,
    }.values;
    final admins = {
      for (final doc in branchAccounts)
        if (doc.id != senderId &&
            '${doc.data()['adminId'] ?? ''}'.trim() != senderId &&
            '${doc.data()['role'] ?? ''}'.trim().toLowerCase() == 'admin' &&
            doc.data()['isVoided'] != true &&
            doc.data()['isDeleted'] != true &&
            doc.data()['isDisabled'] != true &&
            [
              '',
              'accepted',
            ].contains('${doc.data()['status'] ?? ''}'.trim().toLowerCase()))
          (doc.data()['adminId']?.toString().trim().isNotEmpty == true
              ? doc.data()['adminId'].toString().trim()
              : doc.id): (
            doc.data()['adminId']?.toString().trim().isNotEmpty == true
                ? doc.data()['adminId'].toString().trim()
                : doc.id,
            doc.data(),
          ),
    }.values.toList();
    final recipients = admins.isNotEmpty
        ? admins
        : {
            for (final doc in branchAccounts)
              if ('${doc.data()['role'] ?? ''}'.trim().toLowerCase() ==
                      'staff' &&
                  doc.id != senderId &&
                  doc.data()['isVoided'] != true &&
                  doc.data()['isDeleted'] != true &&
                  doc.data()['isDisabled'] != true &&
                  ['', 'accepted'].contains(
                    '${doc.data()['status'] ?? ''}'.trim().toLowerCase(),
                  ))
                doc.id: (doc.id, doc.data()),
          }.values.toList();
    if (recipients.isEmpty) {
      throw StateError(
        'No active admin or staff account is assigned to this branch.',
      );
    }
    final request = firestore.collection(collectionName).doc();
    final now = DateTime.now();
    final recipientRole = admins.isEmpty ? 'staff' : 'admin';
    final chatIds = <String>[];
    for (final recipient in recipients) {
      final recipientId = recipient.$1;
      final ids = [senderId, recipientId]..sort();
      final chatId = ids.join('_');
      chatIds.add(chatId);
    }
    final batch = firestore.batch();
    batch.set(request, {
      'branchId': branchId,
      'branchName': branchName,
      'amount': amount,
      'requestType': startingCash ? 'starting' : 'additional',
      'status': 'pending',
      'recipientRole': recipientRole,
      'recipientIds': recipients.map((recipient) => recipient.$1).toList(),
      'chatIds': chatIds,
      'senderId': senderId,
      'senderName': senderName,
      'createdAt': Timestamp.fromDate(now),
      'updatedAt': Timestamp.fromDate(now),
    });
    for (final recipient in recipients) {
      final recipientId = recipient.$1;
      final recipientData = recipient.$2;
      final ids = [senderId, recipientId]..sort();
      final chatRef = firestore.collection('messages').doc(ids.join('_'));
      final recipientName = accountName(recipientData, recipientRole);
      batch.set(chatRef, {
        'participantIds': ids,
        'participantNames': {senderId: senderName, recipientId: recipientName},
        'participantPhotos': {senderId: '', recipientId: ''},
        'lastMessage': 'Cash float allocation · ${formatMoney(amount)}',
        'updatedAt': Timestamp.fromDate(now),
        'unreadBy': {recipientId: FieldValue.increment(1)},
      }, SetOptions(merge: true));
      batch.set(chatRef.collection('items').doc(), {
        'senderId': senderId,
        'senderName': senderName,
        'text': 'Cash float allocation · ${formatMoney(amount)}',
        'type': 'cash_float',
        'cashFloatRequestId': request.id,
        'createdAt': Timestamp.fromDate(now),
      });
    }
    await batch.commit();
    return request.id;
  }

  static Future<void> receive({
    required FirebaseFirestore firestore,
    required String requestId,
    required String actorId,
    required String actorName,
    required String actorRole,
    String? chatId,
    String? messageActorId,
  }) async {
    final requestRef = firestore.collection(collectionName).doc(requestId);
    final now = DateTime.now();
    final today = CashDrawerService.dayKey(now);
    final historyRef = firestore.collection('budget_history').doc();
    final message = chatId == null
        ? null
        : firestore.collection('messages').doc(chatId);
    final messageRef = message?.collection('items').doc();
    await firestore.runTransaction((transaction) async {
      final requestSnapshot = await transaction.get(requestRef);
      final request = requestSnapshot.data();
      if (request == null || request['status'] != 'pending') {
        throw StateError('This cash float request is no longer pending.');
      }
      final branchId = '${request['branchId'] ?? ''}';
      final amount = (request['amount'] as num?)?.toDouble();
      if (branchId.isEmpty ||
          amount == null ||
          amount <= 0 ||
          !amount.isFinite) {
        throw StateError('This cash float request has invalid details.');
      }
      final drawerRef = firestore.collection('staff_cash_drawer').doc(branchId);
      final budgetRef = firestore.collection('staff_budget').doc(branchId);
      final drawerSnapshot = await transaction.get(drawerRef);
      final budgetSnapshot = await transaction.get(budgetRef);
      final drawer = drawerSnapshot.data() ?? <String, dynamic>{};
      final sameDay = drawer['drawerDate'] == today;
      final priorOpening =
          (drawer['dailyOpeningCash'] as num?)?.toDouble() ??
          (drawer['openingCash'] as num?)?.toDouble() ??
          0;
      final balance = (drawer['balance'] as num?)?.toDouble() ?? priorOpening;
      final budget = budgetSnapshot.data() ?? <String, dynamic>{};
      final budgetDate = budget['budgetDate']?.toString() ?? '';
      final priorAllocation = budgetDate == today
          ? (budget['allocatedBudget'] as num?)?.toDouble() ?? 0
          : 0;
      final startingCash = request['requestType'] == 'starting';
      final recipientId = '${request['senderId'] ?? ''}';
      final opening = startingCash ? amount : priorOpening;
      final nextBalance = startingCash
          ? amount
          : (sameDay ? balance : priorOpening) + amount;
      final nextAllocation = startingCash ? amount : priorAllocation + amount;

      transaction.set(drawerRef, {
        'balance': nextBalance,
        'openingCash': opening,
        'dailyOpeningCash': opening,
        'drawerDate': today,
        'updatedAt': Timestamp.fromDate(now),
        'staffId': branchId,
        'branchId': branchId,
        'branchName': request['branchName'],
        'targetType': 'branch',
      }, SetOptions(merge: true));
      transaction.set(budgetRef, {
        'staffId': branchId,
        'staffName': request['branchName'],
        'branchId': branchId,
        'branchName': request['branchName'],
        'targetType': 'branch',
        'allocatedBudget': nextAllocation,
        'budgetDate': today,
        'updatedAt': Timestamp.fromDate(now),
      }, SetOptions(merge: true));
      transaction.update(requestRef, {
        'status': 'received',
        'receivedById': actorId,
        'receivedByName': actorName,
        'receivedByRole': actorRole,
        'receivedAt': Timestamp.fromDate(now),
        'updatedAt': Timestamp.fromDate(now),
      });
      transaction.set(historyRef, {
        'staffId': branchId,
        'staffName': request['branchName'],
        'branchId': branchId,
        'branchName': request['branchName'],
        'targetType': 'branch',
        'amount': amount,
        'type': 'cash_float_received',
        'receivedById': actorId,
        'receivedByName': actorName,
        'receivedByRole': actorRole,
        'createdAt': Timestamp.fromDate(now),
      });
      if (message != null && messageRef != null) {
        _writeConversationUpdate(
          transaction,
          message,
          messageRef,
          requestId: requestId,
          request: request,
          actorId: messageActorId ?? actorId,
          actorName: actorName,
          recipientId: recipientId,
          text: '$actorName confirmed receipt of ${_money(amount)} cash float.',
        );
      }
    });
  }

  static Future<void> reportNotReceived({
    required FirebaseFirestore firestore,
    required String requestId,
    required String actorId,
    required String actorName,
    required String actorRole,
    required String reason,
    String message = '',
    double shortfallAmount = 0,
    String? chatId,
    String? messageActorId,
  }) async {
    final requestRef = firestore.collection(collectionName).doc(requestId);
    final now = DateTime.now();
    final chatRef = chatId == null
        ? null
        : firestore.collection('messages').doc(chatId);
    final messageRef = chatRef?.collection('items').doc();
    await firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(requestRef);
      final request = snapshot.data();
      if (request?['status'] != 'pending') {
        throw StateError('This cash float request is no longer pending.');
      }
      final amount = (request?['amount'] as num?)?.toDouble();
      if (amount == null || amount <= 0 || !amount.isFinite) {
        throw StateError('This cash float request has invalid details.');
      }
      final isShort = reason == 'Amount is short';
      if (isShort &&
          (!shortfallAmount.isFinite ||
              shortfallAmount <= 0 ||
              shortfallAmount >= amount)) {
        throw ArgumentError.value(
          shortfallAmount,
          'shortfallAmount',
          'Must be greater than zero and less than the allocated amount.',
        );
      }
      final receivedAmount = isShort ? amount - shortfallAmount : 0.0;
      if (isShort) {
        await _creditDrawer(
          transaction,
          firestore,
          request!,
          receivedAmount,
          now,
          reportedShortfall: shortfallAmount,
          actorId: actorId,
          actorName: actorName,
          actorRole: actorRole,
        );
      }
      transaction.update(requestRef, {
        'status': 'reported',
        'reportReason': reason,
        'reportMessage': message.trim(),
        if (isShort) 'shortfallAmount': shortfallAmount,
        if (isShort) 'receivedAmount': receivedAmount,
        'reportedById': actorId,
        'reportedByName': actorName,
        'reportedByRole': actorRole,
        'reportedAt': Timestamp.fromDate(now),
        'updatedAt': Timestamp.fromDate(now),
      });
      if (chatRef != null && messageRef != null) {
        final detail = isShort
            ? '$actorName reported a shortfall of ${_money(shortfallAmount)}. ${_money(receivedAmount)} was recorded to the branch cash drawer.'
            : '$actorName reported the cash float: $reason.';
        _writeConversationUpdate(
          transaction,
          chatRef,
          messageRef,
          requestId: requestId,
          request: request!,
          actorId: messageActorId ?? actorId,
          actorName: actorName,
          recipientId: '${request['senderId'] ?? ''}',
          text: message.trim().isEmpty ? detail : '$detail ${message.trim()}',
        );
      }
    });
  }

  static String accountName(Map<String, dynamic> data, String role) {
    final name = [
      data['firstName'],
      data['lastName'],
    ].map((value) => '${value ?? ''}'.trim()).where((part) => part.isNotEmpty);
    final fullName = name.join(' ');
    return fullName.isNotEmpty
        ? fullName
        : '${data['name'] ?? (role == 'admin' ? 'Branch Admin' : 'Branch Staff')}';
  }

  static Future<void> _creditDrawer(
    Transaction transaction,
    FirebaseFirestore firestore,
    Map<String, dynamic> request,
    double receivedAmount,
    DateTime now, {
    double reportedShortfall = 0,
    required String actorId,
    required String actorName,
    required String actorRole,
  }) async {
    final branchId = '${request['branchId'] ?? ''}';
    if (branchId.isEmpty || receivedAmount <= 0 || !receivedAmount.isFinite) {
      throw StateError('This cash float request has invalid details.');
    }
    final today = CashDrawerService.dayKey(now);
    final drawerRef = firestore.collection('staff_cash_drawer').doc(branchId);
    final budgetRef = firestore.collection('staff_budget').doc(branchId);
    final drawerSnapshot = await transaction.get(drawerRef);
    final budgetSnapshot = await transaction.get(budgetRef);
    final drawer = drawerSnapshot.data() ?? <String, dynamic>{};
    final sameDay = drawer['drawerDate'] == today;
    final priorOpening =
        (drawer['dailyOpeningCash'] as num?)?.toDouble() ??
        (drawer['openingCash'] as num?)?.toDouble() ??
        0;
    final balance = (drawer['balance'] as num?)?.toDouble() ?? priorOpening;
    final budget = budgetSnapshot.data() ?? <String, dynamic>{};
    final budgetDate = budget['budgetDate']?.toString() ?? '';
    final priorAllocation = budgetDate == today
        ? (budget['allocatedBudget'] as num?)?.toDouble() ?? 0
        : 0;
    final startingCash = request['requestType'] == 'starting';
    final opening = startingCash ? receivedAmount : priorOpening;
    final nextBalance = startingCash
        ? receivedAmount
        : (sameDay ? balance : priorOpening) + receivedAmount;
    final nextAllocation = startingCash
        ? receivedAmount
        : priorAllocation + receivedAmount;

    transaction.set(drawerRef, {
      'balance': nextBalance,
      'openingCash': opening,
      'dailyOpeningCash': opening,
      'drawerDate': today,
      'updatedAt': Timestamp.fromDate(now),
      'staffId': branchId,
      'branchId': branchId,
      'branchName': request['branchName'],
      'targetType': 'branch',
    }, SetOptions(merge: true));
    transaction.set(budgetRef, {
      'staffId': branchId,
      'staffName': request['branchName'],
      'branchId': branchId,
      'branchName': request['branchName'],
      'targetType': 'branch',
      'allocatedBudget': nextAllocation,
      'budgetDate': today,
      'updatedAt': Timestamp.fromDate(now),
    }, SetOptions(merge: true));
    final historyRef = firestore.collection('budget_history').doc();
    transaction.set(historyRef, {
      'staffId': branchId,
      'staffName': request['branchName'],
      'branchId': branchId,
      'branchName': request['branchName'],
      'targetType': 'branch',
      'amount': receivedAmount,
      'requestedAmount': (request['amount'] as num).toDouble(),
      'shortfallAmount': reportedShortfall,
      'type': reportedShortfall > 0
          ? 'cash_float_received_short'
          : 'cash_float_received',
      'receivedById': actorId,
      'receivedByName': actorName,
      'receivedByRole': actorRole,
      'createdAt': Timestamp.fromDate(now),
    });
  }

  static void _writeConversationUpdate(
    Transaction transaction,
    DocumentReference<Map<String, dynamic>> chatRef,
    DocumentReference<Map<String, dynamic>> messageRef, {
    required String requestId,
    required Map<String, dynamic> request,
    required String actorId,
    required String actorName,
    required String recipientId,
    required String text,
  }) {
    transaction.set(chatRef, {
      'lastMessage': text,
      'updatedAt': FieldValue.serverTimestamp(),
      'unreadBy': {recipientId: FieldValue.increment(1)},
    }, SetOptions(merge: true));
    transaction.set(messageRef, {
      'senderId': actorId,
      'senderName': actorName,
      'text': text,
      'type': 'cash_float_update',
      'cashFloatRequestId': requestId,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  static String _money(double amount) => formatMoney(amount);
}
