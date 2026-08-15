part of '../../../../main.dart';

class MaintenanceScreen extends ConsumerStatefulWidget {
  const MaintenanceScreen({this.initialFilter, super.key});

  final String? initialFilter;

  @override
  ConsumerState<MaintenanceScreen> createState() => _MaintenanceScreenState();
}

class _MaintenanceScreenState extends ConsumerState<MaintenanceScreen> {
  @override
  Widget build(BuildContext context) {
    final tasks = ref.watch(tasksProvider);
    final hasThings = ref.watch(
      assetsProvider.select((state) => state.value?.isNotEmpty ?? false),
    );
    final canAddThing = ref.watch(
      roomsProvider.select((state) => state.value?.isNotEmpty ?? false),
    );
    final taskItems = tasks.value ?? const <TaskItem>[];
    final taskBuckets = getTaskBuckets(taskItems, DateTime.now());
    final showFab =
        widget.initialFilter != 'today' || taskBuckets.today.isNotEmpty;
    return Scaffold(
      appBar: AppBar(
        title: Text(_taskScreenTitle(context, widget.initialFilter)),
        actions: [
          Padding(
            padding: const EdgeInsetsDirectional.only(end: HkSpacing.gutter),
            child: HkPointsPill(
              onTap: () => showPointsWalletSheet(context, ref),
            ),
          ),
        ],
      ),
      floatingActionButton: showFab
          ? Padding(
              padding: const EdgeInsets.only(bottom: HkSpacing.bottomNav),
              child: hk_ui.OwntendFloatingActionButton(
                tooltip: context.l10n.addTask,
                onPressed: _showCreateTaskMenu,
                icon: Symbols.add_rounded,
                label: context.l10n.addTask,
              ),
            )
          : null,
      body: hk_ui.ProductivityBackdrop(
        child: RepaintBoundary(
          key: const ValueKey('tasks-stability-boundary'),
          child: tasks.when(
            data: (items) {
              if (items.isEmpty) {
                return Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 800),
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(
                        16,
                        16,
                        16,
                        HkSpacing.bottomAction + HkSpacing.bottomNav,
                      ),
                      children: [
                        hk_ui.PremiumEmptyState(
                          icon: Symbols.task_alt_rounded,
                          title: hasThings
                              ? context.l10n.noScheduledTasks
                              : canAddThing
                              ? context.l10n.createAnItemFirst
                              : context.l10n.createARoomFirst,
                          body: hasThings
                              ? context
                                    .l10n
                                    .createRecurringPlanForMaintenanceQueue
                              : canAddThing
                              ? context.l10n.maintenanceTasksNeedAnItem
                              : context.l10n.addRoomOrZoneBeforeItemsAndTasks,
                          action: hasThings
                              ? FilledButton.icon(
                                  onPressed: () => showPlanEditorSheet(context),
                                  icon: const Icon(Symbols.add_task_rounded),
                                  label: Text(context.l10n.addTask),
                                )
                              : FilledButton.icon(
                                  onPressed: () =>
                                      startThingSetupFlow(context, ref),
                                  icon: Icon(
                                    canAddThing
                                        ? Symbols.add_home_work_rounded
                                        : Symbols.meeting_room_rounded,
                                  ),
                                  label: Text(
                                    canAddThing
                                        ? context.l10n.createFirstItem
                                        : context.l10n.createFirstRoom,
                                  ),
                                ),
                        ),
                      ],
                    ),
                  ),
                );
              }
              final buckets = getTaskBuckets(items, DateTime.now());
              final groups = _visibleTaskGroups(
                filter: widget.initialFilter,
                buckets: buckets,
                context: context,
              );
              final visibleCount = groups.fold<int>(
                0,
                (count, group) => count + group.tasks.length,
              );
              if (visibleCount == 0 && widget.initialFilter != null) {
                return Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 800),
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(
                        HkSpacing.gutter,
                        HkSpacing.md,
                        HkSpacing.gutter,
                        HkSpacing.bottomAction + HkSpacing.bottomNav,
                      ),
                      children: [
                        _FilteredTaskEmptyState(
                          filter: widget.initialFilter!,
                          onAddTask: () => !hasThings
                              ? startThingSetupFlow(context, ref)
                              : showPlanEditorSheet(context),
                          onNextSeven: () =>
                              context.push('/maintenance?filter=next7'),
                        ),
                      ],
                    ),
                  ),
                );
              }
              return Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 800),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(
                      HkSpacing.gutter,
                      8,
                      HkSpacing.gutter,
                      HkSpacing.bottomAction + HkSpacing.bottomNav,
                    ),
                    children: [
                      const HkNativeAdCard(placement: 'maintenance'),
                      for (final group in groups)
                        TaskGroup(
                          title: widget.initialFilter == null
                              ? group.title
                              : _filteredTaskGroupTitle(
                                  context,
                                  widget.initialFilter!,
                                  group.tasks.length,
                                ),
                          tasks: group.tasks,
                          color: group.color,
                          onComplete: (task) =>
                              _completeTask(context, ref, task),
                          onEdit: (task) =>
                              showPlanEditorSheet(context, task: task),
                          onSnooze: (task) =>
                              snoozeTaskWithFeedback(context, ref, task),
                          onSetEnabled: (task, enabled) =>
                              setTaskEnabledWithFeedback(
                                context,
                                ref,
                                task,
                                enabled,
                              ),
                          onDelete: (task) =>
                              deleteTaskWithConfirmation(context, ref, task),
                        ),
                    ],
                  ),
                ),
              );
            },
            error: (error, _) =>
                ErrorPanel(message: _failureMessage(context, error)),
            loading: () => const Center(child: CircularProgressIndicator()),
          ),
        ),
      ),
    );
  }

  Future<void> _showCreateTaskMenu() async {
    final assets = ref.read(assetsProvider).value ?? const <Asset>[];
    final rooms = ref.read(roomsProvider).value ?? const <Room>[];
    final hasThings = assets.isNotEmpty;
    final canAddThing = rooms.isNotEmpty;
    final action = await runWithNativeAdsSuspended(
      context,
      () => showModalBottomSheet<_TaskCreateAction>(
        context: context,
        useRootNavigator: true,
        useSafeArea: true,
        showDragHandle: true,
        builder: (context) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              HkSpacing.gutter,
              0,
              HkSpacing.gutter,
              HkSpacing.md,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: Icon(
                    hasThings
                        ? Symbols.add_task_rounded
                        : canAddThing
                        ? Symbols.add_home_work_rounded
                        : Symbols.meeting_room_rounded,
                  ),
                  title: Text(
                    hasThings
                        ? context.l10n.addTask
                        : canAddThing
                        ? context.l10n.createFirstItem
                        : context.l10n.createFirstRoom,
                  ),
                  subtitle: Text(
                    hasThings
                        ? context.l10n.createMaintenancePlanManually
                        : canAddThing
                        ? context.l10n.tasksNeedItemFirst
                        : context.l10n.itemsNeedRoomFirst,
                  ),
                  onTap: () => Navigator.of(context).pop(
                    hasThings
                        ? _TaskCreateAction.manual
                        : _TaskCreateAction.setup,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (action == null || !mounted) {
      return;
    }
    switch (action) {
      case _TaskCreateAction.manual:
        showPlanEditorSheet(context);
        break;
      case _TaskCreateAction.setup:
        startThingSetupFlow(context, ref);
        break;
    }
  }

  Future<bool> _completeTask(
    BuildContext context,
    WidgetRef ref,
    TaskItem task,
  ) async {
    return completeTaskWithFeedback(context, ref, task, collectNotes: true);
  }
}

enum _TaskCreateAction { manual, setup }

class _TaskGroupData {
  const _TaskGroupData({
    required this.title,
    required this.tasks,
    required this.color,
  });

  final String title;
  final List<TaskItem> tasks;
  final Color color;
}

String _taskScreenTitle(BuildContext context, String? filter) {
  return switch (filter) {
    'today' => context.l10n.today,
    'next7' => context.l10n.next7Days,
    'overdue' => context.l10n.overdue,
    _ => context.l10n.tasks,
  };
}

String _filteredTaskGroupTitle(BuildContext context, String filter, int count) {
  return switch (filter) {
    'overdue' => context.l10n.needsAttention,
    'next7' => context.l10n.itemStatusDueSoon(count),
    'today' => context.l10n.dueToday,
    _ => context.l10n.taskCountLabel(count),
  };
}

List<_TaskGroupData> _visibleTaskGroups({
  required String? filter,
  required TaskBuckets buckets,
  required BuildContext context,
}) {
  final all = [
    _TaskGroupData(
      title: context.l10n.overdue,
      tasks: buckets.overdue,
      color: HkColors.red,
    ),
    _TaskGroupData(
      title: context.l10n.today,
      tasks: buckets.today,
      color: HkColors.amber,
    ),
    _TaskGroupData(
      title: context.l10n.tomorrow,
      tasks: buckets.tomorrow,
      color: HkColors.green,
    ),
    _TaskGroupData(
      title: context.l10n.next7Days,
      tasks: buckets.next7Days,
      color: HkColors.indigo,
    ),
    _TaskGroupData(
      title: context.l10n.later,
      tasks: buckets.later,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    ),
  ];
  return switch (filter) {
    'today' => [all[1]],
    'next7' => [
      _TaskGroupData(
        title: context.l10n.next7Days,
        tasks: buckets.dueSoon,
        color: HkColors.indigo,
      ),
    ],
    'overdue' => [all[0]],
    _ => all,
  };
}

class _FilteredTaskEmptyState extends StatelessWidget {
  const _FilteredTaskEmptyState({
    required this.filter,
    required this.onAddTask,
    required this.onNextSeven,
  });

  final String filter;
  final VoidCallback onAddTask;
  final VoidCallback onNextSeven;

  @override
  Widget build(BuildContext context) {
    final details = switch (filter) {
      'today' => (
        icon: Symbols.task_alt_rounded,
        title: context.l10n.noTasksDueToday,
        body: context.l10n.yourMaintenancePlanIsClearToday,
      ),
      'overdue' => (
        icon: Symbols.task_alt_rounded,
        title: context.l10n.noOverdueTasks,
        body: context.l10n.yourMaintenancePlanIsUpToDate,
      ),
      'next7' => (
        icon: Symbols.event_available_rounded,
        title: context.l10n.noTasksInTheNext7Days,
        body: context.l10n.upcomingMaintenanceWillAppearHere,
      ),
      _ => (
        icon: Symbols.task_alt_rounded,
        title: context.l10n.noTasks,
        body: context.l10n.createATaskToStartPlanningMaintenance,
      ),
    };
    return Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: const EdgeInsets.only(top: HkSpacing.space40),
        child: hk_ui.PremiumEmptyState(
          icon: details.icon,
          illustrationTone: filter == 'overdue'
              ? hk_ui.HkIllustrationTone.success
              : hk_ui.HkIllustrationTone.info,
          title: details.title,
          body: details.body,
          action: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: double.infinity,
                child: filter == 'overdue'
                    ? FilledButton.icon(
                        onPressed: onNextSeven,
                        icon: const Icon(Symbols.event_available_rounded),
                        label: Text(context.l10n.viewUpcomingTasks),
                      )
                    : FilledButton.icon(
                        onPressed: onAddTask,
                        icon: const Icon(Symbols.add_task_rounded),
                        label: Text(context.l10n.addTask),
                      ),
              ),
              if (filter == 'overdue') ...[
                const SizedBox(height: HkSpacing.xs),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: onAddTask,
                    icon: const Icon(Symbols.add_task_rounded),
                    label: Text(context.l10n.addTask),
                  ),
                ),
              ],
              if (filter == 'today') ...[
                const SizedBox(height: HkSpacing.xs),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: onNextSeven,
                    child: Text(context.l10n.viewNext7Days),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
