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

    if (recordsCompletedToday.isEmpty || hasOpenDueToday || wasAwardedToday) {
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
              ..where(
                (record) =>
                    record.completedAt.isSmallerThanValue(beforeExclusive),
              )
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
