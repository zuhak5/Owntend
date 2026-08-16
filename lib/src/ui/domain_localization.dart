import 'package:flutter/widgets.dart';
import 'package:owntend/l10n/app_localizations_ext.dart';

import '../core/domain/models.dart';

/// Localizes the built-in category catalog by stable domain identity.
///
/// Category names remain locale-neutral persistence data. Unknown categories
/// fall back to their stored/user-facing name so future or user-defined values
/// are never silently discarded.
String localizedCategoryLabel(BuildContext context, Category category) {
  return switch (category.id) {
    'category_appliances' => context.l10n.appliances,
    'category_safety' => context.l10n.safety,
    'category_plants' => context.l10n.plants,
    'category_pets' => context.l10n.pets,
    'category_cleaning' => context.l10n.cleaning,
    'category_general' => context.l10n.general,
    _ => category.name,
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
