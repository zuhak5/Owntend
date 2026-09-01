import 'package:owntend/src/core/data/repositories.dart';
import 'package:owntend/src/core/domain/contracts.dart';

extension MaintenanceTestCommands on DriftMaintenanceRepository {
  Future<LocalMaintenanceCompletionResult> completeCurrentOccurrence(
    String planId, {
    String? operationId,
    DateTime? completedAt,
    String? notes,
  }) async {
    final task = await getTask(planId);
    if (task == null) {
      return const LocalMaintenanceCompletionResult(
        status: LocalMaintenanceCompletionStatus.planUnavailable,
      );
    }
    return completePlanResult(
      planId,
      expectedOccurrenceId: task.plan.currentOccurrenceId,
      operationId: operationId,
      timeZoneId: 'UTC',
      completedAt: completedAt,
      notes: notes,
    );
  }
}
