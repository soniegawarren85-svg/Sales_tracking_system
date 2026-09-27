import 'branch_report_data.dart';
import '../widgets/historical_cash_drawer.dart';

/// A correction to a daily opening replaces that day's earlier opening amount.
Map<String, double> reportCashByOwner(
  Iterable<Map<String, dynamic>> history,
  DateTime start,
  DateTime end,
) {
  final totals = <String, double>{};
  final openings = <String, Map<String, dynamic>>{};
  for (final row in history) {
    final at = cashRecordDate(row['createdAt'] ?? row['timestamp']);
    if (at == null || at.isBefore(start) || !at.isBefore(end)) continue;
    final owner = '${row['branchId'] ?? row['staffId'] ?? 'Unassigned'}';
    if (row['type'] == 'set_daily_cash_drawer') {
      final key = '$owner/${at.year}-${at.month}-${at.day}';
      final previous = openings[key];
      final previousTime = previous == null
          ? null
          : cashRecordDate(previous['createdAt'] ?? previous['timestamp']);
      if (previousTime == null || !at.isBefore(previousTime))
        openings[key] = row;
    } else {
      totals[owner] =
          (totals[owner] ?? 0) + reportValue(row['amount'] ?? row['budget']);
    }
  }
  for (final row in openings.values) {
    final owner = '${row['branchId'] ?? row['staffId'] ?? 'Unassigned'}';
    totals[owner] =
        (totals[owner] ?? 0) + reportValue(row['amount'] ?? row['budget']);
  }
  return totals;
}
