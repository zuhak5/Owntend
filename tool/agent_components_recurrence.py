from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

components_path = ROOT / 'lib/src/ui/components.dart'
text = components_path.read_text(encoding='utf-8')
old = """String _recurrenceText(BuildContext context, RecurrenceRule rule) {
  final unit = _localizedRecurrenceUnit(context, rule);
  if (rule.interval == 1) {
    return context.l10n.recurrenceEveryOne(unit);
  }
  return context.l10n.recurrenceEveryMany(rule.interval, unit);
}

String _localizedRecurrenceUnit(BuildContext context, RecurrenceRule rule) {
  final plural = rule.interval != 1;
  return switch (rule.unit) {
    RecurrenceUnit.hours => plural ? context.l10n.hours2 : context.l10n.hour,
    RecurrenceUnit.days => plural ? context.l10n.days2 : context.l10n.day,
    RecurrenceUnit.weeks => plural ? context.l10n.weeks2 : context.l10n.week,
    RecurrenceUnit.months => plural ? context.l10n.months2 : context.l10n.month,
    RecurrenceUnit.years => plural ? context.l10n.years2 : context.l10n.year,
  };
}
"""
new = """String _recurrenceText(BuildContext context, RecurrenceRule rule) {
  return switch (rule.unit) {
    RecurrenceUnit.hours => context.l10n.recurrenceHours(rule.interval),
    RecurrenceUnit.days => context.l10n.recurrenceDays(rule.interval),
    RecurrenceUnit.weeks => context.l10n.recurrenceWeeks(rule.interval),
    RecurrenceUnit.months => context.l10n.recurrenceMonths(rule.interval),
    RecurrenceUnit.years => context.l10n.recurrenceYears(rule.interval),
  };
}
"""
if text.count(old) != 1:
    raise RuntimeError(f'components recurrence block mismatch: {text.count(old)}')
components_path.write_text(text.replace(old, new, 1), encoding='utf-8')

widget_path = ROOT / 'test/controlled_localization_widget_test.dart'
widget = widget_path.read_text(encoding='utf-8')
old_widget = """    expect(find.textContaining(arabic.cleaning), findsOneWidget);
    expect(find.text('HEPA Purifier · المطبخ'), findsOneWidget);
"""
new_widget = """    expect(find.textContaining(arabic.cleaning), findsOneWidget);
    expect(find.text(arabic.recurrenceDays(2)), findsOneWidget);
    expect(find.text('HEPA Purifier · المطبخ'), findsOneWidget);
"""
if widget.count(old_widget) != 1:
    raise RuntimeError(f'widget assertion anchor mismatch: {widget.count(old_widget)}')
widget_path.write_text(widget.replace(old_widget, new_widget, 1), encoding='utf-8')

source_guard_path = ROOT / 'test/localization_test.dart'
guard = source_guard_path.read_text(encoding='utf-8')
old_guard = """    final components = File('lib/src/ui/components.dart').readAsStringSync();
    expect(components, isNot(contains(\" in \\${task.room.name}\")));

    final search = File(
"""
new_guard = """    final components = File('lib/src/ui/components.dart').readAsStringSync();
    expect(components, isNot(contains(\" in \\${task.room.name}\")));
    expect(components, contains('recurrenceDays(rule.interval)'));
    expect(components, isNot(contains('recurrenceEveryMany(rule.interval')));

    final search = File(
"""
if guard.count(old_guard) != 1:
    raise RuntimeError(f'source guard anchor mismatch: {guard.count(old_guard)}')
source_guard_path.write_text(guard.replace(old_guard, new_guard, 1), encoding='utf-8')

print('TaskCard recurrence localization patch applied.')
