import 'package:flutter_test/flutter_test.dart';
import 'package:owntend/src/core/sync/local_sync_store.dart';
import 'package:owntend/src/features/maintenance/data/task_creation_operation_store.dart';
import 'package:owntend/src/features/maintenance/domain/task_creation.dart';
import 'package:owntend/src/features/monetization/charged_operation_resolver.dart';
import 'package:owntend/src/features/monetization/monetization.dart';

class _FakeMonetizationRepository implements MonetizationRepository {
  _FakeMonetizationRepository({this.statusToReturn});

  final ChargedOperationStatusResult? statusToReturn;
  PointDebitResult? createTaskResult;
  PointDebitResult? createAssetResult;
  bool shouldThrowOnCreateTask = false;
  final List<Map<String, dynamic>> createTaskCalls = [];
  final List<Map<String, dynamic>> createAssetCalls = [];
  final List<Map<String, dynamic>> statusCalls = [];

  @override
  String? get currentUserId => 'user-a';

  @override
  Stream<PointWallet?> watchWallet(String userId) => Stream.value(null);

  @override
  Stream<MonetizationConfig> watchConfig() =>
      Stream.value(const MonetizationConfig.failClosed());

  @override
  Future<List<PendingRewardClaim>> fetchPendingRewardClaims(
    String userId,
  ) async => const [];

  @override
  Future<PointDebitResult> createAsset(Map<String, dynamic> operation) async {
    createAssetCalls.add(operation);
    if (createAssetResult != null) return createAssetResult!;
    return PointDebitResult(
      balance: 10,
      charged: 0,
      alreadyProcessed: false,
      asset: operation['asset'] as Map<String, dynamic>?,
    );
  }

  @override
  Future<PointDebitResult> createTask(Map<String, dynamic> operation) async {
    createTaskCalls.add(operation);
    if (shouldThrowOnCreateTask) {
      throw Exception('Network timeout during RPC submit');
    }
    if (createTaskResult != null) return createTaskResult!;
    return PointDebitResult(
      balance: 9,
      charged: 1,
      alreadyProcessed: false,
      plan: operation['plan'] as Map<String, dynamic>?,
      metadata: operation['metadata'] as Map<String, dynamic>?,
    );
  }

  @override
  Future<ChargedOperationStatusResult> getChargedOperationStatus(
    String operationId, {
    String? requestHash,
  }) async {
    statusCalls.add({'operation_id': operationId, 'request_hash': requestHash});
    if (statusToReturn != null) return statusToReturn!;
    return const ChargedOperationStatusResult(
      status: 'not_found',
      capabilityVersion: '1.1.0',
    );
  }

  @override
  Future<void> recordEvent(
    String eventName, [
    Map<String, dynamic> properties = const {},
  ]) async {}

  @override
  Future<List<Map<String, dynamic>>> listTransactions() async => const [];

  @override
  Future<RewardClaimRequest> createRewardClaim(
    RewardAdType type, {
    String? timeZone,
  }) => throw UnimplementedError();
}

class _FakeLocalSyncStore implements LocalSyncStore {
  final List<String> reconciledTaskPlanIds = [];
  final List<String> reconciledAssetIds = [];

  @override
  Future<void> reconcileTaskCreationComposite({
    required String planId,
    Map<String, dynamic>? planJson,
    Map<String, dynamic>? metadataJson,
  }) async {
    reconciledTaskPlanIds.add(planId);
  }

  @override
  Future<void> reconcileAssetCreationComposite({
    required String assetId,
    Map<String, dynamic>? assetJson,
  }) async {
    reconciledAssetIds.add(assetId);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('TaskCreationOperationStore & Journal Tests', () {
    test(
      'pre-RPC durable write saves operation in store before network RPC',
      () async {
        final store = TaskCreationOperationStore();
        final now = DateTime.now();
        final op = TaskCreationOperation(
          operationId: 'op-101',
          planId: 'plan-101',
          accountScope: 'user-a',
          requestPayload: const {'test': 'data'},
          requestHash: 'hash-101',
          state: TaskCreationOperationState.submitting,
          createdAt: now,
          updatedAt: now,
        );

        await store.saveOperation(op);
        final retrieved = await store.getOperation('op-101');
        expect(retrieved, isNotNull);
        expect(retrieved!.operationId, equals('op-101'));
        expect(retrieved.accountScope, equals('user-a'));
      },
    );

    test(
      'listOperationsForAccount isolates operations by accountScope',
      () async {
        final store = TaskCreationOperationStore();
        final now = DateTime.now();

        await store.saveOperation(
          TaskCreationOperation(
            operationId: 'op-user-a',
            planId: 'plan-a',
            accountScope: 'user-a',
            requestPayload: const {'user': 'a'},
            requestHash: 'hash-a',
            state: TaskCreationOperationState.submitting,
            createdAt: now,
            updatedAt: now,
          ),
        );

        await store.saveOperation(
          TaskCreationOperation(
            operationId: 'op-user-b',
            planId: 'plan-b',
            accountScope: 'user-b',
            requestPayload: const {'user': 'b'},
            requestHash: 'hash-b',
            state: TaskCreationOperationState.submitting,
            createdAt: now,
            updatedAt: now,
          ),
        );

        final opsA = await store.listOperationsForAccount('user-a');
        expect(opsA.length, equals(1));
        expect(opsA.first.operationId, equals('op-user-a'));

        final opsB = await store.listOperationsForAccount('user-b');
        expect(opsB.length, equals(1));
        expect(opsB.first.operationId, equals('op-user-b'));

        await store.clearOperationsForAccount('user-a');
        expect(await store.listOperationsForAccount('user-a'), isEmpty);
        expect(
          (await store.listOperationsForAccount('user-b')).length,
          equals(1),
        );
      },
    );

    test('purgeTerminalPayloads removes user requestPayload from reconciled operations', () async {
      final store = TaskCreationOperationStore();
      final now = DateTime.now();

      await store.saveOperation(
        TaskCreationOperation(
          operationId: 'op-reconciled',
          planId: 'plan-rec',
          accountScope: 'user-a',
          requestPayload: const {'secret_title': 'Change HVAC Filter'},
          requestHash: 'hash-rec',
          state: TaskCreationOperationState.reconciled,
          createdAt: now,
          updatedAt: now,
        ),
      );

      await store.purgeTerminalPayloads('user-a');

      final purged = await store.getOperation('op-reconciled');
      expect(purged, isNotNull);
      expect(purged!.state, equals(TaskCreationOperationState.reconciled));
      expect(purged.requestPayload, isEmpty);
    });
  });

  group('ChargedOperationResolver Tests', () {
    test(
      'resolves outcomeUnknown operation when server completed RPC',
      () async {
        final store = TaskCreationOperationStore();
        final fakeSyncStore = _FakeLocalSyncStore();
        final fakeMonetization = _FakeMonetizationRepository(
          statusToReturn: ChargedOperationStatusResult(
            status: 'completed',
            capabilityVersion: '1.1.0',
            entityType: 'task',
            entityId: 'plan-lost',
            plan: const {'id': 'plan-lost', 'title': 'Reconciled Task'},
          ),
        );

        final now = DateTime.now();
        await store.saveOperation(
          TaskCreationOperation(
            operationId: 'op-lost-response',
            planId: 'plan-lost',
            accountScope: 'user-a',
            requestPayload: const {
              'plan': {'id': 'plan-lost', 'title': 'Reconciled Task'},
            },
            requestHash: 'hash-lost',
            state: TaskCreationOperationState.outcomeUnknown,
            createdAt: now,
            updatedAt: now,
          ),
        );

        final resolver = ChargedOperationResolver(
          monetizationRepo: fakeMonetization,
          localSyncStore: fakeSyncStore,
          operationStore: store,
        );

        await resolver.resolvePendingOperations('user-a');

        expect(fakeMonetization.statusCalls.length, equals(1));
        expect(
          fakeMonetization.statusCalls.first['operation_id'],
          equals('op-lost-response'),
        );
        expect(fakeSyncStore.reconciledTaskPlanIds, contains('plan-lost'));

        final resolvedOp = await store.getOperation('op-lost-response');
        expect(resolvedOp, isNotNull);
        expect(
          resolvedOp!.state,
          equals(TaskCreationOperationState.reconciled),
        );
        expect(resolvedOp.requestPayload, isEmpty);
      },
    );

    test('resubmits with exact same operationId when status is not_found with capability 1.1.0', () async {
      final store = TaskCreationOperationStore();
      final fakeSyncStore = _FakeLocalSyncStore();
      final fakeMonetization = _FakeMonetizationRepository(
        statusToReturn: const ChargedOperationStatusResult(
          status: 'not_found',
          capabilityVersion: '1.1.0',
        ),
      );

      final now = DateTime.now();
      final payload = {
        'operation_id': 'op-unsubmitted',
        'plan': {'id': 'plan-unsubmitted', 'title': 'Unsubmitted Task'},
      };

      await store.saveOperation(
        TaskCreationOperation(
          operationId: 'op-unsubmitted',
          planId: 'plan-unsubmitted',
          accountScope: 'user-a',
          requestPayload: payload,
          requestHash: 'hash-unsubmitted',
          state: TaskCreationOperationState.outcomeUnknown,
          createdAt: now,
          updatedAt: now,
        ),
      );

      final resolver = ChargedOperationResolver(
        monetizationRepo: fakeMonetization,
        localSyncStore: fakeSyncStore,
        operationStore: store,
      );

      await resolver.resolvePendingOperations('user-a');

      expect(fakeMonetization.statusCalls.length, equals(1));
      expect(fakeMonetization.createTaskCalls.length, equals(1));
      expect(
        fakeMonetization.createTaskCalls.first['operation_id'],
        equals('op-unsubmitted'),
      );
      expect(fakeSyncStore.reconciledTaskPlanIds, contains('plan-unsubmitted'));

      final resolvedOp = await store.getOperation('op-unsubmitted');
      expect(resolvedOp, isNotNull);
      expect(resolvedOp!.state, equals(TaskCreationOperationState.reconciled));
      expect(resolvedOp.requestPayload, isEmpty);
    });
  });
}
