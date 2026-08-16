part of '../../main.dart';

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
    if (tasks.isEmpty) {
      return const SizedBox.shrink();
    }
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
                label: _taskGroupCountLabel(context, tasks.length),
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

class TaskTile extends ConsumerWidget {
  const TaskTile({required this.task, this.dense = false, super.key});

  final TaskItem task;
  final bool dense;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overdue = task.status == TaskStatus.overdue;
    return Card(
      margin: EdgeInsets.only(bottom: dense ? 4 : 10),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: overdue
              ? Theme.of(context).colorScheme.errorContainer
              : null,
          child: Icon(_iconForGroup(task.plan.healthGroup)),
        ),
        title: DynamicText(
          task.plan.title,
          contentType: 'maintenance_plan.title',
        ),
        subtitle: Text(
          '${task.asset.name} · ${_formatShortDate(context, task.plan.nextDueDate)} · ${_recurrenceLabel(context, task.plan.recurrence)}',
        ),
        trailing: IconButton(
          tooltip: context.l10n.completeTask,
          onPressed: () => completeTaskWithFeedback(context, ref, task),
          icon: const Icon(Icons.check_circle_outline),
        ),
      ),
    );
  }
}

class MetricCard extends StatelessWidget {
  const MetricCard({
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
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Icon(icon, color: color),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                value,
                style: Theme.of(context).textTheme.headlineMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            Text(label),
          ],
        ),
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader({
    required this.title,
    this.actionLabel,
    this.onAction,
    super.key,
  });

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleLarge),
        ),
        if (actionLabel != null)
          TextButton(onPressed: onAction, child: Text(actionLabel!)),
      ],
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({
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
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 12),
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(body, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class ErrorPanel extends StatelessWidget {
  const ErrorPanel({required this.message, super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const hk_ui.HkStateIllustration(
              icon: Symbols.error_rounded,
              tone: hk_ui.HkIllustrationTone.danger,
              size: 88,
            ),
            const SizedBox(height: HkSpacing.xs),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ),
      ),
    );
  }
}

class MoreTile extends StatelessWidget {
  const MoreTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.path,
    super.key,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String path;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => context.push(path),
      ),
    );
  }
}

class ChartCard extends StatelessWidget {
  const ChartCard({required this.title, required this.child, super.key});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return hk_ui.PremiumCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: HkSpacing.xs),
          SizedBox(height: 150, child: child),
        ],
      ),
    );
  }
}
