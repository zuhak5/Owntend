part of 'maintenance_presentation.dart';

class CalendarScreen extends ConsumerStatefulWidget {
  const CalendarScreen({super.key});

  @override
  ConsumerState<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends ConsumerState<CalendarScreen> {
  late DateTime _visibleMonth;
  late DateTime _selectedDate;
  late DateTime _observedToday;

  @override
  void initState() {
    super.initState();
    final today = hk_dates.dateOnly(ref.read(localNowProvider)());
    _visibleMonth = DateTime(today.year, today.month);
    _selectedDate = today;
    _observedToday = today;
  }

  @override
  Widget build(BuildContext context) {
    final now =
        ref.watch(localClockProvider).value ?? ref.read(localNowProvider)();
    final today = hk_dates.dateOnly(now);
    if (today != _observedToday) {
      final wasFollowingToday = _selectedDate == _observedToday;
      _observedToday = today;
      if (wasFollowingToday) {
        _selectedDate = today;
        _visibleMonth = DateTime(today.year, today.month);
      }
    }
    final tasksState = ref.watch(tasksProvider);
    if (!tasksState.hasValue) {
      return Scaffold(
        appBar: AppBar(title: Text(context.l10n.calendar)),
        body: tasksState.hasError
            ? hk_ui.ErrorPanel(
                message: failureMessage(context, tasksState.error!),
                onRetry: () => ref.invalidate(tasksProvider),
              )
            : const Center(child: CircularProgressIndicator()),
      );
    }
    final tasks = tasksState.value!;
    final buckets = getTaskBuckets(tasks, now);
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
                    today: today,
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
                      formatLongDate(context, _selectedDate),
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
                                formatLongDate(context, _selectedDate),
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

class _CalendarSummaryCard extends StatelessWidget {
  const _CalendarSummaryCard({
    required this.overdue,
    required this.today,
    required this.upcoming,
  });

  final int overdue;
  final int today;
  final int upcoming;

  @override
  Widget build(BuildContext context) {
    return hk_ui.PremiumCard(
      borderRadius: HkRadii.xxl,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerLowest
          .withValues(alpha: 0.92),
      child: SizedBox(
        height: 70,
        child: Row(
          children: [
            Expanded(
              child: _MiniCalendarMetric(
                label: context.l10n.overdue,
                value: overdue,
                color: HkColors.tertiary,
                icon: Symbols.warning_rounded,
              ),
            ),
            Expanded(
              child: _MiniCalendarMetric(
                label: context.l10n.today,
                value: today,
                color: HkColors.amber,
                icon: Symbols.today_rounded,
              ),
            ),
            Expanded(
              child: _MiniCalendarMetric(
                label: context.l10n.upcoming,
                value: upcoming,
                color: Theme.of(context).colorScheme.primary,
                icon: Symbols.event_upcoming_rounded,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniCalendarMetric extends StatelessWidget {
  const _MiniCalendarMetric({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });

  final String label;
  final int value;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, color: color, size: 16),
        const SizedBox(height: 2),
        Text(
          '$value',
          style: Theme.of(context).textTheme.titleLarge
              ?.copyWith(color: color, fontWeight: FontWeight.w800),
        ),
        Text(label, style: Theme.of(context).textTheme.labelSmall),
      ],
    );
  }
}

class _CalendarMonthCard extends StatelessWidget {
  const _CalendarMonthCard({
    required this.month,
    required this.today,
    required this.selectedDate,
    required this.taskCounts,
    required this.onDateSelected,
    required this.onPreviousMonth,
    required this.onNextMonth,
  });

  final DateTime month;
  final DateTime today;
  final DateTime selectedDate;
  final Map<DateTime, int> taskCounts;
  final ValueChanged<DateTime> onDateSelected;
  final VoidCallback onPreviousMonth;
  final VoidCallback onNextMonth;

  @override
  Widget build(BuildContext context) {
    final weeks = hk_dates.calendarMonthGrid(month);
    final weekdayFormat = DateFormat.E(localeTag(context));
    final weekdays = [
      for (var offset = 0; offset < DateTime.daysPerWeek; offset += 1)
        weekdayFormat.format(DateTime(2024, 1, 7 + offset)),
    ];
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return hk_ui.PremiumCard(
      borderRadius: HkRadii.xxl,
      padding: const EdgeInsets.all(14),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  DateFormat.yMMMM(localeTag(context)).format(month),
                  style: Theme.of(context).textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              IconButton(
                tooltip: context.l10n.previousMonth,
                onPressed: onPreviousMonth,
                iconSize: 18,
                style: IconButton.styleFrom(
                  minimumSize: const Size(48, 48),
                  padding: EdgeInsets.zero,
                ),
                icon: Icon(
                  rtl
                      ? Symbols.chevron_right_rounded
                      : Symbols.chevron_left_rounded,
                ),
              ),
              IconButton(
                tooltip: context.l10n.nextMonth,
                onPressed: onNextMonth,
                iconSize: 18,
                style: IconButton.styleFrom(
                  minimumSize: const Size(48, 48),
                  padding: EdgeInsets.zero,
                ),
                icon: Icon(
                  rtl
                      ? Symbols.chevron_left_rounded
                      : Symbols.chevron_right_rounded,
                ),
              ),
            ],
          ),
          const SizedBox(height: HkSpacing.space4),
          Row(
            children: [
              for (final weekday in weekdays)
                Expanded(
                  child: Center(
                    child: Text(
                      weekday,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: HkSpacing.space4),
          Column(
            children: [
              for (
                var weekIndex = 0;
                weekIndex < weeks.length;
                weekIndex++
              ) ...[
                Row(
                  children: [
                    for (
                      var dayIndex = 0;
                      dayIndex < weeks[weekIndex].length;
                      dayIndex++
                    ) ...[
                      Expanded(
                        child: AspectRatio(
                          aspectRatio: 1,
                          child: _CalendarDayCell(
                            date: weeks[weekIndex][dayIndex],
                            selectedDate: selectedDate,
                            today: today,
                            taskCounts: taskCounts,
                            onDateSelected: onDateSelected,
                          ),
                        ),
                      ),
                      if (dayIndex != weeks[weekIndex].length - 1)
                        const SizedBox(width: HkSpacing.space4),
                    ],
                  ],
                ),
                if (weekIndex != weeks.length - 1)
                  const SizedBox(height: HkSpacing.space4),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _CalendarDayCell extends StatelessWidget {
  const _CalendarDayCell({
    required this.date,
    required this.selectedDate,
    required this.today,
    required this.taskCounts,
    required this.onDateSelected,
  });

  final DateTime? date;
  final DateTime selectedDate;
  final DateTime today;
  final Map<DateTime, int> taskCounts;
  final ValueChanged<DateTime> onDateSelected;

  @override
  Widget build(BuildContext context) {
    final dateValue = date;
    if (dateValue == null) {
      return const SizedBox.shrink();
    }
    final dayValue = dateValue.day;
    final dateOnly = hk_dates.dateOnly(dateValue);
    final selected = hk_dates.isSameDate(dateOnly, selectedDate);
    final isToday = hk_dates.isSameDate(dateOnly, today);
    final count = taskCounts[dateOnly] ?? 0;
    final scheme = Theme.of(context).colorScheme;
    final background = selected
        ? scheme.primary
        : count > 0
        ? scheme.secondaryContainer
        : scheme.surfaceContainerLowest;
    final foreground = selected ? scheme.onPrimary : scheme.onSurface;
    return Semantics(
      button: true,
      selected: selected,
      label: context.l10n.calendarDaySummary(
        isToday.toString(),
        DateFormat.yMMMMd(Localizations.localeOf(context).toLanguageTag())
            .format(dateOnly),
        count,
      ),
      child: InkWell(
        key: ValueKey('calendar-day-${dateOnly.toIso8601String()}'),
        borderRadius: BorderRadius.circular(HkRadii.md),
        onTap: () => onDateSelected(dateOnly),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(HkRadii.md),
            border: Border.all(
              color: isToday && !selected
                  ? scheme.primary.withValues(alpha: 0.55)
                  : Colors.transparent,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '$dayValue',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: foreground,
                  fontWeight: selected || isToday
                      ? FontWeight.w800
                      : FontWeight.w600,
                ),
              ),
              if (count > 0)
                Text(
                  '$count',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: foreground,
                    fontWeight: FontWeight.w800,
                  ),
                )
              else
                const SizedBox.shrink(),
            ],
          ),
        ),
      ),
    );
  }
}
