import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:owntend/l10n/app_localizations_ext.dart';

import '../../../core/domain/models.dart';
import '../../../ui/app_theme.dart';
import '../../../ui/components.dart' as hk_ui;

class TaskGroup extends StatelessWidget {
  const TaskGroup({
    required this.title,
    required this.tasks,
    required this.color,
    required this.onComplete,
    required this.onEdit,
    required this.onSnooze,
    required this.onSetEnabled,
    required this.onDelete,
    super.key,
  });

  final String title;
  final List<TaskItem> tasks;
  final Color color;
  final Future<bool> Function(TaskItem) onComplete;
  final ValueChanged<TaskItem> onEdit;
  final ValueChanged<TaskItem> onSnooze;
  final Future<void> Function(TaskItem task, bool enabled) onSetEnabled;
  final Future<bool> Function(TaskItem) onDelete;

  @override
  Widget build(BuildContext context) {
    if (tasks.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 8),
          child: Row(
            children: [
              Container(
                width: 4,
                height: 32,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: HkSpacing.sm),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.headlineLarge,
                ),
              ),
              hk_ui.StatusPill(
                label: context.l10n.taskCountLabel(tasks.length),
                color: color,
              ),
            ],
          ),
        ),
        for (final task in tasks)
          hk_ui.SwipeDelete(
            margin: const EdgeInsets.only(bottom: HkSpacing.sm),
            dismissKey: ValueKey('task-delete-${task.plan.id}'),
            action: hk_ui.SwipeAction.moveToTrash(
              onAction: () => onDelete(task),
            ),
            child: hk_ui.TaskCard(
              task: task,
              margin: EdgeInsets.zero,
              onTap: () => context.push('/maintenance/${task.plan.id}'),
              onComplete: () => onComplete(task),
              onEdit: () => onEdit(task),
              onSnooze: () => onSnooze(task),
              onSetEnabled: (enabled) => onSetEnabled(task, enabled),
              onArchive: () => onDelete(task),
            ),
          ),
        const SizedBox(height: 8),
      ],
    );
  }
}
