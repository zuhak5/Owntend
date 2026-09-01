part of 'rooms_presentation.dart';

class RoomsScreen extends ConsumerStatefulWidget {
  const RoomsScreen({super.key});

  @override
  ConsumerState<RoomsScreen> createState() => _RoomsScreenState();
}

class _RoomsScreenState extends ConsumerState<RoomsScreen> {
  String? _selectedAreaId;
  String _roomQuery = '';

  @override
  Widget build(BuildContext context) {
    final areaState = ref.watch(areasProvider);
    final areaItems = areaState.value;
    final areas = areaItems != null
        ? AsyncValue<List<Area>>.data(areaItems)
        : areaState.hasError
        ? AsyncValue<List<Area>>.error(
            areaState.error!,
            areaState.stackTrace ?? StackTrace.empty,
          )
        : const AsyncValue<List<Area>>.loading();
    final rooms = ref.watch(roomsProvider).value ?? const <Room>[];
    final assets = ref.watch(assetsProvider).value ?? const <Asset>[];
    final tasks = ref.watch(tasksProvider).value ?? const <TaskItem>[];
    final currentAreaItems = areaItems ?? const <Area>[];
    final selectedAreaForAction =
        currentAreaItems.any((area) => area.id == _selectedAreaId)
        ? _selectedAreaId
        : currentAreaItems.firstOrNull?.id;
    final selectedAreaRooms = selectedAreaForAction == null
        ? <Room>[]
        : rooms.where((room) => room.areaId == selectedAreaForAction).toList();
    final selectedActionArea = selectedAreaForAction == null
        ? null
        : currentAreaItems
              .where((area) => area.id == selectedAreaForAction)
              .firstOrNull;
    final actionAreaIsOutdoor = selectedActionArea?.kind == AreaKind.outdoor;
    final fabLabel = selectedAreaForAction == null
        ? context.l10n.addArea
        : selectedAreaRooms.isEmpty
        ? actionAreaIsOutdoor
              ? context.l10n.addZone
              : context.l10n.addRoom
        : context.l10n.addItem;
    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.rooms),
        actions: [
          HkPointsPill(onTap: () => showPointsWalletSheet(context, ref)),
          IconButton(
            tooltip: context.l10n.addArea,
            onPressed: () => showAreaEditorSheet(context),
            icon: const Icon(Symbols.add_home_rounded),
          ),
          const SizedBox(width: HkSpacing.xs),
        ],
      ),
      floatingActionButton: selectedAreaRooms.isEmpty
          ? null
          : Padding(
              padding: const EdgeInsets.only(bottom: HkSpacing.bottomNav),
              child: hk_ui.OwntendFloatingActionButton(
                onPressed: () => showAssetEditorSheet(
                  context,
                  roomId: selectedAreaRooms.first.id,
                ),
                icon: Symbols.add_home_work_rounded,
                label: fabLabel,
              ),
            ),
      body: RepaintBoundary(
        key: const ValueKey('rooms-stability-boundary'),
        child: areas.when(
          data: (areaItems) {
            if (areaItems.isEmpty) {
              return ListView(
                padding: const EdgeInsets.fromLTRB(
                  16,
                  16,
                  16,
                  HkSpacing.bottomAction + HkSpacing.bottomNav,
                ),
                children: [
                  hk_ui.PremiumEmptyState(
                    icon: Symbols.home_work_rounded,
                    title: context.l10n.noAreasYet,
                    body: context.l10n.createAreaToOrganizeRoomsAndZones,
                    action: FilledButton.icon(
                      onPressed: () => showAreaEditorSheet(context),
                      icon: const Icon(Symbols.add_home_rounded),
                      label: Text(context.l10n.addArea),
                    ),
                  ),
                ],
              );
            }
            final selectedArea =
                areaItems.any((area) => area.id == _selectedAreaId)
                ? _selectedAreaId!
                : areaItems.first.id;
            final visibleRooms = rooms
                .where((room) => room.areaId == selectedArea)
                .toList();
            final filteredRooms = _filterRooms(visibleRooms);
            final selectedAreaModel = areaItems.firstWhere(
              (area) => area.id == selectedArea,
            );
            final roomsByArea = <String, int>{};
            for (final room in rooms) {
              roomsByArea.update(
                room.areaId,
                (value) => value + 1,
                ifAbsent: () => 1,
              );
            }
            final assetsByRoom = <String, List<Asset>>{};
            for (final asset in assets) {
              assetsByRoom.putIfAbsent(asset.roomId, () => []).add(asset);
            }
            final tasksByRoom = <String, List<TaskItem>>{};
            for (final task in tasks) {
              tasksByRoom.putIfAbsent(task.room.id, () => []).add(task);
            }
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 960),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(
                    HkSpacing.gutter,
                    8,
                    HkSpacing.gutter,
                    HkSpacing.bottomAction + HkSpacing.bottomNav,
                  ),
                  children: [
                    const HkNativeAdCard(placement: 'assets'),
                    AreaSelector(
                      areas: areaItems,
                      selectedAreaId: selectedArea,
                      roomCountsByArea: roomsByArea,
                      onSelected: (areaId) {
                        setState(() => _selectedAreaId = areaId);
                      },
                    ),
                    const SizedBox(height: HkSpacing.sm),
                    SelectedAreaTools(
                      area: selectedAreaModel,
                      canMoveBack: areaItems.indexOf(selectedAreaModel) > 0,
                      canMoveForward:
                          areaItems.indexOf(selectedAreaModel) <
                          areaItems.length - 1,
                      onEdit: () =>
                          showAreaEditorSheet(context, area: selectedAreaModel),
                      onDelete: () async {
                        final deleted = await deleteAreaWithConfirmation(
                          context,
                          ref,
                          selectedAreaModel,
                        );
                        if (deleted && mounted) {
                          setState(() => _selectedAreaId = null);
                        }
                        return deleted;
                      },
                      onMoveBack: () =>
                          _moveArea(areaItems, selectedAreaModel, -1),
                      onMoveForward: () =>
                          _moveArea(areaItems, selectedAreaModel, 1),
                    ),
                    if (visibleRooms.length > 6) ...[
                      const SizedBox(height: HkSpacing.sm),
                      TextField(
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Symbols.search_rounded),
                          labelText: selectedAreaModel.kind == AreaKind.outdoor
                              ? context.l10n.searchZones
                              : context.l10n.searchRooms,
                        ),
                        onChanged: (value) =>
                            setState(() => _roomQuery = value),
                      ),
                    ],
                    hk_ui.SectionHeader(
                      title: selectedAreaModel.kind == AreaKind.outdoor
                          ? context.l10n.outdoorZones
                          : context.l10n.rooms,
                      subtitle: _roomCountLabel(
                        context,
                        filteredRooms.length,
                        selectedAreaModel,
                        filtered: _roomQuery.trim().isNotEmpty,
                      ),
                      actionLabel: visibleRooms.isEmpty
                          ? null
                          : selectedAreaModel.kind == AreaKind.outdoor
                          ? context.l10n.addZone
                          : context.l10n.addRoom,
                      onAction: () =>
                          showRoomEditorSheet(context, areaId: selectedArea),
                    ),
                    if (visibleRooms.isEmpty)
                      hk_ui.PremiumEmptyState(
                        icon: Symbols.meeting_room_rounded,
                        title: selectedAreaModel.kind == AreaKind.outdoor
                            ? context.l10n.noZonesYet
                            : context.l10n.noRoomsYet,
                        body: selectedAreaModel.kind == AreaKind.outdoor
                            ? context.l10n.zonesOrganizeOutdoorCare
                            : context.l10n.roomsOrganizeCareByLocation,
                        action: FilledButton.icon(
                          onPressed: () => showRoomEditorSheet(
                            context,
                            areaId: selectedArea,
                          ),
                          icon: const Icon(Symbols.add_home_work_rounded),
                          label: Text(
                            selectedAreaModel.kind == AreaKind.outdoor
                                ? context.l10n.addZone
                                : context.l10n.addRoom,
                          ),
                        ),
                      )
                    else if (filteredRooms.isEmpty)
                      hk_ui.PremiumEmptyState(
                        icon: Symbols.search_rounded,
                        illustrationTone: hk_ui.HkIllustrationTone.neutral,
                        title: context.l10n.noResultsFound,
                        body: context.l10n.tryADifferentNameOrType,
                        action: OutlinedButton(
                          onPressed: () => setState(() => _roomQuery = ''),
                          child: Text(context.l10n.clearSearch),
                        ),
                      )
                    else
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final columns = constraints.maxWidth >= 840
                              ? 3
                              : constraints.maxWidth >= 540
                              ? 2
                              : 1;
                          return GridView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: filteredRooms.length,
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: columns,
                                  mainAxisExtent: columns == 1 ? 68 : 76,
                                  crossAxisSpacing: HkSpacing.xs,
                                  mainAxisSpacing: HkSpacing.xs,
                                ),
                            itemBuilder: (context, index) {
                              final room = filteredRooms[index];
                              return hk_ui.SwipeDelete(
                                dismissKey: ValueKey('room-delete-${room.id}'),
                                action: hk_ui.SwipeAction.moveToTrash(
                                  onAction: () => deleteRoomWithConfirmation(
                                    context,
                                    ref,
                                    room,
                                  ),
                                ),
                                child: RoomCard(
                                  key: ValueKey('room-card-${room.id}'),
                                  room: room,
                                  thingCount:
                                      assetsByRoom[room.id]?.length ?? 0,
                                  tasks: tasksByRoom[room.id] ?? const [],
                                  onTap: () =>
                                      context.push('/assets/room/${room.id}'),
                                  onAddThing: () => showAssetEditorSheet(
                                    context,
                                    roomId: room.id,
                                  ),
                                  onEdit: () => showRoomEditorSheet(
                                    context,
                                    areaId: room.areaId,
                                    room: room,
                                  ),
                                  onMoveUp: index > 0
                                      ? () => _moveRoom(filteredRooms, room, -1)
                                      : null,
                                  onMoveDown: index < filteredRooms.length - 1
                                      ? () => _moveRoom(filteredRooms, room, 1)
                                      : null,
                                  onArchive: () => deleteRoomWithConfirmation(
                                    context,
                                    ref,
                                    room,
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      ),
                  ],
                ),
              ),
            );
          },
          error: (error, _) =>
              hk_ui.ErrorPanel(message: failureMessage(context, error)),
          loading: () => const Center(child: CircularProgressIndicator()),
        ),
      ),
    );
  }

  List<Room> _filterRooms(List<Room> rooms) {
    final query = _roomQuery.trim().toLowerCase();
    if (query.isEmpty) {
      return rooms;
    }
    return rooms.where((room) {
      return room.name.toLowerCase().contains(query) ||
          roomTypeLabel(context, room.roomType).toLowerCase().contains(query);
    }).toList();
  }

  String _roomCountLabel(
    BuildContext context,
    int count,
    Area area, {
    required bool filtered,
  }) {
    if (filtered) {
      return area.kind == AreaKind.outdoor
          ? context.l10n.matchingZoneCount(count)
          : context.l10n.matchingRoomCount(count);
    }
    return area.kind == AreaKind.outdoor
        ? context.l10n.zoneCount(count)
        : context.l10n.roomCount(count);
  }

  Future<void> _moveArea(List<Area> areas, Area area, int direction) async {
    final index = areas.indexWhere((item) => item.id == area.id);
    final targetIndex = index + direction;
    if (index < 0 || targetIndex < 0 || targetIndex >= areas.length) {
      return;
    }
    final target = areas[targetIndex];
    final repo = ref.read(assetRepositoryProvider);
    await repo.saveArea(
      id: area.id,
      name: area.name,
      kind: area.kind,
      sortOrder: target.sortOrder,
      expectedUpdatedAt: area.updatedAt,
    );
    await repo.saveArea(
      id: target.id,
      name: target.name,
      kind: target.kind,
      sortOrder: area.sortOrder,
      expectedUpdatedAt: target.updatedAt,
    );
  }

  Future<void> _moveRoom(List<Room> rooms, Room room, int direction) async {
    final index = rooms.indexWhere((item) => item.id == room.id);
    final targetIndex = index + direction;
    if (index < 0 || targetIndex < 0 || targetIndex >= rooms.length) {
      return;
    }
    final target = rooms[targetIndex];
    final repo = ref.read(assetRepositoryProvider);
    await repo.saveRoom(
      id: room.id,
      areaId: room.areaId,
      name: room.name,
      roomType: room.roomType,
      notes: room.notes,
      sortOrder: target.sortOrder,
      expectedUpdatedAt: room.updatedAt,
    );
    await repo.saveRoom(
      id: target.id,
      areaId: target.areaId,
      name: target.name,
      roomType: target.roomType,
      notes: target.notes,
      sortOrder: room.sortOrder,
      expectedUpdatedAt: target.updatedAt,
    );
  }
}

class AreaSelector extends StatelessWidget {
  const AreaSelector({
    required this.areas,
    required this.selectedAreaId,
    required this.roomCountsByArea,
    required this.onSelected,
    super.key,
  });

  final List<Area> areas;
  final String selectedAreaId;
  final Map<String, int> roomCountsByArea;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return Row(
      key: const ValueKey('area-selector-row'),
      children: [
        for (var index = 0; index < areas.length; index++) ...[
          Expanded(
            child: AreaChip(
              area: areas[index],
              selected: areas[index].id == selectedAreaId,
              roomCount: roomCountsByArea[areas[index].id] ?? 0,
              onTap: () => onSelected(areas[index].id),
            ),
          ),
          if (index != areas.length - 1) const SizedBox(width: HkSpacing.xs),
        ],
      ],
    );
  }
}

class AreaChip extends StatelessWidget {
  const AreaChip({
    required this.area,
    required this.selected,
    required this.roomCount,
    required this.onTap,
    super.key,
  });

  final Area area;
  final bool selected;
  final int roomCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final foreground = selected ? scheme.primary : scheme.onSurfaceVariant;
    final countLabel = area.kind == AreaKind.outdoor
        ? context.l10n.zoneCount(roomCount)
        : context.l10n.roomCount(roomCount);
    return Semantics(
      selected: selected,
      button: true,
      label: '${area.name}, $countLabel',
      child: InkWell(
        key: ValueKey('area-chip-${area.id}'),
        borderRadius: BorderRadius.circular(HkRadii.lg),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          height: 44,
          padding: const EdgeInsets.symmetric(
            horizontal: HkSpacing.xs,
            vertical: HkSpacing.base,
          ),
          decoration: BoxDecoration(
            color: selected
                ? scheme.secondaryContainer
                : scheme.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(HkRadii.lg),
            border: Border.all(
              color: selected
                  ? scheme.primary.withValues(alpha: 0.36)
                  : scheme.outlineVariant.withValues(alpha: 0.34),
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    selected ? Symbols.check_rounded : iconForArea(area),
                    color: foreground,
                    size: 15,
                  ),
                  const SizedBox(width: 3),
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: DynamicText(
                        area.name,
                        contentType: 'area.name',
                        maxLines: 1,
                        softWrap: false,
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(
                              color: foreground,
                              fontWeight: selected
                                  ? FontWeight.w800
                                  : FontWeight.w700,
                            ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                countLabel,
                maxLines: 1,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: foreground.withValues(alpha: 0.78),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SelectedAreaTools extends StatelessWidget {
  const SelectedAreaTools({
    required this.area,
    required this.canMoveBack,
    required this.canMoveForward,
    required this.onEdit,
    required this.onDelete,
    required this.onMoveBack,
    required this.onMoveForward,
    super.key,
  });

  final Area area;
  final bool canMoveBack;
  final bool canMoveForward;
  final VoidCallback onEdit;
  final Future<bool> Function() onDelete;
  final VoidCallback onMoveBack;
  final VoidCallback onMoveForward;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return hk_ui.SwipeDelete(
      dismissKey: ValueKey('area-delete-${area.id}'),
      action: hk_ui.SwipeAction.moveToTrash(onAction: onDelete),
      child: hk_ui.PremiumCard(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        borderRadius: hk_ui.kSwipeRowRadius,
        child: Row(
          children: [
            Icon(iconForArea(area), color: scheme.primary, size: 20),
            const SizedBox(width: HkSpacing.xs),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DynamicText(
                    area.name,
                    contentType: 'area.name',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  Text(
                    areaKindLabel(context, area.kind),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            PopupMenuButton<String>(
              useRootNavigator: true,
              tooltip: context.l10n.areaActions,
              onSelected: (value) {
                if (value == 'edit') {
                  onEdit();
                } else if (value == 'delete') {
                  onDelete();
                } else if (value == 'back') {
                  onMoveBack();
                } else if (value == 'forward') {
                  onMoveForward();
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'edit',
                  child: Text(context.l10n.editArea),
                ),
                PopupMenuItem(
                  value: 'back',
                  enabled: canMoveBack,
                  child: Text(context.l10n.moveEarlier),
                ),
                PopupMenuItem(
                  value: 'forward',
                  enabled: canMoveForward,
                  child: Text(context.l10n.moveLater),
                ),
                PopupMenuItem(
                  value: 'delete',
                  child: Text(context.l10n.moveAreaToTrash),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MetaSeparator extends StatelessWidget {
  const _MetaSeparator();

  @override
  Widget build(BuildContext context) {
    return Text(
      ' | ',
      style: Theme.of(context).textTheme.bodySmall
          ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
    );
  }
}

class RoomCard extends StatelessWidget {
  const RoomCard({
    required this.room,
    required this.thingCount,
    required this.tasks,
    required this.onTap,
    required this.onAddThing,
    required this.onEdit,
    this.onMoveUp,
    this.onMoveDown,
    this.onArchive,
    super.key,
  });

  final Room room;
  final int thingCount;
  final List<TaskItem> tasks;
  final VoidCallback onTap;
  final VoidCallback onAddThing;
  final VoidCallback onEdit;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final VoidCallback? onArchive;

  @override
  Widget build(BuildContext context) {
    final buckets = getTaskBuckets(tasks, DateTime.now());
    final overdue = buckets.overdueCount;
    final dueToday = buckets.todayCount;
    final scheme = Theme.of(context).colorScheme;
    final statusColor = overdue > 0
        ? HkColors.tertiary
        : dueToday > 0
        ? HkColors.amber
        : scheme.primary;
    final taskStatus = tasks.isEmpty
        ? context.l10n.roomTaskStatusNoTasks
        : overdue > 0
        ? context.l10n.roomTaskStatusOverdue(overdue)
        : dueToday > 0
        ? context.l10n.roomTaskStatusDueToday(dueToday)
        : context.l10n.onTrack;
    final typeLabel = roomTypeLabel(context, room.roomType);
    final itemCountLabel = context.l10n.itemCount(thingCount);
    return hk_ui.PremiumCard(
      padding: EdgeInsets.zero,
      borderRadius: hk_ui.kSwipeRowRadius,
      child: InkWell(
        borderRadius: BorderRadius.circular(hk_ui.kSwipeRowRadius),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: scheme.secondaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(iconForRoom(room), color: scheme.primary, size: 18),
              ),
              const SizedBox(width: HkSpacing.xs),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DynamicText(
                      room.name,
                      contentType: 'room.name',
                      style: Theme.of(context).textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      runSpacing: 1,
                      children: [
                        if (typeLabel != room.name) ...[
                          Text(
                            typeLabel,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const _MetaSeparator(),
                        ],
                        Text(
                          itemCountLabel,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const _MetaSeparator(),
                        Text(
                          taskStatus,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: statusColor,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: HkSpacing.space4),
              SizedBox(
                width: 44,
                height: 44,
                child: PopupMenuButton<String>(
                  useRootNavigator: true,
                  tooltip: context.l10n.roomActions,
                  constraints: const BoxConstraints(minWidth: 196),
                  padding: EdgeInsets.zero,
                  iconSize: 20,
                  icon: const Icon(Symbols.more_vert_rounded),
                  onSelected: (value) {
                    if (value == 'edit') {
                      onEdit();
                    } else if (value == 'thing') {
                      onAddThing();
                    } else if (value == 'up') {
                      onMoveUp?.call();
                    } else if (value == 'down') {
                      onMoveDown?.call();
                    } else if (value == 'archive') {
                      onArchive?.call();
                    }
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'thing',
                      child: hk_ui.PopupActionLabel(
                        icon: Symbols.add_home_work_rounded,
                        label: context.l10n.addItem,
                      ),
                    ),
                    PopupMenuItem(
                      value: 'edit',
                      child: hk_ui.PopupActionLabel(
                        icon: Symbols.edit_rounded,
                        label: context.l10n.edit,
                      ),
                    ),
                    PopupMenuItem(
                      value: 'up',
                      enabled: onMoveUp != null,
                      child: hk_ui.PopupActionLabel(
                        icon: Symbols.arrow_upward_rounded,
                        label: context.l10n.moveUp,
                      ),
                    ),
                    PopupMenuItem(
                      value: 'down',
                      enabled: onMoveDown != null,
                      child: hk_ui.PopupActionLabel(
                        icon: Symbols.arrow_downward_rounded,
                        label: context.l10n.moveDown,
                      ),
                    ),
                    if (onArchive != null)
                      PopupMenuItem(
                        value: 'archive',
                        child: hk_ui.PopupActionLabel(
                          icon: Symbols.delete_rounded,
                          label: context.l10n.moveRoomToTrash,
                          destructive: true,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
