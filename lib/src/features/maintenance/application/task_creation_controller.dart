import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

import '../../../core/domain/models.dart';
import '../../../core/sync/sync_providers.dart';
import '../../monetization/charged_operation_resolver.dart';
import '../../monetization/monetization.dart';
import '../data/task_creation_operation_store.dart';
import '../domain/task_creation.dart';

class TaskCreationState {
  const TaskCreationState({
    this.isSubmitting = false,
    this.failure,
    this.completedPlanId,
    this.returnedBalance,
  });

  final bool isSubmitting;
  final TaskCreationFailure? failure;
  final String? completedPlanId;
  final int? returnedBalance;

  TaskCreationState copyWith({
    bool? isSubmitting,
    TaskCreationFailure? failure,
    String? completedPlanId,
    int? returnedBalance,
  }) {
    return TaskCreationState(
      isSubmitting: isSubmitting ?? this.isSubmitting,
      failure: failure,
      completedPlanId: completedPlanId ?? this.completedPlanId,
      returnedBalance: returnedBalance ?? this.returnedBalance,
    );
  }
}

final taskCreationOperationStoreProvider = Provider<TaskCreationOperationStore>(
  (ref) {
    return TaskCreationOperationStore(storage: const FlutterSecureStorage());
  },
);

final chargedOperationResolverProvider = Provider<ChargedOperationResolver?>((
  ref,
) {
  final monetizationRepo = ref.watch(monetizationRepositoryProvider);
  final localSyncStore = ref.watch(localSyncStoreProvider);
  if (monetizationRepo == null || localSyncStore == null) return null;
  return ChargedOperationResolver(
    monetizationRepo: monetizationRepo,
    localSyncStore: localSyncStore,
    operationStore: ref.watch(taskCreationOperationStoreProvider),
  );
});

final taskCreationControllerProvider = Provider<TaskCreationController>((ref) {
  return TaskCreationController(ref: ref);
});

class TaskCreationController extends ValueNotifier<TaskCreationState> {
  TaskCreationController({required this.ref})
    : super(const TaskCreationState());

  final Ref ref;
  static const _uuid = Uuid();

  Future<bool> createNewTask({
    required String assetId,
    required String title,
    String? instructions,
    required RecurrenceRule recurrence,
    required PriorityLevel priority,
    required DateTime nextDueDate,
    required HealthGroup healthGroup,
    int reminderDaysBefore = 0,
    TaskMetadata? metadata,
    required String accountScope,
    TaskCreationOperation? existingOperation,
  }) async {
    if (value.isSubmitting) return false;
    value = value.copyWith(isSubmitting: true);

    try {
      final monetizationRepo = ref.read(monetizationRepositoryProvider);
      final localSyncStore = ref.read(localSyncStoreProvider);
      final operationStore = ref.read(taskCreationOperationStoreProvider);

      if (existingOperation == null && monetizationRepo != null) {
        await _recoverBeforeNewChargedOperation(
          operationStore: operationStore,
          accountScope: accountScope,
        );
      }

      final operationId = existingOperation?.operationId ?? _uuid.v7();
      final planId = existingOperation?.planId ?? _uuid.v7();
      final now = DateTime.now();

      final planPayload = {
        'id': planId,
        'asset_id': assetId.trim(),
        'title': title.trim(),
        if (instructions != null && instructions.trim().isNotEmpty)
          'instructions': instructions.trim(),
        'recurrence_interval': recurrence.interval,
        'recurrence_unit': recurrence.unit.name,
        'priority': priority.name,
        'next_due_date': nextDueDate.toUtc().toIso8601String(),
        'reminder_days_before': reminderDaysBefore,
        'health_group': healthGroup.name,
        'is_enabled': true,
      };

      final metadataPayload = metadata != null
          ? {
              if (metadata.taskType != null &&
                  metadata.taskType!.trim().isNotEmpty)
                'task_type': metadata.taskType!.trim(),
              if (metadata.locationLabel != null &&
                  metadata.locationLabel!.trim().isNotEmpty)
                'location_label': metadata.locationLabel!.trim(),
              if (metadata.estimatedDurationMinutes != null)
                'estimated_duration_minutes': metadata.estimatedDurationMinutes,
              'required_materials': metadata.requiredMaterials,
              if (metadata.reminderRecommendation != null &&
                  metadata.reminderRecommendation!.trim().isNotEmpty)
                'reminder_recommendation': metadata.reminderRecommendation!
                    .trim(),
              'sort_order': metadata.sortOrder,
            }
          : <String, dynamic>{};

      final unsignedRequestPayload = {
        'operation_id': operationId,
        'plan': planPayload,
        'metadata': metadataPayload,
      };
      final computedRequestHash = sha256
          .convert(utf8.encode(jsonEncode(unsignedRequestPayload)))
          .toString();

      final Map<String, dynamic> requestPayload;
      final String requestHash;
      if (existingOperation != null) {
        if (existingOperation.accountScope != accountScope ||
            existingOperation.requestPayload.isEmpty ||
            existingOperation.requestPayload['request_hash'] !=
                existingOperation.requestHash) {
          throw const TaskCreationFailure(
            'The retained charged operation cannot be replayed safely.',
            code: TaskCreationFailureCode.operationIdReused,
          );
        }
        requestHash = existingOperation.requestHash;
        requestPayload = Map<String, dynamic>.from(
          existingOperation.requestPayload,
        );
      } else {
        requestHash = computedRequestHash;
        requestPayload = {
          ...unsignedRequestPayload,
          'request_hash': requestHash,
        };
      }

      final operation = TaskCreationOperation(
        operationId: operationId,
        planId: planId,
        accountScope: accountScope,
        requestPayload: requestPayload,
        requestHash: requestHash,
        state: TaskCreationOperationState.submitting,
        createdAt: existingOperation?.createdAt ?? now,
        updatedAt: now,
      );

      // CTC-002: Persist operation BEFORE network request.
      await operationStore.saveOperation(operation);

      if (monetizationRepo != null) {
        final PointDebitResult result;
        try {
          result = await monetizationRepo.createTask(requestPayload);
        } on InsufficientPointsException {
          await operationStore.saveOperation(
            operation.copyWith(
              state: TaskCreationOperationState.permanentRejected,
              requestPayload: const {},
              lastErrorCode: 'insufficient_points',
              lastErrorMessage: 'INSUFFICIENT_POINTS',
            ),
          );
          throw const TaskCreationFailure(
            'INSUFFICIENT_POINTS',
            code: TaskCreationFailureCode.insufficientPoints,
          );
        } on OperationIdReusedException {
          await operationStore.saveOperation(
            operation.copyWith(
              state: TaskCreationOperationState.permanentRejected,
              lastErrorCode: 'operation_id_reused',
              lastErrorMessage: 'OPERATION_ID_REUSED',
            ),
          );
          throw const TaskCreationFailure(
            'OPERATION_ID_REUSED',
            code: TaskCreationFailureCode.operationIdReused,
          );
        } catch (e) {
          final updatedOp = operation.copyWith(
            state: TaskCreationOperationState.outcomeUnknown,
            lastErrorMessage: e.toString(),
          );
          await operationStore.saveOperation(updatedOp);
          throw const TaskCreationFailure(
            'Network request failed or timed out. Outcome is preserved for safe retry.',
            code: TaskCreationFailureCode.networkTimeout,
          );
        }

        // CTC-006 & CTC-007: Reconcile canonical creation composite before
        // the durable operation journal is made terminal.
        if (localSyncStore != null) {
          await localSyncStore.reconcileTaskCreationComposite(
            planId: planId,
            planJson: result.plan,
            metadataJson: result.metadata,
          );
        }

        final reconciledOp = operation.copyWith(
          state: TaskCreationOperationState.reconciled,
          requestPayload: const {},
        );
        await operationStore.saveOperation(reconciledOp);

        value = TaskCreationState(
          isSubmitting: false,
          completedPlanId: planId,
          returnedBalance: result.balance,
        );
      } else {
        value = TaskCreationState(isSubmitting: false, completedPlanId: planId);
      }
      return true;
    } on TaskCreationFailure catch (failure) {
      value = value.copyWith(isSubmitting: false, failure: failure);
      return false;
    } catch (e) {
      value = value.copyWith(
        isSubmitting: false,
        failure: TaskCreationFailure(
          e.toString(),
          code: TaskCreationFailureCode.unknown,
        ),
      );
      return false;
    }
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
      throw const TaskCreationFailure(
        'A previous charged operation must be recovered before creating another task.',
        code: TaskCreationFailureCode.serverError,
      );
    }

    await resolver.resolvePendingOperations(accountScope);
    final after = await operationStore.listOperationsForAccount(accountScope);
    if (after.any(_isRecoverableChargedOperation)) {
      throw const TaskCreationFailure(
        'A previous charged operation is still awaiting recovery. Try again after connectivity is restored.',
        code: TaskCreationFailureCode.networkTimeout,
      );
    }

    throw const TaskCreationFailure(
      'A previous charged operation was recovered. Review its result before creating another charged task.',
      code: TaskCreationFailureCode.serverError,
    );
  }

  bool _isRecoverableChargedOperation(TaskCreationOperation operation) =>
      operation.state == TaskCreationOperationState.submitting ||
      operation.state == TaskCreationOperationState.outcomeUnknown;
}
