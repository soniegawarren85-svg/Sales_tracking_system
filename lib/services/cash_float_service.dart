import 'package:cloud_firestore/cloud_firestore.dart';

import 'cash_drawer_service.dart';

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
    final profiles = await firestore
        .collection('staff_requests')
        .where('branchIds', arrayContains: branchId)
        .get();
    final legacyProfiles = await firestore
        .collection('staff_requests')
        .where('branchId', isEqualTo: branchId)
        .get();
    final admins = {
      for (final doc in [...profiles.docs, ...legacyProfiles.docs])
        if ('${doc.data()['role'] ?? ''}'.trim().toLowerCase() == 'admin' &&
            doc.data()['isVoided'] != true &&
            [
              '',
              'accepted',
            ].contains('${doc.data()['status'] ?? ''}'.trim().toLowerCase()))
          doc.id: doc,
    }.values.toList();
    final request = firestore.collection(collectionName).doc();
    final now = DateTime.now();
    await request.set({
      'branchId': branchId,
      'branchName': branchName,
      'amount': amount,
      'requestType': startingCash ? 'starting' : 'additional',
      'status': 'pending',
      'recipientRole': admins.isEmpty ? 'staff' : 'admin',
      'recipientIds': admins.map((doc) => doc.id).toList(),
      'senderId': senderId,
      'senderName': senderName,
      'createdAt': Timestamp.fromDate(now),
      'updatedAt': Timestamp.fromDate(now),
    });
    return request.id;
  }

  static Future<void> receive({
    required FirebaseFirestore firestore,
    required String requestId,
    required String actorId,
    required String actorName,
    required String actorRole,
  }) async {
    final requestRef = firestore.collection(collectionName).doc(requestId);
    final now = DateTime.now();
    final today = CashDrawerService.dayKey(now);
    final historyRef = firestore.collection('budget_history').doc();
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
  }) async {
    final requestRef = firestore.collection(collectionName).doc(requestId);
    final now = DateTime.now();
    await firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(requestRef);
      if (snapshot.data()?['status'] != 'pending') {
        throw StateError('This cash float request is no longer pending.');
      }
      transaction.update(requestRef, {
        'status': 'reported',
        'reportReason': reason,
        'reportMessage': message.trim(),
        'reportedById': actorId,
        'reportedByName': actorName,
        'reportedByRole': actorRole,
        'reportedAt': Timestamp.fromDate(now),
        'updatedAt': Timestamp.fromDate(now),
      });
    });
  }
}
