import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:owntend/main.dart';
import 'package:owntend/src/core/domain/contracts.dart';
import 'package:owntend/src/features/maintenance/presentation/task_completion_controller.dart';

import 'support/widget_test_fakes.dart';

void main() {
  test('notes collection ownership is released on every cancellation path', () {
    final controller = TaskCompletionController(
      planId: 'plan-1',
      maintenanceRepo: FakeMaintenanceRepository(),
    );

    expect(controller.tryBeginNotesCollection(), isTrue);
    expect(controller.tryBeginNotesCollection(), isFalse);
    expect(controller.state.phase, TaskCompletionPhase.collectingNotes);

    controller.cancelNotesCollection();

    expect(controller.state.phase, TaskCompletionPhase.idle);
    expect(controller.tryBeginNotesCollection(), isTrue);
  });

  test('an active commit survives auto-disposed provider ownership', () async {
    final repository = _ControlledCompletionRepository();
    final container = ProviderContainer(
      overrides: [maintenanceRepositoryProvider.overrideWithValue(repository)],
    );
    final controller = container.read(
      taskCompletionControllerProvider('plan-1'),
    );

    final first = controller.complete(expectedOccurrenceId: 'occurrence-1');
    final overlapping = await controller.complete(
      expectedOccurrenceId: 'occurrence-1',
    );
    expect(overlapping.status, LocalMaintenanceCompletionStatus.failed);
    expect(overlapping.errorCode, 'completion_in_progress');
    expect(repository.completionCalls, 1);

    container.dispose();
    repository.completion.complete(
      const LocalMaintenanceCompletionResult(
        status: LocalMaintenanceCompletionStatus.appliedPendingSync,
        operationId: 'completion-1',
        completedOccurrenceId: 'occurrence-1',
        nextOccurrenceId: 'occurrence-2',
      ),
    );

    final result = await first;
    expect(result.isApplied, isTrue);
    expect(controller.state.phase, TaskCompletionPhase.completed);
  });

  test('repository failures remain typed and observable', () async {
    final failure = StateError('commit failed');
    final controller = TaskCompletionController(
      planId: 'plan-1',
      maintenanceRepo: _FailingCompletionRepository(failure),
    );

    final result = await controller.complete(
      expectedOccurrenceId: 'occurrence-1',
    );

    expect(result.status, LocalMaintenanceCompletionStatus.failed);
    expect(result.errorCode, 'StateError');
    expect(controller.state.phase, TaskCompletionPhase.failed);
    expect(controller.state.error, same(failure));
  });
}

class _ControlledCompletionRepository extends FakeMaintenanceRepository {
  final completion = Completer<LocalMaintenanceCompletionResult>();
  var completionCalls = 0;

  @override
  Future<LocalMaintenanceCompletionResult> completePlanResult(
    String planId, {
    required String expectedOccurrenceId,
    String? operationId,
    String timeZoneId = 'UTC',
    DateTime? completedAt,
    String? notes,
  }) {
    completionCalls++;
    return completion.future;
  }
}

class _FailingCompletionRepository extends FakeMaintenanceRepository {
  _FailingCompletionRepository(this.failure);

  final Object failure;

  @override
  Future<LocalMaintenanceCompletionResult> completePlanResult(
    String planId, {
    required String expectedOccurrenceId,
    String? operationId,
    String timeZoneId = 'UTC',
    DateTime? completedAt,
    String? notes,
  }) => Future.error(failure);
}
