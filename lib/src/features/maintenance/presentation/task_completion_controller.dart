import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/data/repositories.dart';
import '../../../core/domain/contracts.dart';

enum TaskCompletionPhase {
  idle,
  collectingNotes,
  committingLocal,
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
      phase == TaskCompletionPhase.committingLocal;
}

final taskCompletionControllerProvider = Provider.autoDispose
    .family<TaskCompletionController, String>((ref, planId) {
      final controller = TaskCompletionController(
        planId: planId,
        maintenanceRepo: ref.watch(maintenanceRepositoryProvider),
      );
      return controller;
    });

class TaskCompletionController {
  TaskCompletionController({
    required this.planId,
    required this.maintenanceRepo,
  });

  final String planId;
  final MaintenanceRepository maintenanceRepo;
  TaskCompletionState _state = const TaskCompletionState();

  TaskCompletionState get state => _state;

  bool tryBeginNotesCollection() {
    if (_state.isInProgress) return false;
    _state = const TaskCompletionState(
      phase: TaskCompletionPhase.collectingNotes,
    );
    return true;
  }

  void cancelNotesCollection() {
    if (_state.phase == TaskCompletionPhase.collectingNotes) {
      _state = const TaskCompletionState(phase: TaskCompletionPhase.idle);
    }
  }

  Future<LocalMaintenanceCompletionResult> complete({
    required String expectedOccurrenceId,
    String timeZoneId = 'UTC',
    DateTime? completedAt,
    String? notes,
  }) async {
    if (_state.phase == TaskCompletionPhase.committingLocal) {
      return _state.result ??
          const LocalMaintenanceCompletionResult(
            status: LocalMaintenanceCompletionStatus.failed,
            errorCode: 'completion_in_progress',
          );
    }
    _state = const TaskCompletionState(
      phase: TaskCompletionPhase.committingLocal,
    );

    try {
      final result = await maintenanceRepo.completePlanResult(
        planId,
        expectedOccurrenceId: expectedOccurrenceId,
        timeZoneId: timeZoneId,
        completedAt: completedAt,
        notes: notes,
      );

      if (result.isApplied) {
        _state = TaskCompletionState(
          phase: TaskCompletionPhase.completed,
          result: result,
        );
      } else {
        _state = TaskCompletionState(
          phase: TaskCompletionPhase.failed,
          result: result,
        );
      }
      return result;
    } catch (e) {
      final failResult = LocalMaintenanceCompletionResult(
        status: LocalMaintenanceCompletionStatus.failed,
        errorCode: e.runtimeType.toString(),
      );
      _state = TaskCompletionState(
        phase: TaskCompletionPhase.failed,
        result: failResult,
        error: e,
      );
      return failResult;
    }
  }
}
