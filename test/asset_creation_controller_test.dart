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
  });

  final PointDebitResult? createAssetResult;
  final Object? Function()? createAssetThrow;

  @override
  String? get currentUserId => 'user-a';

  final List<Map<String, dynamic>> createAssetCalls = [];
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
  }) => throw UnimplementedError();
}

class _RecordingLocalSyncStore implements LocalSyncStore {
  final List<String> reconciledAssetIds = [];

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
    });

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
  });
}
