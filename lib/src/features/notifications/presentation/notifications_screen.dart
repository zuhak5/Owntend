import '../../../core/utils/date_utils.dart' as hk_dates;
import '../../../ui/components.dart' as hk_ui;
import '../../../ui/presentation_support.dart';
import '../../maintenance/presentation/task_actions.dart';
import '../../monetization/monetization.dart';
import '../../../ui/widgets/notification_route_validation.dart';

class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  _NotificationFilter _filter = _NotificationFilter.all;

  @override
  Widget build(BuildContext context) {
    final notifications = ref.watch(notificationsProvider);
    final unreadCount = ref.watch(unreadNotificationsProvider).value ?? 0;
    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.inbox),
        actions: [
          if (unreadCount > 0)
            TextButton(
              onPressed: () =>
                  ref.read(notificationInboxRepositoryProvider).markAllRead(),
              child: Text(context.l10n.markAllRead),
            ),
        ],
      ),
      body: notifications.when(
        data: (items) {
          final unread = items.where((item) => item.unread).length;
          final visible = _groupNotifications(_filterNotifications(items));
          if (items.isEmpty) {
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                  children: [
                    hk_ui.PremiumEmptyState(
                      icon: Symbols.notifications_rounded,
                      title: context.l10n.noNotifications,
                      body: context.l10n.inboxMessagesAppearHere,
                    ),
                  ],
                ),
              ),
            );
          }
          final taskCount = items.where((item) => item.kind == 'task').length;
          final hasCriticalGuidance = items.any((item) {
            final text = '${item.title} ${item.body}'.toLowerCase();
            return text.contains('critical') || text.contains('overdue');
          });
          final children = <Widget>[
            if (!hasCriticalGuidance) ...[
              const HkNativeAdCard(placement: 'notifications'),
            ],
            _NotificationSummaryCard(
              total: items.length,
              unread: unread,
              tasks: taskCount,
            ),
            const SizedBox(height: HkSpacing.xs),
            _NotificationFilterChips(
              selected: _filter,
              onSelected: (filter) => setState(() => _filter = filter),
              unreadCount: unread,
            ),
            const SizedBox(height: HkSpacing.sm),
          ];
          if (visible.isEmpty) {
            children.add(
              hk_ui.PremiumEmptyState(
                icon: Symbols.filter_alt_off_rounded,
                illustrationTone: hk_ui.HkIllustrationTone.neutral,
                title: _filteredNotificationEmptyTitle(context, _filter),
                body: context.l10n.changeFilterForOtherUpdates,
                action: OutlinedButton(
                  onPressed: () =>
                      setState(() => _filter = _NotificationFilter.all),
                  child: Text(context.l10n.showAll),
                ),
              ),
            );
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                  children: children,
                ),
              ),
            );
          }
          DateTime? previousDay;
          for (final item in visible) {
            final completionRecords = item.planId == null
                ? const <MaintenanceRecord>[]
                : ref.watch(taskRecordsProvider(item.planId!)).value ??
                      const <MaintenanceRecord>[];
            final completedAt = _completedTaskNotificationAt(
              item,
              completionRecords,
            );
            final itemDay = hk_dates.dateOnly(item.createdAt);
            if (previousDay == null ||
                !hk_dates.isSameDate(previousDay, itemDay)) {
              children.add(
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
                  child: Text(
                    _notificationDateLabel(context, item.createdAt),
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ),
              );
              previousDay = itemDay;
            }
            children.add(
              NotificationCard(
                notification: item,
                completedAt: completedAt,
                onTap: () => _openNotification(context, ref, item),
                onAction: (action) => _handleAction(context, ref, item, action),
                onComplete: item.planId == null || completedAt != null
                    ? null
                    : () => _completeFromNotification(context, ref, item),
              ),
            );
          }
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                children: children,
              ),
            ),
          );
        },
        error: (error, _) =>
            hk_ui.ErrorPanel(message: failureMessage(context, error)),
        loading: () => const Center(child: CircularProgressIndicator()),
      ),
    );
  }

  Future<void> _handleAction(
    BuildContext context,
    WidgetRef ref,
    InboxNotification item,
    NotificationAction action,
  ) async {
    switch (action) {
      case NotificationAction.open:
        await _openNotification(context, ref, item);
      case NotificationAction.markRead:
        await ref.read(notificationInboxRepositoryProvider).markRead(item.id);
    }
  }

  Future<void> _completeFromNotification(
    BuildContext context,
    WidgetRef ref,
    InboxNotification item,
  ) async {
    final planId = item.planId;
    if (planId == null) {
      return;
    }
    final task = await ref.read(maintenanceRepositoryProvider).getTask(planId);
    if (!context.mounted) {
      return;
    }
    if (task == null) {
      hk_ui.showToast(
        context,
        content: Text(context.l10n.taskIsNoLongerAvailable),
        severity: hk_ui.HkToastSeverity.error,
      );
      return;
    }
    final completed = await completeTaskWithFeedback(
      context,
      ref,
      task,
      collectNotes: true,
    );
    if (!completed) {
      return;
    }
    await ref.read(notificationInboxRepositoryProvider).markRead(item.id);
  }

  Future<void> _openNotification(
    BuildContext context,
    WidgetRef ref,
    InboxNotification item,
  ) async {
    await ref.read(notificationInboxRepositoryProvider).markRead(item.id);
    if (!context.mounted) {
      return;
    }
    final route = item.route;
    final destination = route == null
        ? null
        : validatedNotificationRoute(route);
    if (destination != null) {
      context.push(destination);
    }
  }

  List<InboxNotification> _filterNotifications(List<InboxNotification> items) {
    return switch (_filter) {
      _NotificationFilter.all => items,
      _NotificationFilter.unread => items.where((item) => item.unread).toList(),
      _NotificationFilter.tasks =>
        items
            .where((item) => item.kind == 'task' || item.planId != null)
            .toList(),
      _NotificationFilter.system =>
        items
            .where((item) => item.kind != 'task' && item.kind != 'digest')
            .toList(),
    };
  }
}

DateTime? _completedTaskNotificationAt(
  InboxNotification notification,
  List<MaintenanceRecord> records,
) {
  if (notification.planId == null || records.isEmpty) {
    return null;
  }
  final completedAfterNotification =
      records
          .where(
            (record) => !record.completedAt.isBefore(notification.createdAt),
          )
          .toList()
        ..sort((a, b) => b.completedAt.compareTo(a.completedAt));
  if (completedAfterNotification.isEmpty) {
    return null;
  }
  return completedAfterNotification.first.completedAt;
}

enum NotificationAction { open, markRead }

class _NotificationSummaryCard extends StatelessWidget {
  const _NotificationSummaryCard({
    required this.total,
    required this.unread,
    required this.tasks,
  });

  final int total;
  final int unread;
  final int tasks;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dot = String.fromCharCode(0x2022);
    return hk_ui.PremiumCard(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 14, 14, 14),
      borderRadius: 26,
      backgroundColor: Color.alphaBlend(
        scheme.primary.withValues(alpha: 0.035),
        scheme.surfaceContainerLowest,
      ),
      borderColor: scheme.outlineVariant.withValues(alpha: 0.62),
      shadows: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.08),
          blurRadius: 24,
          offset: const Offset(0, 10),
        ),
      ],
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 360;
          return Row(
            children: [
              _NotificationSummaryIcon(
                size: compact ? 52 : 58,
                hasUnread: unread > 0,
              ),
              SizedBox(width: compact ? HkSpacing.xs : HkSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(
                        context.l10n.inboxUpdateCount(total),
                        maxLines: 1,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: scheme.onSurface,
                          fontSize: compact ? 19 : 23,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0,
                        ),
                      ),
                    ),
                    const SizedBox(height: HkSpacing.space6),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(
                        '${context.l10n.unreadCount(unread)} $dot ${context.l10n.taskReminderCount(tasks)}',
                        maxLines: 1,
                        softWrap: false,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: compact ? 12 : 14,
                          fontWeight: FontWeight.w600,
                          height: 1.15,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: HkSpacing.xs),
              _InboxEnvelopeIllustration(size: compact ? 62 : 88),
            ],
          );
        },
      ),
    );
  }
}

class _NotificationSummaryIcon extends StatelessWidget {
  const _NotificationSummaryIcon({required this.size, required this.hasUnread});

  final double size;
  final bool hasUnread;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox.square(
      dimension: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.11),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Symbols.notifications_active_rounded,
                color: scheme.primary,
                size: size * 0.44,
              ),
            ),
          ),
          if (hasUnread)
            PositionedDirectional(
              end: size * 0.06,
              top: size * 0.08,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: scheme.primary,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: scheme.surfaceContainerLowest,
                    width: 2,
                  ),
                ),
                child: SizedBox.square(dimension: size * 0.20),
              ),
            ),
        ],
      ),
    );
  }
}

class _InboxEnvelopeIllustration extends StatelessWidget {
  const _InboxEnvelopeIllustration({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: size,
      height: size * 0.76,
      child: CustomPaint(
        painter: _InboxEnvelopePainter(
          primary: scheme.primary,
          surface: scheme.surfaceContainerLowest,
          muted: scheme.primary.withValues(alpha: 0.18),
          line: scheme.outlineVariant,
        ),
      ),
    );
  }
}

class _InboxEnvelopePainter extends CustomPainter {
  const _InboxEnvelopePainter({
    required this.primary,
    required this.surface,
    required this.muted,
    required this.line,
  });

  final Color primary;
  final Color surface;
  final Color muted;
  final Color line;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..isAntiAlias = true;
    final envelopeRect = Rect.fromLTWH(
      size.width * 0.23,
      size.height * 0.38,
      size.width * 0.65,
      size.height * 0.48,
    );
    final paperRect = Rect.fromLTWH(
      size.width * 0.34,
      size.height * 0.14,
      size.width * 0.42,
      size.height * 0.48,
    );

    paint
      ..color = muted
      ..strokeWidth = size.width * 0.035
      ..style = PaintingStyle.stroke;
    final stem = Path()
      ..moveTo(size.width * 0.18, size.height * 0.70)
      ..quadraticBezierTo(
        size.width * 0.10,
        size.height * 0.47,
        size.width * 0.22,
        size.height * 0.27,
      );
    canvas.drawPath(stem, paint);
    paint.style = PaintingStyle.fill;
    for (final leaf in [
      Offset(size.width * 0.13, size.height * 0.48),
      Offset(size.width * 0.22, size.height * 0.38),
      Offset(size.width * 0.16, size.height * 0.28),
    ]) {
      canvas.save();
      canvas.translate(leaf.dx, leaf.dy);
      canvas.rotate(-0.72);
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset.zero,
          width: size.width * 0.14,
          height: size.height * 0.08,
        ),
        paint,
      );
      canvas.restore();
    }

    paint.color = surface;
    canvas.drawRRect(
      RRect.fromRectAndRadius(paperRect, Radius.circular(size.width * 0.04)),
      paint,
    );
    paint.color = line.withValues(alpha: 0.56);
    for (var index = 0; index < 3; index += 1) {
      final y = paperRect.top + paperRect.height * (0.30 + (index * 0.18));
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            paperRect.left + paperRect.width * 0.16,
            y,
            paperRect.width * 0.68,
            size.height * 0.026,
          ),
          Radius.circular(size.height * 0.02),
        ),
        paint,
      );
    }

    paint.color = primary.withValues(alpha: 0.90);
    canvas.drawRRect(
      RRect.fromRectAndRadius(envelopeRect, Radius.circular(size.width * 0.07)),
      paint,
    );
    final flap = Path()
      ..moveTo(envelopeRect.left, envelopeRect.top)
      ..lineTo(envelopeRect.center.dx, envelopeRect.top - size.height * 0.22)
      ..lineTo(envelopeRect.right, envelopeRect.top)
      ..lineTo(envelopeRect.right, envelopeRect.bottom)
      ..lineTo(envelopeRect.center.dx, envelopeRect.center.dy)
      ..lineTo(envelopeRect.left, envelopeRect.bottom)
      ..close();
    paint.color = primary.withValues(alpha: 0.62);
    canvas.drawPath(flap, paint);

    paint.color = muted;
    for (final star in [
      Offset(size.width * 0.22, size.height * 0.12),
      Offset(size.width * 0.91, size.height * 0.11),
      Offset(size.width * 0.78, size.height * 0.02),
    ]) {
      _drawSpark(canvas, paint, star, size.width * 0.04);
    }
  }

  void _drawSpark(Canvas canvas, Paint paint, Offset center, double radius) {
    paint
      ..strokeWidth = radius * 0.36
      ..style = PaintingStyle.stroke;
    canvas.drawLine(
      center.translate(0, -radius),
      center.translate(0, radius),
      paint,
    );
    canvas.drawLine(
      center.translate(-radius, 0),
      center.translate(radius, 0),
      paint,
    );
    paint.style = PaintingStyle.fill;
  }

  @override
  bool shouldRepaint(covariant _InboxEnvelopePainter oldDelegate) {
    return primary != oldDelegate.primary ||
        surface != oldDelegate.surface ||
        muted != oldDelegate.muted ||
        line != oldDelegate.line;
  }
}

class _NotificationFilterChips extends StatelessWidget {
  const _NotificationFilterChips({
    required this.selected,
    required this.onSelected,
    required this.unreadCount,
  });

  final _NotificationFilter selected;
  final ValueChanged<_NotificationFilter> onSelected;
  final int unreadCount;

  @override
  Widget build(BuildContext context) {
    final filters = [
      (_NotificationFilter.all, context.l10n.all, null),
      (_NotificationFilter.unread, context.l10n.unread, unreadCount),
      (_NotificationFilter.tasks, context.l10n.tasks, null),
      (_NotificationFilter.system, context.l10n.system, null),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 360;
        final gap = compact ? HkSpacing.space6 : HkSpacing.xs;
        final children = <Widget>[];
        for (var index = 0; index < filters.length; index += 1) {
          final filter = filters[index];
          children.add(
            Expanded(
              child: _NotificationFilterButton(
                label: filter.$2,
                badgeCount: filter.$3,
                selected: selected == filter.$1,
                compact: compact,
                onTap: () => onSelected(filter.$1),
              ),
            ),
          );
          if (index != filters.length - 1) {
            children.add(SizedBox(width: gap));
          }
        }
        return Row(mainAxisSize: MainAxisSize.max, children: children);
      },
    );
  }
}

class _NotificationFilterButton extends StatelessWidget {
  const _NotificationFilterButton({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.compact,
    this.badgeCount,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool compact;
  final int? badgeCount;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final showBadge = badgeCount != null && badgeCount! > 0;
    final foreground = selected
        ? scheme.onPrimary
        : (isDark ? scheme.onSurface : HkColors.appPrimaryDark);
    final semanticLabel = showBadge
        ? context.l10n.filterUnreadCount(label, badgeCount!)
        : label;
    const chipHeight = 38.0;
    const tapHeight = 48.0;
    final badgeSpace = compact ? 5.0 : 6.0;
    final fontSize = compact ? 12.0 : 14.0;
    return Tooltip(
      message: semanticLabel,
      child: Semantics(
        button: true,
        selected: selected,
        label: semanticLabel,
        child: SizedBox(
          height: tapHeight + badgeSpace,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: 0,
                right: 0,
                bottom: (tapHeight - chipHeight) / 2,
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(999),
                    onTap: onTap,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOutCubic,
                      height: chipHeight,
                      padding: EdgeInsets.symmetric(
                        horizontal: compact ? 3 : 8,
                      ),
                      decoration: BoxDecoration(
                        color: selected
                            ? scheme.primary
                            : Color.alphaBlend(
                                scheme.primary.withValues(alpha: 0.025),
                                scheme.surfaceContainerLowest,
                              ),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: selected
                              ? scheme.primary.withValues(alpha: 0.48)
                              : scheme.outlineVariant.withValues(alpha: 0.74),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: (selected ? scheme.primary : Colors.black)
                                .withValues(alpha: selected ? 0.18 : 0.045),
                            blurRadius: selected ? 18 : 12,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Center(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            softWrap: false,
                            style: Theme.of(context).textTheme.labelLarge
                                ?.copyWith(
                                  color: foreground,
                                  fontSize: fontSize,
                                  fontWeight: FontWeight.w800,
                                  height: 1,
                                  letterSpacing: 0,
                                ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (showBadge)
                PositionedDirectional(
                  top: 0,
                  end: compact ? 2 : 8,
                  child: _NotificationFilterBadge(
                    count: badgeCount!,
                    selected: selected,
                    compact: compact,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NotificationFilterBadge extends StatelessWidget {
  const _NotificationFilterBadge({
    required this.count,
    required this.selected,
    required this.compact,
  });

  final int count;
  final bool selected;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final label = count > 99 ? '99+' : '$count';
    final size = compact ? 20.0 : 22.0;
    return Container(
      constraints: BoxConstraints(minWidth: size),
      height: size,
      padding: EdgeInsets.symmetric(horizontal: compact ? 5 : 6),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: selected ? scheme.surfaceContainerLowest : scheme.primary,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: scheme.surfaceContainerLowest, width: 2),
        boxShadow: [
          BoxShadow(
            color: scheme.primary.withValues(alpha: 0.22),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.clip,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: selected ? scheme.primary : scheme.onPrimary,
          fontSize: compact ? 10 : 11,
          fontWeight: FontWeight.w900,
          height: 1,
        ),
      ),
    );
  }
}

class NotificationCard extends StatelessWidget {
  const NotificationCard({
    required this.notification,
    required this.onTap,
    required this.onAction,
    this.completedAt,
    this.onComplete,
    super.key,
  });

  final InboxNotification notification;
  final VoidCallback onTap;
  final ValueChanged<NotificationAction> onAction;
  final DateTime? completedAt;
  final VoidCallback? onComplete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final localizedNotification = localizeInboxNotification(
      context.l10n,
      notification,
    );
    final completed = completedAt != null;
    final accent = completed
        ? HkColors.green
        : _notificationAccent(context, notification);
    return hk_ui.PremiumCard(
      margin: const EdgeInsets.only(bottom: HkSpacing.sm),
      backgroundColor: completed
          ? Color.alphaBlend(
              HkColors.green.withValues(alpha: 0.07),
              scheme.surfaceContainerLowest,
            )
          : null,
      borderColor: completed
          ? HkColors.green.withValues(alpha: 0.34)
          : notification.unread
          ? accent.withValues(alpha: 0.34)
          : scheme.outlineVariant,
      child: InkWell(
        borderRadius: BorderRadius.circular(HkRadii.xl),
        onTap: onTap,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 38,
              child: Stack(
                alignment: Alignment.topCenter,
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      completed
                          ? Symbols.check_circle_rounded
                          : _notificationIcon(notification.kind),
                      size: 18,
                      color: accent,
                    ),
                  ),
                  if (notification.unread && !completed)
                    PositionedDirectional(
                      end: 1,
                      top: 0,
                      child: Semantics(
                        label: context.l10n.unread,
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: HkColors.appDanger,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: HkSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          localizedNotification.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ),
                      const SizedBox(width: HkSpacing.xs),
                      Text(
                        formatShortTime(context, notification.createdAt),
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ],
                  ),
                  const SizedBox(height: HkSpacing.space4),
                  Text(
                    localizedNotification.body,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                  if (completed) ...[
                    const SizedBox(height: HkSpacing.xs),
                    _CompletedNotificationBadge(completedAt: completedAt!),
                  ] else if (onComplete != null) ...[
                    const SizedBox(height: HkSpacing.xs),
                    Align(
                      alignment: Alignment.center,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          minWidth: 176,
                          maxWidth: 220,
                        ),
                        child: Semantics(
                          button: true,
                          label: context.l10n.completeAction,
                          child: Material(
                            key: const ValueKey('inbox-complete-action'),
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: onComplete,
                              child: SizedBox(
                                height: 48,
                                child: Center(
                                  child: Container(
                                    height: 40,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: scheme.secondaryContainer,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          Symbols.check_rounded,
                                          size: 17,
                                          color: scheme.onSecondaryContainer,
                                        ),
                                        const SizedBox(width: 7),
                                        Text(
                                          context.l10n.completeAction,
                                          style: Theme.of(context)
                                              .textTheme
                                              .labelLarge
                                              ?.copyWith(
                                                color:
                                                    scheme.onSecondaryContainer,
                                                fontWeight: FontWeight.w800,
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
                    ),
                  ],
                ],
              ),
            ),
            PopupMenuButton<NotificationAction>(
              useRootNavigator: true,
              tooltip: context.l10n.notificationActions,
              onSelected: onAction,
              itemBuilder: (context) => [
                if (notification.route?.isNotEmpty ?? false)
                  PopupMenuItem(
                    value: NotificationAction.open,
                    child: Text(context.l10n.open),
                  ),
                if (notification.unread)
                  PopupMenuItem(
                    value: NotificationAction.markRead,
                    child: Text(context.l10n.markRead),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CompletedNotificationBadge extends StatelessWidget {
  const _CompletedNotificationBadge({required this.completedAt});

  final DateTime completedAt;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: HkSpacing.xs,
        vertical: HkSpacing.space6,
      ),
      decoration: BoxDecoration(
        color: HkColors.green.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(HkRadii.full),
        border: Border.all(color: HkColors.green.withValues(alpha: 0.20)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Symbols.check_circle_rounded,
            color: HkColors.green,
            size: 16,
          ),
          const SizedBox(width: HkSpacing.space4),
          Text(
            context.l10n.completedAtTime(
              _completedNotificationTimeLabel(context, completedAt),
            ),
            style: Theme.of(context).textTheme.labelMedium
                ?.copyWith(color: HkColors.green, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

String _completedNotificationTimeLabel(BuildContext context, DateTime value) {
  return MaterialLocalizations.of(context)
      .formatTimeOfDay(TimeOfDay.fromDateTime(value));
}

List<InboxNotification> _groupNotifications(List<InboxNotification> items) {
  final seen = <String>{};
  final grouped = <InboxNotification>[];
  for (final item in items) {
    final day = hk_dates.dateOnly(item.createdAt).toIso8601String();
    final key = switch (item.kind) {
      'task' => 'task:${item.planId ?? item.route ?? item.title}:$day',
      'digest' => 'digest:$day',
      _ => '${item.kind}:${item.title}:${item.route ?? ''}:$day',
    };
    if (seen.add(key)) {
      grouped.add(item);
    }
  }
  return grouped;
}

String _filteredNotificationEmptyTitle(
  BuildContext context,
  _NotificationFilter filter,
) {
  return switch (filter) {
    _NotificationFilter.unread => context.l10n.noUnreadNotifications,
    _NotificationFilter.tasks => context.l10n.noTaskNotifications,
    _NotificationFilter.system => context.l10n.noSystemNotifications,
    _NotificationFilter.all => context.l10n.noNotifications,
  };
}

Color _notificationAccent(BuildContext context, InboxNotification item) {
  final body = '${item.title} ${item.body}'.toLowerCase();
  if (body.contains('critical') || body.contains('overdue')) {
    return HkColors.appDanger;
  }
  return switch (item.kind) {
    'task' => HkColors.appWarning,
    'digest' => Theme.of(context).colorScheme.onSurfaceVariant,
    'weather' => HkColors.appWarning,
    _ => Theme.of(context).colorScheme.primary,
  };
}

IconData _notificationIcon(String kind) {
  return switch (kind) {
    'weather' => Symbols.rainy_rounded,
    'task' => Symbols.task_alt_rounded,
    'digest' => Symbols.summarize_rounded,
    _ => Symbols.notifications_rounded,
  };
}

String _notificationDateLabel(BuildContext context, DateTime value) {
  final today = DateTime.now();
  if (hk_dates.isSameDate(value, today)) {
    return context.l10n.today;
  }
  final yesterday = DateTime(today.year, today.month, today.day - 1);
  if (hk_dates.isSameDate(value, yesterday)) {
    return context.l10n.yesterday;
  }
  final locale = Localizations.localeOf(context).toLanguageTag();
  final sevenDaysAgo = DateTime(today.year, today.month, today.day - 7);
  if (value.isAfter(sevenDaysAgo)) {
    return DateFormat.EEEE(locale).add_MMMd().format(value);
  }
  return DateFormat.yMMMd(locale).format(value);
}

enum _NotificationFilter { all, unread, tasks, system }
