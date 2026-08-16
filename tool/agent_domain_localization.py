from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def replace_once(path: str, old: str, new: str) -> None:
    file = ROOT / path
    text = file.read_text(encoding='utf-8')
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f'{path}: expected one match, found {count}')
    file.write_text(text.replace(old, new, 1), encoding='utf-8')


replace_once(
    'lib/main.dart',
    "import 'src/ui/app_theme.dart';\nimport 'src/ui/components.dart' as hk_ui;",
    "import 'src/ui/app_theme.dart';\nimport 'src/ui/domain_localization.dart';\nimport 'src/ui/components.dart' as hk_ui;",
)

replace_once(
    'lib/src/ui/enum_formatters.dart',
    """String _categoryLabel(BuildContext context, Category category) {
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
""",
    """String _categoryLabel(BuildContext context, Category category) =>
    localizedCategoryLabel(context, category);
""",
)

replace_once(
    'lib/src/ui/enum_formatters.dart',
    """String _recurrenceLabel(BuildContext context, RecurrenceRule rule) {
  return switch (rule.unit) {
    RecurrenceUnit.hours => context.l10n.recurrenceHours(rule.interval),
    RecurrenceUnit.days => context.l10n.recurrenceDays(rule.interval),
    RecurrenceUnit.weeks => context.l10n.recurrenceWeeks(rule.interval),
    RecurrenceUnit.months => context.l10n.recurrenceMonths(rule.interval),
    RecurrenceUnit.years => context.l10n.recurrenceYears(rule.interval),
  };
}
""",
    """String _recurrenceLabel(BuildContext context, RecurrenceRule rule) =>
    localizedRecurrenceLabel(context, rule);
""",
)

replace_once(
    'lib/src/ui/components.dart',
    "import 'app_theme.dart';\nimport 'feedback/feedback_coordinator.dart';",
    "import 'app_theme.dart';\nimport 'domain_localization.dart';\nimport 'feedback/feedback_coordinator.dart';",
)

replace_once(
    'lib/src/ui/components.dart',
    "'${_localizedCategoryName(context, task.category.name)} · ${_localizedPriorityLabel(context, task.plan.priority)}';",
    "'${localizedCategoryLabel(context, task.category)} · ${_localizedPriorityLabel(context, task.plan.priority)}';",
)

replace_once(
    'lib/src/ui/components.dart',
    """String _recurrenceText(BuildContext context, RecurrenceRule rule) {
  return switch (rule.unit) {
    RecurrenceUnit.hours => context.l10n.recurrenceHours(rule.interval),
    RecurrenceUnit.days => context.l10n.recurrenceDays(rule.interval),
    RecurrenceUnit.weeks => context.l10n.recurrenceWeeks(rule.interval),
    RecurrenceUnit.months => context.l10n.recurrenceMonths(rule.interval),
    RecurrenceUnit.years => context.l10n.recurrenceYears(rule.interval),
  };
}
""",
    """String _recurrenceText(BuildContext context, RecurrenceRule rule) =>
    localizedRecurrenceLabel(context, rule);
""",
)

replace_once(
    'lib/src/ui/components.dart',
    """String _localizedCategoryName(BuildContext context, String name) =>
    switch (name) {
      'Safety' => context.l10n.safety,
      'Pets' => context.l10n.pets,
      'Appliances' => context.l10n.appliances,
      'Plants' => context.l10n.plants,
      'Cleaning' => context.l10n.cleaning,
      'General' => context.l10n.general,
      _ => name,
    };

""",
    '',
)

replace_once(
    'test/controlled_localization_widget_test.dart',
    "name: 'Cleaning',",
    "name: 'Legacy category display name',",
)
replace_once(
    'test/controlled_localization_widget_test.dart',
    """    expect(find.textContaining('Cleaning'), findsNothing);
    expect(find.textContaining(' in '), findsNothing);
""",
    """    expect(find.textContaining('Legacy category display name'), findsNothing);
    expect(find.textContaining('Cleaning'), findsNothing);
    expect(find.textContaining(' in '), findsNothing);
""",
)

replace_once(
    'test/localization_test.dart',
    """    expect(components, contains('recurrenceDays(rule.interval)'));
    expect(components, isNot(contains('recurrenceEveryMany(rule.interval')));
""",
    """    expect(components, contains('localizedCategoryLabel(context, task.category)'));
    expect(components, contains('localizedRecurrenceLabel(context, rule)'));
    expect(components, isNot(contains('_localizedCategoryName')));
    expect(components, isNot(contains('recurrenceEveryMany(rule.interval')));
""",
)

replace_once(
    'docs/development/localization-and-rtl.md',
    'Category presentation is keyed by stable category ID rather than English category spelling.',
    'Category presentation is centralized and keyed by stable category ID rather than English category spelling.',
)

print('Controlled domain localization centralized successfully.')
