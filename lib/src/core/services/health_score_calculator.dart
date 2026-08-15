import '../domain/contracts.dart';
import '../domain/models.dart';
import '../domain/task_selectors.dart';
import '../utils/date_utils.dart';

class WeightedHealthScoreCalculator implements HealthScoreCalculator {
  const WeightedHealthScoreCalculator();

  static const weights = <HealthGroup, double>{
    HealthGroup.safety: 30,
    HealthGroup.pets: 25,
    HealthGroup.appliances: 20,
    HealthGroup.plants: 15,
    HealthGroup.cleaning: 10,
  };

  @override
  HealthScoreBreakdown calculate(List<TaskItem> tasks, DateTime now) {
    final activeGroups = <HealthGroup, List<TaskItem>>{};
    for (final task in tasks) {
      if (!isTaskActionable(task)) {
        continue;
      }
      if (!weights.containsKey(task.plan.healthGroup)) {
        continue;
      }
      activeGroups.putIfAbsent(task.plan.healthGroup, () => []).add(task);
    }

    if (activeGroups.isEmpty) {
      return const HealthScoreBreakdown(
        score: 100,
        groupScores: {},
        activeWeights: {},
      );
    }

    final activeWeightTotal = activeGroups.keys.fold<double>(
      0,
      (sum, group) => sum + weights[group]!,
    );
    final activeWeights = <HealthGroup, double>{};
    final groupScores = <HealthGroup, double>{};
    var weightedScore = 0.0;

    for (final entry in activeGroups.entries) {
      final group = entry.key;
      final groupTasks = entry.value;
      final overduePenalty = groupTasks.fold<double>(0, (sum, task) {
        final overdueDays = daysBetweenDates(task.plan.nextDueDate, now);
        if (overdueDays <= 0) {
          return sum;
        }
        final priorityMultiplier = switch (task.plan.priority) {
          PriorityLevel.low => 0.7,
          PriorityLevel.medium => 1.0,
          PriorityLevel.high => 1.25,
          PriorityLevel.critical => 1.6,
        };
        return sum + (overdueDays.clamp(1, 30) / 30) * priorityMultiplier;
      });
      final rawScore = (100 - ((overduePenalty / groupTasks.length) * 100))
          .clamp(0, 100)
          .toDouble();
      final normalizedWeight = weights[group]! / activeWeightTotal;
      activeWeights[group] = normalizedWeight;
      groupScores[group] = rawScore;
      weightedScore += rawScore * normalizedWeight;
    }

    return HealthScoreBreakdown(
      score: weightedScore.round().clamp(0, 100),
      groupScores: groupScores,
      activeWeights: activeWeights,
    );
  }
}
