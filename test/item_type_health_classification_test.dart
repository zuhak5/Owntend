import 'package:flutter_test/flutter_test.dart';
import 'package:owntend/src/core/domain/models.dart';
import 'package:owntend/src/core/services/health_score_calculator.dart';

void main() {
  const calculator = WeightedHealthScoreCalculator();
  final now = DateTime(2026, 8, 19, 12);

  test('health score derives from linked Item Type', () {
    final safety = _task(
      assetType: AssetType.safety,
      dueDate: now.subtract(const Duration(days: 3)),
      priority: PriorityLevel.critical,
    );
    final device = _task(
      assetType: AssetType.device,
      dueDate: now.add(const Duration(days: 2)),
    );

    final result = calculator.calculate([safety, device], now);

    expect(
      result.activeWeights.keys,
      containsAll(<AssetType>[AssetType.safety, AssetType.device]),
    );
    expect(
      result.groupScores[AssetType.safety],
      lessThan(result.groupScores[AssetType.device]!),
    );
  });

  test('General is explicitly excluded from weighted normalization', () {
    final overdueGeneral = _task(
      assetType: AssetType.general,
      dueDate: now.subtract(const Duration(days: 30)),
      priority: PriorityLevel.critical,
    );

    final result = calculator.calculate([overdueGeneral], now);

    expect(
      WeightedHealthScoreCalculator.weights,
      isNot(contains(AssetType.general)),
    );
    expect(result.score, 100);
    expect(result.groupScores, isEmpty);
    expect(result.activeWeights, isEmpty);
  });

  test('Cleaning remains task semantics and inherits Plant classification', () {
    final cleaning = _task(
      assetType: AssetType.plant,
      taskType: 'Cleaning',
      dueDate: now.subtract(const Duration(days: 1)),
    );

    final result = calculator.calculate([cleaning], now);

    expect(cleaning.plan.metadata?.taskType, 'Cleaning');
    expect(cleaning.asset.assetType, AssetType.plant);
    expect(result.activeWeights.keys, contains(AssetType.plant));
    expect(
      AssetType.values.map((value) => value.name),
      isNot(contains('cleaning')),
    );
  });
}

TaskItem _task({
  required AssetType assetType,
  required DateTime dueDate,
  PriorityLevel priority = PriorityLevel.medium,
  String? taskType,
}) {
  final created = DateTime(2026, 1, 1);
  final asset = Asset(
    id: 'asset-${assetType.name}-${taskType ?? 'care'}',
    name: 'Item',
    assetType: assetType,
    roomId: 'room',
    createdAt: created,
    updatedAt: created,
  );
  return TaskItem(
    plan: MaintenancePlan(
      id: 'plan-${asset.id}',
      assetId: asset.id,
      title: taskType ?? 'Care task',
      recurrence: const RecurrenceRule(interval: 1, unit: RecurrenceUnit.days),
      priority: priority,
      nextDueDate: dueDate,
      metadata: taskType == null ? null : TaskMetadata(taskType: taskType),
      createdAt: created,
      updatedAt: created,
    ),
    asset: asset,
    room: Room(
      id: 'room',
      name: 'Room',
      createdAt: created,
      updatedAt: created,
    ),
    status: dueDate.isBefore(DateTime(2026, 8, 19, 12))
        ? TaskStatus.overdue
        : TaskStatus.upcoming,
  );
}
