/// Local branch closing time, shared by scheduling and catch-up checks.
DateTime branchClosingTime(DateTime date, {int closingMinutes = 1140}) =>
    DateTime(
      date.year,
      date.month,
      date.day,
      closingMinutes ~/ 60,
      closingMinutes % 60,
    );

DateTime latestClosedBranchDay(DateTime now, {int closingMinutes = 1140}) {
  final today = DateTime(now.year, now.month, now.day);
  return now.isBefore(branchClosingTime(now, closingMinutes: closingMinutes))
      ? today.subtract(const Duration(days: 1))
      : today;
}

DateTime nextBranchClosingTime(DateTime now, {int closingMinutes = 1140}) {
  final closing = branchClosingTime(now, closingMinutes: closingMinutes);
  return now.isBefore(closing)
      ? closing
      : branchClosingTime(
          DateTime(now.year, now.month, now.day + 1),
          closingMinutes: closingMinutes,
        );
}
