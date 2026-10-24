import 'package:cloud_firestore/cloud_firestore.dart';

bool saleBelongsToStaff(
  Map<String, dynamic> sale,
  String staffId, {
  Set<String> staffAliases = const {},
}) {
  final ids = {staffId.trim(), ...staffAliases.map((id) => id.trim())}
    ..remove('');
  if (ids.isEmpty) return false;
  return ['userId', 'cashierId', 'staffUid', 'staffId', 'staffPublicId'].any((
    key,
  ) {
    final owner = '${sale[key] ?? ''}'.trim();
    return owner.isNotEmpty && ids.contains(owner);
  });
}

DateTime? staffReceiptDate(Map<String, dynamic> sale) {
  for (final key in [
    'timestamp',
    'createdAt',
    'soldAt',
    'transactionDate',
    'saleDate',
    'date',
  ]) {
    final raw = sale[key];
    final numeric = raw is num ? raw : num.tryParse('$raw');
    final parsed = raw is Timestamp
        ? raw.toDate()
        : raw is DateTime
        ? raw
        : numeric != null
        ? DateTime.fromMillisecondsSinceEpoch(
            numeric < 1000000000000
                ? (numeric * 1000).toInt()
                : numeric.toInt(),
          )
        : DateTime.tryParse('$raw');
    if (parsed != null) return parsed.toLocal();
  }
  final match = RegExp(
    r'^[A-Za-z]-?(\d{4})(\d{2})(\d{2})',
  ).firstMatch('${sale['salesId'] ?? ''}');
  if (match == null) return null;
  return DateTime(
    int.parse(match[1]!),
    int.parse(match[2]!),
    int.parse(match[3]!),
  );
}

List<Map<String, dynamic>> filterStaffReceiptDates(
  Iterable<Map<String, dynamic>> receipts, {
  DateTime? start,
  DateTime? end,
}) {
  final localStart = start?.toLocal();
  final localEnd = end?.toLocal();
  final from = localStart == null
      ? null
      : DateTime(localStart.year, localStart.month, localStart.day);
  final until = localEnd == null
      ? null
      : DateTime(localEnd.year, localEnd.month, localEnd.day + 1);
  final result = receipts.where((receipt) {
    if (from == null && until == null) return true;
    final date = staffReceiptDate(receipt);
    return date != null &&
        (from == null || !date.isBefore(from)) &&
        (until == null || date.isBefore(until));
  }).toList();
  result.sort(
    (a, b) => (staffReceiptDate(b)?.millisecondsSinceEpoch ?? 0).compareTo(
      staffReceiptDate(a)?.millisecondsSinceEpoch ?? 0,
    ),
  );
  return result;
}
