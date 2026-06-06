import 'package:cloud_firestore/cloud_firestore.dart';

class CashDrawerService {
  CashDrawerService._();

  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static DateTime? _toDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return DateTime.tryParse(value?.toString() ?? '');
  }

  static Future<void> zeroIfPast24Hours(
    String drawerId,
    Map<String, dynamic> data,
  ) async {
    if (drawerId.trim().isEmpty) return;
    final openingCash = (data['openingCash'] as num?)?.toDouble() ?? 0.0;
    final dailyOpeningCash =
        (data['dailyOpeningCash'] as num?)?.toDouble() ?? openingCash;
    final resetBalance = dailyOpeningCash > 0 ? dailyOpeningCash : openingCash;

    final lastTouched =
        _toDate(data['updatedAt']) ??
        _toDate(data['lastResetAt']) ??
        _toDate(data['createdAt']);
    if (lastTouched == null) return;

    final now = DateTime.now();
    if (now.difference(lastTouched) < const Duration(hours: 24)) return;

    final lastAutoZeroAt = _toDate(data['lastAutoZeroAt']);
    if (lastAutoZeroAt != null &&
        now.difference(lastAutoZeroAt) < const Duration(hours: 23)) {
      return;
    }

    await _firestore.collection('staff_cash_drawer').doc(drawerId).set({
      'balance': resetBalance,
      'openingCash': resetBalance,
      'dailyOpeningCash': resetBalance,
      'lastAutoZeroAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}
