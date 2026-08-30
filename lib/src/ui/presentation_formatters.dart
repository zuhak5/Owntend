import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:owntend/l10n/app_localizations_ext.dart';

import '../core/domain/input_validation.dart';
import '../core/domain/models.dart';
import '../core/utils/app_failure.dart';

AppLanguage supportedDeviceLanguage(Locale locale) {
  return locale.languageCode.toLowerCase() == AppLanguage.ar.name
      ? AppLanguage.ar
      : AppLanguage.en;
}

String failureMessage(
  BuildContext context,
  Object error, {
  AppFailureCode fallback = AppFailureCode.general,
}) {
  if (error is InputValidationException) {
    return switch (error.issue) {
      InputValidationIssue.required => context.l10n.completeRequiredFields,
      InputValidationIssue.invalidFormat => context.l10n.reviewInvalidFields,
      InputValidationIssue.tooLong => context.l10n.keepFieldWithinCharacters(
        error.maxLength ?? 0,
      ),
      InputValidationIssue.mustBePositive => context.l10n.use1OrMore,
      InputValidationIssue.mustBeNonNegative => context.l10n.use0OrMore,
    };
  }
  return localizedFailureMessage(
    context.l10n,
    appFailureCodeFor(error, fallback: fallback),
  );
}

List<TextInputFormatter> limitInputLength(int maximumLength) => [
  LengthLimitingTextInputFormatter(maximumLength),
];

String localeTag(BuildContext context) =>
    Localizations.localeOf(context).toLanguageTag();

String formatShortDate(BuildContext context, DateTime value) =>
    DateFormat.yMMMd(localeTag(context)).format(value);

String formatLongDate(BuildContext context, DateTime value) =>
    DateFormat.yMMMMEEEEd(localeTag(context)).format(value);

String formatShortTime(BuildContext context, DateTime value) =>
    DateFormat.jm(localeTag(context)).format(value);

String formatShortDateTime(BuildContext context, DateTime value) =>
    DateFormat.yMMMd(localeTag(context)).add_jm().format(value);

String formatMonthDay(BuildContext context, DateTime value) =>
    DateFormat.MMMd(localeTag(context)).format(value);

String formatInteger(BuildContext context, num value) =>
    NumberFormat.decimalPattern(localeTag(context)).format(value);

String localizedFeatureMessage(BuildContext context, String value) {
  final l10n = context.l10n;
  final countMatch = RegExp(
    r'^(\d+) (overdue task\(s\)|item\(s\)|due today|warranty alert\(s\))\.$',
  ).firstMatch(value);
  if (countMatch != null) {
    final count = int.parse(countMatch.group(1)!);
    return switch (countMatch.group(2)) {
      'overdue task(s)' => l10n.overdueTaskSentence(count),
      'item(s)' => l10n.itemCountSentence(count),
      'due today' => l10n.dueTodayTaskSentence(count),
      'warranty alert(s)' => l10n.warrantyAlertSentence(count),
      _ => value,
    };
  }
  return switch (value) {
    'No maintenance plan yet.' => l10n.noMaintenancePlanYet,
    'Add a maintenance task.' => l10n.addAMaintenanceTask,
    'Critical task due today.' => l10n.criticalTaskDueToday,
    'Critical care is due soon.' => l10n.criticalCareIsDueSoon,
    'Warranty has expired.' => l10n.warrantyHasExpired,
    'Warranty expires within 30 days.' => l10n.warrantyExpiresWithin30Days,
    'Maintenance is on track.' => l10n.maintenanceIsOnTrack,
    'Review upcoming maintenance.' => l10n.reviewUpcomingMaintenance,
    'No items in this room yet.' => l10n.noItemsInThisRoomYet,
    'Add the first item.' => l10n.addTheFirstItem,
    'Room is on track.' => l10n.roomIsOnTrack,
    'Add maintenance tasks for this room.' =>
      l10n.addMaintenanceTasksForThisRoom,
    'Home setup is incomplete.' => l10n.homeSetupIsIncomplete,
    'No successful backup yet.' => l10n.noSuccessfulBackupYet,
    'Home maintenance is ready.' => l10n.homeMaintenanceIsReady,
    'Review upcoming tasks.' => l10n.reviewUpcomingTasks,
    _ => value,
  };
}

ThemeMode effectiveThemeMode(
  ThemePreference preference, {
  required bool timeOfDayThemeEnabled,
  required DateTime now,
}) {
  final automaticUsesLocalClock =
      preference == ThemePreference.system || timeOfDayThemeEnabled;
  return switch (preference) {
    ThemePreference.light => ThemeMode.light,
    ThemePreference.dark => ThemeMode.dark,
    ThemePreference.system =>
      automaticUsesLocalClock && isLocalDaytime(now)
          ? ThemeMode.light
          : ThemeMode.dark,
  };
}

bool isLocalDaytime(DateTime value) {
  final local = value.toLocal();
  return local.hour >= 6 && local.hour < 18;
}

String hourLabel(BuildContext context, int hour) {
  return MaterialLocalizations.of(context)
      .formatTimeOfDay(TimeOfDay(hour: hour, minute: 0));
}

String? nullableEditText(String value) {
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

List<String> commaSeparatedValues(String value) {
  return value
      .split(',')
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
}

String durationLabel(BuildContext context, Duration duration) {
  if (duration.inMinutes < 60) {
    return context.l10n.durationMinutesShort(duration.inMinutes);
  }
  if (duration.inHours < 24) {
    final minutes = duration.inMinutes.remainder(60);
    return context.l10n.durationHoursMinutesShort(duration.inHours, minutes);
  }
  return duration.inDays == 1
      ? context.l10n.durationDay(duration.inDays)
      : context.l10n.durationDays(duration.inDays);
}
