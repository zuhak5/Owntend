import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

import '../../../core/domain/models.dart';
import '../../../core/sync/sync_providers.dart';
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

      final requestPayload = {
        'operation_id': operationId,
        'plan': planPayload,
        'metadata': metadataPayload,
      };

      final payloadString = jsonEncode(requestPayload);
      final requestHash = sha256.convert(utf8.encode(payloadString)).toString();

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

      // CTC-002: Persist operation BEFORE network request
      await operationStore.saveOperation(operation);

      if (monetizationRepo != null) {
        // Submit RPC to server
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
          throw TaskCreationFailure(
            'INSUFFICIENT_POINTS',
            code: TaskCreationFailureCode.insufficientPoints,
          );
        } catch (e) {
          // CTR-001: Timeout or network failure -> mark outcomeUnknown
          final updatedOp = operation.copyWith(
            state: TaskCreationOperationState.outcomeUnknown,
            lastErrorMessage: e.toString(),
          );
          await operationStore.saveOperation(updatedOp);
          throw TaskCreationFailure(
            'Network request failed or timed out. Outcome is preserved for safe retry.',
            code: TaskCreationFailureCode.networkTimeout,
          );
        }

        // CTC-006 & CTC-007: Reconcile canonical creation composite
        if (localSyncStore != null) {
          await localSyncStore.reconcileTaskCreationComposite(
            planId: planId,
            planJson: result.plan,
            metadataJson: result.metadata,
          );
        }

        // Mark operation reconciled and purge payload
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
}
