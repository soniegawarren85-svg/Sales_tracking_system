List<int> analyticsHours(
  DateTime day,
  Iterable<DateTime> dates, {
  int openingMinutes = 600,
  int closingMinutes = 1140,
}) {
  final hours = <int>{
    for (var hour = openingMinutes ~/ 60; hour <= closingMinutes ~/ 60; hour++)
      hour,
  };
  for (final date in dates) {
    if (date.year == day.year && date.month == day.month && date.day == day.day)
      hours.add(date.hour);
  }
  return hours.toList()..sort();
}
