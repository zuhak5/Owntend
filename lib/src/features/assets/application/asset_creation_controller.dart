import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/domain/input_validation.dart';
import '../../../core/sync/sync_providers.dart';
import '../../maintenance/application/task_creation_controller.dart';
import '../../../core/services/charged_operation_journal/charged_operation_store.dart';
import '../../../core/services/charged_operation_journal/charged_operation_contracts.dart';
import '../../monetization/charged_operation_resolver.dart';
import '../../monetization/monetization.dart';

final assetCreationControllerProvider = Provider<AssetCreationController>((
  ref,
) {
  return AssetCreationController(ref: ref);
});

/// Application-layer controller for charged asset creation.
///
/// Mirrors [TaskCreationController]: the durable operation journal entry is
/// persisted BEFORE the network call so a process death between the server
/// point debit and the local write is recoverable through
/// [ChargedOperationResolver] at startup (F-001). The task operation store is
/// the shared charged-creation journal; its payload discriminator (`plan`
/// versus `asset`) selects the replay branch.
class AssetCreationResult {
  const AssetCreationResult({
    required this.assetId,
    required this.balance,
    required this.charged,
  });

  final String assetId;
  final int balance;
  final int charged;
}

class AssetCreationController {
  AssetCreationController({required this.ref});

  final Ref ref;
  static const _uuid = Uuid();

  Future<AuthoritativeMutationResult> changeAssetTypeWithPointDelta({
    required Map<String, dynamic> operation,
    required String accountScope,
  }) async {
    final monetizationRepo = ref.read(monetizationRepositoryProvider);
    if (monetizationRepo == null ||
        monetizationRepo.currentUserId != accountScope) {
      throw StateError('Cloud points service is unavailable.');
    }

    final result = await monetizationRepo.changeAssetType(operation);
    if (result.applied) {
      ref
          .read(pointWalletControllerProvider.notifier)
          .adoptAuthoritativeMutationResult(
            result.balance,
            userId: accountScope,
          );
    }
    return result;
  }

  Future<AssetCreationResult> createChargedAsset({
    required String assetId,
    required Map<String, dynamic> assetPayload,
    required Map<String, dynamic> detailsPayload,
    required String accountScope,
    String? operationIdOverride,
  }) async {
    validateAuthoritativeAssetPayload(assetPayload, detailsPayload);
    final monetizationRepo = ref.read(monetizationRepositoryProvider);
    if (monetizationRepo == null) {
      throw StateError('Cloud points service is unavailable.');
    }
    final localSyncStore = ref.read(localSyncStoreProvider);
    final operationStore = ref.read(taskCreationOperationStoreProvider);

    // A previously ambiguous charged operation must be resolved before a new
    // one can safely stack on top of it.
    await _recoverBeforeNewChargedOperation(
      operationStore: operationStore,
      accountScope: accountScope,
    );

    final operationId = operationIdOverride ?? _uuid.v7();
    final now = DateTime.now();

    final unsignedRequestPayload = <String, dynamic>{
      'operation_id': operationId,
      'asset': assetPayload,
      'details': detailsPayload,
      'initial_plans': const <Map<String, dynamic>>[],
    };
    final requestHash = sha256
        .convert(utf8.encode(jsonEncode(unsignedRequestPayload)))
        .toString();

    final operation = TaskCreationOperation(
      operationId: operationId,
      planId: assetId,
      accountScope: accountScope,
      requestPayload: {...unsignedRequestPayload, 'request_hash': requestHash},
      requestHash: requestHash,
      state: TaskCreationOperationState.submitting,
      createdAt: now,
      updatedAt: now,
    );

    // F-001: persist the journal BEFORE the network request so any outcome is
    // recoverable with the same idempotency key.
    await operationStore.saveOperation(operation);

    final PointDebitResult result;
    try {
      result = await monetizationRepo.createAsset(operation.requestPayload);
    } on InsufficientPointsException {
      await operationStore.saveOperation(
        operation.copyWith(
          state: TaskCreationOperationState.permanentRejected,
          requestPayload: const {},
          lastErrorCode: 'insufficient_points',
          lastErrorMessage: 'INSUFFICIENT_POINTS',
        ),
      );
      rethrow;
    } on OperationIdReusedException {
      await operationStore.saveOperation(
        operation.copyWith(
          state: TaskCreationOperationState.permanentRejected,
          requestPayload: const {},
          lastErrorCode: 'operation_id_reused',
          lastErrorMessage: 'OPERATION_ID_REUSED',
        ),
      );
      rethrow;
    } on AuthoritativeRpcRejectionException catch (error) {
      await operationStore.saveOperation(
        operation.copyWith(
          state: TaskCreationOperationState.permanentRejected,
          requestPayload: const {},
          lastErrorCode: error.journalCode,
          lastErrorMessage: error.serverCode,
        ),
      );
      rethrow;
    } catch (_) {
      await operationStore.saveOperation(
        operation.copyWith(
          state: TaskCreationOperationState.outcomeUnknown,
          lastErrorCode: 'transport_or_unknown',
          lastErrorMessage: 'TRANSPORT_OR_UNKNOWN',
        ),
      );
      throw StateError(
        'Charged asset creation outcome is unknown; recovery is journaled.',
      );
    }

    ref
        .read(pointWalletControllerProvider.notifier)
        .adoptAuthoritativeMutationResult(result.balance, userId: accountScope);

    // Apply the server-canonical composite before the journal turns terminal.
    if (localSyncStore != null && result.asset != null) {
      await localSyncStore.reconcileAssetCreationComposite(
        assetId: assetId,
        assetJson: result.asset,
      );
    }

    await operationStore.saveOperation(
      operation.copyWith(
        state: TaskCreationOperationState.reconciled,
        requestPayload: const {},
      ),
    );

    if (result.charged == 1) {
      unawaited(
        monetizationRepo.recordEvent('points_debited', {
          'entity_type': 'asset',
          'entity_id': assetId,
          'cost': result.charged,
          'new_balance': result.balance,
        }),
      );
    }

    return AssetCreationResult(
      assetId: assetId,
      balance: result.balance,
      charged: result.charged,
    );
  }

  Future<AssetCreationResult> copyOwnedAsset({
    required String sourceAssetId,
    required String targetAssetId,
    required String destinationRoomId,
    required bool includeTasks,
    required bool includePhotos,
    required Map<String, String> planIdMap,
    required String accountScope,
    required Future<void> Function() applyLocalCopy,
    String? operationIdOverride,
  }) async {
    final monetizationRepo = ref.read(monetizationRepositoryProvider);
    if (monetizationRepo == null ||
        monetizationRepo.currentUserId != accountScope) {
      throw StateError('Cloud points service is unavailable.');
    }
    final operationStore = ref.read(taskCreationOperationStoreProvider);
    final localSyncStore = ref.read(localSyncStoreProvider);
    await _recoverBeforeNewChargedOperation(
      operationStore: operationStore,
      accountScope: accountScope,
    );

    final operationId = operationIdOverride ?? _uuid.v7();
    final unsignedPayload = <String, dynamic>{
      'operation_id': operationId,
      'source_asset_id': sourceAssetId,
      'target_asset_id': targetAssetId,
      'destination_room_id': destinationRoomId,
      'include_tasks': includeTasks,
      'plan_id_map': planIdMap,
    };
    final requestHash = sha256
        .convert(utf8.encode(jsonEncode(unsignedPayload)))
        .toString();
    final now = DateTime.now();
    var operation = TaskCreationOperation(
      operationId: operationId,
      planId: targetAssetId,
      accountScope: accountScope,
      requestPayload: {
        ...unsignedPayload,
        'request_hash': requestHash,
        '_local_context': {'include_photos': includePhotos},
      },
      requestHash: requestHash,
      state: TaskCreationOperationState.submitting,
      createdAt: now,
      updatedAt: now,
    );
    await operationStore.saveOperation(operation);

    final AssetCopyResult result;
    try {
      result = await monetizationRepo.copyAsset(
        authoritativeAssetCopyPayload(operation.requestPayload),
      );
    } on OperationIdReusedException {
      await operationStore.saveOperation(
        operation.copyWith(
          state: TaskCreationOperationState.permanentRejected,
          requestPayload: const {},
          lastErrorCode: 'operation_id_reused',
          lastErrorMessage: 'OPERATION_ID_REUSED',
        ),
      );
      rethrow;
    } on AuthoritativeRpcRejectionException catch (error) {
      await operationStore.saveOperation(
        operation.copyWith(
          state: TaskCreationOperationState.permanentRejected,
          requestPayload: const {},
          lastErrorCode: error.journalCode,
          lastErrorMessage: error.serverCode,
        ),
      );
      rethrow;
    } on Object catch (_) {
      await operationStore.saveOperation(
        operation.copyWith(
          state: TaskCreationOperationState.outcomeUnknown,
          lastErrorCode: 'transport_or_unknown',
          lastErrorMessage: 'TRANSPORT_OR_UNKNOWN',
        ),
      );
      throw StateError('Asset copy outcome is unknown; recovery is journaled.');
    }

    operation = operation.copyWith(
      state: TaskCreationOperationState.serverAcceptedNeedsReconcile,
      updatedAt: DateTime.now(),
    );
    await operationStore.saveOperation(operation);
    ref
        .read(pointWalletControllerProvider.notifier)
        .adoptAuthoritativeMutationResult(result.balance, userId: accountScope);

    await applyLocalCopy();
    if (localSyncStore != null) {
      await localSyncStore.reconcileAssetCopyComposite(
        assetId: targetAssetId,
        assetJson: result.asset,
        plans: result.plans,
        planMetadata: result.planMetadata,
        detailRows: result.detailRows,
      );
    }
    await operationStore.saveOperation(
      operation.copyWith(
        state: TaskCreationOperationState.reconciled,
        requestPayload: const {},
        updatedAt: DateTime.now(),
      ),
    );
    return AssetCreationResult(
      assetId: targetAssetId,
      balance: result.balance,
      charged: result.charged,
    );
  }

  Future<void> _recoverBeforeNewChargedOperation({
    required TaskCreationOperationStore operationStore,
    required String accountScope,
  }) async {
    final before = await operationStore.listOperationsForAccount(accountScope);
    final recoverable = before.where(_isRecoverableChargedOperation).toList();
    if (recoverable.isEmpty) return;

    final resolver = ref.read(chargedOperationResolverProvider);
    if (resolver == null) {
      throw StateError(
        'A previous charged operation must be recovered before creating another one.',
      );
    }

    await resolver.resolvePendingOperations(accountScope);
    final after = await operationStore.listOperationsForAccount(accountScope);
    if (after.any(_isRecoverableChargedOperation)) {
      throw StateError(
        'A previous charged operation is still awaiting recovery.',
      );
    }
  }

  bool _isRecoverableChargedOperation(TaskCreationOperation operation) =>
      operation.state == TaskCreationOperationState.submitting ||
      operation.state == TaskCreationOperationState.outcomeUnknown ||
      operation.state ==
          TaskCreationOperationState.serverAcceptedNeedsReconcile;
}
