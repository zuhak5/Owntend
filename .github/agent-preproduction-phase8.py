from pathlib import Path

repo_path = Path('lib/src/core/data/maintenance_repository.dart')
text = repo_path.read_text()
old_fields = """  final AppDatabase db;
  final RecurrenceEngine _recurrenceEngine;
  final DateTime Function() _now;
  static const _completionDuplicateWindow = Duration(seconds: 4);
"""
new_fields = """  final AppDatabase db;
  final RecurrenceEngine _recurrenceEngine;
  final DateTime Function() _now;
  static const _completionDuplicateWindow = Duration(seconds: 4);
  final Map<String, DateTime> _lastCompletionActionAt = {};
  final Map<String, LocalMaintenanceCompletionResult> _lastCompletionResult = {};
"""
if old_fields not in text:
    raise SystemExit('repository fields did not match')
text = text.replace(old_fields, new_fields, 1)

old_block = """      final canonicalExpectedNextDue = expectedNextDueDate != null
          ? canonicalSyncSecond(expectedNextDueDate)
          : null;
      final canonicalPlanNextDue = canonicalSyncSecond(plan.nextDueDate);

      if (canonicalExpectedNextDue != null &&
          !canonicalPlanNextDue.isAtSameMomentAs(canonicalExpectedNextDue)) {
        return const LocalMaintenanceCompletionResult(
          status: LocalMaintenanceCompletionStatus.occurrenceChanged,
        );
      }

      final completionInstant = completedAt ?? _now();
      final completed = canonicalSyncSecond(completionInstant);
      final previousDueDate = canonicalPlanNextDue;

      final latestRecord =
          await (db.select(db.maintenanceRecords)
                ..where((record) => record.planId.equals(planId))
                ..orderBy([
                  (record) => OrderingTerm.desc(record.completedAt),
                  (record) => OrderingTerm.desc(record.id),
                ])
                ..limit(1))
              .getSingleOrNull();
      if (latestRecord != null) {
        final sinceLatest = completed.difference(
          canonicalSyncSecond(latestRecord.completedAt),
        );
        if (sinceLatest.compareTo(Duration.zero) >= 0 &&
            sinceLatest.compareTo(_completionDuplicateWindow) < 0) {
          return LocalMaintenanceCompletionResult(
            status: LocalMaintenanceCompletionStatus.applied,
            operationId: latestRecord.id,
            previousDueDate: canonicalSyncSecond(latestRecord.dueDate),
            nextDueDate: canonicalPlanNextDue,
            duplicateIgnored: true,
          );
        }
      }

      final nextDue = canonicalSyncSecond(
"""
new_block = """      final actionAt = _now();
      final lastActionAt = _lastCompletionActionAt[planId];
      final lastResult = _lastCompletionResult[planId];
      if (lastActionAt != null && lastResult != null) {
        final sinceLastAction = actionAt.difference(lastActionAt);
        if (!sinceLastAction.isNegative &&
            sinceLastAction < _completionDuplicateWindow) {
          return LocalMaintenanceCompletionResult(
            status: lastResult.status,
            operationId: lastResult.operationId,
            previousDueDate: lastResult.previousDueDate,
            nextDueDate: lastResult.nextDueDate,
            duplicateIgnored: true,
          );
        }
      }

      final canonicalExpectedNextDue = expectedNextDueDate != null
          ? canonicalSyncSecond(expectedNextDueDate)
          : null;
      final canonicalPlanNextDue = canonicalSyncSecond(plan.nextDueDate);

      if (canonicalExpectedNextDue != null &&
          !canonicalPlanNextDue.isAtSameMomentAs(canonicalExpectedNextDue)) {
        return const LocalMaintenanceCompletionResult(
          status: LocalMaintenanceCompletionStatus.occurrenceChanged,
        );
      }

      final completionInstant = completedAt ?? actionAt;
      final completed = canonicalSyncSecond(completionInstant);
      final previousDueDate = canonicalPlanNextDue;

      final nextDue = canonicalSyncSecond(
"""
if old_block not in text:
    raise SystemExit('old duplicate guard block did not match')
text = text.replace(old_block, new_block, 1)
text = text.replace(
    """      final planUpdatedAt = canonicalSyncSecond(_now());
""",
    """      final planUpdatedAt = canonicalSyncSecond(actionAt);
""",
    1,
)
old_return = """      return LocalMaintenanceCompletionResult(
        status: LocalMaintenanceCompletionStatus.applied,
        operationId: completionId,
        previousDueDate: previousDueDate,
        nextDueDate: nextDue,
      );
"""
new_return = """      final result = LocalMaintenanceCompletionResult(
        status: LocalMaintenanceCompletionStatus.applied,
        operationId: completionId,
        previousDueDate: previousDueDate,
        nextDueDate: nextDue,
      );
      _lastCompletionActionAt[planId] = actionAt;
      _lastCompletionResult[planId] = result;
      return result;
"""
if old_return not in text:
    raise SystemExit('completion return block did not match')
text = text.replace(old_return, new_return, 1)
repo_path.write_text(text)

test_path = Path('test/recurring_completion_precision_test.dart')
test = test_path.read_text()
old_test_open = """  test(
    'rapid repeated completions are idempotent but a later completion is allowed',
    () async {
"""
new_test_open = """  test(
    'rapid repeated completions use the action clock while a later action is allowed',
    () async {
      var actionNow = DateTime(2026, 8, 16, 14, 30, 10);
      final guardedMaintenance = DriftMaintenanceRepository(
        db,
        now: () => actionNow,
      );
"""
if old_test_open not in test:
    raise SystemExit('rapid test opening did not match')
test = test.replace(old_test_open, new_test_open, 1)
# Limit replacements to the rapid test slice.
start = test.index(new_test_open)
end_marker = "\n  test('completion recurrence matrix anchors every supported unit to completedAt'"
end = test.index(end_marker, start)
slice_text = test[start:end]
slice_text = slice_text.replace('maintenance.savePlan(', 'guardedMaintenance.savePlan(')
slice_text = slice_text.replace('maintenance.completePlanResult(', 'guardedMaintenance.completePlanResult(')
slice_text = slice_text.replace('maintenance.listRecordsForPlan(', 'guardedMaintenance.listRecordsForPlan(')
slice_text = slice_text.replace('maintenance.getTask(', 'guardedMaintenance.getTask(')
# Advance action clock independently before each duplicate invocation.
old_loop = """      for (var i = 1; i <= 4; i++) {
        final repeat = await guardedMaintenance.completePlanResult(
          planId,
          completedAt: firstAt.add(Duration(milliseconds: 500 * i)),
          expectedNextDueDate: first.nextDueDate,
        );
"""
new_loop = """      for (var i = 1; i <= 4; i++) {
        actionNow = firstAt.add(Duration(milliseconds: 500 * i));
        final repeat = await guardedMaintenance.completePlanResult(
          planId,
          completedAt: i == 2
              ? firstAt.add(const Duration(hours: 1))
              : firstAt.add(Duration(milliseconds: 500 * i)),
          expectedNextDueDate: first.nextDueDate,
        );
"""
if old_loop not in slice_text:
    raise SystemExit('rapid test loop did not match')
slice_text = slice_text.replace(old_loop, new_loop, 1)
old_after = """      final afterWindowAt = firstAt.add(const Duration(seconds: 5));
      final second = await guardedMaintenance.completePlanResult(
"""
new_after = """      final afterWindowAt = firstAt.add(const Duration(seconds: 5));
      actionNow = afterWindowAt;
      final second = await guardedMaintenance.completePlanResult(
"""
if old_after not in slice_text:
    raise SystemExit('after-window test block did not match')
slice_text = slice_text.replace(old_after, new_after, 1)
test = test[:start] + slice_text + test[end:]
test_path.write_text(test)
