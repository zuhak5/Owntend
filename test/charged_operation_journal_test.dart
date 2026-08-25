import 'package:flutter_test/flutter_test.dart';
import 'package:owntend/src/core/sync/local_sync_store.dart';
import 'package:owntend/src/core/services/charged_operation_journal/charged_operation_store.dart';
import 'package:owntend/src/core/services/charged_operation_journal/charged_operation_contracts.dart';
import 'package:owntend/src/features/monetization/charged_operation_resolver.dart';
import 'package:owntend/src/features/monetization/monetization.dart';

class _FakeMonetizationRepository implements MonetizationRepository {
  _FakeMonetizationRepository({
    this.statusToReturn,
    this.currentUserIdOverride = 'user-a',
  });

  final ChargedOperationStatusResult? statusToReturn;
  final String? currentUserIdOverride;
  PointDebitResult? createTaskResult;
  PointDebitResult? createAssetResult;
  bool shouldThrowOnCreateTask = false;
  bool shouldThrowOnStatus = false;
  bool shouldThrowOperationIdReusedOnStatus = false;
  final List<Map<String, dynamic>> createTaskCalls = [];
  final List<Map<String, dynamic>> createAssetCalls = [];
  final List<Map<String, dynamic>> statusCalls = [];

  @override
  String? get currentUserId => currentUserIdOverride;

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
    required String requestHash,
  }) async {
    statusCalls.add({'operation_id': operationId, 'request_hash': requestHash});
    if (shouldThrowOperationIdReusedOnStatus) {
      throw const OperationIdReusedException();
    }
    if (shouldThrowOnStatus) {
      throw Exception('Network unavailable during operation recovery');
    }
    if (statusToReturn != null) return statusToReturn!;
    return const ChargedOperationStatusResult(status: 'not_found');
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

TaskCreationOperation _pendingTaskOperation({
  required String operationId,
  required String planId,
  required String requestHash,
  TaskCreationOperationState state = TaskCreationOperationState.outcomeUnknown,
}) {
  final now = DateTime.now();
  return TaskCreationOperation(
    operationId: operationId,
    planId: planId,
    accountScope: 'user-a',
    requestPayload: {
      'operation_id': operationId,
      'request_hash': requestHash,
      'plan': {'id': planId, 'title': 'Reconciled Task'},
    },
    requestHash: requestHash,
    state: state,
    createdAt: now,
    updatedAt: now,
  );
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
      'response-loss recovery is hash-qualified, terminal, and idempotent',
      () async {
        final store = TaskCreationOperationStore();
        final fakeSyncStore = _FakeLocalSyncStore();
        final fakeMonetization = _FakeMonetizationRepository(
          statusToReturn: const ChargedOperationStatusResult(
            status: 'completed',
            entityType: 'task',
            entityId: 'plan-lost',
            balance: 8,
            plan: {'id': 'plan-lost', 'title': 'Reconciled Task'},
          ),
        );

        await store.saveOperation(
          _pendingTaskOperation(
            operationId: 'op-lost-response',
            planId: 'plan-lost',
            requestHash: 'hash-lost',
          ),
        );

        final adoptedBalances = <int>[];
        final resolver = ChargedOperationResolver(
          monetizationRepo: fakeMonetization,
          localSyncStore: fakeSyncStore,
          operationStore: store,
          adoptAuthoritativeBalance: (userId, balance) {
            expect(userId, 'user-a');
            adoptedBalances.add(balance);
          },
        );

        await resolver.resolvePendingOperations('user-a');
        await resolver.resolvePendingOperations('user-a');

        expect(fakeMonetization.statusCalls, hasLength(1));
        expect(
          fakeMonetization.statusCalls.single,
          equals({
            'operation_id': 'op-lost-response',
            'request_hash': 'hash-lost',
          }),
        );
        expect(fakeSyncStore.reconciledTaskPlanIds, ['plan-lost']);
        expect(adoptedBalances, [8]);

        final resolvedOp = await store.getOperation('op-lost-response');
        expect(resolvedOp, isNotNull);
        expect(
          resolvedOp!.state,
          equals(TaskCreationOperationState.reconciled),
        );
        expect(resolvedOp.requestPayload, isEmpty);
      },
    );

    test(
      'not_found replay uses exact retained operation id, hash, and payload',
      () async {
        final store = TaskCreationOperationStore();
        final fakeSyncStore = _FakeLocalSyncStore();
        final fakeMonetization =
            _FakeMonetizationRepository(
                statusToReturn: const ChargedOperationStatusResult(
                  status: 'not_found',
                ),
              )
              ..createTaskResult = const PointDebitResult(
                balance: 7,
                charged: 1,
                alreadyProcessed: false,
                plan: {'id': 'plan-unsubmitted', 'title': 'Unsubmitted Task'},
              );

        final payload = {
          'operation_id': 'op-unsubmitted',
          'request_hash': 'hash-unsubmitted',
          'plan': {'id': 'plan-unsubmitted', 'title': 'Unsubmitted Task'},
        };
        final now = DateTime.now();
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

        final adoptedBalances = <int>[];
        final resolver = ChargedOperationResolver(
          monetizationRepo: fakeMonetization,
          localSyncStore: fakeSyncStore,
          operationStore: store,
          adoptAuthoritativeBalance: (userId, balance) {
            expect(userId, 'user-a');
            adoptedBalances.add(balance);
          },
        );

        await resolver.resolvePendingOperations('user-a');

        expect(fakeMonetization.statusCalls, [
          {
            'operation_id': 'op-unsubmitted',
            'request_hash': 'hash-unsubmitted',
          },
        ]);
        expect(fakeMonetization.createTaskCalls, [payload]);
        expect(fakeSyncStore.reconciledTaskPlanIds, ['plan-unsubmitted']);
        expect(adoptedBalances, [7]);

        final resolvedOp = await store.getOperation('op-unsubmitted');
        expect(resolvedOp, isNotNull);
        expect(
          resolvedOp!.state,
          equals(TaskCreationOperationState.reconciled),
        );
        expect(resolvedOp.requestPayload, isEmpty);
      },
    );

    test(
      'network failure preserves the original pending operation for restart',
      () async {
        final store = TaskCreationOperationStore();
        final fakeSyncStore = _FakeLocalSyncStore();
        final fakeMonetization = _FakeMonetizationRepository()
          ..shouldThrowOnStatus = true;
        final pending = _pendingTaskOperation(
          operationId: 'op-retry-later',
          planId: 'plan-retry-later',
          requestHash: 'hash-retry-later',
        );
        await store.saveOperation(pending);

        final resolver = ChargedOperationResolver(
          monetizationRepo: fakeMonetization,
          localSyncStore: fakeSyncStore,
          operationStore: store,
          adoptAuthoritativeBalance: (_, _) {},
        );
        await resolver.resolvePendingOperations('user-a');

        final retained = await store.getOperation('op-retry-later');
        expect(retained, isNotNull);
        expect(retained!.state, TaskCreationOperationState.outcomeUnknown);
        expect(retained.requestPayload, pending.requestPayload);
        expect(retained.requestHash, 'hash-retry-later');
        expect(fakeMonetization.createTaskCalls, isEmpty);
        expect(fakeSyncStore.reconciledTaskPlanIds, isEmpty);
      },
    );

    test('operation id and request hash conflict is terminal and never resubmitted', () async {
      final store = TaskCreationOperationStore();
      final fakeSyncStore = _FakeLocalSyncStore();
      final fakeMonetization = _FakeMonetizationRepository()
        ..shouldThrowOperationIdReusedOnStatus = true;
      await store.saveOperation(
        _pendingTaskOperation(
          operationId: 'op-conflict',
          planId: 'plan-conflict',
          requestHash: 'hash-conflict',
        ),
      );

      final resolver = ChargedOperationResolver(
        monetizationRepo: fakeMonetization,
        localSyncStore: fakeSyncStore,
        operationStore: store,
        adoptAuthoritativeBalance: (_, _) {},
      );
      await resolver.resolvePendingOperations('user-a');

      final rejected = await store.getOperation('op-conflict');
      expect(rejected, isNotNull);
      expect(rejected!.state, TaskCreationOperationState.permanentRejected);
      expect(rejected.lastErrorCode, 'operation_id_reused');
      expect(rejected.requestPayload, isEmpty);
      expect(fakeMonetization.createTaskCalls, isEmpty);
      expect(fakeSyncStore.reconciledTaskPlanIds, isEmpty);
    });

    test(
      'stale account scope cannot inspect or apply pending charged work',
      () async {
        final store = TaskCreationOperationStore();
        final fakeSyncStore = _FakeLocalSyncStore();
        final fakeMonetization = _FakeMonetizationRepository(
          currentUserIdOverride: 'user-b',
        );
        await store.saveOperation(
          _pendingTaskOperation(
            operationId: 'op-stale-account',
            planId: 'plan-stale-account',
            requestHash: 'hash-stale-account',
          ),
        );

        final resolver = ChargedOperationResolver(
          monetizationRepo: fakeMonetization,
          localSyncStore: fakeSyncStore,
          operationStore: store,
          adoptAuthoritativeBalance: (_, _) {},
        );
        await resolver.resolvePendingOperations('user-a');

        expect(fakeMonetization.statusCalls, isEmpty);
        expect(fakeSyncStore.reconciledTaskPlanIds, isEmpty);
        final retained = await store.getOperation('op-stale-account');
        expect(retained!.state, TaskCreationOperationState.outcomeUnknown);
      },
    );

    test(
      'unqualified journal entry fails closed without network work',
      () async {
        final store = TaskCreationOperationStore();
        final fakeSyncStore = _FakeLocalSyncStore();
        final fakeMonetization = _FakeMonetizationRepository();
        final now = DateTime.now();
        await store.saveOperation(
          TaskCreationOperation(
            operationId: 'op-unqualified',
            planId: 'plan-unqualified',
            accountScope: 'user-a',
            requestPayload: const {
              'operation_id': 'op-unqualified',
              'plan': {'id': 'plan-unqualified'},
            },
            requestHash: 'hash-unqualified',
            state: TaskCreationOperationState.outcomeUnknown,
            createdAt: now,
            updatedAt: now,
          ),
        );

        final resolver = ChargedOperationResolver(
          monetizationRepo: fakeMonetization,
          localSyncStore: fakeSyncStore,
          operationStore: store,
          adoptAuthoritativeBalance: (_, _) {},
        );
        await resolver.resolvePendingOperations('user-a');

        expect(fakeMonetization.statusCalls, isEmpty);
        final rejected = await store.getOperation('op-unqualified');
        expect(rejected!.state, TaskCreationOperationState.permanentRejected);
        expect(rejected.lastErrorCode, 'unqualified_request_hash');
        expect(rejected.requestPayload, isEmpty);
      },
    );

    test('a charged asset creation lost after debit is recovered through the '
        'server status lookup and reconciled locally (F-001)', () async {
      final store = TaskCreationOperationStore();
      final fakeSyncStore = _FakeLocalSyncStore();
      const assetId = 'asset-crash-1';
      const requestHash =
          'b5a31c1ab8a4aff792d16ba9f6ec52f22d7e2a3d47726a8f5e0f2152412c6a91';
      final now = DateTime.now();
      await store.saveOperation(
        TaskCreationOperation(
          operationId: 'op-asset-crash-1',
          planId: assetId,
          accountScope: 'user-a',
          requestPayload: {
            'operation_id': 'op-asset-crash-1',
            'request_hash': requestHash,
            'asset': {'id': assetId, 'name': 'Recovered Sofa'},
            'initial_plans': const <Map<String, dynamic>>[],
          },
          requestHash: requestHash,
          state: TaskCreationOperationState.outcomeUnknown,
          createdAt: now,
          updatedAt: now,
        ),
      );
      final fakeMonetization = _FakeMonetizationRepository(
        statusToReturn: ChargedOperationStatusResult(
          status: 'completed',
          entityType: 'asset',
          entityId: assetId,
          balance: 7,
          asset: {'id': assetId, 'name': 'Recovered Sofa'},
        ),
      );

      final resolver = ChargedOperationResolver(
        monetizationRepo: fakeMonetization,
        localSyncStore: fakeSyncStore,
        operationStore: store,
        adoptAuthoritativeBalance: (userId, balance) {
          expect(userId, 'user-a');
          expect(balance, 7);
        },
      );
      await resolver.resolvePendingOperations('user-a');

      // The server was asked about the retained idempotency identity.
      expect(fakeMonetization.statusCalls, hasLength(1));
      expect(
        fakeMonetization.statusCalls.single['operation_id'],
        'op-asset-crash-1',
      );
      // The canonical composite reached the local store; no replay charge
      // occurred because the server already processed the operation.
      expect(fakeSyncStore.reconciledAssetIds, equals([assetId]));
      expect(fakeMonetization.createAssetCalls, isEmpty);
      final resolved = await store.getOperation('op-asset-crash-1');
      expect(resolved!.state, TaskCreationOperationState.reconciled);
      expect(resolved.requestPayload, isEmpty);
    });

    test(
      'an asset creation never seen by the server is safely resubmitted with '
      'the same idempotency key during recovery',
      () async {
        final store = TaskCreationOperationStore();
        final fakeSyncStore = _FakeLocalSyncStore();
        const assetId = 'asset-lost-1';
        const requestHash =
            'cf2f7a4bd1e0a54bbcc53f6d18ea9f21d0aa4b7f5b6c3d2e1f0a9b8c7d6e5f40';
        final now = DateTime.now();
        await store.saveOperation(
          TaskCreationOperation(
            operationId: 'op-asset-lost-1',
            planId: assetId,
            accountScope: 'user-a',
            requestPayload: {
              'operation_id': 'op-asset-lost-1',
              'request_hash': requestHash,
              'asset': {'id': assetId, 'name': 'Lost Sofa'},
              'initial_plans': const <Map<String, dynamic>>[],
            },
            requestHash: requestHash,
            state: TaskCreationOperationState.submitting,
            createdAt: now,
            updatedAt: now,
          ),
        );
        final fakeMonetization = _FakeMonetizationRepository();

        final resolver = ChargedOperationResolver(
          monetizationRepo: fakeMonetization,
          localSyncStore: fakeSyncStore,
          operationStore: store,
          adoptAuthoritativeBalance: (_, _) {},
        );
        await resolver.resolvePendingOperations('user-a');

        expect(fakeMonetization.createAssetCalls, hasLength(1));
        expect(
          fakeMonetization.createAssetCalls.single['operation_id'],
          'op-asset-lost-1',
        );
        expect(fakeSyncStore.reconciledAssetIds, equals([assetId]));
        final resolved = await store.getOperation('op-asset-lost-1');
        expect(resolved!.state, TaskCreationOperationState.reconciled);
      },
    );
  });
}
