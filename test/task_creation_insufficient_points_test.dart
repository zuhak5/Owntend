import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:owntend/src/core/domain/models.dart';
import 'package:owntend/src/features/maintenance/application/task_creation_controller.dart';
import 'package:owntend/src/core/services/charged_operation_journal/charged_operation_store.dart';
import 'package:owntend/src/core/services/charged_operation_journal/charged_operation_contracts.dart';
import 'package:owntend/src/features/monetization/monetization.dart';

class _InsufficientPointsRepository extends MonetizationRepository {
  @override
  Future<PointDebitResult> createTask(Map<String, dynamic> operation) {
    throw const InsufficientPointsException(balance: 0);
  }
}

void main() {
  test(
    'task creation preserves insufficient points as a permanent rejection',
    () async {
      final operationStore = TaskCreationOperationStore();
      final container = ProviderContainer(
        overrides: [
          monetizationRepositoryProvider.overrideWithValue(
            _InsufficientPointsRepository(),
          ),
          taskCreationOperationStoreProvider.overrideWithValue(operationStore),
        ],
      );
      addTearDown(container.dispose);
      final controller = container.read(taskCreationControllerProvider);
      addTearDown(controller.dispose);

      final created = await controller.createNewTask(
        assetId: 'asset-1',
        title: 'Check filter',
        recurrence: const RecurrenceRule(
          interval: 1,
          unit: RecurrenceUnit.months,
        ),
        priority: PriorityLevel.medium,
        nextDueDate: DateTime.utc(2026, 8, 10),
        accountScope: 'account-1',
      );

      expect(created, isFalse);
      expect(
        controller.value.failure?.code,
        TaskCreationFailureCode.insufficientPoints,
      );
      expect(controller.value.failure?.message, 'INSUFFICIENT_POINTS');

      final operations = await operationStore.listOperationsForAccount(
        'account-1',
      );
      expect(operations, hasLength(1));
      expect(
        operations.single.state,
        TaskCreationOperationState.permanentRejected,
      );
      expect(operations.single.lastErrorCode, 'insufficient_points');
      expect(operations.single.lastErrorMessage, 'INSUFFICIENT_POINTS');
    },
  );
}
