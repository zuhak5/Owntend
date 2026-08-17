import '../../core/sync/local_sync_store.dart';
import '../maintenance/data/task_creation_operation_store.dart';
import '../maintenance/domain/task_creation.dart';
import 'monetization.dart';

class ChargedOperationResolver {
  ChargedOperationResolver({
    required this.monetizationRepo,
    required this.localSyncStore,
    required this.operationStore,
  });

  final MonetizationRepository monetizationRepo;
  final LocalSyncStore localSyncStore;
  final TaskCreationOperationStore operationStore;

  Future<void> resolvePendingOperations(String accountScope) async {
    if (!_accountIsCurrent(accountScope)) return;

    final operations = await operationStore.listOperationsForAccount(
      accountScope,
    );
    for (final op in operations) {
      if (op.state != TaskCreationOperationState.outcomeUnknown &&
          op.state != TaskCreationOperationState.submitting) {
        continue;
      }
      if (!_accountIsCurrent(accountScope)) return;

      if (op.requestHash.trim().isEmpty ||
          op.requestPayload['request_hash'] != op.requestHash) {
        await operationStore.saveOperation(
          op.copyWith(
            state: TaskCreationOperationState.permanentRejected,
            updatedAt: DateTime.now(),
            lastErrorCode: 'unqualified_request_hash',
            lastErrorMessage:
                'The retained charged operation is not hash-qualified.',
          ),
        );
        continue;
      }

      try {
        final status = await monetizationRepo.getChargedOperationStatus(
          op.operationId,
          requestHash: op.requestHash,
        );
        if (!_accountIsCurrent(accountScope)) return;

        if (status.status == 'completed') {
          final expectsTask = op.requestPayload.containsKey('plan');
          final expectedType = expectsTask ? 'task' : 'asset';
          if (status.entityType != expectedType ||
              status.entityId != op.planId) {
            await operationStore.saveOperation(
              op.copyWith(
                state: TaskCreationOperationState.permanentRejected,
                updatedAt: DateTime.now(),
                lastErrorCode: 'operation_identity_mismatch',
                lastErrorMessage:
                    'Recovered operation identity did not match the local request.',
              ),
            );
            continue;
          }
          if (op.requestPayload.containsKey('plan') || status.plan != null) {
            await localSyncStore.reconcileTaskCreationComposite(
              planId: op.planId,
              planJson: status.plan,
              metadataJson: status.metadata,
            );
          } else if (op.requestPayload.containsKey('asset') ||
              status.asset != null) {
            await localSyncStore.reconcileAssetCreationComposite(
              assetId: status.entityId ?? op.planId,
              assetJson: status.asset,
            );
          }
          if (!_accountIsCurrent(accountScope)) return;
          await operationStore.saveOperation(
            op.copyWith(
              state: TaskCreationOperationState.reconciled,
              requestPayload: const {},
              updatedAt: DateTime.now(),
            ),
          );
        } else if (status.status == 'not_found') {
          if (status.capabilityVersion == '1.2.0' &&
              op.requestPayload.isNotEmpty) {
            try {
              if (op.requestPayload.containsKey('plan')) {
                final result = await monetizationRepo.createTask(
                  op.requestPayload,
                );
                if (!_accountIsCurrent(accountScope)) return;
                await localSyncStore.reconcileTaskCreationComposite(
                  planId: op.planId,
                  planJson: result.plan,
                  metadataJson: result.metadata,
                );
              } else if (op.requestPayload.containsKey('asset')) {
                final result = await monetizationRepo.createAsset(
                  op.requestPayload,
                );
                if (!_accountIsCurrent(accountScope)) return;
                await localSyncStore.reconcileAssetCreationComposite(
                  assetId: op.planId,
                  assetJson: result.asset,
                );
              }
              if (!_accountIsCurrent(accountScope)) return;
              await operationStore.saveOperation(
                op.copyWith(
                  state: TaskCreationOperationState.reconciled,
                  requestPayload: const {},
                  updatedAt: DateTime.now(),
                ),
              );
            } on InsufficientPointsException {
              await operationStore.saveOperation(
                op.copyWith(
                  state: TaskCreationOperationState.permanentRejected,
                  requestPayload: const {},
                  updatedAt: DateTime.now(),
                  lastErrorCode: 'insufficient_points',
                  lastErrorMessage: 'INSUFFICIENT_POINTS',
                ),
              );
            } on OperationIdReusedException {
              await _markOperationIdConflict(op);
            } on Object catch (error) {
              await _markOutcomeUnknown(op, error);
            }
          }
        }
      } on OperationIdReusedException {
        await _markOperationIdConflict(op);
      } on Object catch (error) {
        await _markOutcomeUnknown(op, error);
      }
    }
    await operationStore.purgeTerminalPayloads(accountScope);
  }

  bool _accountIsCurrent(String accountScope) =>
      monetizationRepo.currentUserId == accountScope;

  Future<void> _markOperationIdConflict(TaskCreationOperation op) {
    return operationStore.saveOperation(
      op.copyWith(
        state: TaskCreationOperationState.permanentRejected,
        updatedAt: DateTime.now(),
        lastErrorCode: 'operation_id_reused',
        lastErrorMessage: 'OPERATION_ID_REUSED',
      ),
    );
  }

  Future<void> _markOutcomeUnknown(
    TaskCreationOperation op,
    Object error,
  ) {
    return operationStore.saveOperation(
      op.copyWith(
        state: TaskCreationOperationState.outcomeUnknown,
        updatedAt: DateTime.now(),
        lastErrorCode: 'recovery_retryable',
        lastErrorMessage: error.toString(),
      ),
    );
  }
}
