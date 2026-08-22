import '../../../ui/components.dart' as hk_ui;
import '../../../ui/presentation_support.dart';
import '../../maintenance/presentation/task_actions.dart';
import 'trash_actions.dart';

class TrashScreen extends ConsumerWidget {
  const TrashScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final areas = ref.watch(archivedAreasProvider);
    final rooms = ref.watch(archivedRoomsProvider);
    final assets = ref.watch(archivedAssetsProvider);
    final tasks = ref.watch(archivedTasksProvider);
    final areaItems = areas.value ?? const <Area>[];
    final roomItems = rooms.value ?? const <Room>[];
    final assetItems = assets.value ?? const <Asset>[];
    final taskItems = tasks.value ?? const <TaskItem>[];
    final total =
        areaItems.length +
        roomItems.length +
        assetItems.length +
        taskItems.length;
    final loading =
        areas.isLoading ||
        rooms.isLoading ||
        assets.isLoading ||
        tasks.isLoading;
    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.trash),
        actions: [
          if (total > 0)
            TextButton.icon(
              onPressed: () => _emptyTrash(context, ref),
              icon: const Icon(Symbols.delete_sweep_rounded),
              label: Text(context.l10n.emptyTrash),
            ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            children: [
              const HkNativeAdCard(placement: 'trash'),
              hk_ui.PremiumCard(
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Symbols.restore_from_trash_rounded),
                  title: Text(
                    total == 0
                        ? context.l10n.trashIsEmpty
                        : context.l10n.trashItemCount(total),
                  ),
                  subtitle: Text(context.l10n.restoreOrDeleteForever),
                ),
              ),
              if (loading) ...[
                const SizedBox(height: HkSpacing.sm),
                const LinearProgressIndicator(),
              ],
              if (!loading && total == 0)
                Padding(
                  padding: EdgeInsets.only(top: HkSpacing.md),
                  child: hk_ui.PremiumEmptyState(
                    icon: Symbols.delete_sweep_rounded,
                    illustrationTone: hk_ui.HkIllustrationTone.success,
                    title: context.l10n.nothingToRestore,
                    body: context.l10n.trashedContentAppearsHere,
                  ),
                ),
              _TrashSection(
                title: context.l10n.areas,
                count: areaItems.length,
                children: [
                  for (final area in areaItems)
                    _TrashRow(
                      icon: Symbols.home_work_rounded,
                      title: area.name,
                      subtitle: context.l10n.trashAreaType(
                        areaKindLabel(context, area.kind),
                      ),
                      onRestore: () => _restoreArea(context, ref, area),
                      onDeleteForever: () =>
                          _deleteAreaForever(context, ref, area),
                    ),
                ],
              ),
              _TrashSection(
                title: context.l10n.rooms,
                count: roomItems.length,
                children: [
                  for (final room in roomItems)
                    _TrashRow(
                      icon: Symbols.meeting_room_rounded,
                      title: room.name,
                      subtitle: context.l10n.trashRoomType(
                        roomTypeLabel(context, room.roomType),
                      ),
                      onRestore: () => _restoreRoom(context, ref, room),
                      onDeleteForever: () =>
                          _deleteRoomForever(context, ref, room),
                    ),
                ],
              ),
              _TrashSection(
                title: context.l10n.items,
                count: assetItems.length,
                children: [
                  for (final asset in assetItems)
                    _TrashRow(
                      icon: iconForAssetType(asset.assetType),
                      title: asset.name,
                      subtitle: context.l10n.trashItemType(
                        assetTypeLabel(context, asset.assetType),
                      ),
                      onRestore: () => _restoreAsset(context, ref, asset),
                      onDeleteForever: () =>
                          _deleteAssetForever(context, ref, asset),
                    ),
                ],
              ),
              _TrashSection(
                title: context.l10n.tasks,
                count: taskItems.length,
                children: [
                  for (final task in taskItems)
                    _TrashRow(
                      icon: Symbols.task_alt_rounded,
                      title: task.plan.title,
                      subtitle: '${task.asset.name} · ${task.room.name}',
                      onRestore: () => _restoreTask(context, ref, task),
                      onDeleteForever: () =>
                          _deleteTaskForever(context, ref, task),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _emptyTrash(BuildContext context, WidgetRef ref) async {
    final confirmed = await confirmPermanentDelete(
      context,
      title: context.l10n.emptyTrashConfirmationTitle,
      message: context.l10n.emptyTrashConfirmationMessage,
      actionLabel: context.l10n.emptyTrashAction,
    );
    if (!confirmed) return;
    await ref.read(assetRepositoryProvider).emptyTrash();
    await refreshNotificationSchedules(ref);
    if (!context.mounted) return;
    await _afterTrashMutation(context, ref, context.l10n.trashEmptied);
  }

  Future<void> _restoreArea(
    BuildContext context,
    WidgetRef ref,
    Area area,
  ) async {
    await ref.read(assetRepositoryProvider).restoreArea(area.id);
    await refreshNotificationSchedules(ref);
    if (!context.mounted) return;
    await _afterTrashMutation(
      context,
      ref,
      context.l10n.nameRestored(area.name),
    );
  }

  Future<void> _restoreRoom(
    BuildContext context,
    WidgetRef ref,
    Room room,
  ) async {
    await ref.read(assetRepositoryProvider).restoreRoom(room.id);
    await refreshNotificationSchedules(ref);
    if (!context.mounted) return;
    await _afterTrashMutation(
      context,
      ref,
      context.l10n.nameRestored(room.name),
    );
  }

  Future<void> _restoreAsset(
    BuildContext context,
    WidgetRef ref,
    Asset asset,
  ) async {
    await ref.read(assetRepositoryProvider).restoreAsset(asset.id);
    await refreshNotificationSchedules(ref);
    if (!context.mounted) return;
    await _afterTrashMutation(
      context,
      ref,
      context.l10n.nameRestored(asset.name),
    );
  }

  Future<void> _restoreTask(
    BuildContext context,
    WidgetRef ref,
    TaskItem task,
  ) async {
    await ref.read(maintenanceRepositoryProvider).restorePlan(task.plan.id);
    await refreshNotificationSchedules(ref);
    if (!context.mounted) return;
    await _afterTrashMutation(
      context,
      ref,
      context.l10n.nameRestored(task.plan.title),
    );
  }

  Future<void> _deleteAreaForever(
    BuildContext context,
    WidgetRef ref,
    Area area,
  ) async {
    final confirmed = await confirmPermanentDelete(
      context,
      title: context.l10n.deleteAreaForever,
      message: context.l10n.permanentlyDeleteAreaMessage(area.name),
    );
    if (!confirmed) return;
    await ref.read(assetRepositoryProvider).deleteArea(area.id);
    await refreshNotificationSchedules(ref);
    if (!context.mounted) return;
    await _afterTrashMutation(
      context,
      ref,
      context.l10n.nameDeletedForever(area.name),
    );
  }

  Future<void> _deleteRoomForever(
    BuildContext context,
    WidgetRef ref,
    Room room,
  ) async {
    final confirmed = await confirmPermanentDelete(
      context,
      title: context.l10n.deleteRoomForever,
      message: context.l10n.permanentlyDeleteRoomMessage(room.name),
    );
    if (!confirmed) return;
    await ref.read(assetRepositoryProvider).deleteRoom(room.id);
    await refreshNotificationSchedules(ref);
    if (!context.mounted) return;
    await _afterTrashMutation(
      context,
      ref,
      context.l10n.nameDeletedForever(room.name),
    );
  }

  Future<void> _deleteAssetForever(
    BuildContext context,
    WidgetRef ref,
    Asset asset,
  ) async {
    final confirmed = await confirmPermanentDelete(
      context,
      title: context.l10n.deleteItemForever,
      message: context.l10n.permanentlyDeleteItemMessage(asset.name),
    );
    if (!confirmed) return;
    await ref.read(assetRepositoryProvider).deleteAsset(asset.id);
    await refreshNotificationSchedules(ref);
    if (!context.mounted) return;
    await _afterTrashMutation(
      context,
      ref,
      context.l10n.nameDeletedForever(asset.name),
    );
  }

  Future<void> _deleteTaskForever(
    BuildContext context,
    WidgetRef ref,
    TaskItem task,
  ) async {
    final confirmed = await confirmPermanentDelete(
      context,
      title: context.l10n.deleteTaskForever,
      message: context.l10n.permanentlyDeleteTaskMessage(task.plan.title),
    );
    if (!confirmed) return;
    await ref.read(maintenanceRepositoryProvider).deletePlan(task.plan.id);
    await refreshNotificationSchedules(ref);
    if (!context.mounted) return;
    await _afterTrashMutation(
      context,
      ref,
      context.l10n.nameDeletedForever(task.plan.title),
    );
  }

  Future<void> _afterTrashMutation(
    BuildContext context,
    WidgetRef ref,
    String message,
  ) async {
    await ref.read(searchRepositoryProvider).rebuildIndex();
    if (!context.mounted) return;
    hk_ui.showToast(context, content: Text(message));
  }
}

class _TrashSection extends StatelessWidget {
  const _TrashSection({
    required this.title,
    required this.count,
    required this.children,
  });

  final String title;
  final int count;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    if (count == 0) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        hk_ui.SectionHeader(
          title: title,
          subtitle: context.l10n.trashSectionItemCount(count),
        ),
        ...children,
      ],
    );
  }
}

class _TrashRow extends StatelessWidget {
  const _TrashRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onRestore,
    required this.onDeleteForever,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Future<void> Function() onRestore;
  final Future<void> Function() onDeleteForever;

  @override
  Widget build(BuildContext context) {
    return hk_ui.PremiumCard(
      margin: const EdgeInsets.only(bottom: HkSpacing.xs),
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(icon),
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: Wrap(
          spacing: 2,
          children: [
            IconButton(
              tooltip: context.l10n.restore,
              onPressed: () => unawaited(onRestore()),
              icon: const Icon(Symbols.restore_rounded),
            ),
            IconButton(
              tooltip: context.l10n.deleteForever,
              onPressed: () => unawaited(onDeleteForever()),
              icon: Icon(
                Symbols.delete_forever_rounded,
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
