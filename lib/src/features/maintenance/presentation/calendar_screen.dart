part of '../../../../main.dart';

class CalendarScreen extends ConsumerStatefulWidget {
  const CalendarScreen({super.key});

  @override
  ConsumerState<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends ConsumerState<CalendarScreen> {
  late DateTime _visibleMonth;
  late DateTime _selectedDate;

  @override
  void initState() {
    super.initState();
    final today = hk_dates.dateOnly(DateTime.now());
    _visibleMonth = DateTime(today.year, today.month);
    _selectedDate = today;
  }

  @override
  Widget build(BuildContext context) {
    final tasks = ref.watch(tasksProvider).value ?? [];
    final buckets = getTaskBuckets(tasks, DateTime.now());
    final grouped = groupTasksByDueDate(tasks);
    final taskCounts = {
      for (final entry in grouped.entries) entry.key: entry.value.length,
    };
    final selectedTasks = grouped[_selectedDate] ?? const <TaskItem>[];
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.calendar)),
      body: hk_ui.ProductivityBackdrop(
        child: Center(
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
                const HkNativeAdCard(placement: 'calendar'),
                hk_ui.PremiumEntrance(
                  child: _CalendarSummaryCard(
                    overdue: buckets.overdueCount,
                    today: buckets.todayCount,
                    upcoming: buckets.upcomingCount,
                  ),
                ),
                const SizedBox(height: HkSpacing.sm),
                hk_ui.PremiumEntrance(
                  delay: const Duration(milliseconds: 80),
                  child: _CalendarMonthCard(
                    month: _visibleMonth,
                    selectedDate: _selectedDate,
                    taskCounts: taskCounts,
                    onDateSelected: (date) {
                      setState(() => _selectedDate = date);
                    },
                    onPreviousMonth: () => _changeMonth(-1),
                    onNextMonth: () => _changeMonth(1),
                  ),
                ),
                const SizedBox(height: HkSpacing.xs),
                Text(
                  context.l10n.calendarLegend,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                if (selectedTasks.isEmpty)
                  hk_ui.PremiumEmptyState(
                    icon: Symbols.event_available_rounded,
                    illustrationTone: hk_ui.HkIllustrationTone.neutral,
                    title: context.l10n.noTasksOnThisDay,
                    body: context.l10n.selectedDateLabel(
                      _formatLongDate(context, _selectedDate),
                    ),
                  )
                else
                  hk_ui.PremiumCard(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.primary,
                                borderRadius: BorderRadius.circular(HkRadii.md),
                              ),
                              child: Center(
                                child: Text(
                                  '${_selectedDate.day}',
                                  style: Theme.of(context).textTheme.titleMedium
                                      ?.copyWith(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onPrimary,
                                        fontWeight: FontWeight.w700,
                                      ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                _formatLongDate(context, _selectedDate),
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        for (final task in selectedTasks)
                          hk_ui.SwipeDelete(
                            margin: const EdgeInsets.only(bottom: HkSpacing.xs),
                            dismissKey: ValueKey(
                              'calendar-task-delete-${task.plan.id}',
                            ),
                            action: hk_ui.SwipeAction.moveToTrash(
                              onAction: () => deleteTaskWithConfirmation(
                                context,
                                ref,
                                task,
                              ),
                            ),
                            child: hk_ui.TaskCard(
                              task: task,
                              dense: true,
                              margin: EdgeInsets.zero,
                              onTap: () =>
                                  context.push('/maintenance/${task.plan.id}'),
                              onComplete: () =>
                                  completeTaskWithFeedback(context, ref, task),
                              onSnooze: () =>
                                  snoozeTaskWithFeedback(context, ref, task),
                              onSetEnabled: (enabled) =>
                                  setTaskEnabledWithFeedback(
                                    context,
                                    ref,
                                    task,
                                    enabled,
                                  ),
                              onArchive: () => deleteTaskWithConfirmation(
                                context,
                                ref,
                                task,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _changeMonth(int offset) {
    final nextMonth = DateTime(
      _visibleMonth.year,
      _visibleMonth.month + offset,
    );
    final lastDay = DateTime(nextMonth.year, nextMonth.month + 1, 0).day;
    final selectedDay = _selectedDate.day > lastDay
        ? lastDay
        : _selectedDate.day;
    setState(() {
      _visibleMonth = nextMonth;
      _selectedDate = hk_dates.dateOnly(
        DateTime(nextMonth.year, nextMonth.month, selectedDay),
      );
    });
  }
}
