from pathlib import Path
import re


def replace_once(path: str, old: str, new: str) -> None:
    file = Path(path)
    text = file.read_text()
    if new in text and old not in text:
        return
    if old not in text:
        raise SystemExit(f"expected snippet not found in {path}: {old[:180]!r}")
    file.write_text(text.replace(old, new, 1))


replace_once(
    "lib/src/core/domain/contracts.dart",
    """  Future<void> setNotificationPreferences(NotificationPreferences preferences);
""",
    """  Future<void> setNotificationPreferences(NotificationPreferences preferences);
  Future<void> mergeNotificationPreferences({
    required NotificationPreferences baseline,
    required NotificationPreferences desired,
  });
""",
)

replace_once(
    "lib/src/core/data/settings_repository.dart",
    """  final AppDatabase db;
""",
    """  final AppDatabase db;
  Future<void> _notificationPreferencesWriteQueue = Future<void>.value();
""",
)

old_set = """  @override
  Future<void> setNotificationPreferences(
    domain.NotificationPreferences preferences,
  ) async {
    final normalized = _normalizeNotificationPreferences(preferences);
    await _setSetting(
      'notification_preferences',
      jsonEncode(_notificationPreferencesToJson(normalized)),
    );
    await _setSetting('notifications_enabled', normalized.enabled.toString());
  }
"""
new_set = """  @override
  Future<void> setNotificationPreferences(
    domain.NotificationPreferences preferences,
  ) {
    return _queueNotificationPreferencesWrite(
      () => _writeNotificationPreferences(preferences),
    );
  }

  @override
  Future<void> mergeNotificationPreferences({
    required domain.NotificationPreferences baseline,
    required domain.NotificationPreferences desired,
  }) {
    return _queueNotificationPreferencesWrite(() async {
      final current = await notificationPreferences();
      final merged = current.copyWith(
        enabled: desired.enabled != baseline.enabled ? desired.enabled : null,
        localReminders: desired.localReminders != baseline.localReminders
            ? desired.localReminders
            : null,
        inAppInbox: desired.inAppInbox != baseline.inAppInbox
            ? desired.inAppInbox
            : null,
        weatherAlerts: desired.weatherAlerts != baseline.weatherAlerts
            ? desired.weatherAlerts
            : null,
        quietHoursEnabled:
            desired.quietHoursEnabled != baseline.quietHoursEnabled
            ? desired.quietHoursEnabled
            : null,
        quietHoursStartMinutes:
            desired.quietHoursStartMinutes != baseline.quietHoursStartMinutes
            ? desired.quietHoursStartMinutes
            : null,
        quietHoursEndMinutes:
            desired.quietHoursEndMinutes != baseline.quietHoursEndMinutes
            ? desired.quietHoursEndMinutes
            : null,
        criticalBypassQuietHours:
            desired.criticalBypassQuietHours != baseline.criticalBypassQuietHours
            ? desired.criticalBypassQuietHours
            : null,
        privacyMode: desired.privacyMode != baseline.privacyMode
            ? desired.privacyMode
            : null,
        dailyDigest: desired.dailyDigest != baseline.dailyDigest
            ? desired.dailyDigest
            : null,
        digestHour: desired.digestHour != baseline.digestHour
            ? desired.digestHour
            : null,
        reminderHour: desired.reminderHour != baseline.reminderHour
            ? desired.reminderHour
            : null,
        maxRemindersPerDay:
            desired.maxRemindersPerDay != baseline.maxRemindersPerDay
            ? desired.maxRemindersPerDay
            : null,
        defaultSnoozeMinutes:
            desired.defaultSnoozeMinutes != baseline.defaultSnoozeMinutes
            ? desired.defaultSnoozeMinutes
            : null,
        preferExactReminders:
            desired.preferExactReminders != baseline.preferExactReminders
            ? desired.preferExactReminders
            : null,
      );
      await _writeNotificationPreferences(merged);
    });
  }

  Future<void> _queueNotificationPreferencesWrite(
    Future<void> Function() operation,
  ) {
    final next = _notificationPreferencesWriteQueue.then(
      (_) => operation(),
      onError: (_) => operation(),
    );
    _notificationPreferencesWriteQueue = next;
    return next;
  }

  Future<void> _writeNotificationPreferences(
    domain.NotificationPreferences preferences,
  ) async {
    final normalized = _normalizeNotificationPreferences(preferences);
    final now = DateTime.now();
    await db.transaction(() async {
      await _setSettingAt(
        'notification_preferences',
        jsonEncode(_notificationPreferencesToJson(normalized)),
        now,
      );
      await _setSettingAt(
        'notifications_enabled',
        normalized.enabled.toString(),
        now,
      );
    });
  }
"""
replace_once("lib/src/core/data/settings_repository.dart", old_set, new_set)

# Every direct settings-screen copyWith mutation now passes its captured source
# snapshot explicitly so the repository can merge only that action's delta.
settings = Path("lib/src/features/settings/presentation/settings_screen.dart")
text = settings.read_text()
for variable in ("notificationPreferences", "preferences"):
    pattern = re.compile(
        rf"_saveNotificationPreferences\(\s*context,\s*ref,\s*{variable}\.copyWith\(",
        re.MULTILINE,
    )
    text = pattern.sub(
        f"_saveNotificationPreferences(context, ref, {variable}, {variable}.copyWith(",
        text,
    )

# The quiet-hour picker passes a ternary rather than a direct copyWith call.
old_quiet = """    await _saveNotificationPreferences(
      context,
      ref,
      start
          ? preferences.copyWith(quietHoursStartMinutes: minutes)
          : preferences.copyWith(quietHoursEndMinutes: minutes),
    );
"""
new_quiet = """    await _saveNotificationPreferences(
      context,
      ref,
      preferences,
      start
          ? preferences.copyWith(quietHoursStartMinutes: minutes)
          : preferences.copyWith(quietHoursEndMinutes: minutes),
    );
"""
if old_quiet in text:
    text = text.replace(old_quiet, new_quiet, 1)

old_method = """  Future<void> _saveNotificationPreferences(
    BuildContext context,
    WidgetRef ref,
    NotificationPreferences preferences,
  ) async {
    try {
      await ref
          .read(settingsRepositoryProvider)
          .setNotificationPreferences(preferences);
"""
new_method = """  Future<void> _saveNotificationPreferences(
    BuildContext context,
    WidgetRef ref,
    NotificationPreferences baseline,
    NotificationPreferences preferences,
  ) async {
    try {
      await ref.read(settingsRepositoryProvider).mergeNotificationPreferences(
        baseline: baseline,
        desired: preferences,
      );
"""
if old_method not in text:
    raise SystemExit("settings save helper signature not found after call rewrites")
text = text.replace(old_method, new_method, 1)
settings.write_text(text)

# Repository-level concurrency regression coverage.
test_path = Path("test/home_structure_repository_test.dart")
text = test_path.read_text()
addition = r'''

    test('concurrent notification preference changes merge independent fields', () async {
      final settings = DriftSettingsRepository(db);
      const baseline = NotificationPreferences();
      await settings.setNotificationPreferences(baseline);
      await Future.wait([
        settings.mergeNotificationPreferences(
          baseline: baseline,
          desired: baseline.copyWith(quietHoursEnabled: true),
        ),
        settings.mergeNotificationPreferences(
          baseline: baseline,
          desired: baseline.copyWith(privacyMode: true),
        ),
      ]);
      final saved = await settings.notificationPreferences();
      expect(saved.quietHoursEnabled, isTrue);
      expect(saved.privacyMode, isTrue);
    });
'''
if "concurrent notification preference changes merge independent fields" not in text:
    marker = "\n  });\n}"
    index = text.rfind(marker)
    if index < 0:
        raise SystemExit("home structure test closing marker not found")
    test_path.write_text(text[:index] + addition + text[index:])
