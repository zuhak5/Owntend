from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    file = Path(path)
    text = file.read_text()
    if new in text and old not in text:
        return
    if old not in text:
        raise SystemExit(f"expected snippet not found in {path}: {old[:180]!r}")
    file.write_text(text.replace(old, new, 1))


# Refresh requests that arrive while reconciliation is running must trigger a
# second pass over the latest database state.
replace_once(
    "lib/src/core/services/notification_service.dart",
    """  bool _initialized = false;
  Future<void>? _refreshInFlight;
""",
    """  bool _initialized = false;
  Future<void>? _refreshInFlight;
  bool _refreshRequestedWhileInFlight = false;
""",
)
replace_once(
    "lib/src/core/services/notification_service.dart",
    """  @override
  Future<void> refreshSchedules() {
    final active = _refreshInFlight;
    if (active != null) return active;
    final refresh = _refreshSchedulesNow();
    _refreshInFlight = refresh;
    return refresh.whenComplete(() {
      if (identical(_refreshInFlight, refresh)) {
        _refreshInFlight = null;
      }
    });
  }
""",
    """  @override
  Future<void> refreshSchedules() {
    final active = _refreshInFlight;
    if (active != null) {
      _refreshRequestedWhileInFlight = true;
      return active;
    }
    final refresh = _runRefreshLoop();
    _refreshInFlight = refresh;
    return refresh.whenComplete(() {
      if (identical(_refreshInFlight, refresh)) {
        _refreshInFlight = null;
      }
    });
  }

  Future<void> _runRefreshLoop() async {
    do {
      _refreshRequestedWhileInFlight = false;
      await _refreshSchedulesNow();
    } while (_refreshRequestedWhileInFlight);
  }
""",
)

# Persist snooze state in the reminder snapshot store. A snooze replaces the
# ordinary reminder, survives unrelated refreshes, and is invalidated when the
# task revision changes.
replace_once(
    "lib/src/core/services/notification_service.dart",
    """    final tasks = await maintenanceRepository.listTasks();
    final now = DateTime.now();
    final buckets = getTaskBuckets(tasks, now);
""",
    """    final tasks = await maintenanceRepository.listTasks();
    final now = DateTime.now();
    final tasksById = {for (final task in tasks) task.plan.id: task};
    final activeSnoozes = <String, ReminderScheduleEntry>{};
    for (final entry in current) {
      if (!entry.identity.startsWith('snooze:')) continue;
      final planId = entry.identity.substring('snooze:'.length);
      final task = tasksById[planId];
      if (task == null) continue;
      final currentRevision = task.plan.updatedAt.toUtc().toIso8601String();
      if (entry.planRevision == currentRevision &&
          entry.scheduledAt.isAfter(now.toUtc())) {
        activeSnoozes[planId] = entry;
      }
    }
    final buckets = getTaskBuckets(tasks, now);
""",
)
replace_once(
    "lib/src/core/services/notification_service.dart",
    """    for (final task in tasks.take(128)) {
      if (scheduledCount >= _maxScheduledReminders) {
        break;
      }
      final critical = task.plan.priority == PriorityLevel.critical;
""",
    """    for (final task in tasks.take(128)) {
      if (scheduledCount >= _maxScheduledReminders) {
        break;
      }
      final activeSnooze = activeSnoozes[task.plan.id];
      if (activeSnooze != null) {
        desired.add(_DesiredReminder(activeSnooze, () async {}));
        scheduledCount++;
        continue;
      }
      final critical = task.plan.priority == PriorityLevel.critical;
""",
)

old_snooze = """  @override
  Future<void> snoozePlan(String planId, Duration duration) async {
    if (!_initialized) {
      await initialize();
    }
    await _configureTimezone();
    final preferences = await _preferences();
    if (!preferences.allowsLocalReminders) {
      return;
    }
    final task = await maintenanceRepository.getTask(planId);
    if (task == null || !task.plan.isEnabled) {
      return;
    }
    final scheduledFor = _adjustForQuietHours(
      DateTime.now().add(duration),
      preferences,
      critical: task.plan.priority == PriorityLevel.critical,
    );
    await _scheduleTaskReminder(
      task,
      scheduledFor: scheduledFor,
      preferences: preferences,
      scheduleMode: await _taskScheduleMode(preferences),
      snoozed: true,
    );
  }
"""
new_snooze = """  @override
  Future<void> snoozePlan(String planId, Duration duration) async {
    if (!_initialized) {
      await initialize();
    }
    await _configureTimezone();
    final preferences = await _preferences();
    if (!preferences.allowsLocalReminders) {
      return;
    }
    final task = await maintenanceRepository.getTask(planId);
    if (task == null || !task.plan.isEnabled) {
      return;
    }
    final scheduledFor = _adjustForQuietHours(
      DateTime.now().add(duration),
      preferences,
      critical: task.plan.priority == PriorityLevel.critical,
    );
    final scheduleMode = await _taskScheduleMode(preferences);
    final snoozeId = _stableNotificationId(
      'snooze:$planId',
      _snoozeIdBase,
    );
    await _scheduleTaskReminder(
      task,
      scheduledFor: scheduledFor,
      preferences: preferences,
      scheduleMode: scheduleMode,
      snoozed: true,
    );
    try {
      await _plugin.cancel(
        id: _stableNotificationId('task:$planId', _maintenanceIdBase),
      );
    } on Object {
      await _plugin.cancel(id: snoozeId);
      rethrow;
    }
    final current = await _scheduleStore.readAll();
    final snapshot = _scheduleSnapshot(
      identity: 'snooze:$planId',
      notificationId: snoozeId,
      planRevision: task.plan.updatedAt.toUtc().toIso8601String(),
      scheduledFor: scheduledFor,
      scheduleMode: scheduleMode,
      contentVersion:
          '${task.plan.title}|${task.plan.priority.name}|snoozed|'
          '${preferences.privacyMode}',
    );
    await _scheduleStore.replaceAll([
      for (final entry in current)
        if (entry.identity != 'task:$planId' &&
            entry.identity != 'snooze:$planId')
          entry,
      snapshot,
    ]);
  }
"""
replace_once("lib/src/core/services/notification_service.dart", old_snooze, new_snooze)

# A recent read task notification is reopened when the obligation becomes due
# again; digest duplicates update their current counts/body instead of freezing.
replace_once(
    "lib/src/core/data/notification_inbox_repository.dart",
    """    if (await duplicateQuery.getSingleOrNull() != null) {
      return;
    }
""",
    """    final duplicate = await duplicateQuery.getSingleOrNull();
    if (duplicate != null) {
      final contentChanged =
          duplicate.body != cleanBody ||
          duplicate.messageCode != messageCode?.wireValue ||
          duplicate.messageArgs != jsonEncode(messageArgs);
      final shouldReopen =
          normalizedKind == 'task' && duplicate.readAt != null ||
          normalizedKind == 'digest' && contentChanged;
      if (contentChanged || shouldReopen) {
        await (db.update(
          db.inboxNotifications,
        )..where((row) => row.id.equals(duplicate.id))).write(
          InboxNotificationsCompanion(
            title: Value(cleanTitle.isEmpty ? 'Owntend update' : cleanTitle),
            body: Value(cleanBody),
            messageCode: Value(messageCode?.wireValue),
            messageArgs: Value(jsonEncode(messageArgs)),
            readAt: shouldReopen ? const Value(null) : Value(duplicate.readAt),
            updatedAt: Value(now),
          ),
        );
      }
      return;
    }
""",
)

# Reject reminder lead times that are guaranteed to land outside every cycle.
replace_once(
    "lib/src/core/data/maintenance_repository.dart",
    """    if (reminderDaysBefore < 0) {
      throw const MaintenancePlanValidationException(
        'Reminder lead time cannot be negative.',
        code: 'invalid_reminder',
      );
    }
""",
    """    if (reminderDaysBefore < 0) {
      throw const MaintenancePlanValidationException(
        'Reminder lead time cannot be negative.',
        code: 'invalid_reminder',
      );
    }
    if (!_reminderLeadFitsRecurrence(recurrence, reminderDaysBefore)) {
      throw const MaintenancePlanValidationException(
        'Reminder lead time must be shorter than the recurrence interval.',
        code: 'invalid_reminder_cadence',
      );
    }
""",
)

maintenance = Path("lib/src/core/data/maintenance_repository.dart")
text = maintenance.read_text()
helper = r'''

bool _reminderLeadFitsRecurrence(
  domain.RecurrenceRule recurrence,
  int reminderDaysBefore,
) {
  if (reminderDaysBefore == 0) return true;
  final leadHours = reminderDaysBefore * 24;
  final minimumCycleHours = switch (recurrence.unit) {
    domain.RecurrenceUnit.hours => recurrence.interval,
    domain.RecurrenceUnit.days => recurrence.interval * 24,
    domain.RecurrenceUnit.weeks => recurrence.interval * 7 * 24,
    domain.RecurrenceUnit.months => recurrence.interval * 28 * 24,
    domain.RecurrenceUnit.years => recurrence.interval * 365 * 24,
  };
  return leadHours < minimumCycleHours;
}
'''
if "bool _reminderLeadFitsRecurrence(" not in text:
    maintenance.write_text(text + helper)

# New tasks use the user's reminder hour and always choose a future default.
dialogs = Path("lib/src/features/maintenance/presentation/maintenance_dialogs.dart")
text = dialogs.read_text()
text = text.replace(
    "_dueDate = plan?.nextDueDate ?? _defaultPlanDueDate();",
    "_dueDate = plan?.nextDueDate ?? _nextDefaultPlanDueDate();",
)
text = text.replace(
    "          _defaultPlanDueDate();",
    "          _nextDefaultPlanDueDate();",
)
text = text.replace(
    "            _dueDate = _defaultPlanDueDate();",
    "            _dueDate = _nextDefaultPlanDueDate();",
)
marker = """  String get _offlineDraftKey {
"""
method = """  DateTime _nextDefaultPlanDueDate() {
    final reminderHour =
        ref.read(notificationPreferencesProvider).value?.reminderHour ??
        const NotificationPreferences().reminderHour;
    return _defaultPlanDueDate(reminderHour: reminderHour);
  }

  String get _offlineDraftKey {
"""
if method not in text:
    if marker not in text:
        raise SystemExit("offline draft key marker not found")
    text = text.replace(marker, method, 1)
old_default = """DateTime _defaultPlanDueDate() {
  final now = DateTime.now();
  return DateTime(
    now.year,
    now.month,
    now.day,
    const NotificationPreferences().reminderHour,
  );
}
"""
new_default = """DateTime _defaultPlanDueDate({
  required int reminderHour,
  DateTime? clock,
}) {
  final now = clock ?? DateTime.now();
  final today = DateTime(now.year, now.month, now.day, reminderHour);
  if (today.isAfter(now)) return today;
  return DateTime(now.year, now.month, now.day + 1, reminderHour);
}
"""
if old_default not in text:
    raise SystemExit("default due function not found")
text = text.replace(old_default, new_default, 1)
dialogs.write_text(text)

# Add focused repository/Inbox regression tests to the existing canonical test.
test_path = Path("test/home_structure_repository_test.dart")
text = test_path.read_text()
addition = r'''

    test('task dedupe reopens read reminder and digest dedupe updates counts', () async {
      final inbox = DriftNotificationInboxRepository(db);
      await inbox.createNotification(
        title: 'Task due',
        body: 'Open Owntend',
        kind: 'task',
        route: '/maintenance/plan-dedupe',
        planId: 'plan-dedupe',
      );
      final first = (await inbox.listNotifications()).single;
      await inbox.markRead(first.id);
      expect(await inbox.unreadCount(), 0);
      await inbox.createNotification(
        title: 'Task due',
        body: 'Open Owntend',
        kind: 'task',
        route: '/maintenance/plan-dedupe',
        planId: 'plan-dedupe',
      );
      expect(await inbox.unreadCount(), 1);
      expect(await inbox.listNotifications(), hasLength(1));

      await inbox.createNotification(
        title: 'Daily digest',
        body: '5 due today',
        kind: 'digest',
        route: '/maintenance',
        messageArgs: const {'dueToday': 5},
      );
      await inbox.createNotification(
        title: 'Daily digest',
        body: '2 due today',
        kind: 'digest',
        route: '/maintenance',
        messageArgs: const {'dueToday': 2},
      );
      final digest = (await inbox.listNotifications())
          .firstWhere((item) => item.kind == 'digest');
      expect(digest.body, '2 due today');
      expect(digest.messageArgs['dueToday'], 2);
    });

    test('reminder lead must fit inside recurrence cadence', () async {
      final maintenance = DriftMaintenanceRepository(db);
      final roomId = await repo.saveRoom(
        areaId: 'area_first_floor',
        name: 'Reminder cadence room',
      );
      final categoryId = (await repo.listCategories()).first.id;
      final assetId = await repo.saveAsset(
        name: 'Reminder cadence asset',
        categoryId: categoryId,
        roomId: roomId,
      );
      await expectLater(
        maintenance.savePlan(
          assetId: assetId,
          title: 'Daily impossible reminder',
          recurrence: const RecurrenceRule(interval: 1, unit: RecurrenceUnit.days),
          priority: PriorityLevel.medium,
          nextDueDate: DateTime(2026, 8, 17, 9),
          reminderDaysBefore: 2,
          healthGroup: HealthGroup.other,
        ),
        throwsA(isA<MaintenancePlanValidationException>()),
      );
      final valid = await maintenance.savePlan(
        assetId: assetId,
        title: 'Weekly reminder',
        recurrence: const RecurrenceRule(interval: 1, unit: RecurrenceUnit.weeks),
        priority: PriorityLevel.medium,
        nextDueDate: DateTime(2026, 8, 23, 9),
        reminderDaysBefore: 2,
        healthGroup: HealthGroup.other,
      );
      expect(valid, isNotEmpty);
    });
'''
if "task dedupe reopens read reminder and digest dedupe updates counts" not in text:
    marker = "\n  });\n}"
    index = text.rfind(marker)
    if index < 0:
        raise SystemExit("home structure test closing marker not found")
    test_path.write_text(text[:index] + addition + text[index:])
