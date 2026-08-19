import 'package:flutter/widgets.dart';
import 'package:owntend/l10n/app_localizations_ext.dart';

import '../core/domain/models.dart';

String localizedAssetTypeLabel(BuildContext context, AssetType type) {
  return switch (type) {
    AssetType.device => context.l10n.deviceOrAppliance,
    AssetType.pet => context.l10n.pet,
    AssetType.plant => context.l10n.plant,
    AssetType.safety => context.l10n.safetyItem,
    AssetType.general => context.l10n.generalItem,
  };
}

/// Formats a recurrence rule with the locale's unit-specific ICU message.
///
/// Unit-specific messages are required for Arabic because singular, dual,
/// few, and other forms cannot be produced correctly by composing a generic
/// translated unit with an English-style "every N" sentence.
String localizedRecurrenceLabel(BuildContext context, RecurrenceRule rule) {
  return switch (rule.unit) {
    RecurrenceUnit.hours => context.l10n.recurrenceHours(rule.interval),
    RecurrenceUnit.days => context.l10n.recurrenceDays(rule.interval),
    RecurrenceUnit.weeks => context.l10n.recurrenceWeeks(rule.interval),
    RecurrenceUnit.months => context.l10n.recurrenceMonths(rule.interval),
    RecurrenceUnit.years => context.l10n.recurrenceYears(rule.interval),
  };
}
