import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/data/repositories.dart';
import '../../../core/domain/contracts.dart';

enum TaskCompletionPhase {
  idle,
  collectingNotes,
  committingLocal,
  reconcilingReminder,
  completed,
  failed,
}

class TaskCompletionState {
  const TaskCompletionState({
    this.phase = TaskCompletionPhase.idle,
    this.result,
    this.error,
  });

  final TaskCompletionPhase phase;
  final LocalMaintenanceCompletionResult? result;
  final Object? error;

  bool get isInProgress =>
      phase == TaskCompletionPhase.collectingNotes ||
      phase == TaskCompletionPhase.committingLocal ||
      phase == TaskCompletionPhase.reconcilingReminder;
}

final taskCompletionControllerProvider =
    Provider.family<TaskCompletionController, String>((ref, planId) {
      return TaskCompletionController(
        planId: planId,
        maintenanceRepo: ref.watch(maintenanceRepositoryProvider),
      );
    });

class TaskCompletionController extends ValueNotifier<TaskCompletionState> {
  TaskCompletionController({
    required this.planId,
    required this.maintenanceRepo,
  }) : super(const TaskCompletionState());

  final String planId;
  final MaintenanceRepository maintenanceRepo;

  bool tryBeginNotesCollection() {
    if (value.isInProgress) return false;
    value = const TaskCompletionState(
      phase: TaskCompletionPhase.collectingNotes,
    );
    return true;
  }

  void cancelNotesCollection() {
    if (value.phase == TaskCompletionPhase.collectingNotes) {
      value = const TaskCompletionState(phase: TaskCompletionPhase.idle);
    }
  }

  Future<LocalMaintenanceCompletionResult> complete({
    DateTime? completedAt,
    String? notes,
    DateTime? expectedNextDueDate,
  }) async {
    if (value.phase == TaskCompletionPhase.committingLocal ||
        value.phase == TaskCompletionPhase.reconcilingReminder) {
      return value.result ??
          const LocalMaintenanceCompletionResult(
            status: LocalMaintenanceCompletionStatus.occurrenceChanged,
          );
    }
    value = const TaskCompletionState(
      phase: TaskCompletionPhase.committingLocal,
    );

    try {
      final result = await maintenanceRepo.completePlanResult(
        planId,
        completedAt: completedAt,
        notes: notes,
        expectedNextDueDate: expectedNextDueDate,
      );

      if (result.isApplied) {
        value = TaskCompletionState(
          phase: TaskCompletionPhase.completed,
          result: result,
        );
      } else {
        value = TaskCompletionState(
          phase: TaskCompletionPhase.failed,
          result: result,
        );
      }
      return result;
    } catch (e) {
      final failResult = LocalMaintenanceCompletionResult(
        status: LocalMaintenanceCompletionStatus.occurrenceChanged,
      );
      value = TaskCompletionState(
        phase: TaskCompletionPhase.failed,
        result: failResult,
        error: e,
      );
      return failResult;
    }
  }
}
