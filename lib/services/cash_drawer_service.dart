import 'package:cloud_firestore/cloud_firestore.dart';

class CashDrawerService {
  CashDrawerService._();

  static DateTime? toDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return DateTime.tryParse(value?.toString() ?? '');
  }

  // Business days follow the branch's Philippine calendar, including offline.
  static String dayKey(DateTime value) => value
      .toUtc()
      .add(const Duration(hours: 8))
      .toIso8601String()
      .substring(0, 10);

  static Map<String, dynamic> forDay(
    Map<String, dynamic> data,
    DateTime now, {
    Iterable<Map<String, dynamic>> receipts = const [],
  }) {
    final key = dayKey(now);
    final previous =
        data['drawerDate']?.toString() ??
        (toDate(
                  data['lastResetAt'] ?? data['updatedAt'] ?? data['createdAt'],
                ) ==
                null
            ? ''
            : dayKey(
                toDate(
                  data['lastResetAt'] ?? data['updatedAt'] ?? data['createdAt'],
                )!,
              ));
    if (previous == key) return {...data, 'drawerDate': key};
    final opening =
        num.tryParse(
          '${data['dailyOpeningCash'] ?? data['openingCash'] ?? 0}',
        )?.toDouble() ??
        0;
    var cash = 0.0, gcash = 0.0;
    final seen = <String>{};
    final applied = (data['appliedOfflineMutationIds'] as List? ?? []).toSet();
    final localApplied = (data['localReceiptIds'] as List? ?? []).toSet();
    for (final receipt in receipts) {
      final id = '${receipt['salesId'] ?? receipt['_localDocId'] ?? ''}';
      final date = toDate(receipt['timestamp']);
      if (id.isEmpty || date == null || dayKey(date) != key || !seen.add(id))
        continue;
      if (!applied.contains('receipt-$id') && !localApplied.contains(id))
        continue;
      final payment = '${receipt['paymentMode'] ?? 'Cash'}'.toLowerCase();
      final delta =
          num.tryParse(
            '${receipt['cashDrawerDelta'] ?? receipt['total'] ?? 0}',
          )?.toDouble() ??
          0;
      if (payment == 'cash') cash += delta;
      if (payment == 'gcash')
        gcash += num.tryParse('${receipt['total'] ?? 0}')?.toDouble() ?? 0;
    }
    return {
      ...data,
      'balance': opening + cash,
      'openingCash': opening,
      'dailyOpeningCash': opening,
      'gcashBalance': gcash,
      'drawerDate': key,
      'lastResetAt': now,
    };
  }

  static Future<void> zeroIfPast24Hours(
    String drawerId,
    Map<String, dynamic> data,
  ) async {
    if (drawerId.isEmpty || data['drawerDate'] == dayKey(DateTime.now()))
      return;
    await ensureToday(FirebaseFirestore.instance, drawerId);
  }

  static Future<void> ensureToday(FirebaseFirestore db, String drawerId) async {
    final existing = await db
        .collection('staff_cash_drawer')
        .doc(drawerId)
        .get();
    if (!existing.exists ||
        existing.data()?['drawerDate'] == dayKey(DateTime.now()))
      return;
    final sales = await db
        .collection('completed_sales')
        .where('branchId', isEqualTo: drawerId)
        .get();
    final ref = db.collection('staff_cash_drawer').doc(drawerId);
    await db.runTransaction((tx) async {
      final snapshot = await tx.get(ref);
      if (!snapshot.exists) return;
      final current = snapshot.data()!;
      if (current['drawerDate'] == dayKey(DateTime.now())) return;
      final normalized = forDay(
        current,
        DateTime.now(),
        receipts: sales.docs.map(
          (doc) => {...doc.data(), '_localDocId': doc.id},
        ),
      );
      tx.set(ref, normalized, SetOptions(merge: true));
    });
  }
}
