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
  final checkUndoAccount = captureUndoAccountGuard(ref);
  final repository = ref.read(assetRepositoryProvider);
  final reconcileNotifications = captureNotificationReconciliation(ref);
  await repository.trashAsset(asset.id);
  if (!context.mounted) {
    return false;
  }
  await reconcileNotifications();
  if (!context.mounted) {
    return false;
  }
  unawaited(hkActionFeedbackService.playDeleted());
  hk_ui.showMovedToTrashSnackBar(
    context,
    content: Text(context.l10n.nameMovedToTrash(asset.name)),
    actionSuccessMessage: Text(context.l10n.nameRestored(asset.name)),
    onUndo: () async {
      checkUndoAccount();
      await repository.restoreAsset(asset.id);
      await reconcileNotifications();
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
  final checkUndoAccount = captureUndoAccountGuard(ref);
  final repository = ref.read(assetRepositoryProvider);
  final reconcileNotifications = captureNotificationReconciliation(ref);
  await repository.trashRoom(room.id);
  if (!context.mounted) {
    return false;
  }
  await reconcileNotifications();
  if (!context.mounted) {
    return false;
  }
  unawaited(hkActionFeedbackService.playDeleted());
  hk_ui.showMovedToTrashSnackBar(
    context,
    content: Text(context.l10n.nameMovedToTrash(room.name)),
    actionSuccessMessage: Text(context.l10n.nameRestored(room.name)),
    onUndo: () async {
      checkUndoAccount();
      await repository.restoreRoom(room.id);
      await reconcileNotifications();
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
  final checkUndoAccount = captureUndoAccountGuard(ref);
  final repository = ref.read(assetRepositoryProvider);
  final reconcileNotifications = captureNotificationReconciliation(ref);
  await repository.trashArea(area.id);
  if (!context.mounted) {
    return false;
  }
  await reconcileNotifications();
  if (!context.mounted) {
    return false;
  }
  unawaited(hkActionFeedbackService.playDeleted());
  hk_ui.showMovedToTrashSnackBar(
    context,
    content: Text(context.l10n.nameMovedToTrash(area.name)),
    actionSuccessMessage: Text(context.l10n.nameRestored(area.name)),
    onUndo: () async {
      checkUndoAccount();
      await repository.restoreArea(area.id);
      await reconcileNotifications();
    },
  );
  return true;
}
