part of '../components.dart';

class StatusPill extends StatelessWidget {
  const StatusPill({
    required this.label,
    required this.color,
    this.icon,
    this.compact = false,
    this.contentType,
    this.semanticLabel,
    super.key,
  });

  final String label;
  final Color color;
  final IconData? icon;
  final bool compact;
  final String? contentType;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final pill = Container(
      constraints: BoxConstraints(minHeight: compact ? 22 : 26),
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 7 : 9,
        vertical: compact ? 3 : 4,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(HkRadii.full),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: compact ? 12 : 14, color: color),
            const SizedBox(width: HkSpacing.base),
          ],
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: compact ? 110 : 160),
            child: contentType == null
                ? Text(
                    label,
                    style: Theme.of(context).textTheme.labelMedium
                        ?.copyWith(color: color, fontWeight: FontWeight.w700),
                  )
                : DynamicText(
                    label,
                    contentType: contentType!,
                    style: Theme.of(context).textTheme.labelMedium
                        ?.copyWith(color: color, fontWeight: FontWeight.w700),
                  ),
          ),
        ],
      ),
    );
    if (semanticLabel == null) {
      return pill;
    }
    return Semantics(label: semanticLabel, child: pill);
  }
}

class ItemDueIndicator extends StatelessWidget {
  const ItemDueIndicator({required this.summary, super.key});

  final ItemTaskStatusSummary summary;

  @override
  Widget build(BuildContext context) {
    return StatusPill(
      label: itemDueLabel(context, summary),
      color: _itemDueColor(context, summary.status),
      icon: _itemDueIcon(summary.status),
      compact: true,
    );
  }
}

String itemDueLabel(BuildContext context, ItemTaskStatusSummary summary) {
  return switch (summary.status) {
    ItemDueStatus.overdue => context.l10n.itemStatusOverdue(summary.count),
    ItemDueStatus.dueToday => context.l10n.itemStatusDueToday(summary.count),
    ItemDueStatus.dueSoon => context.l10n.itemStatusDueSoon(summary.count),
    ItemDueStatus.onTrack => context.l10n.onTrack,
    ItemDueStatus.noTasks => context.l10n.noTasks,
  };
}

Color itemDueAccentColor(BuildContext context, ItemDueStatus status) {
  return _itemDueColor(context, status);
}

Color _itemDueColor(BuildContext context, ItemDueStatus status) {
  final scheme = Theme.of(context).colorScheme;
  return switch (status) {
    ItemDueStatus.overdue => HkColors.appDanger,
    ItemDueStatus.dueToday => HkColors.appWarning,
    ItemDueStatus.dueSoon => HkColors.appInfo,
    ItemDueStatus.onTrack => scheme.primary,
    ItemDueStatus.noTasks => scheme.onSurfaceVariant,
  };
}

IconData _itemDueIcon(ItemDueStatus status) {
  return switch (status) {
    ItemDueStatus.overdue => Symbols.warning_rounded,
    ItemDueStatus.dueToday => Symbols.today_rounded,
    ItemDueStatus.dueSoon => Symbols.event_upcoming_rounded,
    ItemDueStatus.onTrack => Symbols.check_circle_rounded,
    ItemDueStatus.noTasks => Symbols.remove_circle_outline_rounded,
  };
}

class _InlineSeparator extends StatelessWidget {
  const _InlineSeparator();

  @override
  Widget build(BuildContext context) {
    return Text(
      ' · ',
      style: Theme.of(context).textTheme.bodySmall
          ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
    );
  }
}

class TaskCard extends StatefulWidget {
  const TaskCard({
    required this.task,
    this.onComplete,
    this.onEdit,
    this.onSnooze,
    this.onArchive,
    this.onSetEnabled,
    this.onTap,
    this.dense = false,
    this.showChevron = false,
    this.showLocation = true,
    this.margin,
    super.key,
  });

  final TaskItem task;
  final Future<bool> Function()? onComplete;
  final VoidCallback? onEdit;
  final VoidCallback? onSnooze;
  final VoidCallback? onArchive;
  final Future<void> Function(bool enabled)? onSetEnabled;
  final VoidCallback? onTap;
  final bool dense;
  final bool showChevron;
  final bool showLocation;
  final EdgeInsetsGeometry? margin;

  @override
  State<TaskCard> createState() => _TaskCardState();
}

class _TaskCardState extends State<TaskCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _completionController;
  bool _completing = false;

  @override
  void initState() {
    super.initState();
    _completionController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
      reverseDuration: const Duration(milliseconds: 180),
    );
  }

  @override
  void dispose() {
    _completionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _completionController,
      builder: (context, _) => _buildCard(context, _completionController.value),
    );
  }

  Widget _buildCard(BuildContext context, double completionProgress) {
    final task = widget.task;
    final disabled = !task.plan.isEnabled;
    final onComplete = disabled ? null : widget.onComplete;
    final onEdit = widget.onEdit;
    final onSnooze = disabled ? null : widget.onSnooze;
    final onArchive = widget.onArchive;
    final onSetEnabled = widget.onSetEnabled;
    final onTap = widget.onTap;
    final dense = widget.dense;
    final showChevron = widget.showChevron;
    final showLocation = widget.showLocation;
    final margin = widget.margin;
    final scheme = Theme.of(context).colorScheme;
    final colors = _taskColors(
      task.status,
      task.plan.priority,
      disabled: disabled,
    );
    final completed = task.status == TaskStatus.completed;
    final visuallyCompleted = completed || completionProgress > 0.52;
    final locationText = '${task.asset.name} · ${task.room.name}';
    final primaryMeta =
        '${localizedAssetTypeLabel(context, task.asset.assetType)} · ${_localizedPriorityLabel(context, task.plan.priority)}';
    final statusText = _statusText(context, task);
    final card = PremiumCard(
      margin:
          margin ??
          EdgeInsets.only(bottom: dense ? HkSpacing.xs : HkSpacing.sm),
      padding: EdgeInsets.symmetric(
        horizontal: dense ? HkSpacing.xs : 9,
        vertical: dense ? HkSpacing.space6 : 7,
      ),
      borderRadius: kSwipeRowRadius,
      backgroundColor: Color.alphaBlend(
        scheme.primary.withValues(alpha: 0.10 * completionProgress),
        scheme.surfaceContainerLowest,
      ),
      borderColor: Color.lerp(
        !disabled && task.status == TaskStatus.overdue
            ? HkColors.appDanger.withValues(alpha: 0.22)
            : scheme.outlineVariant,
        scheme.primary.withValues(alpha: 0.55),
        completionProgress,
      ),
      shadows: const [],
      child: Stack(
        children: [
          if (completionProgress > 0)
            Positioned.fill(
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: FractionallySizedBox(
                  key: const ValueKey('task-completion-sweep'),
                  widthFactor: completionProgress.clamp(0.0, 1.0),
                  child: ColoredBox(
                    color: scheme.primary.withValues(alpha: 0.07),
                  ),
                ),
              ),
            ),
          if (!disabled && task.status == TaskStatus.overdue)
            PositionedDirectional(
              start: -10,
              top: -10,
              bottom: -10,
              child: Container(width: 3, color: colors.accent),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: dense ? 28 : 30,
                height: dense ? 28 : 30,
                decoration: BoxDecoration(
                  color: colors.container,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _taskIcon(task),
                  color: colors.accent,
                  size: dense ? 16 : 17,
                ),
              ),
              const SizedBox(width: HkSpacing.xs),
              Expanded(
                child: Opacity(
                  opacity: visuallyCompleted
                      ? 0.62
                      : disabled
                      ? 0.82
                      : 1 - (0.20 * completionProgress),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      DynamicText(
                        task.plan.title,
                        contentType: 'maintenance_plan.title',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          decoration: visuallyCompleted
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        primaryMeta,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: disabled
                              ? scheme.onSurfaceVariant
                              : colors.accent,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        runSpacing: 1,
                        children: [
                          Icon(
                            Symbols.autorenew_rounded,
                            size: 14,
                            color: scheme.primary,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            _recurrenceText(context, task.plan.recurrence),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                          const _InlineSeparator(),
                          if (disabled)
                            StatusPill(
                              label: context.l10n.disabled,
                              color: scheme.onSurfaceVariant,
                              icon: Symbols.pause_circle_rounded,
                              compact: true,
                              semanticLabel: context.l10n.taskDisabled,
                            )
                          else
                            Text(
                              statusText,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: task.status == TaskStatus.overdue
                                        ? colors.accent
                                        : scheme.onSurfaceVariant,
                                    fontWeight:
                                        task.status == TaskStatus.overdue
                                        ? FontWeight.w600
                                        : FontWeight.w400,
                                  ),
                            ),
                          if (showLocation) ...[
                            const _InlineSeparator(),
                            DynamicText(
                              locationText,
                              contentType: 'task.location',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: scheme.onSurfaceVariant),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: HkSpacing.space4),
              if (onComplete != null ||
                  onEdit != null ||
                  onSnooze != null ||
                  onArchive != null ||
                  onSetEnabled != null)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (onComplete != null)
                      IconButton(
                        tooltip: context.l10n.completeTask,
                        onPressed: _completing ? null : _handleComplete,
                        iconSize: 20,
                        style: IconButton.styleFrom(
                          backgroundColor: scheme.primary.withValues(
                            alpha: 0.10 + (0.75 * completionProgress),
                          ),
                          foregroundColor: Color.lerp(
                            scheme.primary,
                            scheme.onPrimary,
                            completionProgress,
                          ),
                          minimumSize: Size.square(dense ? 36 : 38),
                          fixedSize: Size.square(dense ? 36 : 38),
                          padding: EdgeInsets.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        icon: Icon(
                          completionProgress > 0.52
                              ? Symbols.check_rounded
                              : Symbols.check_circle_rounded,
                        ),
                      ),
                    if (onComplete != null &&
                        (onEdit != null ||
                            onSnooze != null ||
                            onArchive != null ||
                            onSetEnabled != null))
                      const SizedBox(width: HkSpacing.space4),
                    if (onEdit != null ||
                        onSnooze != null ||
                        onArchive != null ||
                        onSetEnabled != null)
                      Container(
                        width: dense ? 36 : 38,
                        height: dense ? 36 : 38,
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerLow,
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: PopupMenuButton<String>(
                            useRootNavigator: true,
                            tooltip: context.l10n.taskActions,
                            padding: EdgeInsets.zero,
                            iconSize: 20,
                            icon: Icon(
                              Symbols.more_vert_rounded,
                              color: scheme.onSurfaceVariant,
                            ),
                            onSelected: (value) {
                              if (value == 'edit') {
                                onEdit?.call();
                              } else if (value == 'snooze') {
                                onSnooze?.call();
                              } else if (value == 'archive') {
                                onArchive?.call();
                              } else if (value == 'set_enabled') {
                                final callback = onSetEnabled;
                                if (callback != null) {
                                  unawaited(callback(disabled));
                                }
                              }
                            },
                            itemBuilder: (context) => [
                              if (onEdit != null)
                                PopupMenuItem(
                                  value: 'edit',
                                  child: _TaskMenuActionLabel(
                                    icon: Symbols.edit_rounded,
                                    label: context.l10n.editPlan,
                                  ),
                                ),
                              if (onSnooze != null)
                                PopupMenuItem(
                                  value: 'snooze',
                                  child: _TaskMenuActionLabel(
                                    icon: Symbols.snooze_rounded,
                                    label: context.l10n.snooze,
                                  ),
                                ),
                              if (onSetEnabled != null)
                                PopupMenuItem(
                                  value: 'set_enabled',
                                  child: _TaskMenuActionLabel(
                                    icon: disabled
                                        ? Symbols.play_circle_rounded
                                        : Symbols.pause_circle_rounded,
                                    label: disabled
                                        ? context.l10n.enableTask
                                        : context.l10n.disableTask,
                                  ),
                                ),
                              if (onArchive != null)
                                PopupMenuItem(
                                  value: 'archive',
                                  child: _TaskMenuActionLabel(
                                    icon: Symbols.delete_rounded,
                                    label: context.l10n.moveTaskToTrash,
                                    destructive: true,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                  ],
                )
              else if (showChevron)
                Icon(
                  Symbols.chevron_right_rounded,
                  color: scheme.outlineVariant,
                  size: 20,
                ),
            ],
          ),
        ],
      ),
    );
    if (onTap == null) {
      return _scaleForCompletion(card, completionProgress);
    }
    final interactiveCard = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _completing ? null : onTap,
      child: card,
    );
    return _scaleForCompletion(interactiveCard, completionProgress);
  }

  Widget _scaleForCompletion(Widget child, double progress) {
    final scale = progress <= 0.5
        ? 1 - (0.025 * (progress / 0.5))
        : 0.975 + (0.025 * ((progress - 0.5) / 0.5));
    return Transform.scale(scale: scale, child: child);
  }

  Future<void> _handleComplete() async {
    final callback = widget.onComplete;
    if (callback == null || _completing) {
      return;
    }
    setState(() => _completing = true);
    final reduceMotion = HkMotion.reduceMotionOf(context);
    if (reduceMotion) {
      _completionController.value = 1;
    } else {
      unawaited(_completionController.forward(from: 0));
    }
    var success = false;
    try {
      success = await callback();
    } catch (_) {
      success = false;
    }
    if (!mounted) {
      return;
    }
    if (!success || widget.task.status != TaskStatus.completed) {
      await _completionController.reverse();
    }
    if (mounted) {
      setState(() => _completing = false);
    }
  }
}

class _TaskMenuActionLabel extends StatelessWidget {
  const _TaskMenuActionLabel({
    required this.icon,
    required this.label,
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = destructive ? scheme.error : scheme.onSurface;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: HkSpacing.sm),
        Flexible(
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontWeight: destructive ? FontWeight.w700 : FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}
