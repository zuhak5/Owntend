import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

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

  Future<AssetCreationResult> createChargedAsset({
    required String assetId,
    required Map<String, dynamic> assetPayload,
    required Map<String, dynamic> detailsPayload,
    required String accountScope,
    String? operationIdOverride,
    List<Map<String, dynamic>> initialPlans = const [],
  }) async {
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
      'initial_plans': initialPlans,
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
          lastErrorCode: 'operation_id_reused',
          lastErrorMessage: 'OPERATION_ID_REUSED',
        ),
      );
      rethrow;
    } catch (error) {
      await operationStore.saveOperation(
        operation.copyWith(
          state: TaskCreationOperationState.outcomeUnknown,
          lastErrorMessage: error.toString(),
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
      operation.state == TaskCreationOperationState.outcomeUnknown;
}
