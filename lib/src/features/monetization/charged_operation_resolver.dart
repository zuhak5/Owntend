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
    final operations = await operationStore.listOperationsForAccount(
      accountScope,
    );
    for (final op in operations) {
      if (op.state == TaskCreationOperationState.outcomeUnknown ||
          op.state == TaskCreationOperationState.submitting) {
        try {
          final status = await monetizationRepo.getChargedOperationStatus(
            op.operationId,
          );
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
                  lastErrorMessage: 'Recovered operation identity did not match the local request.',
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
            final reconciledOp = op.copyWith(
              state: TaskCreationOperationState.reconciled,
              requestPayload: const {},
              updatedAt: DateTime.now(),
            );
            await operationStore.saveOperation(reconciledOp);
          } else if (status.status == 'not_found') {
            // Capability version '1.1.0' confirms the server never received/committed this operation.
            // Resubmit using the exact same operationId and payload.
            if (status.capabilityVersion == '1.1.0' &&
                op.requestPayload.isNotEmpty) {
              try {
                if (op.requestPayload.containsKey('plan')) {
                  final result = await monetizationRepo.createTask(
                    op.requestPayload,
                  );
                  await localSyncStore.reconcileTaskCreationComposite(
                    planId: op.planId,
                    planJson: result.plan,
                    metadataJson: result.metadata,
                  );
                } else if (op.requestPayload.containsKey('asset')) {
                  final result = await monetizationRepo.createAsset(
                    op.requestPayload,
                  );
                  await localSyncStore.reconcileAssetCreationComposite(
                    assetId: op.planId,
                    assetJson: result.asset,
                  );
                }
                final reconciledOp = op.copyWith(
                  state: TaskCreationOperationState.reconciled,
                  requestPayload: const {},
                  updatedAt: DateTime.now(),
                );
                await operationStore.saveOperation(reconciledOp);
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
              } catch (_) {
                // Keep as outcomeUnknown for future retry
              }
            }
          }
        } catch (_) {
          // Keep as outcomeUnknown on transient error
        }
      }
    }
    await operationStore.purgeTerminalPayloads(accountScope);
  }
}
