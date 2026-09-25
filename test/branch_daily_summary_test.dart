import 'package:flutter_test/flutter_test.dart';
import 'package:sales_tracking/widgets/branch_daily_summary.dart';
void main() {
  test('configured daily fund is added to selected-day revenue', () {
    final totals = branchDayTotals(DateTime(2026, 9, 24), [], [
      {'timestamp': '2026-09-24T12:00:00', 'total': 799.8},
      {'timestamp': '2026-09-25T12:00:00', 'total': 500},
    ], 1200);
    expect(totals['Starting fund'], 1200);
    expect(totals['Closing cash drawer'], closeTo(1999.8, .001));
  });
  test('historical fund overrides current setting and refunds reduce gain', () {
    final totals = branchDayTotals(DateTime(2026, 9, 24), [
      {'createdAt': '2026-09-23T08:00:00', 'type': 'set_daily_cash_drawer', 'amount': 1200},
      {'createdAt': '2026-09-25T08:00:00', 'type': 'set_daily_cash_drawer', 'amount': 2000},
    ], [
      {'timestamp': '2026-09-24T12:00:00', 'total': 800},
      {'timestamp': '2026-09-24T13:00:00', 'type': 'refund', 'total': -100},
    ], 2000);
    expect(totals['Starting fund'], 1200);
    expect(totals['Total gain (net sales)'], 700);
    expect(totals['Closing cash drawer'], 1900);
  });
}
