import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:owntend/src/core/domain/models.dart';
import 'package:owntend/src/core/sync/local_sync_store.dart';
import 'package:owntend/src/core/sync/sync_providers.dart';
import 'package:owntend/src/features/maintenance/application/task_creation_controller.dart';
import 'package:owntend/src/features/maintenance/data/task_creation_operation_store.dart';
import 'package:owntend/src/features/maintenance/domain/task_creation.dart';
import 'package:owntend/src/features/monetization/monetization.dart';

class _RecoveryMonetizationRepository implements MonetizationRepository {
  final List<Map<String, dynamic>> statusCalls = [];
  final List<Map<String, dynamic>> createTaskCalls = [];

  @override
  String? get currentUserId => 'account-1';

  @override
  Stream<PointWallet?> watchWallet(String userId) => Stream.value(null);

  @override
  Future<ChargedOperationStatusResult> getChargedOperationStatus(
    String operationId, {
    required String requestHash,
  }) async {
    statusCalls.add({'operation_id': operationId, 'request_hash': requestHash});
    return const ChargedOperationStatusResult(
      status: 'completed',
      entityType: 'task',
      entityId: 'plan-existing',
      plan: {'id': 'plan-existing', 'title': 'Recovered task'},
    );
  }

  @override
  Future<PointDebitResult> createTask(Map<String, dynamic> operation) async {
    createTaskCalls.add(operation);
    return PointDebitResult(
      balance: 8,
      charged: 1,
      alreadyProcessed: false,
      plan: operation['plan'] as Map<String, dynamic>?,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _RecoveryLocalSyncStore implements LocalSyncStore {
  final List<String> reconciledPlanIds = [];

  @override
  Future<void> reconcileTaskCreationComposite({
    required String planId,
    Map<String, dynamic>? planJson,
    Map<String, dynamic>? metadataJson,
  }) async {
    reconciledPlanIds.add(planId);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test(
    'new charged task resolves its journal without minting another operation',
    () async {
      final operationStore = TaskCreationOperationStore();
      final monetization = _RecoveryMonetizationRepository();
      final syncStore = _RecoveryLocalSyncStore();
      final now = DateTime.now();
      await operationStore.saveOperation(
        TaskCreationOperation(
          operationId: 'op-existing',
          planId: 'plan-existing',
          accountScope: 'account-1',
          requestPayload: const {
            'operation_id': 'op-existing',
            'request_hash': 'hash-existing',
            'plan': {'id': 'plan-existing', 'title': 'Recovered task'},
          },
          requestHash: 'hash-existing',
          state: TaskCreationOperationState.outcomeUnknown,
          createdAt: now,
          updatedAt: now,
        ),
      );

      final container = ProviderContainer(
        overrides: [
          monetizationRepositoryProvider.overrideWithValue(monetization),
          localSyncStoreProvider.overrideWithValue(syncStore),
          taskCreationOperationStoreProvider.overrideWithValue(operationStore),
        ],
      );
      addTearDown(container.dispose);
      final controller = container.read(taskCreationControllerProvider);
      addTearDown(controller.dispose);

      final created = await controller.createNewTask(
        assetId: 'asset-1',
        title: 'Second task',
        recurrence: const RecurrenceRule(
          interval: 1,
          unit: RecurrenceUnit.months,
        ),
        priority: PriorityLevel.medium,
        nextDueDate: DateTime.utc(2026, 9, 1),
        accountScope: 'account-1',
        existingOperation: TaskCreationOperation(
          operationId: 'op-reserved-next',
          planId: 'plan-reserved-next',
          accountScope: 'account-1',
          requestPayload: const {},
          requestHash: '',
          state: TaskCreationOperationState.submitting,
          createdAt: now,
          updatedAt: now,
        ),
      );

      expect(created, isFalse);
      expect(monetization.statusCalls, [
        {'operation_id': 'op-existing', 'request_hash': 'hash-existing'},
      ]);
      expect(monetization.createTaskCalls, isEmpty);
      expect(syncStore.reconciledPlanIds, ['plan-existing']);
      expect(
        controller.value.failure?.code,
        TaskCreationFailureCode.serverError,
      );

      final recovered = await operationStore.getOperation('op-existing');
      expect(recovered, isNotNull);
      expect(recovered!.state, TaskCreationOperationState.reconciled);
      expect(recovered.requestPayload, isEmpty);
      expect(
        await operationStore.listOperationsForAccount('account-1'),
        hasLength(1),
      );
    },
  );

  test(
    'new charged task sends and journals the same immutable request hash',
    () async {
      final operationStore = TaskCreationOperationStore();
      final monetization = _RecoveryMonetizationRepository();
      final syncStore = _RecoveryLocalSyncStore();
      final container = ProviderContainer(
        overrides: [
          monetizationRepositoryProvider.overrideWithValue(monetization),
          localSyncStoreProvider.overrideWithValue(syncStore),
          taskCreationOperationStoreProvider.overrideWithValue(operationStore),
        ],
      );
      addTearDown(container.dispose);
      final controller = container.read(taskCreationControllerProvider);
      addTearDown(controller.dispose);

      final created = await controller.createNewTask(
        assetId: 'asset-1',
        title: 'Hash-qualified task',
        recurrence: const RecurrenceRule(
          interval: 1,
          unit: RecurrenceUnit.months,
        ),
        priority: PriorityLevel.medium,
        nextDueDate: DateTime.utc(2026, 9, 1),
        accountScope: 'account-1',
        existingOperation: TaskCreationOperation(
          operationId: 'op-reserved-new',
          planId: 'plan-reserved-new',
          accountScope: 'account-1',
          requestPayload: const {},
          requestHash: '',
          state: TaskCreationOperationState.submitting,
          createdAt: DateTime.utc(2026, 8, 17),
          updatedAt: DateTime.utc(2026, 8, 17),
        ),
      );

      expect(created, isTrue);
      expect(monetization.createTaskCalls, hasLength(1));
      final outbound = monetization.createTaskCalls.single;
      expect(outbound['operation_id'], 'op-reserved-new');
      expect(
        (outbound['plan'] as Map<String, dynamic>)['id'],
        'plan-reserved-new',
      );
      final requestHash = outbound['request_hash'];
      expect(requestHash, isA<String>());
      expect(requestHash as String, matches(RegExp(r'^[0-9a-f]{64}$')));

      final operations = await operationStore.listOperationsForAccount(
        'account-1',
      );
      expect(operations, hasLength(1));
      expect(operations.single.operationId, 'op-reserved-new');
      expect(operations.single.planId, 'plan-reserved-new');
      expect(operations.single.requestHash, requestHash);
      expect(operations.single.state, TaskCreationOperationState.reconciled);
    },
  );
}
