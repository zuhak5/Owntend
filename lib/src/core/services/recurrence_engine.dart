import '../domain/contracts.dart';
import '../domain/models.dart';

class OwntendRecurrenceEngine implements RecurrenceEngine {
  const OwntendRecurrenceEngine();

  @override
  DateTime nextDueDate(DateTime completionDate, RecurrenceRule rule) {
    if (rule.interval < 1) {
      throw ArgumentError.value(
        rule.interval,
        'interval',
        'Must be greater than zero.',
      );
    }
    return switch (rule.unit) {
      RecurrenceUnit.hours => completionDate.add(
        Duration(hours: rule.interval),
      ),
      RecurrenceUnit.days => _createDateTime(
        completionDate,
        completionDate.year,
        completionDate.month,
        completionDate.day + rule.interval,
        completionDate.hour,
        completionDate.minute,
        completionDate.second,
        completionDate.millisecond,
        completionDate.microsecond,
      ),
      RecurrenceUnit.weeks => _createDateTime(
        completionDate,
        completionDate.year,
        completionDate.month,
        completionDate.day + (rule.interval * 7),
        completionDate.hour,
        completionDate.minute,
        completionDate.second,
        completionDate.millisecond,
        completionDate.microsecond,
      ),
      RecurrenceUnit.months => _addMonthsClamped(completionDate, rule.interval),
      RecurrenceUnit.years => _addMonthsClamped(
        completionDate,
        rule.interval * 12,
      ),
    };
  }

  DateTime _addMonthsClamped(DateTime value, int months) {
    final totalMonths = (value.year * 12) + (value.month - 1) + months;
    final year = totalMonths ~/ 12;
    final month = (totalMonths % 12) + 1;
    final lastDayOfTargetMonth = _createDateTime(
      value,
      year,
      month + 1,
      0,
      0,
      0,
      0,
      0,
      0,
    ).day;
    final day = value.day > lastDayOfTargetMonth
        ? lastDayOfTargetMonth
        : value.day;
    return _createDateTime(
      value,
      year,
      month,
      day,
      value.hour,
      value.minute,
      value.second,
      value.millisecond,
      value.microsecond,
    );
  }

  DateTime _createDateTime(
    DateTime source,
    int year,
    int month,
    int day,
    int hour,
    int minute,
    int second,
    int millisecond,
    int microsecond,
  ) {
    if (source.isUtc) {
      return DateTime.utc(
        year,
        month,
        day,
        hour,
        minute,
        second,
        millisecond,
        microsecond,
      );
    }
    return DateTime(
      year,
      month,
      day,
      hour,
      minute,
      second,
      millisecond,
      microsecond,
    );
  }
}
