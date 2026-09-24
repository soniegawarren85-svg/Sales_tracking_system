import 'package:flutter_test/flutter_test.dart';
import 'package:sales_tracking/services/branch_report_schedule.dart';

void main() {
  test('Before 7PM today is not treated as closed', () {
    final now = DateTime(2026, 9, 24, 18, 59);
    expect(latestClosedBranchDay(now), DateTime(2026, 9, 23));
    expect(nextBranchClosingTime(now), DateTime(2026, 9, 24, 19));
  });

  test('At 7PM the current day is ready to report', () {
    final now = DateTime(2026, 9, 24, 19);
    expect(latestClosedBranchDay(now), DateTime(2026, 9, 24));
    expect(nextBranchClosingTime(now), DateTime(2026, 9, 25, 19));
  });

  test('Reopening after closing catches up the same day', () {
    expect(
      latestClosedBranchDay(DateTime(2026, 9, 24, 22)),
      DateTime(2026, 9, 24),
    );
  });

  test('Midnight catch-up uses the preceding calendar day', () {
    final now = DateTime(2027, 1, 1);
    expect(latestClosedBranchDay(now), DateTime(2026, 12, 31));
    expect(nextBranchClosingTime(now), DateTime(2027, 1, 1, 19));
  });
}
