/// Local branch closing time, shared by scheduling and catch-up checks.
DateTime branchClosingTime(DateTime date) =>
    DateTime(date.year, date.month, date.day, 19);

DateTime latestClosedBranchDay(DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  return now.isBefore(branchClosingTime(now))
      ? today.subtract(const Duration(days: 1))
      : today;
}

DateTime nextBranchClosingTime(DateTime now) {
  final closing = branchClosingTime(now);
  return now.isBefore(closing)
      ? closing
      : DateTime(now.year, now.month, now.day + 1, 19);
}
