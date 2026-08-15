import 'models.dart';

import '../utils/date_utils.dart' as hk_dates;

/// Owntend treats maintenance due dates as local calendar-day obligations.
/// A task due earlier today remains in the Today bucket until the next local day.
enum TaskBucketStatus {
  overdue,
  today,
  tomorrow,
  next7Days,
  later,
  completed,
  skipped,
  archived,
}

enum ItemDueStatus { overdue, dueToday, dueSoon, onTrack, noTasks }

class ItemTaskStatusSummary {
  const ItemTaskStatusSummary({
    required this.status,
    required this.label,
    required this.count,
    this.priority,
    this.nextDueAt,
  });

  final ItemDueStatus status;
  final String label;
  final int count;
  final PriorityLevel? priority;
  final DateTime? nextDueAt;
}

class TaskBuckets {
  const TaskBuckets({
    this.overdue = const [],
    this.today = const [],
    this.tomorrow = const [],
    this.next7Days = const [],
    this.later = const [],
    this.completedToday = const [],
  });

  final List<TaskItem> overdue;
  final List<TaskItem> today;
  final List<TaskItem> tomorrow;
  final List<TaskItem> next7Days;
  final List<TaskItem> later;
  final List<TaskItem> completedToday;

  List<TaskItem> get dueSoon => [...tomorrow, ...next7Days];
  List<TaskItem> get upcoming => [
    ...today,
    ...tomorrow,
    ...next7Days,
    ...later,
  ];
  List<TaskItem> get active => [...overdue, ...upcoming];

  int get overdueCount => overdue.length;
  int get todayCount => today.length;
  int get tomorrowCount => tomorrow.length;
  int get next7DaysCount => dueSoon.length;
  int get laterCount => later.length;
  int get upcomingCount => upcoming.length;
}

TaskStatus activeTaskStatusForDueDate(DateTime dueDate, DateTime now) {
  return switch (getTaskBucketStatusFromDueDate(dueDate, now)) {
    TaskBucketStatus.overdue => TaskStatus.overdue,
    TaskBucketStatus.today => TaskStatus.dueToday,
    TaskBucketStatus.tomorrow ||
    TaskBucketStatus.next7Days ||
    TaskBucketStatus.later => TaskStatus.upcoming,
    TaskBucketStatus.completed ||
    TaskBucketStatus.skipped ||
    TaskBucketStatus.archived => TaskStatus.completed,
  };
}

TaskBucketStatus getTaskBucketStatus(TaskItem task, DateTime now) {
  if (task.plan.archivedAt != null || !task.plan.isEnabled) {
    return TaskBucketStatus.archived;
  }
  if (task.status == TaskStatus.completed) {
    return TaskBucketStatus.completed;
  }
  return getTaskBucketStatusFromDueDate(task.plan.nextDueDate, now);
}

bool isTaskActionable(TaskItem task) =>
    task.plan.archivedAt == null &&
    task.plan.isEnabled &&
    task.status != TaskStatus.completed;

TaskBucketStatus getTaskBucketStatusFromDueDate(
  DateTime dueDate,
  DateTime now,
) {
  final today = hk_dates.dateOnly(now.toLocal());
  final dueDay = hk_dates.dateOnly(dueDate.toLocal());
  if (dueDay.isBefore(today)) {
    return TaskBucketStatus.overdue;
  }
  if (hk_dates.isSameDate(dueDay, today)) {
    return TaskBucketStatus.today;
  }
  final tomorrow = DateTime(today.year, today.month, today.day + 1);
  if (hk_dates.isSameDate(dueDay, tomorrow)) {
    return TaskBucketStatus.tomorrow;
  }
  final nextSevenEnd = DateTime(today.year, today.month, today.day + 7);
  if (!dueDay.isAfter(nextSevenEnd)) {
    return TaskBucketStatus.next7Days;
  }
  return TaskBucketStatus.later;
}

TaskBuckets getTaskBuckets(Iterable<TaskItem> tasks, DateTime now) {
  final overdue = <TaskItem>[];
  final today = <TaskItem>[];
  final tomorrow = <TaskItem>[];
  final next7Days = <TaskItem>[];
  final later = <TaskItem>[];
  final completedToday = <TaskItem>[];
  for (final task in tasks) {
    if (task.plan.archivedAt != null || !task.plan.isEnabled) {
      continue;
    }
    switch (getTaskBucketStatus(task, now)) {
      case TaskBucketStatus.overdue:
        overdue.add(task);
        break;
      case TaskBucketStatus.today:
        today.add(task);
        break;
      case TaskBucketStatus.tomorrow:
        tomorrow.add(task);
        break;
      case TaskBucketStatus.next7Days:
        next7Days.add(task);
        break;
      case TaskBucketStatus.later:
        later.add(task);
        break;
      case TaskBucketStatus.completed:
        completedToday.add(task);
        break;
      case TaskBucketStatus.skipped:
      case TaskBucketStatus.archived:
        break;
    }
  }
  return TaskBuckets(
    overdue: _sortedByDueDate(overdue),
    today: _sortedByDueDate(today),
    tomorrow: _sortedByDueDate(tomorrow),
    next7Days: _sortedByDueDate(next7Days),
    later: _sortedByDueDate(later),
    completedToday: _sortedByDueDate(completedToday),
  );
}

List<TaskItem> tasksDueOnDate(Iterable<TaskItem> tasks, DateTime date) {
  final selected = hk_dates.dateOnly(date.toLocal());
  return _sortedByDueDate(
    tasks.where((task) {
      if (!isTaskActionable(task)) {
        return false;
      }
      return hk_dates.isSameDate(task.plan.nextDueDate.toLocal(), selected);
    }).toList(),
  );
}

ItemTaskStatusSummary itemTaskStatusFor(
  Asset asset,
  Iterable<TaskItem> tasks,
  DateTime now,
) {
  final itemTasks = tasks
      .where((task) => task.asset.id == asset.id)
      .where(isTaskActionable)
      .toList();
  if (itemTasks.isEmpty) {
    return const ItemTaskStatusSummary(
      status: ItemDueStatus.noTasks,
      label: 'No tasks',
      count: 0,
    );
  }

  final buckets = getTaskBuckets(itemTasks, now);
  if (buckets.overdue.isNotEmpty) {
    return _itemStatusSummary(ItemDueStatus.overdue, buckets.overdue);
  }
  if (buckets.today.isNotEmpty) {
    return _itemStatusSummary(ItemDueStatus.dueToday, buckets.today);
  }
  if (buckets.dueSoon.isNotEmpty) {
    return _itemStatusSummary(ItemDueStatus.dueSoon, buckets.dueSoon);
  }
  final sortedItemTasks = _sortedByDueDate(itemTasks);
  return ItemTaskStatusSummary(
    status: ItemDueStatus.onTrack,
    label: 'On track',
    count: sortedItemTasks.length,
    priority: _highestPriority(sortedItemTasks),
    nextDueAt: sortedItemTasks.first.plan.nextDueDate,
  );
}

Map<DateTime, List<TaskItem>> groupTasksByDueDate(Iterable<TaskItem> tasks) {
  final grouped = <DateTime, List<TaskItem>>{};
  for (final task in tasks) {
    if (!isTaskActionable(task)) {
      continue;
    }
    grouped
        .putIfAbsent(
          hk_dates.dateOnly(task.plan.nextDueDate.toLocal()),
          () => [],
        )
        .add(task);
  }
  for (final entry in grouped.entries) {
    entry.value.sort(
      (a, b) => a.plan.nextDueDate.compareTo(b.plan.nextDueDate),
    );
  }
  return grouped;
}

ItemTaskStatusSummary _itemStatusSummary(
  ItemDueStatus status,
  List<TaskItem> tasks,
) {
  final count = tasks.length;
  return ItemTaskStatusSummary(
    status: status,
    label: switch (status) {
      ItemDueStatus.overdue => '$count overdue',
      ItemDueStatus.dueToday => count == 1 ? '1 due today' : '$count due today',
      ItemDueStatus.dueSoon => count == 1 ? 'Due soon' : '$count due soon',
      ItemDueStatus.onTrack => 'On track',
      ItemDueStatus.noTasks => 'No tasks',
    },
    count: count,
    priority: _highestPriority(tasks),
    nextDueAt: tasks.first.plan.nextDueDate,
  );
}

PriorityLevel _highestPriority(Iterable<TaskItem> tasks) {
  PriorityLevel? highest;
  for (final task in tasks) {
    final priority = task.plan.priority;
    if (highest == null || _priorityRank(priority) > _priorityRank(highest)) {
      highest = priority;
    }
  }
  return highest ?? PriorityLevel.low;
}

int _priorityRank(PriorityLevel priority) {
  return switch (priority) {
    PriorityLevel.low => 0,
    PriorityLevel.medium => 1,
    PriorityLevel.high => 2,
    PriorityLevel.critical => 3,
  };
}

List<TaskItem> _sortedByDueDate(List<TaskItem> tasks) {
  return tasks
    ..sort((a, b) => a.plan.nextDueDate.compareTo(b.plan.nextDueDate));
}
