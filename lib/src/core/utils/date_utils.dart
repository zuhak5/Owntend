DateTime dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

DateTime startOfMonth(DateTime value) => DateTime(value.year, value.month);

DateTime endOfMonth(DateTime value) =>
    DateTime(value.year, value.month + 1, 0, 23, 59, 59, 999, 999);

bool isSameDate(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

String monthKey(DateTime value) {
  final month = value.month.toString().padLeft(2, '0');
  return '${value.year}-$month';
}

int compareDateOnly(DateTime a, DateTime b) =>
    dateOnly(a).compareTo(dateOnly(b));

int daysBetweenDates(DateTime start, DateTime end) {
  final utcStart = DateTime.utc(start.year, start.month, start.day);
  final utcEnd = DateTime.utc(end.year, end.month, end.day);
  return utcEnd.difference(utcStart).inDays;
}

List<List<DateTime?>> calendarMonthGrid(DateTime month) {
  final firstDay = DateTime(month.year, month.month);
  final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
  final leadingBlanks = firstDay.weekday % 7;
  final totalCells = ((leadingBlanks + daysInMonth + 6) ~/ 7) * 7;
  return [
    for (var weekStart = 0; weekStart < totalCells; weekStart += 7)
      [
        for (var offset = 0; offset < 7; offset++)
          _calendarDateForCell(
            month,
            weekStart + offset,
            leadingBlanks,
            daysInMonth,
          ),
      ],
  ];
}

DateTime? _calendarDateForCell(
  DateTime month,
  int index,
  int leadingBlanks,
  int daysInMonth,
) {
  final day = index - leadingBlanks + 1;
  if (day < 1 || day > daysInMonth) {
    return null;
  }
  return DateTime(month.year, month.month, day);
}
