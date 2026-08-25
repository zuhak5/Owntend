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
