import '../../../ui/components.dart' as hk_ui;
import '../../../ui/presentation_support.dart';
import '../../maintenance/presentation/task_actions.dart';
import '../../maintenance/presentation/task_disposal_actions.dart';

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
  await ref.read(assetRepositoryProvider).trashAsset(asset.id);
  if (!context.mounted) {
    return false;
  }
  await wakeNotificationReconciliation(ref);
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
        await wakeNotificationReconciliation(ref);
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
  await ref.read(assetRepositoryProvider).trashRoom(room.id);
  if (!context.mounted) {
    return false;
  }
  await wakeNotificationReconciliation(ref);
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
        await wakeNotificationReconciliation(ref);
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
  await ref.read(assetRepositoryProvider).trashArea(area.id);
  if (!context.mounted) {
    return false;
  }
  await wakeNotificationReconciliation(ref);
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
        await wakeNotificationReconciliation(ref);
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
