import '../domain/contracts.dart';
import '../domain/models.dart';
import '../domain/task_selectors.dart';
import '../utils/date_utils.dart';

class WeightedHealthScoreCalculator implements HealthScoreCalculator {
  const WeightedHealthScoreCalculator();

  /// Weighted health classification is derived from the linked item's Item Type.
  ///
  /// AssetType.general is intentionally excluded: before the Problem #5 cutover,
  /// HealthGroup.other was outside the weighted map. This preserves that
  /// normalization behavior. Cleaning remains task/activity semantics and does
  /// not receive its former standalone classifier weight.
  static const weights = <AssetType, double>{
    AssetType.safety: 30,
    AssetType.pet: 25,
    AssetType.device: 20,
    AssetType.plant: 15,
  };

  @override
  HealthScoreBreakdown calculate(List<TaskItem> tasks, DateTime now) {
    final activeTypes = <AssetType, List<TaskItem>>{};
    for (final task in tasks) {
      if (!isTaskActionable(task)) {
        continue;
      }
      final assetType = task.asset.assetType;
      if (!weights.containsKey(assetType)) {
        continue;
      }
      activeTypes.putIfAbsent(assetType, () => []).add(task);
    }

    if (activeTypes.isEmpty) {
      return const HealthScoreBreakdown(
        score: 100,
        groupScores: {},
        activeWeights: {},
      );
    }

    final activeWeightTotal = activeTypes.keys.fold<double>(
      0,
      (sum, type) => sum + weights[type]!,
    );
    final activeWeights = <AssetType, double>{};
    final typeScores = <AssetType, double>{};
    var weightedScore = 0.0;

    for (final entry in activeTypes.entries) {
      final type = entry.key;
      final typeTasks = entry.value;
      final overduePenalty = typeTasks.fold<double>(0, (sum, task) {
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
      final rawScore = (100 - ((overduePenalty / typeTasks.length) * 100))
          .clamp(0, 100)
          .toDouble();
      final normalizedWeight = weights[type]! / activeWeightTotal;
      activeWeights[type] = normalizedWeight;
      typeScores[type] = rawScore;
      weightedScore += rawScore * normalizedWeight;
    }

    return HealthScoreBreakdown(
      score: weightedScore.round().clamp(0, 100),
      groupScores: typeScores,
      activeWeights: activeWeights,
    );
  }
}
