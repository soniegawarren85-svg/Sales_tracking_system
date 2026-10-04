List<int> analyticsHours(
  DateTime day,
  Iterable<DateTime> dates, {
  int openingMinutes = 600,
  int closingMinutes = 1140,
}) {
  return List.generate(24, (hour) => hour);
}
