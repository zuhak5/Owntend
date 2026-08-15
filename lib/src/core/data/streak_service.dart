part of 'repositories.dart';

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
    final plans =
        await (db.select(db.maintenancePlans)..where(
              (plan) => plan.archivedAt.isNull() & plan.isEnabled.equals(true),
            ))
            .get();
    final existing = await current();
    final missedObligation = plans.any(
      (plan) => compareDateOnly(plan.nextDueDate, today) < 0,
    );
    if (missedObligation) {
      return _write(
        currentStreak: 0,
        bestStreak: existing.bestStreak,
        lastCompletedDate: existing.lastCompletedDate,
        now: now,
      );
    }

    final tomorrow = DateTime(today.year, today.month, today.day + 1);
    final recordsDueToday =
        await (db.select(db.maintenanceRecords)..where(
              (record) =>
                  record.dueDate.isBiggerOrEqualValue(today) &
                  record.dueDate.isSmallerThanValue(tomorrow),
            ))
            .get();
    final hasOpenDueToday = plans.any(
      (plan) => isSameDate(plan.nextDueDate, today),
    );
    if (recordsDueToday.isEmpty ||
        hasOpenDueToday ||
        isSameDate(existing.lastCompletedDate ?? DateTime(1900), today)) {
      return existing;
    }

    final yesterday = DateTime(today.year, today.month, today.day - 1);
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
