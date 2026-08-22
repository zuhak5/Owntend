import '../../../ui/components.dart' as hk_ui;
import '../../../ui/presentation_support.dart';
import '../../maintenance/presentation/task_actions.dart';

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
  try {
    await cancelPlanReminderSchedules(ref, [task.plan.id]);
    await refreshNotificationSchedules(ref);
  } on Object catch (error) {
    if (context.mounted) {
      hk_ui.showToast(
        context,
        content: Text(
          failureMessage(
            context,
            error,
            fallback: AppFailureCode.notificationSetup,
          ),
        ),
        severity: hk_ui.HkToastSeverity.error,
      );
    }
  }
  if (!context.mounted) {
    return true;
  }
  hk_ui.showTaskMovedToTrashSnackBar(
    context,
    duration: const Duration(seconds: 5),
    onUndo: () async {
      try {
        await ref.read(maintenanceRepositoryProvider).restorePlan(task.plan.id);
        await refreshNotificationSchedules(ref);
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

Future<bool> deleteThingWithConfirmation(
  BuildContext context,
  WidgetRef ref,
  Asset asset,
) async {
  final confirmed = await confirmPermanentDelete(
    context,
    title: context.l10n.moveItemToTrash2,
    message: context.l10n.moveItemToTrashMessage(asset.name),
    actionLabel: context.l10n.moveToTrash,
  );
  if (!confirmed || !context.mounted) {
    return false;
  }
  final planIds = await planIdsForAssets(ref, [asset.id]);
  if (!context.mounted) {
    return false;
  }
  await ref.read(assetRepositoryProvider).trashAsset(asset.id);
  if (!context.mounted) {
    return false;
  }
  await cancelPlanReminderSchedules(ref, planIds);
  await refreshNotificationSchedules(ref);
  if (!context.mounted) {
    return false;
  }
  unawaited(hkActionFeedbackService.playDeleted());
  hk_ui.showMovedToTrashSnackBar(
    context,
    content: Text(context.l10n.nameMovedToTrash(asset.name)),
    onUndo: () async {
      try {
        await ref.read(assetRepositoryProvider).restoreAsset(asset.id);
        await refreshNotificationSchedules(ref);
        if (context.mounted) {
          hk_ui.showToast(
            context,
            content: Text(context.l10n.nameRestored(asset.name)),
          );
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

Future<bool> deleteRoomWithConfirmation(
  BuildContext context,
  WidgetRef ref,
  Room room,
) async {
  final confirmed = await confirmPermanentDelete(
    context,
    title: context.l10n.moveRoomToTrash2,
    message: context.l10n.moveRoomToTrashMessage(room.name),
    actionLabel: context.l10n.moveToTrash,
  );
  if (!confirmed || !context.mounted) {
    return false;
  }
  final assets = await ref
      .read(assetRepositoryProvider)
      .listAssets(roomId: room.id);
  final planIds = await planIdsForAssets(ref, assets.map((asset) => asset.id));
  if (!context.mounted) {
    return false;
  }
  await ref.read(assetRepositoryProvider).trashRoom(room.id);
  if (!context.mounted) {
    return false;
  }
  await cancelPlanReminderSchedules(ref, planIds);
  await refreshNotificationSchedules(ref);
  if (!context.mounted) {
    return false;
  }
  unawaited(hkActionFeedbackService.playDeleted());
  hk_ui.showMovedToTrashSnackBar(
    context,
    content: Text(context.l10n.nameMovedToTrash(room.name)),
    onUndo: () async {
      try {
        await ref.read(assetRepositoryProvider).restoreRoom(room.id);
        await refreshNotificationSchedules(ref);
        if (context.mounted) {
          hk_ui.showToast(
            context,
            content: Text(context.l10n.nameRestored(room.name)),
          );
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

Future<bool> deleteAreaWithConfirmation(
  BuildContext context,
  WidgetRef ref,
  Area area,
) async {
  final confirmed = await confirmPermanentDelete(
    context,
    title: context.l10n.moveAreaToTrash2,
    message: context.l10n.moveAreaToTrashMessage(area.name),
    actionLabel: context.l10n.moveToTrash,
  );
  if (!confirmed || !context.mounted) {
    return false;
  }
  final rooms = await ref
      .read(assetRepositoryProvider)
      .listRooms(areaId: area.id);
  final assetIds = <String>[];
  for (final room in rooms) {
    final assets = await ref
        .read(assetRepositoryProvider)
        .listAssets(roomId: room.id);
    assetIds.addAll(assets.map((asset) => asset.id));
  }
  final planIds = await planIdsForAssets(ref, assetIds);
  if (!context.mounted) {
    return false;
  }
  await ref.read(assetRepositoryProvider).trashArea(area.id);
  if (!context.mounted) {
    return false;
  }
  await cancelPlanReminderSchedules(ref, planIds);
  await refreshNotificationSchedules(ref);
  if (!context.mounted) {
    return false;
  }
  unawaited(hkActionFeedbackService.playDeleted());
  hk_ui.showMovedToTrashSnackBar(
    context,
    content: Text(context.l10n.nameMovedToTrash(area.name)),
    onUndo: () async {
      try {
        await ref.read(assetRepositoryProvider).restoreArea(area.id);
        await refreshNotificationSchedules(ref);
        if (context.mounted) {
          hk_ui.showToast(
            context,
            content: Text(context.l10n.nameRestored(area.name)),
          );
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
