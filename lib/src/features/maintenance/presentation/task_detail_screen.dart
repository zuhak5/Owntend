part of 'maintenance_presentation.dart';

class TaskDetailScreen extends ConsumerWidget {
  const TaskDetailScreen({required this.planId, super.key});

  final String planId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final taskState = ref.watch(taskDetailProvider(planId));
    return taskState.when(
      data: (task) {
        if (task == null) {
          return Scaffold(
            appBar: AppBar(title: Text(context.l10n.task)),
            body: Center(
              child: hk_ui.PremiumEmptyState(
                icon: Symbols.task_rounded,
                title: context.l10n.taskNotFound,
                body: '',
                action: FilledButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  child: Text(context.l10n.back),
                ),
              ),
            ),
          );
        }
        final records = ref.watch(taskRecordsProvider(planId));
        return Scaffold(
          appBar: AppBar(
            title: DynamicText(
              task.plan.title,
              contentType: 'maintenance_plan.title',
            ),
            actions: [
              IconButton(
                tooltip: context.l10n.editTask,
                onPressed: () => showPlanEditorSheet(context, task: task),
                icon: const Icon(Symbols.edit_rounded),
              ),
              PopupMenuButton<String>(
                useRootNavigator: true,
                tooltip: context.l10n.taskActions,
                onSelected: (value) async {
                  if (value == 'skip') {
                    await skipTaskWithConfirmation(context, ref, task);
                    return;
                  }
                  if (value == 'postpone') {
                    await postponeTaskWithDialog(context, ref, task);
                    return;
                  }
                  if (value == 'set_enabled') {
                    await setTaskEnabledWithFeedback(
                      context,
                      ref,
                      task,
                      !task.plan.isEnabled,
                    );
                    return;
                  }
                  if (value == 'delete') {
                    final deleted = await deleteTaskWithConfirmation(
                      context,
                      ref,
                      task,
                    );
                    if (deleted && context.mounted) {
                      if (context.canPop()) {
                        context.pop();
                      } else {
                        context.go('/maintenance');
                      }
                    }
                  }
                },
                itemBuilder: (context) => [
                  if (task.plan.isEnabled)
                    PopupMenuItem(
                      value: 'skip',
                      child: hk_ui.PopupActionLabel(
                        icon: Symbols.skip_next_rounded,
                        label: context.l10n.skipThisOccurrence,
                      ),
                    ),
                  if (task.plan.isEnabled)
                    PopupMenuItem(
                      value: 'postpone',
                      child: hk_ui.PopupActionLabel(
                        icon: Symbols.edit_calendar_rounded,
                        label: context.l10n.postponeDueDate,
                      ),
                    ),
                  PopupMenuItem(
                    value: 'set_enabled',
                    child: hk_ui.PopupActionLabel(
                      icon: task.plan.isEnabled
                          ? Symbols.pause_circle_rounded
                          : Symbols.play_circle_rounded,
                      label: task.plan.isEnabled
                          ? context.l10n.disableTask
                          : context.l10n.enableTask,
                    ),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: hk_ui.PopupActionLabel(
                      icon: Symbols.delete_rounded,
                      label: context.l10n.moveTaskToTrash,
                      destructive: true,
                    ),
                  ),
                ],
              ),
            ],
          ),
          bottomNavigationBar: task.plan.isEnabled
              ? hk_ui.PremiumBottomActionBar(
                  label: context.l10n.completeTask,
                  icon: Symbols.check_circle_rounded,
                  onPressed: () async {
                    await completeTaskWithFeedback(
                      context,
                      ref,
                      task,
                      collectNotes: true,
                    );
                  },
                )
              : null,
          body: RepaintBoundary(
            key: const ValueKey('task-detail-stability-boundary'),
            child: Center(
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
                    const HkNativeAdCard(placement: 'task_detail'),
                    hk_ui.PremiumCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              CircleAvatar(
                                radius: 17,
                                backgroundColor: Theme.of(context)
                                    .colorScheme
                                    .secondaryContainer,
                                child: Icon(
                                  iconForAssetType(task.asset.assetType),
                                ),
                              ),
                              const SizedBox(width: HkSpacing.sm),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    DynamicText(
                                      task.plan.title,
                                      contentType: 'maintenance_plan.title',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w800,
                                          ),
                                    ),
                                    const SizedBox(height: 4),
                                    DynamicText(
                                      '${task.asset.name} \u00B7 ${task.room.name}',
                                      contentType: 'task.location',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium
                                          ?.copyWith(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .onSurfaceVariant,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: HkSpacing.xs),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              if (task.plan.isEnabled)
                                hk_ui.StatusPill(
                                  label: taskStatusLabel(context, task.status),
                                  color: taskStatusColor(context, task.status),
                                )
                              else
                                hk_ui.StatusPill(
                                  label: context.l10n.disabled,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                  icon: Symbols.pause_circle_rounded,
                                  semanticLabel: context.l10n.taskDisabled,
                                ),
                              hk_ui.StatusPill(
                                label: recurrenceLabel(
                                  context,
                                  task.plan.recurrence,
                                ),
                                color: Theme.of(context).colorScheme.primary,
                              ),
                              hk_ui.StatusPill(
                                label: priorityLabel(
                                  context,
                                  task.plan.priority,
                                ),
                                color: HkColors.tertiary,
                              ),
                            ],
                          ),
                          const SizedBox(height: HkSpacing.xs),
                          DetailRow(
                            icon: Symbols.event_rounded,
                            label: context.l10n.nextDue,
                            value: formatLongDate(
                              context,
                              task.plan.nextDueDate,
                            ),
                          ),
                          if (task.plan.reminderDaysBefore > 0)
                            DetailRow(
                              icon: Symbols.notifications_active_rounded,
                              label: context.l10n.reminder,
                              value: context.l10n.reminderDaysBeforeDue(
                                task.plan.reminderDaysBefore,
                              ),
                            ),
                          if (task.plan.instructions?.trim().isNotEmpty ??
                              false)
                            DetailRow(
                              icon: Symbols.notes_rounded,
                              label: context.l10n.instructions,
                              value: task.plan.instructions!,
                              contentType: 'maintenance_plan.instructions',
                            ),
                          ...taskMetadataRows(context, task.plan.metadata),
                          const SizedBox(height: HkSpacing.xs),
                          _TaskItemActionRow(
                            itemName: task.asset.name,
                            roomName: task.room.name,
                            onOpen: () =>
                                context.push('/assets/thing/${task.asset.id}'),
                          ),
                        ],
                      ),
                    ),
                    hk_ui.SectionHeader(
                      title: context.l10n.timeline,
                      subtitle: context.l10n.completionHistoryForThisTask,
                    ),
                    records.when(
                      data: (items) => MaintenanceTimeline(
                        records: items,
                        taskTitle: task.plan.title,
                      ),
                      error: (error, _) => hk_ui.ErrorPanel(
                        message: failureMessage(context, error),
                      ),
                      loading: () =>
                          const Center(child: CircularProgressIndicator()),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
      error: (error, _) => Scaffold(
        appBar: AppBar(title: Text(context.l10n.task)),
        body: hk_ui.ErrorPanel(
          message: failureMessage(context, error),
          onRetry: () => ref.invalidate(taskDetailProvider(planId)),
        ),
      ),
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
    );
  }
}

class _TaskItemActionRow extends StatelessWidget {
  const _TaskItemActionRow({
    required this.itemName,
    required this.roomName,
    required this.onOpen,
  });

  final String itemName;
  final String roomName;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.34),
        borderRadius: BorderRadius.circular(HkRadii.lg),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Symbols.inventory_2_rounded,
              color: scheme.primary,
              size: 20,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.l10n.item,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  '$itemName · $roomName',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton(
            onPressed: onOpen,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(48, 48),
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
            child: Text(context.l10n.openItem),
          ),
        ],
      ),
    );
  }
}
