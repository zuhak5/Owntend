import 'task_completion_controller.dart';
import '../../monetization/monetization.dart';

import 'dart:math' as math;

import '../../../ui/components.dart' as hk_ui;
import '../../../ui/presentation_support.dart';
import '../../../core/services/native_capabilities.dart';
import 'complete_task_dialog.dart';

enum _SnoozePreset { thirtyMinutes, oneHour, threeHours, tomorrow, custom }

Future<void> snoozeTaskWithFeedback(
  BuildContext context,
  WidgetRef ref,
  TaskItem task,
) async {
  if (!task.plan.isEnabled) {
    hk_ui.showToast(
      context,
      content: Text(context.l10n.enableThisTaskBeforeSnoozingIt),
      severity: hk_ui.HkToastSeverity.error,
    );
    return;
  }
  final preferences =
      ref.read(notificationPreferencesProvider).value ??
      await ref.read(settingsRepositoryProvider).notificationPreferences();
  if (!context.mounted) {
    return;
  }
  final preset = await runWithNativeAdsSuspended(
    context,
    () => showModalBottomSheet<_SnoozePreset>(
      context: context,
      useRootNavigator: true,
      useSafeArea: true,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Symbols.snooze_rounded),
                title: Text(context.l10n.snoozeTask(task.plan.title)),
                subtitle: Text(context.l10n.snoozeReminderDescription),
              ),
              ListTile(
                leading: const Icon(Symbols.timer_rounded),
                title: Text(context.l10n.message30Minutes),
                onTap: () =>
                    Navigator.of(context).pop(_SnoozePreset.thirtyMinutes),
              ),
              ListTile(
                leading: const Icon(Symbols.schedule_rounded),
                title: Text(context.l10n.message1Hour),
                onTap: () => Navigator.of(context).pop(_SnoozePreset.oneHour),
              ),
              ListTile(
                leading: const Icon(Symbols.more_time_rounded),
                title: Text(context.l10n.message3Hours),
                onTap: () =>
                    Navigator.of(context).pop(_SnoozePreset.threeHours),
              ),
              ListTile(
                leading: const Icon(Symbols.today_rounded),
                title: Text(
                  context.l10n.tomorrowAtTime(
                    hourLabel(context, preferences.reminderHour),
                  ),
                ),
                onTap: () => Navigator.of(context).pop(_SnoozePreset.tomorrow),
              ),
              ListTile(
                leading: const Icon(Symbols.edit_calendar_rounded),
                title: Text(context.l10n.customDateAndTime),
                onTap: () => Navigator.of(context).pop(_SnoozePreset.custom),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  if (preset == null || !context.mounted) {
    return;
  }
  final duration = await _durationForSnoozePreset(context, preset, preferences);
  if (duration == null || !context.mounted) {
    return;
  }
  await ref
      .read(notificationSchedulerProvider)
      .snoozePlan(task.plan.id, duration);
  if (!context.mounted) {
    return;
  }
  hk_ui.showToast(
    context,
    content: Text(
      context.l10n.taskSnoozedForDuration(
        task.plan.title,
        durationLabel(context, duration),
      ),
    ),
  );
}

Future<bool> skipTaskWithConfirmation(
  BuildContext context,
  WidgetRef ref,
  TaskItem task,
) async {
  final reason = await _taskReasonDialog(
    context,
    title: context.l10n.skipThisOccurrence2,
    message: context.l10n.skipCurrentCycleMessage,
    actionLabel: context.l10n.skipOccurrence,
    icon: Symbols.skip_next_rounded,
  );
  if (reason == null || !context.mounted) {
    return false;
  }
  try {
    await ref
        .read(maintenanceRepositoryProvider)
        .skipPlanOccurrence(
          task.plan.id,
          expectedOccurrenceId: task.plan.currentOccurrenceId,
          reason: reason,
        );
    unawaited(wakeNotificationReconciliation(ref));
    if (!context.mounted) {
      return true;
    }
    hk_ui.showToast(
      context,
      content: Text(context.l10n.taskSkippedForThisCycle(task.plan.title)),
    );
    return true;
  } catch (error) {
    if (context.mounted) {
      hk_ui.showToast(
        context,
        content: Text(
          failureMessage(context, error, fallback: AppFailureCode.taskUpdate),
        ),
        severity: hk_ui.HkToastSeverity.error,
      );
    }
    return false;
  }
}

Future<bool> postponeTaskWithDialog(
  BuildContext context,
  WidgetRef ref,
  TaskItem task,
) async {
  final now = DateTime.now();
  final initialPostponeDate = task.plan.nextDueDate.isAfter(now)
      ? task.plan.nextDueDate
      : now;
  final date = await showDatePicker(
    context: context,
    initialDate: initialPostponeDate,
    firstDate: DateTime(now.year, now.month, now.day),
    lastDate: now.add(const Duration(days: 3650)),
  );
  if (date == null || !context.mounted) {
    return false;
  }
  final time = await showTimePicker(
    context: context,
    initialTime: TimeOfDay.fromDateTime(
      task.plan.nextDueDate.isAfter(now)
          ? task.plan.nextDueDate
          : now.add(const Duration(hours: 1)),
    ),
  );
  if (time == null || !context.mounted) {
    return false;
  }
  final nextDueDate = DateTime(
    date.year,
    date.month,
    date.day,
    time.hour,
    time.minute,
  );
  final reason = await _taskReasonDialog(
    context,
    title: context.l10n.postponeTask,
    message: context.l10n.postponeCurrentCycleMessage,
    actionLabel: context.l10n.postpone,
    icon: Symbols.edit_calendar_rounded,
  );
  if (reason == null || !context.mounted) {
    return false;
  }
  try {
    await ref
        .read(maintenanceRepositoryProvider)
        .postponePlan(
          task.plan.id,
          nextDueDate,
          expectedOccurrenceId: task.plan.currentOccurrenceId,
          reason: reason,
        );
    unawaited(wakeNotificationReconciliation(ref));
    if (!context.mounted) {
      return true;
    }
    hk_ui.showToast(
      context,
      content: Text(
        context.l10n.taskPostponedUntil(
          task.plan.title,
          DateFormat.yMMMd(Localizations.localeOf(context).toLanguageTag())
              .add_jm()
              .format(nextDueDate),
        ),
      ),
    );
    return true;
  } catch (error) {
    if (context.mounted) {
      hk_ui.showToast(
        context,
        content: Text(
          failureMessage(context, error, fallback: AppFailureCode.taskUpdate),
        ),
        severity: hk_ui.HkToastSeverity.error,
      );
    }
    return false;
  }
}

Future<String?> _taskReasonDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String actionLabel,
  required IconData icon,
}) async {
  final controller = TextEditingController();
  try {
    return await runWithNativeAdsSuspended(
      context,
      () => showDialog<String?>(
        context: context,
        builder: (context) => AlertDialog(
          scrollable: true,
          actionsOverflowButtonSpacing: HkSpacing.xs,
          icon: Icon(icon),
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(message),
              const SizedBox(height: HkSpacing.sm),
              TextField(
                controller: controller,
                minLines: 2,
                maxLines: 4,
                decoration: InputDecoration(
                  labelText: context.l10n.reason,
                  hintText: context.l10n.optional,
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(null),
              child: Text(context.l10n.cancel),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(context).pop(controller.text.trim()),
              child: Text(actionLabel),
            ),
          ],
        ),
      ),
    );
  } finally {
    controller.dispose();
  }
}

Future<Duration?> _durationForSnoozePreset(
  BuildContext context,
  _SnoozePreset preset,
  NotificationPreferences preferences,
) async {
  final now = DateTime.now();
  switch (preset) {
    case _SnoozePreset.thirtyMinutes:
      return const Duration(minutes: 30);
    case _SnoozePreset.oneHour:
      return const Duration(hours: 1);
    case _SnoozePreset.threeHours:
      return const Duration(hours: 3);
    case _SnoozePreset.tomorrow:
      return DateTime(
        now.year,
        now.month,
        now.day + 1,
        preferences.reminderHour,
      ).difference(now);
    case _SnoozePreset.custom:
      final date = await showDatePicker(
        context: context,
        initialDate: now.add(const Duration(hours: 1)),
        firstDate: now,
        lastDate: now.add(const Duration(days: 30)),
      );
      if (date == null || !context.mounted) {
        return null;
      }
      final time = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(now.add(const Duration(hours: 1))),
      );
      if (time == null) {
        return null;
      }
      final scheduled = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
      return scheduled.isAfter(now)
          ? scheduled.difference(now)
          : const Duration(minutes: 5);
  }
}

Future<void> wakeNotificationReconciliation(WidgetRef ref) async {
  try {
    final session = ref.read(authRepositoryProvider)?.currentSession;
    final consumer = ref.read(notificationReconciliationConsumerProvider);
    if (consumer != null) {
      if (session != null) {
        await consumer.drainForAccount(session.userId);
      } else {
        await consumer.drainLocal();
      }
      return;
    }
    await ref.read(notificationSchedulerProvider).refreshSchedules();
  } catch (_) {
    // The repository transaction already persisted reconciliation intent.
  }
}

Future<bool> setTaskEnabledWithFeedback(
  BuildContext context,
  WidgetRef ref,
  TaskItem task,
  bool enabled,
) async {
  try {
    await ref
        .read(maintenanceRepositoryProvider)
        .setTaskEnabled(task.plan.id, enabled);
  } catch (error) {
    if (context.mounted) {
      hk_ui.showToast(
        context,
        content: Text(
          enabled
              ? failureMessage(
                  context,
                  error,
                  fallback: AppFailureCode.taskUpdate,
                )
              : failureMessage(
                  context,
                  error,
                  fallback: AppFailureCode.taskUpdate,
                ),
        ),
        severity: hk_ui.HkToastSeverity.error,
      );
    }
    return false;
  }

  await wakeNotificationReconciliation(ref);

  if (!context.mounted) {
    return true;
  }
  hk_ui.showToast(
    context,
    content: Text(
      enabled
          ? context.l10n.taskEnabledConfirmation
          : context.l10n.taskDisabledConfirmation,
    ),
  );
  return true;
}

enum TaskActionFeedbackType { created, completed, deleted }

void showTaskActionFeedback(
  BuildContext context,
  TaskActionFeedbackType type, {
  String? label,
}) {
  unawaited(_playTaskActionFeedback(type));
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) {
    return;
  }
  var removed = false;
  late final OverlayEntry entry;
  void removeEntry() {
    if (removed) {
      return;
    }
    removed = true;
    entry.remove();
  }

  entry = OverlayEntry(
    builder: (context) => _TaskActionBurstOverlay(
      type: type,
      label: label ?? _taskActionFeedbackLabel(context, type),
      onDone: removeEntry,
    ),
  );
  overlay.insert(entry);
}

Future<void> _playTaskActionFeedback(TaskActionFeedbackType type) async {
  switch (type) {
    case TaskActionFeedbackType.completed:
      await hkActionFeedbackService.playCompleted();
    case TaskActionFeedbackType.created:
      await hkActionFeedbackService.playCreated();
    case TaskActionFeedbackType.deleted:
      await hkActionFeedbackService.playDeleted();
  }
}

String _taskActionFeedbackLabel(
  BuildContext context,
  TaskActionFeedbackType type,
) {
  return switch (type) {
    TaskActionFeedbackType.created => context.l10n.taskAdded,
    TaskActionFeedbackType.completed => context.l10n.taskDone,
    TaskActionFeedbackType.deleted => context.l10n.taskDeleted,
  };
}

class _TaskActionBurstOverlay extends StatefulWidget {
  const _TaskActionBurstOverlay({
    required this.type,
    required this.label,
    required this.onDone,
  });

  final TaskActionFeedbackType type;
  final String label;
  final VoidCallback onDone;

  @override
  State<_TaskActionBurstOverlay> createState() =>
      _TaskActionBurstOverlayState();
}

class _TaskActionBurstOverlayState extends State<_TaskActionBurstOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 1180),
        )..addStatusListener((status) {
          if (status == AnimationStatus.completed) {
            widget.onDone();
          }
        });
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style = _TaskActionFeedbackStyle.from(context, widget.type);
    return IgnorePointer(
      child: Material(
        type: MaterialType.transparency,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            final progress = _controller.value;
            final intro = Curves.easeOutBack.transform(
              (progress / 0.36).clamp(0.0, 1.0),
            );
            final fadeOut = progress < 0.76
                ? 1.0
                : (1 - ((progress - 0.76) / 0.24)).clamp(0.0, 1.0);
            final slide = Curves.easeOutCubic.transform(
              progress.clamp(0.0, 1.0),
            );
            return Stack(
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _TaskActionBurstPainter(
                      progress: progress,
                      accent: style.accent,
                      secondary: style.secondary,
                    ),
                  ),
                ),
                SafeArea(
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: Transform.translate(
                      offset: Offset(0, 50 - (18 * slide)),
                      child: Opacity(
                        opacity: fadeOut,
                        child: Transform.scale(
                          scale: 0.82 + (0.18 * intro),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: Color.alphaBlend(
                                style.accent.withValues(alpha: 0.07),
                                scheme.surfaceContainerLowest,
                              ).withValues(alpha: 0.96),
                              borderRadius: BorderRadius.circular(HkRadii.full),
                              border: Border.all(
                                color: style.accent.withValues(alpha: 0.24),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: style.accent.withValues(alpha: 0.22),
                                  blurRadius: 30,
                                  offset: const Offset(0, 12),
                                ),
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.08),
                                  blurRadius: 18,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: HkSpacing.md,
                                vertical: HkSpacing.sm,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 34,
                                    height: 34,
                                    decoration: BoxDecoration(
                                      color: style.accent,
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      style.icon,
                                      color: style.onAccent,
                                      size: 20,
                                    ),
                                  ),
                                  const SizedBox(width: HkSpacing.xs),
                                  Text(
                                    widget.label,
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelLarge
                                        ?.copyWith(
                                          color: scheme.onSurface,
                                          fontWeight: FontWeight.w900,
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
              ],
            );
          },
        ),
      ),
    );
  }
}

class _TaskActionFeedbackStyle {
  const _TaskActionFeedbackStyle({
    required this.icon,
    required this.accent,
    required this.secondary,
    required this.onAccent,
  });

  final IconData icon;
  final Color accent;
  final Color secondary;
  final Color onAccent;

  factory _TaskActionFeedbackStyle.from(
    BuildContext context,
    TaskActionFeedbackType type,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return switch (type) {
      TaskActionFeedbackType.created => _TaskActionFeedbackStyle(
        icon: Symbols.add_task_rounded,
        accent: scheme.primary,
        secondary: HkColors.appInfo,
        onAccent: scheme.onPrimary,
      ),
      TaskActionFeedbackType.completed => _TaskActionFeedbackStyle(
        icon: Symbols.check_circle_rounded,
        accent: scheme.primary,
        secondary: scheme.primaryContainer,
        onAccent: scheme.onPrimary,
      ),
      TaskActionFeedbackType.deleted => _TaskActionFeedbackStyle(
        icon: Symbols.delete_rounded,
        accent: scheme.error,
        secondary: scheme.errorContainer,
        onAccent: scheme.onError,
      ),
    };
  }
}

class _TaskActionBurstPainter extends CustomPainter {
  const _TaskActionBurstPainter({
    required this.progress,
    required this.accent,
    required this.secondary,
  });

  final double progress;
  final Color accent;
  final Color secondary;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, 92);
    final outward = Curves.easeOutCubic.transform(
      (progress / 0.72).clamp(0.0, 1.0),
    );
    final fade = progress < 0.72
        ? 1.0
        : (1 - ((progress - 0.72) / 0.28)).clamp(0.0, 1.0);
    final paint = Paint()..style = PaintingStyle.fill;
    for (var index = 0; index < 18; index += 1) {
      final angle = (-math.pi * 0.88) + (index * math.pi * 1.76 / 17);
      final stagger = 0.76 + ((index % 4) * 0.08);
      final radius = (18 + (72 * outward)) * stagger;
      final particleCenter =
          center + Offset(math.cos(angle), math.sin(angle)) * radius;
      final particleSize = 3.5 + ((index % 3) * 1.8);
      paint.color = (index.isEven ? accent : secondary).withValues(
        alpha: (0.78 * fade).clamp(0.0, 1.0),
      );
      if (index % 5 == 0) {
        canvas.save();
        canvas.translate(particleCenter.dx, particleCenter.dy);
        canvas.rotate(angle + (progress * math.pi));
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
              center: Offset.zero,
              width: particleSize * 2.2,
              height: particleSize,
            ),
            Radius.circular(particleSize / 2),
          ),
          paint,
        );
        canvas.restore();
      } else {
        canvas.drawCircle(particleCenter, particleSize, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _TaskActionBurstPainter oldDelegate) {
    return progress != oldDelegate.progress ||
        accent != oldDelegate.accent ||
        secondary != oldDelegate.secondary;
  }
}

Future<bool> completeTaskWithFeedback(
  BuildContext context,
  WidgetRef ref,
  TaskItem task, {
  bool collectNotes = false,
}) async {
  final controllerNotifier = ref.read(
    taskCompletionControllerProvider(task.plan.id),
  );
  if (collectNotes) {
    if (!controllerNotifier.tryBeginNotesCollection()) {
      return false;
    }
  }
  String? notes;
  try {
    if (collectNotes) {
      notes = await showEditorModal<String>(
        context,
        builder: (context) => CompleteTaskDialog(task: task),
      );
      if (notes == null || !context.mounted) {
        return false;
      }
    }
  } finally {
    controllerNotifier.cancelNotesCollection();
  }
  final previousDueDate = task.plan.nextDueDate;
  final timeZoneId =
      await ref.read(nativeCapabilitiesProvider).getTimeZoneId() ?? 'UTC';
  final result = await controllerNotifier.complete(
    expectedOccurrenceId: task.plan.currentOccurrenceId,
    timeZoneId: timeZoneId,
    completedAt: DateTime.now(),
    notes: notes,
  );

  if (!context.mounted) {
    return result.isApplied;
  }
  if (!result.isApplied) {
    hk_ui.showToast(
      context,
      content: Text(context.l10n.thisTaskWasAlreadyUpdated),
      severity: hk_ui.HkToastSeverity.error,
    );
    return false;
  }

  unawaited(wakeNotificationReconciliation(ref));

  try {
    await ref.read(streakServiceProvider).refresh(DateTime.now());
  } catch (error) {
    AppLogger.warning('streak_refresh_failed', error: error);
  }
  if (!context.mounted) {
    return true;
  }
  showTaskActionFeedback(context, TaskActionFeedbackType.completed);
  if (!prefersReducedMotion(context)) {
    await Future<void>.delayed(const Duration(milliseconds: 450));
  }
  if (!context.mounted) {
    return true;
  }
  hk_ui.showUndoToast(
    context,
    content: Text(context.l10n.taskCompleted),
    onUndo: () async {
      try {
        final completionId = result.operationId;
        final completedOccurrenceId = result.completedOccurrenceId;
        final nextOccurrenceId = result.nextOccurrenceId;
        final completedNextDue = result.nextDueDate;
        if (completionId == null ||
            completedOccurrenceId == null ||
            nextOccurrenceId == null ||
            completedNextDue == null) {
          throw StateError(
            'Completion acknowledgement is missing undo identity.',
          );
        }
        await ref
            .read(maintenanceRepositoryProvider)
            .undoCompletion(
              planId: task.plan.id,
              completionId: completionId,
              completedOccurrenceId: completedOccurrenceId,
              expectedCurrentOccurrenceId: nextOccurrenceId,
              previousDueDate: result.previousDueDate ?? previousDueDate,
              expectedCurrentNextDueDate: completedNextDue,
            );
        try {
          await ref.read(streakServiceProvider).refresh(DateTime.now());
          await wakeNotificationReconciliation(ref);
        } catch (error) {
          AppLogger.warning('streak_undo_refresh_failed', error: error);
        }
        if (context.mounted) {
          hk_ui.showToast(
            context,
            content: Text(context.l10n.completionUndone),
          );
        }
      } catch (error) {
        if (context.mounted) {
          hk_ui.showToast(
            context,
            content: Text(
              failureMessage(context, error, fallback: AppFailureCode.undo),
            ),
            severity: hk_ui.HkToastSeverity.error,
          );
        }
      }
    },
  );
  if (context.mounted) {
    final config =
        ref.read(monetizationConfigProvider).value ??
        const MonetizationConfig.failClosed();
    await ref
        .read(completionAdCoordinatorProvider)
        .onTaskCompleted(
          config: config,
          keyboardVisible: MediaQuery.viewInsetsOf(context).bottom > 0,
          modalActive: false,
        );
  }
  return true;
}
