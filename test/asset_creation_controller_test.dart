import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:owntend/src/core/sync/local_sync_store.dart';
import 'package:owntend/src/core/sync/sync_providers.dart';
import 'package:owntend/src/features/assets/application/asset_creation_controller.dart';
import 'package:owntend/src/features/maintenance/application/task_creation_controller.dart';
import 'package:owntend/src/core/services/charged_operation_journal/charged_operation_store.dart';
import 'package:owntend/src/core/services/charged_operation_journal/charged_operation_contracts.dart';
import 'package:owntend/src/features/monetization/monetization.dart';

class _ScriptedMonetizationRepository implements MonetizationRepository {
  _ScriptedMonetizationRepository({
    this.createAssetResult,
    this.createAssetThrow,
    this.copyAssetResult,
    this.movePlanResult,
    this.changeAssetTypeResult,
  });

  final PointDebitResult? createAssetResult;
  final Object? Function()? createAssetThrow;
  final AssetCopyResult? copyAssetResult;
  final AuthoritativeMutationResult? movePlanResult;
  final AuthoritativeMutationResult? changeAssetTypeResult;

  @override
  String? get currentUserId => 'user-a';

  final List<Map<String, dynamic>> createAssetCalls = [];
  final List<Map<String, dynamic>> copyAssetCalls = [];
  final List<Map<String, dynamic>> movePlanCalls = [];
  final List<Map<String, dynamic>> changeAssetTypeCalls = [];
  final List<void> journalStatesAtCallTime = [];

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
    createAssetCalls.add(Map<String, dynamic>.from(operation));
    final thrown = createAssetThrow?.call();
    if (thrown != null) throw thrown;
    return createAssetResult!;
  }

  @override
  Future<PointDebitResult> createTask(Map<String, dynamic> operation) async {
    throw UnimplementedError();
  }

  @override
  Future<AssetCopyResult> copyAsset(Map<String, dynamic> operation) async {
    copyAssetCalls.add(Map<String, dynamic>.from(operation));
    return copyAssetResult!;
  }

  @override
  Future<AuthoritativeQuote> quoteMaintenancePlanMove({
    required String planId,
    required String targetAssetId,
  }) => throw UnimplementedError();

  @override
  Future<AuthoritativeMutationResult> moveMaintenancePlan(
    Map<String, dynamic> operation,
  ) async {
    movePlanCalls.add(Map<String, dynamic>.from(operation));
    return movePlanResult!;
  }

  @override
  Future<AuthoritativeQuote> quoteAssetTypeChange({
    required String assetId,
    required String targetType,
  }) => throw UnimplementedError();

  @override
  Future<AuthoritativeMutationResult> changeAssetType(
    Map<String, dynamic> operation,
  ) async {
    changeAssetTypeCalls.add(Map<String, dynamic>.from(operation));
    return changeAssetTypeResult!;
  }

  @override
  Future<ChargedOperationStatusResult> getChargedOperationStatus(
    String operationId, {
    required String requestHash,
  }) async {
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
    String? eligibilityToken,
  }) => throw UnimplementedError();
}

class _RecordingLocalSyncStore implements LocalSyncStore {
  final List<String> reconciledAssetIds = [];
  final List<String> reconciledCopyIds = [];

  @override
  Future<void> reconcileAssetCreationComposite({
    required String assetId,
    Map<String, dynamic>? assetJson,
  }) async {
    reconciledAssetIds.add(assetId);
  }

  @override
  Future<void> reconcileAssetCopyComposite({
    required String assetId,
    Map<String, dynamic>? assetJson,
    List<Map<String, dynamic>> plans = const [],
    List<Map<String, dynamic>> planMetadata = const [],
    List<Map<String, dynamic>> detailRows = const [],
  }) async {
    reconciledCopyIds.add(assetId);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Map<String, dynamic> _assetPayload(String assetId) => {
  'id': assetId,
  'name': 'Living Room Sofa',
  'asset_type': 'general',
  'room_id': 'room-living',
};

ProviderContainer _container({
  required _ScriptedMonetizationRepository repo,
  required TaskCreationOperationStore store,
  _RecordingLocalSyncStore? syncStore,
}) {
  final container = ProviderContainer(
    overrides: [
      monetizationRepositoryProvider.overrideWithValue(repo),
      taskCreationOperationStoreProvider.overrideWithValue(store),
      if (syncStore != null)
        localSyncStoreProvider.overrideWithValue(syncStore)
      else
        localSyncStoreProvider.overrideWithValue(null),
      chargedOperationResolverProvider.overrideWithValue(null),
      syncConnectivityProvider.overrideWith((ref) => Stream.value(true)),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('AssetCreationController journaled charged creation', () {
    test('persists the durable journal BEFORE the network RPC', () async {
      final repo = _ScriptedMonetizationRepository(
        createAssetThrow: () => Exception('Network timeout during RPC submit'),
        createAssetResult: null,
      );
      final store = TaskCreationOperationStore();
      final syncStore = _RecordingLocalSyncStore();
      final container = _container(
        repo: repo,
        store: store,
        syncStore: syncStore,
      );

      final controller = container.read(assetCreationControllerProvider);
      await expectLater(
        controller.createChargedAsset(
          assetId: 'asset-j-1',
          assetPayload: _assetPayload('asset-j-1'),
          detailsPayload: const {'brand': 'X'},
          accountScope: 'user-a',
        ),
        throwsStateError,
      );

      expect(repo.createAssetCalls, hasLength(1));
      // The journal entry existed with the exact idempotency payload when the
      // RPC fired; it is now retained as outcomeUnknown for recovery.
      final retained = await store.getOperation(
        repo.createAssetCalls.single['operation_id'] as String,
      );
      expect(retained, isNotNull);
      expect(
        retained!.state,
        equals(TaskCreationOperationState.outcomeUnknown),
      );
      expect(retained.requestPayload['asset'], isNotNull);
      expect(retained.requestPayload['request_hash'], isA<String>());
      expect(
        retained.requestPayload['request_hash'],
        equals(retained.requestHash),
      );
      expect(retained.lastErrorCode, 'transport_or_unknown');
      expect(retained.lastErrorMessage, 'TRANSPORT_OR_UNKNOWN');
      expect(retained.lastErrorMessage, isNot(contains('Network timeout')));
      expect(syncStore.reconciledAssetIds, isEmpty);
    });

    test(
      'success adopts balance, reconciles the composite, then goes terminal',
      () async {
        final repo = _ScriptedMonetizationRepository(
          createAssetResult: PointDebitResult(
            balance: 4,
            charged: 0,
            alreadyProcessed: false,
            asset: _assetPayload('asset-j-2'),
          ),
        );
        final store = TaskCreationOperationStore();
        final syncStore = _RecordingLocalSyncStore();
        final container = _container(
          repo: repo,
          store: store,
          syncStore: syncStore,
        );

        final controller = container.read(assetCreationControllerProvider);
        final result = await controller.createChargedAsset(
          assetId: 'asset-j-2',
          assetPayload: _assetPayload('asset-j-2'),
          detailsPayload: const {},
          accountScope: 'user-a',
        );

        expect(result.assetId, equals('asset-j-2'));
        expect(result.charged, equals(0));
        expect(syncStore.reconciledAssetIds, equals(['asset-j-2']));
        final opId = repo.createAssetCalls.single['operation_id'] as String;
        final terminal = await store.getOperation(opId);
        expect(terminal!.state, equals(TaskCreationOperationState.reconciled));
        // Terminal payloads are purged so no user content lingers in storage.
        expect(terminal.requestPayload, isEmpty);
      },
    );

    test(
      'insufficient points fail closed as permanentRejected and rethrow',
      () async {
        final repo = _ScriptedMonetizationRepository(
          createAssetThrow: () => const InsufficientPointsException(balance: 0),
          createAssetResult: null,
        );
        final store = TaskCreationOperationStore();
        final container = _container(repo: repo, store: store);

        final controller = container.read(assetCreationControllerProvider);
        await expectLater(
          controller.createChargedAsset(
            assetId: 'asset-j-3',
            assetPayload: _assetPayload('asset-j-3'),
            detailsPayload: const {},
            accountScope: 'user-a',
          ),
          throwsA(isA<InsufficientPointsException>()),
        );

        final ops = await store.listOperationsForAccount('user-a');
        expect(ops, hasLength(1));
        expect(
          ops.single.state,
          equals(TaskCreationOperationState.permanentRejected),
        );
        expect(ops.single.lastErrorCode, equals('insufficient_points'));
      },
    );

    test('OPERATION_ID_REUSED maps to permanentRejected', () async {
      final repo = _ScriptedMonetizationRepository(
        createAssetThrow: () => const OperationIdReusedException(),
        createAssetResult: null,
      );
      final store = TaskCreationOperationStore();
      final container = _container(repo: repo, store: store);

      final controller = container.read(assetCreationControllerProvider);
      await expectLater(
        controller.createChargedAsset(
          assetId: 'asset-j-4',
          assetPayload: _assetPayload('asset-j-4'),
          detailsPayload: const {},
          accountScope: 'user-a',
          operationIdOverride: 'op-reused-1',
        ),
        throwsA(isA<OperationIdReusedException>()),
      );

      final op = await store.getOperation('op-reused-1');
      expect(op!.state, equals(TaskCreationOperationState.permanentRejected));
      expect(op.lastErrorCode, equals('operation_id_reused'));
      expect(op.requestPayload, isEmpty);
    });

    test(
      'definitive RPC validation rejection is terminal and scrubbed',
      () async {
        final repo = _ScriptedMonetizationRepository(
          createAssetThrow: () => const AuthoritativeRpcRejectionException(
            code: AuthoritativeRpcRejectionCode.invalidPayload,
            serverCode: 'INVALID_ASSET_PAYLOAD',
          ),
          createAssetResult: null,
        );
        final store = TaskCreationOperationStore();
        final container = _container(repo: repo, store: store);

        await expectLater(
          container
              .read(assetCreationControllerProvider)
              .createChargedAsset(
                assetId: 'asset-invalid-rpc',
                assetPayload: _assetPayload('asset-invalid-rpc'),
                detailsPayload: const {},
                accountScope: 'user-a',
                operationIdOverride: 'op-invalid-rpc',
              ),
          throwsA(isA<AuthoritativeRpcRejectionException>()),
        );

        final operation = await store.getOperation('op-invalid-rpc');
        expect(operation!.state, TaskCreationOperationState.permanentRejected);
        expect(operation.requestPayload, isEmpty);
        expect(operation.lastErrorCode, 'invalid_payload');
        expect(operation.lastErrorMessage, 'INVALID_ASSET_PAYLOAD');
      },
    );

    test('an ambiguous prior operation blocks new charged creation until '
        'recovery is available', () async {
      final repo = _ScriptedMonetizationRepository(
        createAssetResult: PointDebitResult(
          balance: 5,
          charged: 0,
          alreadyProcessed: false,
          asset: _assetPayload('asset-j-6'),
        ),
      );
      final store = TaskCreationOperationStore();
      final now = DateTime.now();
      await store.saveOperation(
        TaskCreationOperation(
          operationId: 'op-stuck-1',
          planId: 'asset-stuck-1',
          accountScope: 'user-a',
          requestPayload: {
            'operation_id': 'op-stuck-1',
            'request_hash': 'aa'.padRight(64, 'a'),
            'asset': {'id': 'asset-stuck-1'},
          },
          requestHash: 'aa'.padRight(64, 'a'),
          state: TaskCreationOperationState.outcomeUnknown,
          createdAt: now,
          updatedAt: now,
        ),
      );
      final container = _container(repo: repo, store: store);

      final controller = container.read(assetCreationControllerProvider);
      await expectLater(
        controller.createChargedAsset(
          assetId: 'asset-j-6',
          assetPayload: _assetPayload('asset-j-6'),
          detailsPayload: const {},
          accountScope: 'user-a',
        ),
        throwsStateError,
      );
      // The blocking operation was not silently discarded.
      final stuck = await store.getOperation('op-stuck-1');
      expect(stuck!.state, equals(TaskCreationOperationState.outcomeUnknown));
      expect(repo.createAssetCalls, isEmpty);
    });

    test(
      'owned copy journals before RPC and sends no client-authored content',
      () async {
        final repo = _ScriptedMonetizationRepository(
          createAssetResult: null,
          copyAssetResult: AssetCopyResult(
            balance: 5,
            charged: 0,
            alreadyProcessed: false,
            asset: _assetPayload('asset-copy'),
          ),
        );
        final store = TaskCreationOperationStore();
        final syncStore = _RecordingLocalSyncStore();
        final container = _container(
          repo: repo,
          store: store,
          syncStore: syncStore,
        );
        var localCopyApplied = false;

        await container
            .read(assetCreationControllerProvider)
            .copyOwnedAsset(
              sourceAssetId: 'asset-source',
              targetAssetId: 'asset-copy',
              destinationRoomId: 'room-target',
              includeTasks: true,
              includePhotos: true,
              planIdMap: const {'plan-source': 'plan-copy'},
              accountScope: 'user-a',
              operationIdOverride: 'copy-operation',
              applyLocalCopy: () async => localCopyApplied = true,
            );

        final sent = repo.copyAssetCalls.single;
        expect(
          sent.keys.toSet(),
          equals({
            'operation_id',
            'source_asset_id',
            'target_asset_id',
            'destination_room_id',
            'include_tasks',
            'plan_id_map',
            'request_hash',
          }),
        );
        expect(localCopyApplied, isTrue);
        expect(syncStore.reconciledCopyIds, equals(['asset-copy']));
        final terminal = await store.getOperation('copy-operation');
        expect(terminal!.state, TaskCreationOperationState.reconciled);
        expect(terminal.requestPayload, isEmpty);
      },
    );
  });

  group('authoritative entitlement-delta controllers', () {
    test(
      'asset type changes adopt the server wallet outside presentation',
      () async {
        final repo = _ScriptedMonetizationRepository(
          changeAssetTypeResult: const AuthoritativeMutationResult(
            status: 'applied',
            charged: 2,
            balance: 3,
            alreadyProcessed: false,
          ),
        );
        final container = _container(
          repo: repo,
          store: TaskCreationOperationStore(),
        );
        final operation = <String, dynamic>{
          'operation_id': 'type-operation',
          'asset_id': 'asset-1',
        };

        final result = await container
            .read(assetCreationControllerProvider)
            .changeAssetTypeWithPointDelta(
              operation: operation,
              accountScope: 'user-a',
            );

        expect(result.balance, 3);
        expect(repo.changeAssetTypeCalls, [operation]);
        expect(container.read(pointWalletProvider).value?.balance, 3);
      },
    );

    test('plan moves adopt the server wallet outside presentation', () async {
      final repo = _ScriptedMonetizationRepository(
        movePlanResult: const AuthoritativeMutationResult(
          status: 'applied',
          charged: 1,
          balance: 4,
          alreadyProcessed: false,
        ),
      );
      final container = _container(
        repo: repo,
        store: TaskCreationOperationStore(),
      );
      final controller = container.read(taskCreationControllerProvider);
      addTearDown(controller.dispose);
      final operation = <String, dynamic>{
        'operation_id': 'move-operation',
        'plan_id': 'plan-1',
      };

      final result = await controller.movePlanWithPointDelta(
        operation: operation,
        accountScope: 'user-a',
      );

      expect(result.balance, 4);
      expect(repo.movePlanCalls, [operation]);
      expect(container.read(pointWalletProvider).value?.balance, 4);
    });
  });
}
