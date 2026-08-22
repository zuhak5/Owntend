part of '../components.dart';

class ToolTile extends StatelessWidget {
  const ToolTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    super.key,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PremiumCard(
      margin: const EdgeInsets.only(bottom: HkSpacing.xs),
      padding: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(HkRadii.lg),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: scheme.secondaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: scheme.primary, size: 18),
              ),
              const SizedBox(width: HkSpacing.xs),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: HkSpacing.space4),
              Icon(
                Symbols.chevron_right_rounded,
                color: scheme.outline,
                size: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum SereneBottomNavLabel { home, rooms, tasks, calendar, tools }

class SereneBottomNavDestination {
  const SereneBottomNavDestination({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });

  final IconData icon;
  final IconData selectedIcon;
  final SereneBottomNavLabel label;
}

class SereneBottomNavigationBar extends StatelessWidget {
  const SereneBottomNavigationBar({
    required this.selectedIndex,
    required this.destinations,
    required this.onDestinationSelected,
    super.key,
  });

  final int selectedIndex;
  final List<SereneBottomNavDestination> destinations;
  final ValueChanged<int> onDestinationSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Align(
        alignment: Alignment.bottomCenter,
        heightFactor: 1.0,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(HkRadii.xxl),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerLowest.withValues(
                      alpha: 0.91,
                    ),
                    borderRadius: BorderRadius.circular(HkRadii.xxl),
                    border: Border.all(
                      color: scheme.outlineVariant.withValues(alpha: 0.28),
                    ),
                    boxShadow: HkShadows.ambient(tint: scheme.primary),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 5, 8, 5),
                    child: Row(
                      children: [
                        for (
                          var index = 0;
                          index < destinations.length;
                          index++
                        )
                          Expanded(
                            child: _BottomNavItem(
                              destination: destinations[index],
                              selected: selectedIndex == index,
                              onTap: () => onDestinationSelected(index),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BottomNavItem extends StatelessWidget {
  const _BottomNavItem({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final SereneBottomNavDestination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = selected ? scheme.primary : scheme.onSurfaceVariant;
    final label = switch (destination.label) {
      SereneBottomNavLabel.home => context.l10n.home,
      SereneBottomNavLabel.rooms => context.l10n.rooms,
      SereneBottomNavLabel.tasks => context.l10n.tasks,
      SereneBottomNavLabel.calendar => context.l10n.calendar,
      SereneBottomNavLabel.tools => context.l10n.tools,
    };
    return Semantics(
      selected: selected,
      button: true,
      label: label,
      child: InkWell(
        borderRadius: BorderRadius.circular(HkRadii.lg),
        onTap: onTap,
        child: SizedBox(
          height: 52,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: selected ? 42 : 32,
                height: 24,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected
                      ? scheme.primary.withValues(alpha: 0.13)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(HkRadii.full),
                ),
                child: Icon(
                  selected ? destination.selectedIcon : destination.icon,
                  color: color,
                  size: 19,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: color,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

IconData _taskIcon(TaskItem task) {
  if (!task.plan.isEnabled) {
    return Symbols.pause_circle_rounded;
  }
  if (task.status == TaskStatus.completed) {
    return Symbols.check_circle_rounded;
  }
  return iconForAssetType(task.asset.assetType);
}

String _statusText(BuildContext context, TaskItem task) {
  final dueDate = task.plan.nextDueDate;
  final now = DateTime.now();
  return switch (task.status) {
    TaskStatus.overdue => context.l10n.statusOverdueBy(
      _overdueDayText(context, dueDate, now),
    ),
    TaskStatus.dueToday => _dueTodayText(context, dueDate, now),
    TaskStatus.upcoming => context.l10n.statusDueDate(
      _formatTaskDueDate(context, dueDate),
    ),
    TaskStatus.completed => context.l10n.completedToday,
  };
}

String _formatTaskDueDate(BuildContext context, DateTime dueDate) {
  final locale = Localizations.maybeLocaleOf(context)?.toString();
  try {
    return DateFormat.MMMd(locale).add_jm().format(dueDate);
  } on Object {
    return DateFormat.MMMd().add_jm().format(dueDate);
  }
}

String _overdueDayText(BuildContext context, DateTime dueDate, DateTime now) {
  final days = hk_dates.daysBetweenDates(dueDate, now).clamp(1, 10000);
  return days == 1
      ? context.l10n.durationDay(days)
      : context.l10n.durationDays(days);
}

String _dueTodayText(BuildContext context, DateTime dueDate, DateTime now) {
  final remaining = dueDate.difference(now);
  if (remaining.inMinutes <= 0) {
    return context.l10n.dueNow;
  }
  return context.l10n.statusDueIn(_durationText(context, remaining));
}

String _durationText(BuildContext context, Duration duration) {
  final minutes = duration.inMinutes.abs();
  if (minutes < 60) {
    return context.l10n.durationMinutesShort(minutes.clamp(1, 59));
  }
  if (minutes < 24 * 60) {
    final hours = minutes ~/ 60;
    final remainder = minutes % 60;
    return context.l10n.durationHoursMinutesShort(hours, remainder);
  }
  final days = minutes ~/ (24 * 60);
  return days == 1
      ? context.l10n.durationDay(days)
      : context.l10n.durationDays(days);
}

String _recurrenceText(BuildContext context, RecurrenceRule rule) =>
    localizedRecurrenceLabel(context, rule);

String _localizedPriorityLabel(BuildContext context, PriorityLevel priority) =>
    switch (priority) {
      PriorityLevel.low => context.l10n.routine,
      PriorityLevel.medium => context.l10n.medium,
      PriorityLevel.high => context.l10n.high,
      PriorityLevel.critical => context.l10n.critical,
    };

_TaskColors _taskColors(
  TaskStatus status,
  PriorityLevel priority, {
  bool disabled = false,
}) {
  if (disabled) {
    return const _TaskColors(HkColors.onSurfaceVariant, HkColors.surfaceDim);
  }
  if (status == TaskStatus.completed) {
    return const _TaskColors(HkColors.primary, HkColors.primaryFixed);
  }
  if (status == TaskStatus.overdue || priority == PriorityLevel.critical) {
    return const _TaskColors(HkColors.appDanger, HkColors.appDangerSurface);
  }
  if (priority == PriorityLevel.high) {
    return const _TaskColors(HkColors.appWarning, HkColors.appWarningSurface);
  }
  return const _TaskColors(HkColors.onSurfaceVariant, HkColors.appSurfaceGreen);
}
