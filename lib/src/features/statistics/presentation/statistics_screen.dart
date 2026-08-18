part of '../../../../main.dart';

class StatisticsScreen extends ConsumerWidget {
  const StatisticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(statisticsProvider);
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.statistics)),
      body: RepaintBoundary(
        key: const ValueKey('statistics-stability-boundary'),
        child: stats.when(
          data: (summary) => SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1080),
                child: SingleChildScrollView(
                  padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const HkNativeAdCard(placement: 'statistics'),
                      _StatisticsMetricGrid(summary: summary),
                      const SizedBox(height: HkSpacing.sm),
                      _StatisticsChartsGrid(summary: summary),
                    ],
                  ),
                ),
              ),
            ),
          ),
          error: (error, _) =>
              ErrorPanel(message: _failureMessage(context, error)),
          loading: () => const Center(child: CircularProgressIndicator()),
        ),
      ),
    );
  }
}

class _StatisticsMetricGrid extends StatelessWidget {
  const _StatisticsMetricGrid({required this.summary});

  final StatisticsSummary summary;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final textScale = MediaQuery.textScalerOf(context).scale(1);
        const gap = HkSpacing.sm;
        const minimumMetricWidth = 168.0;
        final useTwoColumns =
            textScale < 1.6 &&
            constraints.maxWidth >= (minimumMetricWidth * 2) + gap;
        final columns = useTwoColumns ? 2 : 1;
        final itemWidth =
            (constraints.maxWidth - (gap * (columns - 1))) / columns;

        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            SizedBox(
              width: itemWidth,
              child: _StatisticMetric(
                key: const ValueKey('statistics-metric-completion'),
                label: context.l10n.historyCompletion,
                value: '${(summary.completionRate * 100).round()}%',
                icon: Symbols.done_all_rounded,
                color: HkColors.green,
              ),
            ),
            SizedBox(
              width: itemWidth,
              child: _StatisticMetric(
                key: const ValueKey('statistics-metric-overdue'),
                label: context.l10n.activeOverdue,
                value: '${(summary.overdueRate * 100).round()}%',
                icon: Symbols.warning_rounded,
                color: HkColors.red,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _StatisticsChartsGrid extends StatelessWidget {
  const _StatisticsChartsGrid({required this.summary});

  final StatisticsSummary summary;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final textScale = MediaQuery.textScalerOf(context).scale(1);
        final sideBySide = constraints.maxWidth >= 720 && textScale < 1.6;
        final monthly = _CompactChartPanel(
          key: const ValueKey('statistics-chart-monthly'),
          title: context.l10n.monthlyCompletions,
          child: MonthlyCompletionsChart(data: summary.completedByMonth),
        );
        final distribution = _CompactChartPanel(
          key: const ValueKey('statistics-chart-distribution'),
          title: context.l10n.taskDistribution,
          child: TaskDistributionChart(data: summary.taskDistribution),
        );

        if (!sideBySide) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              monthly,
              const SizedBox(height: HkSpacing.sm),
              distribution,
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: monthly),
            const SizedBox(width: HkSpacing.sm),
            Expanded(child: distribution),
          ],
        );
      },
    );
  }
}

class _StatisticMetric extends StatelessWidget {
  const _StatisticMetric({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    super.key,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      container: true,
      label: label,
      value: value,
      child: ExcludeSemantics(
        child: hk_ui.PremiumCard(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 60),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: color, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(
                              color: scheme.onSurface,
                              fontWeight: FontWeight.w800,
                              height: 1.15,
                            ),
                      ),
                      const SizedBox(height: HkSpacing.space4),
                      Text(
                        value,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: scheme.onSurface,
                              fontWeight: FontWeight.w900,
                              height: 1.05,
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
}

class _CompactChartPanel extends StatelessWidget {
  const _CompactChartPanel({
    required this.title,
    required this.child,
    super.key,
  });

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return hk_ui.PremiumCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: HkSpacing.sm),
          child,
        ],
      ),
    );
  }
}

class _StatisticsInlineEmptyState extends StatelessWidget {
  const _StatisticsInlineEmptyState({
    required this.icon,
    required this.title,
    required this.body,
    super.key,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 128),
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(12, 16, 12, 14),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ExcludeSemantics(
              child: Icon(icon, size: 30, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: HkSpacing.xs),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: scheme.onSurface,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: HkSpacing.space4),
            Text(
              body,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class MonthlyCompletionsChart extends StatelessWidget {
  const MonthlyCompletionsChart({required this.data, super.key});

  final Map<String, int> data;

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return _StatisticsInlineEmptyState(
        key: const ValueKey('statistics-monthly-empty'),
        icon: Icons.bar_chart,
        title: context.l10n.notEnoughDataYet,
        body: context.l10n.completeMoreTasksToSeeMonthlyTrends,
      );
    }
    final entries = data.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final maxValue = entries
        .map((entry) => entry.value)
        .fold<int>(0, math.max)
        .clamp(1, 10000)
        .toDouble();
    final semanticValue = entries
        .map(
          (entry) =>
              '${_statisticsMonthLabel(context, entry.key)} ${entry.value}',
        )
        .join(', ');

    return Semantics(
      key: const ValueKey('statistics-monthly-chart-semantics'),
      container: true,
      label: context.l10n.monthlyCompletions,
      value: semanticValue,
      child: ExcludeSemantics(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final chartHeight = math.min(
              280.0,
              math.max(200.0, constraints.maxWidth * 0.58),
            );
            return SizedBox(
              key: const ValueKey('statistics-monthly-chart'),
              height: chartHeight,
              child: BarChart(
                BarChartData(
                  borderData: FlBorderData(show: false),
                  maxY: maxValue + 1,
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    getDrawingHorizontalLine: (_) => FlLine(
                      color: Theme.of(context).colorScheme.outlineVariant,
                      strokeWidth: 1,
                    ),
                  ),
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 34,
                        getTitlesWidget: (value, meta) => Text(
                          value.round().toString(),
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          final index = value.toInt();
                          if (index < 0 || index >= entries.length) {
                            return const SizedBox.shrink();
                          }
                          return Text(
                            _statisticsMonthLabel(context, entries[index].key),
                            style: Theme.of(context).textTheme.labelSmall,
                          );
                        },
                      ),
                    ),
                    topTitles: const AxisTitles(),
                    rightTitles: const AxisTitles(),
                  ),
                  barGroups: [
                    for (var index = 0; index < entries.length; index++)
                      BarChartGroupData(
                        x: index,
                        showingTooltipIndicators: [0],
                        barRods: [
                          BarChartRodData(
                            toY: entries[index].value.toDouble(),
                            color: Theme.of(context).colorScheme.primary,
                            width: 18,
                          ),
                        ],
                      ),
                  ],
                  barTouchData: BarTouchData(
                    enabled: false,
                    touchTooltipData: BarTouchTooltipData(
                      getTooltipColor: (_) => Colors.transparent,
                      tooltipPadding: EdgeInsets.zero,
                      tooltipMargin: 2,
                      getTooltipItem: (group, groupIndex, rod, rodIndex) {
                        return BarTooltipItem(
                          rod.toY.round().toString(),
                          Theme.of(context).textTheme.labelSmall!.copyWith(
                            color: Theme.of(context).colorScheme.onSurface,
                            fontWeight: FontWeight.w800,
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

String _statisticsMonthLabel(BuildContext context, String value) {
  final parts = value.split('-');
  if (parts.length != 2) return value;
  final year = int.tryParse(parts[0]);
  final month = int.tryParse(parts[1]);
  if (year == null || month == null || month < 1 || month > 12) return value;
  final localeTag = Localizations.localeOf(context).toLanguageTag();
  return DateFormat.MMM(localeTag).format(DateTime(year, month));
}

class TaskDistributionChart extends StatelessWidget {
  const TaskDistributionChart({required this.data, super.key});

  final Map<HealthGroup, int> data;

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return _StatisticsInlineEmptyState(
        key: const ValueKey('statistics-distribution-empty'),
        icon: Icons.pie_chart,
        title: context.l10n.noTaskDistribution,
        body: context.l10n.scheduledPlansWillAppearHere,
      );
    }
    final colors = [
      Colors.teal,
      Colors.indigo,
      Colors.orange,
      Colors.green,
      Colors.pink,
      Colors.blueGrey,
    ];
    final entries = data.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final total = entries.fold<int>(0, (sum, entry) => sum + entry.value);
    final semanticValue = entries
        .map(
          (entry) => '${_healthGroupLabel(context, entry.key)} ${entry.value}',
        )
        .join(', ');
    final sectionTitleStyle =
        Theme.of(context).textTheme.labelSmall
            ?.copyWith(color: Colors.white, fontWeight: FontWeight.w700) ??
        const TextStyle(
          fontSize: 11,
          color: Colors.white,
          fontWeight: FontWeight.w700,
        );

    return Semantics(
      key: const ValueKey('statistics-distribution-chart-semantics'),
      container: true,
      label: context.l10n.taskDistribution,
      value: semanticValue,
      child: ExcludeSemantics(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final chartHeight = math.min(
                  230.0,
                  math.max(180.0, constraints.maxWidth * 0.52),
                );
                final radius = math.min(
                  68.0,
                  math.max(
                    44.0,
                    math.min(constraints.maxWidth, chartHeight) * 0.30,
                  ),
                );
                return SizedBox(
                  key: const ValueKey('statistics-distribution-pie'),
                  height: chartHeight,
                  child: PieChart(
                    PieChartData(
                      sections: [
                        for (var index = 0; index < entries.length; index++)
                          PieChartSectionData(
                            value: entries[index].value.toDouble(),
                            title: NumberFormat.percentPattern(
                              _localeTag(context),
                            ).format(entries[index].value / total),
                            color: colors[index % colors.length],
                            radius: radius,
                            titleStyle: sectionTitleStyle,
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: HkSpacing.xs),
            LayoutBuilder(
              builder: (context, constraints) {
                const legendSpacing = HkSpacing.space4;
                final textScale = MediaQuery.textScalerOf(context).scale(1);
                final threeColumnWidth =
                    (constraints.maxWidth - (legendSpacing * 2)) / 3;
                final maxLegendWidth = math.min(
                  240.0,
                  textScale < 1.6 ? threeColumnWidth : constraints.maxWidth,
                );
                return Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Wrap(
                    key: const ValueKey('statistics-distribution-legend'),
                    spacing: legendSpacing,
                    runSpacing: legendSpacing,
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      for (var index = 0; index < entries.length; index++)
                        ConstrainedBox(
                          constraints: BoxConstraints(maxWidth: maxLegendWidth),
                          child: _StatisticsLegendItem(
                            key: ValueKey(
                              'statistics-legend-${entries[index].key.name}',
                            ),
                            label:
                                '${_healthGroupLabel(context, entries[index].key)} ${entries[index].value}',
                            color: colors[index % colors.length],
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _StatisticsLegendItem extends StatelessWidget {
  const _StatisticsLegendItem({
    required this.label,
    required this.color,
    super.key,
  });

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          color.withValues(alpha: 0.08),
          scheme.surfaceContainerLow,
        ),
        borderRadius: BorderRadius.circular(HkRadii.full),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(6, 4, 7, 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: scheme.onSurface,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
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
    required this.selectedDate,
    required this.taskCounts,
    required this.onDateSelected,
    required this.onPreviousMonth,
    required this.onNextMonth,
  });

  final DateTime month;
  final DateTime selectedDate;
  final Map<DateTime, int> taskCounts;
  final ValueChanged<DateTime> onDateSelected;
  final VoidCallback onPreviousMonth;
  final VoidCallback onNextMonth;

  @override
  Widget build(BuildContext context) {
    final weeks = hk_dates.calendarMonthGrid(month);
    final today = hk_dates.dateOnly(DateTime.now());
    final weekdayFormat = DateFormat.E(_localeTag(context));
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
                  DateFormat.yMMMM(_localeTag(context)).format(month),
                  style: Theme.of(context).textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              IconButton(
                tooltip: context.l10n.previousMonth,
                onPressed: onPreviousMonth,
                iconSize: 18,
                style: IconButton.styleFrom(
                  minimumSize: const Size(40, 40),
                  padding: EdgeInsets.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
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
                  minimumSize: const Size(40, 40),
                  padding: EdgeInsets.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
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
              SizedBox(
                height: 11,
                child: count > 0
                    ? Text(
                        '$count',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: foreground,
                          fontWeight: FontWeight.w800,
                        ),
                      )
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
