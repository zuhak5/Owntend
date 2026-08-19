part of '../../../../main.dart';

class RoomDetailScreen extends ConsumerWidget {
  const RoomDetailScreen({required this.roomId, super.key});

  final String roomId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rooms = ref.watch(roomsProvider).value ?? [];
    final areas = ref.watch(areasProvider).value ?? [];
    final assets = ref.watch(roomAssetsProvider(roomId));
    final tasks = ref.watch(tasksProvider).value ?? [];
    final room = rooms.where((item) => item.id == roomId).firstOrNull;
    if (room == null) {
      return Scaffold(
        appBar: AppBar(title: Text(context.l10n.room)),
        body: Center(
          child: hk_ui.PremiumEmptyState(
            icon: Symbols.meeting_room_rounded,
            title: context.l10n.roomNotFound,
            body: '',
          ),
        ),
      );
    }
    final areaName = areas
        .where((area) => area.id == room.areaId)
        .firstOrNull
        ?.name;
    return Scaffold(
      appBar: AppBar(
        title: DynamicText(room.name, contentType: 'room.name'),
        actions: [
          IconButton(
            tooltip: context.l10n.addItem,
            onPressed: () => showAssetEditorSheet(context, roomId: roomId),
            icon: const Icon(Symbols.add_home_work_rounded),
          ),
          IconButton(
            tooltip: context.l10n.editRoom,
            onPressed: () =>
                showRoomEditorSheet(context, areaId: room.areaId, room: room),
            icon: const Icon(Symbols.edit_rounded),
          ),
        ],
      ),
      body: assets.when(
        data: (items) {
          final grouped = <AssetType, List<Asset>>{
            for (final type in AssetType.values) type: [],
          };
          for (final asset in items) {
            grouped[asset.assetType]?.add(asset);
          }
          final roomTasks = tasks
              .where((task) => task.room.id == roomId)
              .toList();
          final now = DateTime.now();
          final roomHealth = feature_selectors.roomHealthScore(
            room: room,
            assets: items,
            tasks: tasks,
            now: now,
          );
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 800),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  16,
                  8,
                  16,
                  HkSpacing.bottomAction,
                ),
                children: [
                  const HkNativeAdCard(placement: 'room_detail'),
                  hk_ui.PremiumCard(
                    child: Row(
                      children: [
                        const hk_ui.BrandMark(size: 44),
                        const SizedBox(width: HkSpacing.sm),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                areaName ?? context.l10n.homeArea,
                                style: Theme.of(context).textTheme.labelLarge,
                              ),
                              Text(
                                '${context.l10n.itemCount(items.length)} \u00B7 ${context.l10n.taskCountLabel(roomTasks.length)}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              Text(
                                context.l10n.roomHealthSemantic(
                                  roomHealth.score,
                                  _healthStateLabel(context, roomHealth.state),
                                ),
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: HkSpacing.md),
                  if (items.isEmpty)
                    hk_ui.PremiumEmptyState(
                      icon: Symbols.inventory_2_rounded,
                      title: context.l10n.noItemsInThisRoom,
                      body: context.l10n.addItemsToRoomBody,
                      action: FilledButton.icon(
                        onPressed: () =>
                            showAssetEditorSheet(context, roomId: roomId),
                        icon: const Icon(Symbols.add_home_work_rounded),
                        label: Text(context.l10n.addItem),
                      ),
                    )
                  else
                    for (final entry in grouped.entries.where(
                      (entry) => entry.value.isNotEmpty,
                    )) ...[
                      hk_ui.SectionHeader(
                        title:
                            '${_assetTypePluralLabel(context, entry.key)} · ${entry.value.length}',
                      ),
                      for (final asset in entry.value)
                        hk_ui.SwipeDelete(
                          margin: const EdgeInsets.only(bottom: HkSpacing.xs),
                          dismissKey: ValueKey('thing-delete-${asset.id}'),
                          action: hk_ui.SwipeAction.moveToTrash(
                            onAction: () => deleteThingWithConfirmation(
                              context,
                              ref,
                              asset,
                            ),
                          ),
                          child: ThingCard(
                            asset: asset,
                            dueStatus: itemTaskStatusFor(asset, tasks, now),
                            margin: EdgeInsets.zero,
                            onTap: () =>
                                context.push('/assets/thing/${asset.id}'),
                            onEdit: () =>
                                showAssetEditorSheet(context, asset: asset),
                            onPhoto: () => addPhotoToAsset(context, ref, asset),
                            onArchive: () => deleteThingWithConfirmation(
                              context,
                              ref,
                              asset,
                            ),
                          ),
                        ),
                    ],
                ],
              ),
            ),
          );
        },
        error: (error, _) =>
            ErrorPanel(message: _failureMessage(context, error)),
        loading: () => const Center(child: CircularProgressIndicator()),
      ),
    );
  }
}
