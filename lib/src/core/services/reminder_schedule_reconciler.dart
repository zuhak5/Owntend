import 'package:drift/drift.dart';

import '../database/app_database.dart';

class ReminderScheduleEntry {
  const ReminderScheduleEntry({
    required this.identity,
    required this.notificationId,
    required this.planRevision,
    required this.scheduledAt,
    required this.timezone,
    required this.localComponents,
    required this.scheduleMode,
    required this.contentVersion,
  });

  final String identity;
  final int notificationId;
  final String planRevision;
  final DateTime scheduledAt;
  final String timezone;
  final String localComponents;
  final String scheduleMode;
  final String contentVersion;

  bool hasSameSchedule(ReminderScheduleEntry other) {
    return notificationId == other.notificationId &&
        planRevision == other.planRevision &&
        scheduledAt.toUtc().isAtSameMomentAs(other.scheduledAt.toUtc()) &&
        timezone == other.timezone &&
        localComponents == other.localComponents &&
        scheduleMode == other.scheduleMode &&
        contentVersion == other.contentVersion;
  }
}

class ReminderScheduleDiff {
  const ReminderScheduleDiff({
    required this.added,
    required this.changed,
    required this.removed,
    required this.unchanged,
  });

  final List<ReminderScheduleEntry> added;
  final List<ReminderScheduleEntry> changed;
  final List<ReminderScheduleEntry> removed;
  final List<ReminderScheduleEntry> unchanged;
}

ReminderScheduleDiff diffReminderSchedules({
  required Iterable<ReminderScheduleEntry> current,
  required Iterable<ReminderScheduleEntry> desired,
}) {
  final currentByIdentity = {
    for (final entry in current) entry.identity: entry,
  };
  final desiredByIdentity = {
    for (final entry in desired) entry.identity: entry,
  };
  final added = <ReminderScheduleEntry>[];
  final changed = <ReminderScheduleEntry>[];
  final unchanged = <ReminderScheduleEntry>[];
  for (final entry in desiredByIdentity.values) {
    final previous = currentByIdentity[entry.identity];
    if (previous == null) {
      added.add(entry);
    } else if (previous.hasSameSchedule(entry)) {
      unchanged.add(entry);
    } else {
      changed.add(entry);
    }
  }
  final removed = [
    for (final entry in currentByIdentity.values)
      if (!desiredByIdentity.containsKey(entry.identity)) entry,
  ];
  return ReminderScheduleDiff(
    added: added,
    changed: changed,
    removed: removed,
    unchanged: unchanged,
  );
}

abstract interface class ReminderScheduleStore {
  Future<List<ReminderScheduleEntry>> readAll();
  Future<void> replaceAll(Iterable<ReminderScheduleEntry> entries);
}

class DriftReminderScheduleStore implements ReminderScheduleStore {
  const DriftReminderScheduleStore(this.db);

  final AppDatabase db;

  @override
  Future<List<ReminderScheduleEntry>> readAll() async {
    final rows = await db.select(db.reminderScheduleSnapshots).get();
    return [
      for (final row in rows)
        ReminderScheduleEntry(
          identity: row.identity,
          notificationId: row.notificationId,
          planRevision: row.planRevision,
          scheduledAt: row.scheduledAt,
          timezone: row.timezone,
          localComponents: row.localComponents,
          scheduleMode: row.scheduleMode,
          contentVersion: row.contentVersion,
        ),
    ];
  }

  @override
  Future<void> replaceAll(Iterable<ReminderScheduleEntry> entries) {
    return db.transaction(() async {
      await db.delete(db.reminderScheduleSnapshots).go();
      final now = DateTime.now();
      for (final entry in entries) {
        await db
            .into(db.reminderScheduleSnapshots)
            .insert(
              ReminderScheduleSnapshotsCompanion.insert(
                identity: entry.identity,
                notificationId: entry.notificationId,
                planRevision: entry.planRevision,
                scheduledAt: entry.scheduledAt,
                timezone: entry.timezone,
                localComponents: entry.localComponents,
                scheduleMode: entry.scheduleMode,
                contentVersion: entry.contentVersion,
                updatedAt: Value(now),
              ),
            );
      }
    });
  }
}

class MemoryReminderScheduleStore implements ReminderScheduleStore {
  List<ReminderScheduleEntry> _entries = const [];

  @override
  Future<List<ReminderScheduleEntry>> readAll() async =>
      List.unmodifiable(_entries);

  @override
  Future<void> replaceAll(Iterable<ReminderScheduleEntry> entries) async {
    _entries = List.unmodifiable(entries);
  }
}
