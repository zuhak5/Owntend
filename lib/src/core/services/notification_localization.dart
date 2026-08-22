import 'package:owntend/l10n/app_localizations.dart';
import 'package:intl/intl.dart';

import '../domain/models.dart';

typedef LocalizedNotificationContent = ({String title, String body});

LocalizedNotificationContent localizeInboxNotification(
  AppLocalizations l10n,
  InboxNotification notification,
) {
  final code = notification.messageCode;
  final args = notification.messageArgs;
  return switch (code) {
    NotificationMessageCode.generic => (
      title: notification.title.trim().isEmpty
          ? l10n.notificationGenericTitle
          : notification.title,
      body: notification.body,
    ),
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
  };
}

String _taskName(InboxNotification notification) {
  final value = _stringArg(notification.messageArgs, 'task');
  if (value.isNotEmpty) return value;
  return notification.title;
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
