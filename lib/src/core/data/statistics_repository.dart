part of 'repositories.dart';

class DriftStatisticsRepository implements StatisticsRepository {
  DriftStatisticsRepository(
    this.db,
    this.maintenanceRepository,
    this.streakService, {
    this._healthScoreCalculator = const WeightedHealthScoreCalculator(),
  });

  final AppDatabase db;
  final MaintenanceRepository maintenanceRepository;
  final StreakService streakService;
  final HealthScoreCalculator _healthScoreCalculator;

  @override
  Future<domain.DashboardSummary> dashboardSummary(DateTime now) async {
    final tasks = await maintenanceRepository.listTasks();
    final buckets = getTaskBuckets(tasks, now);
    final startMonth = startOfMonth(now);
    final endMonth = endOfMonth(now);
    final recordsThisMonth =
        await (db.select(db.maintenanceRecords)..where(
              (record) =>
                  record.completedAt.isBiggerOrEqualValue(startMonth) &
                  record.completedAt.isSmallerOrEqualValue(endMonth),
            ))
            .get();
    final completionRate = _completionRate(
      recordsThisMonth.length,
      buckets.overdueCount,
    );
    return domain.DashboardSummary(
      todayTasks: buckets.todayCount,
      upcomingTasks: buckets.upcomingCount,
      overdueTasks: buckets.overdueCount,
      health: _healthScoreCalculator.calculate(tasks, now),
      streak: await streakService.current(),
      completionRate: completionRate,
      completedThisMonth: recordsThisMonth.length,
    );
  }

  @override
  Stream<domain.DashboardSummary> watchDashboardSummary() {
    return watchReloaded(
      triggers: [
        maintenanceRepository.watchTasks(),
        db.select(db.maintenanceRecords).watch(),
        db.select(db.streaks).watch(),
      ],
      load: () => dashboardSummary(DateTime.now()),
      fingerprint: dashboardSummaryFingerprint,
    );
  }

  @override
  Stream<domain.StatisticsSummary> watchStatisticsSummary() {
    return watchReloaded(
      triggers: [
        maintenanceRepository.watchTasks(),
        db.select(db.maintenanceRecords).watch(),
      ],
      load: () => statisticsSummary(DateTime.now()),
      fingerprint: statisticsSummaryFingerprint,
    );
  }

  @override
  Future<domain.StatisticsSummary> statisticsSummary(DateTime now) async {
    final tasks = await maintenanceRepository.listTasks();
    final buckets = getTaskBuckets(tasks, now);
    final records = await db.select(db.maintenanceRecords).get();
    final completedByMonth = <String, int>{};
    for (final record in records) {
      completedByMonth.update(
        monthKey(record.completedAt),
        (value) => value + 1,
        ifAbsent: () => 1,
      );
    }
    final distribution = <domain.HealthGroup, int>{};
    for (final task in tasks) {
      distribution.update(
        task.plan.healthGroup,
        (value) => value + 1,
        ifAbsent: () => 1,
      );
    }
    return domain.StatisticsSummary(
      completionRate: _completionRate(records.length, buckets.overdueCount),
      overdueRate: tasks.isEmpty ? 0 : buckets.overdueCount / tasks.length,
      completedByMonth: completedByMonth,
      taskDistribution: distribution,
    );
  }

  double _completionRate(int completed, int overdue) {
    final denominator = completed + overdue;
    if (denominator == 0) {
      return 1;
    }
    return completed / denominator;
  }
}
