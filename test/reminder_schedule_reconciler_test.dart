import 'package:flutter_test/flutter_test.dart';
import 'package:owntend/src/core/services/reminder_schedule_reconciler.dart';

void main() {
  test('an identical desired reminder is a zero-operation diff', () {
    final entry = _entry();
    final diff = diffReminderSchedules(current: [entry], desired: [entry]);

    expect(diff.added, isEmpty);
    expect(diff.changed, isEmpty);
    expect(diff.removed, isEmpty);
    expect(diff.unchanged, [entry]);
  });

  test('one changed trigger affects only that stable reminder', () {
    final unchanged = _entry(identity: 'task:a', notificationId: 1);
    final previous = _entry(identity: 'task:b', notificationId: 2);
    final changed = _entry(
      identity: 'task:b',
      notificationId: 2,
      scheduledAt: DateTime.utc(2026, 7, 2, 9),
    );
    final diff = diffReminderSchedules(
      current: [unchanged, previous],
      desired: [unchanged, changed],
    );

    expect(diff.added, isEmpty);
    expect(diff.removed, isEmpty);
    expect(diff.changed, [changed]);
    expect(diff.unchanged, [unchanged]);
  });

  test('disabling reminders removes every persisted OS schedule', () {
    final first = _entry(identity: 'task:a', notificationId: 1);
    final second = _entry(identity: 'digest:daily', notificationId: 9000);
    final diff = diffReminderSchedules(
      current: [first, second],
      desired: const [],
    );

    expect(diff.removed, [first, second]);
    expect(diff.added, isEmpty);
    expect(diff.changed, isEmpty);
  });
}

ReminderScheduleEntry _entry({
  String identity = 'task:plan',
  int notificationId = 42,
  DateTime? scheduledAt,
}) {
  return ReminderScheduleEntry(
    identity: identity,
    notificationId: notificationId,
    planRevision: '7',
    scheduledAt: scheduledAt ?? DateTime.utc(2026, 7, 1, 9),
    timezone: 'Asia/Baghdad',
    localComponents: '2026-07-01T12:00:00',
    scheduleMode: 'inexactAllowWhileIdle',
    contentVersion: 'content-v1',
  );
}
