import 'package:owntend/l10n/app_localizations.dart';
import 'package:intl/intl.dart';

import '../domain/models.dart';

typedef LocalizedNotificationContent = ({String title, String body});

LocalizedNotificationContent localizeInboxNotification(
  AppLocalizations l10n,
  InboxNotification notification,
) {
  final code =
      NotificationMessageCode.fromWireValue(notification.messageCode) ??
      _legacyCode(notification);
  final args = _messageArgs(notification, code);
  if (notification.messageCode != null && code == null) {
    return (
      title: l10n.notificationGenericTitle,
      body: l10n.notificationGenericBody,
    );
  }
  return switch (code) {
    NotificationMessageCode.weatherAlert => (
      title: l10n.notificationWeatherAlertTitle,
      body: l10n.notificationWeatherAlertBody(
        _stringArg(args, 'location'),
        _intArg(args, 'precipitation'),
        _intArg(args, 'wind'),
      ),
    ),
    NotificationMessageCode.taskOverdue => (
      title: l10n.notificationTaskOverdueTitle(_taskName(notification)),
      body: l10n.notificationTaskBody,
    ),
    NotificationMessageCode.taskDueToday => (
      title: l10n.notificationTaskDueTodayTitle(_taskName(notification)),
      body: l10n.notificationTaskBody,
    ),
    NotificationMessageCode.dailyDigest => (
      title: l10n.notificationDailyDigestTitle,
      body: l10n.notificationDailyDigestBody(
        _intArg(args, 'overdue'),
        _intArg(args, 'dueToday'),
        _intArg(args, 'upcoming'),
      ),
    ),
    NotificationMessageCode.taskSkipped => (
      title: l10n.notificationTaskSkippedTitle,
      body: l10n.notificationTaskSkippedBody(
        _stringArg(args, 'reason').isEmpty ? 'other' : 'reason',
        _stringArg(args, 'task'),
        _stringArg(args, 'reason'),
      ),
    ),
    NotificationMessageCode.taskPostponed => (
      title: l10n.notificationTaskPostponedTitle,
      body: l10n.notificationTaskPostponedBody(
        _stringArg(args, 'reason').isEmpty ? 'other' : 'reason',
        _stringArg(args, 'task'),
        _stringArg(args, 'reason'),
        _localizedDate(l10n, _stringArg(args, 'date')),
      ),
    ),
    null => (
      title: notification.title.trim().isEmpty
          ? l10n.notificationGenericTitle
          : notification.title,
      body: notification.body,
    ),
  };
}

NotificationMessageCode? _legacyCode(InboxNotification notification) {
  if (notification.kind == 'digest' ||
      notification.title == 'Daily maintenance digest') {
    return NotificationMessageCode.dailyDigest;
  }
  if (notification.kind == 'task') {
    if (notification.title == 'Task skipped') {
      return NotificationMessageCode.taskSkipped;
    }
    if (notification.title == 'Task postponed') {
      return NotificationMessageCode.taskPostponed;
    }
    if (notification.title.endsWith(' is overdue')) {
      return NotificationMessageCode.taskOverdue;
    }
    if (notification.title.endsWith(' is due today')) {
      return NotificationMessageCode.taskDueToday;
    }
  }
  return null;
}

Map<String, dynamic> _messageArgs(
  InboxNotification notification,
  NotificationMessageCode? code,
) {
  if (notification.messageArgs.isNotEmpty || code == null) {
    return notification.messageArgs;
  }
  final body = notification.body;
  if (code == NotificationMessageCode.taskSkipped) {
    final withReason = RegExp(r'^(.+) was skipped: (.+)$').firstMatch(body);
    if (withReason != null) {
      return {'task': withReason.group(1)!, 'reason': withReason.group(2)!};
    }
    final withoutReason = RegExp(r'^(.+) was skipped for this occurrence\.$')
        .firstMatch(body);
    if (withoutReason != null) return {'task': withoutReason.group(1)!};
  }
  if (code == NotificationMessageCode.taskPostponed) {
    final withReason = RegExp(r'^(.+) was postponed: (.+)$').firstMatch(body);
    if (withReason != null) {
      return {'task': withReason.group(1)!, 'reason': withReason.group(2)!};
    }
    final withoutReason = RegExp(r'^(.+) was postponed to (.+)\.$')
        .firstMatch(body);
    if (withoutReason != null) {
      return {'task': withoutReason.group(1)!, 'date': withoutReason.group(2)!};
    }
  }
  return notification.messageArgs;
}

String _taskName(InboxNotification notification) {
  final value = _stringArg(notification.messageArgs, 'task');
  if (value.isNotEmpty) return value;
  return notification.title
      .replaceFirst(RegExp(r' is (overdue|due today)$'), '')
      .trim();
}

String _stringArg(Map<String, dynamic> args, String key) =>
    args[key]?.toString() ?? '';

int _intArg(Map<String, dynamic> args, String key) {
  final value = args[key];
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

String _localizedDate(AppLocalizations l10n, String value) {
  final date = DateTime.tryParse(value)?.toLocal();
  return date == null
      ? value
      : DateFormat.yMMMd(l10n.localeName).add_jm().format(date);
}
