from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    file = Path(path)
    text = file.read_text()
    if new in text and old not in text:
        return
    if old not in text:
        raise SystemExit(f"expected snippet not found in {path}: {old[:180]!r}")
    file.write_text(text.replace(old, new, 1))


# Recompute today's streak from actual completion activity and allow same-day
# Undo to repair both current and best streak state.
Path("lib/src/core/data/streak_service.dart").write_text(r'''part of 'repositories.dart';

class DatabaseStreakService implements StreakService {
  DatabaseStreakService(this.db);

  final AppDatabase db;

  @override
  Future<domain.StreakState> current() async {
    final row = await (db.select(
      db.streaks,
    )..where((streak) => streak.id.equals('default'))).getSingleOrNull();
    if (row == null) {
      return domain.StreakState(
        currentStreak: 0,
        bestStreak: 0,
        updatedAt: DateTime.now(),
      );
    }
    return _streakFromRow(row);
  }

  @override
  Future<domain.StreakState> refresh(DateTime now) async {
    final today = dateOnly(now);
    final tomorrow = DateTime(today.year, today.month, today.day + 1);
    final yesterday = DateTime(today.year, today.month, today.day - 1);
    final plans =
        await (db.select(db.maintenancePlans)..where(
              (plan) => plan.archivedAt.isNull() & plan.isEnabled.equals(true),
            ))
            .get();
    final existing = await current();
    final missedObligation = plans.any(
      (plan) => compareDateOnly(plan.nextDueDate, today) < 0,
    );
    final recordsCompletedToday =
        await (db.select(db.maintenanceRecords)..where(
              (record) =>
                  record.completedAt.isBiggerOrEqualValue(today) &
                  record.completedAt.isSmallerThanValue(tomorrow),
            ))
            .get();
    final hasOpenDueToday = plans.any(
      (plan) => isSameDate(plan.nextDueDate, today),
    );
    final wasAwardedToday =
        existing.lastCompletedDate != null &&
        isSameDate(existing.lastCompletedDate!, today);

    if (wasAwardedToday &&
        (recordsCompletedToday.isEmpty ||
            hasOpenDueToday ||
            missedObligation)) {
      final repairedCurrent = existing.currentStreak > 0
          ? existing.currentStreak - 1
          : 0;
      final priorBest = await _longestCompletionRun(beforeExclusive: today);
      final repairedBestCandidate = priorBest > repairedCurrent
          ? priorBest
          : repairedCurrent;
      final repairedBest = repairedBestCandidate < existing.bestStreak
          ? repairedBestCandidate
          : existing.bestStreak;
      return _write(
        currentStreak: repairedCurrent,
        bestStreak: repairedBest,
        lastCompletedDate: repairedCurrent > 0 ? yesterday : null,
        now: now,
      );
    }

    if (missedObligation) {
      return _write(
        currentStreak: 0,
        bestStreak: existing.bestStreak,
        lastCompletedDate: existing.lastCompletedDate,
        now: now,
      );
    }

    if (recordsCompletedToday.isEmpty ||
        hasOpenDueToday ||
        wasAwardedToday) {
      return existing;
    }

    final nextCurrent =
        existing.lastCompletedDate != null &&
            isSameDate(existing.lastCompletedDate!, yesterday)
        ? existing.currentStreak + 1
        : 1;
    return _write(
      currentStreak: nextCurrent,
      bestStreak: nextCurrent > existing.bestStreak
          ? nextCurrent
          : existing.bestStreak,
      lastCompletedDate: today,
      now: now,
    );
  }

  Future<int> _longestCompletionRun({required DateTime beforeExclusive}) async {
    final rows =
        await (db.select(db.maintenanceRecords)
              ..where((record) => record.completedAt.isSmallerThanValue(beforeExclusive))
              ..orderBy([(record) => OrderingTerm.asc(record.completedAt)]))
            .get();
    final days = <DateTime>[];
    DateTime? lastDay;
    for (final row in rows) {
      final day = dateOnly(row.completedAt.toLocal());
      if (lastDay == null || !isSameDate(lastDay, day)) {
        days.add(day);
        lastDay = day;
      }
    }
    var best = 0;
    var currentRun = 0;
    DateTime? previous;
    for (final day in days) {
      final consecutive =
          previous != null && day.difference(previous).inDays == 1;
      currentRun = consecutive ? currentRun + 1 : 1;
      if (currentRun > best) best = currentRun;
      previous = day;
    }
    return best;
  }

  Future<domain.StreakState> _write({
    required int currentStreak,
    required int bestStreak,
    required DateTime? lastCompletedDate,
    required DateTime now,
  }) async {
    await db
        .into(db.streaks)
        .insertOnConflictUpdate(
          StreaksCompanion.insert(
            id: 'default',
            currentStreak: Value(currentStreak),
            bestStreak: Value(bestStreak),
            lastCompletedDate: Value(lastCompletedDate),
            updatedAt: Value(now),
          ),
        );
    return domain.StreakState(
      currentStreak: currentStreak,
      bestStreak: bestStreak,
      lastCompletedDate: lastCompletedDate,
      updatedAt: now,
    );
  }
}
''')

# Editing a plan is not notification acknowledgement; null metadata on a full
# edit means the optional metadata row should be removed.
replace_once(
    "lib/src/core/data/maintenance_repository.dart",
    """        if (metadata != null) {
          await _savePlanMetadata(planId, metadata, now);
        }
        await _markPlanInboxRead(planId);
      }
""",
    """        if (metadata != null) {
          await _savePlanMetadata(planId, metadata, now);
        } else {
          await (db.delete(db.maintenancePlanMetadata)..where(
                (row) => row.planId.equals(planId),
              ))
              .go();
        }
      }
""",
)

# Archiving is a lifecycle dismissal, so its outstanding task notification
# should be acknowledged at the same time.
replace_once(
    "lib/src/core/data/maintenance_repository.dart",
    """  @override
  Future<void> archivePlan(String planId) async {
    await (db.update(
      db.maintenancePlans,
    )..where((plan) => plan.id.equals(planId))).write(
      MaintenancePlansCompanion(
        archivedAt: Value(_now()),
        updatedAt: Value(_now()),
      ),
    );
  }
""",
    """  @override
  Future<void> archivePlan(String planId) async {
    final now = _now();
    await db.transaction(() async {
      await (db.update(
        db.maintenancePlans,
      )..where((plan) => plan.id.equals(planId))).write(
        MaintenancePlansCompanion(
          archivedAt: Value(now),
          updatedAt: Value(now),
        ),
      );
      await _markPlanInboxRead(planId);
    });
  }
""",
)

# Postpone is a forward-only action. It must not behave like a no-op or move an
# occurrence backwards; repeated same-target actions are rejected instead of
# reporting multiple successes while collapsing their history.
replace_once(
    "lib/src/core/data/maintenance_repository.dart",
    """      if (plan == null) return;
      await (db.update(
        db.maintenancePlans,
      )..where((row) => row.id.equals(planId))).write(
        MaintenancePlansCompanion(
          nextDueDate: Value(nextDueDate),
          updatedAt: Value(_now()),
        ),
      );
""",
    """      if (plan == null) return;
      final now = _now();
      if (!nextDueDate.isAfter(now) || !nextDueDate.isAfter(plan.nextDueDate)) {
        throw const MaintenancePlanValidationException(
          'Postpone must move the task to a later future time.',
          code: 'invalid_postpone',
        );
      }
      await (db.update(
        db.maintenancePlans,
      )..where((row) => row.id.equals(planId))).write(
        MaintenancePlansCompanion(
          nextDueDate: Value(nextDueDate),
          updatedAt: Value(now),
        ),
      );
""",
)

# Keep the picker itself out of the past while the repository remains the
# authoritative exact date+time validator.
replace_once(
    "lib/src/features/backup/presentation/backup_screen.dart",
    """  final date = await showDatePicker(
    context: context,
    initialDate: task.plan.nextDueDate,
    firstDate: DateTime.now().subtract(const Duration(days: 365)),
    lastDate: DateTime.now().add(const Duration(days: 3650)),
  );
""",
    """  final now = DateTime.now();
  final initialPostponeDate = task.plan.nextDueDate.isAfter(now)
      ? task.plan.nextDueDate
      : now;
  final date = await showDatePicker(
    context: context,
    initialDate: initialPostponeDate,
    firstDate: DateTime(now.year, now.month, now.day),
    lastDate: now.add(const Duration(days: 3650)),
  );
""",
)
replace_once(
    "lib/src/features/backup/presentation/backup_screen.dart",
    """  final time = await showTimePicker(
    context: context,
    initialTime: TimeOfDay.fromDateTime(task.plan.nextDueDate),
  );
""",
    """  final time = await showTimePicker(
    context: context,
    initialTime: TimeOfDay.fromDateTime(
      task.plan.nextDueDate.isAfter(now)
          ? task.plan.nextDueDate
          : now.add(const Duration(hours: 1)),
    ),
  );
""",
)

# Regression coverage lives in an existing canonical test file.
test_path = Path("test/home_structure_repository_test.dart")
text = test_path.read_text()
addition = r'''

    test('editing clears optional metadata and does not acknowledge Inbox', () async {
      final maintenance = DriftMaintenanceRepository(db);
      final roomId = await repo.saveRoom(
        areaId: 'area_first_floor',
        name: 'Metadata room',
      );
      final categoryId = (await repo.listCategories()).first.id;
      final assetId = await repo.saveAsset(
        name: 'Metadata asset',
        categoryId: categoryId,
        roomId: roomId,
      );
      final planId = await maintenance.savePlan(
        assetId: assetId,
        title: 'Metadata task',
        recurrence: const RecurrenceRule(interval: 1, unit: RecurrenceUnit.months),
        priority: PriorityLevel.medium,
        nextDueDate: DateTime(2026, 8, 16, 9),
        healthGroup: HealthGroup.other,
        metadata: const TaskMetadata(
          taskType: 'Inspect',
          locationLabel: 'Garage',
          requiredMaterials: ['Filter'],
        ),
      );
      final inbox = DriftNotificationInboxRepository(db);
      await inbox.createNotification(
        title: 'Due',
        body: 'Metadata task is due',
        kind: 'task',
        route: '/maintenance/$planId',
        planId: planId,
      );
      expect(await inbox.unreadCount(), 1);

      await maintenance.savePlan(
        id: planId,
        assetId: assetId,
        title: 'Metadata task edited',
        recurrence: const RecurrenceRule(interval: 1, unit: RecurrenceUnit.months),
        priority: PriorityLevel.medium,
        nextDueDate: DateTime(2026, 8, 16, 9),
        healthGroup: HealthGroup.other,
        metadata: null,
      );

      expect((await maintenance.getTask(planId))!.plan.metadata, isNull);
      expect(await inbox.unreadCount(), 1);
    });

    test('postpone is forward-only and repeated same-target action is rejected', () async {
      final now = DateTime(2026, 8, 16, 12);
      final maintenance = DriftMaintenanceRepository(db, now: () => now);
      final roomId = await repo.saveRoom(
        areaId: 'area_first_floor',
        name: 'Postpone room',
      );
      final categoryId = (await repo.listCategories()).first.id;
      final assetId = await repo.saveAsset(
        name: 'Postpone asset',
        categoryId: categoryId,
        roomId: roomId,
      );
      final due = DateTime(2026, 8, 17, 9);
      final planId = await maintenance.savePlan(
        assetId: assetId,
        title: 'Postpone task',
        recurrence: const RecurrenceRule(interval: 1, unit: RecurrenceUnit.days),
        priority: PriorityLevel.medium,
        nextDueDate: due,
        healthGroup: HealthGroup.other,
      );
      await expectLater(
        maintenance.postponePlan(planId, DateTime(2026, 8, 15, 9)),
        throwsA(isA<MaintenancePlanValidationException>()),
      );
      final target = DateTime(2026, 8, 18, 9);
      await maintenance.postponePlan(planId, target, reason: 'Travel');
      expect((await maintenance.getTask(planId))!.plan.nextDueDate, target);
      await expectLater(
        maintenance.postponePlan(planId, target, reason: 'Duplicate'),
        throwsA(isA<MaintenancePlanValidationException>()),
      );
    });

    test('completion Undo repairs same-day streak and best streak', () async {
      final now = DateTime(2026, 8, 16, 12);
      final maintenance = DriftMaintenanceRepository(db, now: () => now);
      final streaks = DatabaseStreakService(db);
      final roomId = await repo.saveRoom(
        areaId: 'area_first_floor',
        name: 'Streak room',
      );
      final categoryId = (await repo.listCategories()).first.id;
      final assetId = await repo.saveAsset(
        name: 'Streak asset',
        categoryId: categoryId,
        roomId: roomId,
      );
      final due = DateTime(2026, 8, 16, 9);
      final planId = await maintenance.savePlan(
        assetId: assetId,
        title: 'Streak task',
        recurrence: const RecurrenceRule(interval: 1, unit: RecurrenceUnit.days),
        priority: PriorityLevel.medium,
        nextDueDate: due,
        healthGroup: HealthGroup.other,
      );
      final completion = await maintenance.completePlanResult(
        planId,
        completedAt: now,
        expectedNextDueDate: due,
      );
      var streak = await streaks.refresh(now);
      expect(streak.currentStreak, 1);
      expect(streak.bestStreak, 1);

      await maintenance.undoCompletion(
        planId: planId,
        completionId: completion.operationId!,
        previousDueDate: completion.previousDueDate!,
        expectedCurrentNextDueDate: completion.nextDueDate!,
      );
      streak = await streaks.refresh(now);
      expect(streak.currentStreak, 0);
      expect(streak.bestStreak, 0);
    });
'''
if "editing clears optional metadata and does not acknowledge Inbox" not in text:
    marker = "\n  });\n}"
    index = text.rfind(marker)
    if index < 0:
        raise SystemExit("home structure test group closing marker not found")
    test_path.write_text(text[:index] + addition + text[index:])
