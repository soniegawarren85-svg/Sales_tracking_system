List<int> analyticsHours(DateTime day, Iterable<DateTime> dates) {
  final hours = <int>{for (var hour = 10; hour <= 19; hour++) hour};
  for (final date in dates) {
    if (date.year == day.year && date.month == day.month && date.day == day.day)
      hours.add(date.hour);
  }
  return hours.toList()..sort();
}
