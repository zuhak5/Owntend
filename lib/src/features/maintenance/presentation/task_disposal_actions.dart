import '../../../ui/components.dart' as hk_ui;
import '../../monetization/monetization.dart';
import '../../../ui/presentation_support.dart';
import 'task_actions.dart';

/// WP-009 (F-017): task disposal actions moved out of the trash feature so
/// maintenance and trash no longer import each other. Trash consumes these
/// through the single remaining trash→maintenance edge.
Future<bool> confirmPermanentDelete(
  BuildContext context, {
  required String title,
  required String message,
  String? actionLabel,
}) async {
  final confirmed = await runWithNativeAdsSuspended(
    context,
    () => showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        actionsOverflowButtonSpacing: HkSpacing.xs,
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.l10n.cancel),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(Symbols.delete_rounded),
            label: Text(actionLabel ?? context.l10n.delete),
          ),
        ],
      ),
    ),
  );
  return confirmed == true;
}

Future<bool> deleteTaskWithConfirmation(
  BuildContext context,
  WidgetRef ref,
  TaskItem task,
) async {
  final confirmed = await confirmPermanentDelete(
    context,
    title: context.l10n.moveTaskToTrash2,
    message: context.l10n.moveTaskToTrashMessage(task.plan.title),
    actionLabel: context.l10n.moveToTrash,
  );
  if (!confirmed || !context.mounted) {
    return false;
  }
  return moveTaskToTrashWithUndo(context, ref, task);
}

Future<bool> moveTaskToTrashWithUndo(
  BuildContext context,
  WidgetRef ref,
  TaskItem task,
) async {
  try {
    await ref.read(maintenanceRepositoryProvider).archivePlan(task.plan.id);
  } on Object catch (error) {
    if (context.mounted) {
      hk_ui.showToast(
        context,
        content: Text(
          failureMessage(context, error, fallback: AppFailureCode.taskUpdate),
        ),
        severity: hk_ui.HkToastSeverity.error,
      );
    }
    return false;
  }
  await wakeNotificationReconciliation(ref);
  if (!context.mounted) {
    return true;
  }
  hk_ui.showTaskMovedToTrashSnackBar(
    context,
    duration: const Duration(seconds: 5),
    onUndo: () async {
      try {
        await ref.read(maintenanceRepositoryProvider).restorePlan(task.plan.id);
        await wakeNotificationReconciliation(ref);
        if (context.mounted) {
          hk_ui.showToast(context, content: Text(context.l10n.taskRestored));
        }
      } on Object catch (error) {
        if (context.mounted) {
          hk_ui.showToast(
            context,
            content: Text(
              failureMessage(context, error, fallback: AppFailureCode.undo),
            ),
            severity: hk_ui.HkToastSeverity.error,
          );
        }
      }
    },
  );
  return true;
}
