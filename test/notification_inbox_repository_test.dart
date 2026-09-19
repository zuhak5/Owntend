import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:owntend/src/core/data/repositories.dart';
import 'package:owntend/src/core/database/app_database.dart';
import 'package:owntend/src/core/domain/models.dart';

void main() {
  late AppDatabase db;
  late DriftNotificationInboxRepository inbox;
  late DriftMaintenanceRepository maintenance;
  late DriftAssetRepository assets;

  setUp(() {
    db = AppDatabase(executor: NativeDatabase.memory());
    inbox = DriftNotificationInboxRepository(db);
    maintenance = DriftMaintenanceRepository(db);
    assets = DriftAssetRepository(db);
  });

  tearDown(() => db.close());

  Future<String> createPlan(String title) async {
    final areaId = await assets.saveArea(
      name: 'Area for $title',
      kind: AreaKind.indoor,
    );
    final roomId = await assets.saveRoom(
      areaId: areaId,
      name: 'Room for $title',
    );
    final assetId = await assets.saveAsset(
      name: 'Asset for $title',
      roomId: roomId,
    );
    return maintenance.savePlan(
      assetId: assetId,
      title: title,
      recurrence: const RecurrenceRule(interval: 1, unit: RecurrenceUnit.days),
      priority: PriorityLevel.medium,
      nextDueDate: DateTime.now(),
    );
  }

  group('DriftNotificationInboxRepository', () {
    test(
      'markAllRead marks all unread notifications read with updated timestamp',
      () async {
        final plan1 = await createPlan('Task 1');
        final plan2 = await createPlan('Task 2');

        await inbox.createNotification(
          title: 'Task 1 is due today',
          body: 'Check steps',
          kind: 'task',
          planId: plan1,
          messageCode: NotificationMessageCode.taskDueToday,
        );
        await inbox.createNotification(
          title: 'Task 2 is due today',
          body: 'Check steps',
          kind: 'task',
          planId: plan2,
          messageCode: NotificationMessageCode.taskDueToday,
        );

        var unread = await inbox.unreadCount();
        expect(unread, 2);

        final beforeMark = DateTime.now();
        await inbox.markAllRead();

        unread = await inbox.unreadCount();
        expect(unread, 0);

        final notifications = await inbox.listNotifications();
        expect(notifications, hasLength(2));
        for (final n in notifications) {
          expect(n.readAt, isNotNull);
          expect(
            n.readAt!.isAfter(beforeMark.subtract(const Duration(seconds: 1))),
            isTrue,
          );
        }
      },
    );

    test('identical task notification does not revert readAt to null on reconciliation', () async {
      final planId = await createPlan('Clean HVAC Filters');

      await inbox.createNotification(
        title: 'Clean HVAC Filters is due today',
        body: 'Check required steps and mark completed when done.',
        kind: 'task',
        planId: planId,
        messageCode: NotificationMessageCode.taskDueToday,
        messageArgs: {'task': 'Clean HVAC Filters'},
      );

      await inbox.markAllRead();

      var list = await inbox.listNotifications();
      expect(list.single.readAt, isNotNull);
      final initialReadAt = list.single.readAt;

      // Simulate periodic background reconciliation running 15 minutes later with identical task payload
      await inbox.createNotification(
        title: 'Clean HVAC Filters is due today',
        body: 'Check required steps and mark completed when done.',
        kind: 'task',
        planId: planId,
        messageCode: NotificationMessageCode.taskDueToday,
        messageArgs: {'task': 'Clean HVAC Filters'},
      );

      list = await inbox.listNotifications();
      expect(list, hasLength(1));
      expect(
        list.single.readAt,
        equals(initialReadAt),
        reason:
            'Identical task notification must preserve readAt and not reopen',
      );
      expect(list.single.unread, isFalse);
    });

    test('task notification with changed body preserves readAt', () async {
      final planId = await createPlan('Water Plants');

      await inbox.createNotification(
        title: 'Water Plants is due today',
        body: 'Old body text',
        kind: 'task',
        planId: planId,
        messageCode: NotificationMessageCode.taskDueToday,
      );

      final initialRow = (await inbox.listNotifications()).single;
      await inbox.markRead(initialRow.id);

      var list = await inbox.listNotifications();
      final readAt = list.single.readAt;
      expect(readAt, isNotNull);

      // Re-create with changed body
      await inbox.createNotification(
        title: 'Water Plants is due today',
        body: 'Updated body text with instructions',
        kind: 'task',
        planId: planId,
        messageCode: NotificationMessageCode.taskDueToday,
      );

      list = await inbox.listNotifications();
      expect(list, hasLength(1));
      expect(list.single.body, 'Updated body text with instructions');
      expect(
        list.single.readAt,
        equals(readAt),
        reason: 'Task notifications must remain read when updated',
      );
    });

    test('daily digest notification with changed content reopens to unread', () async {
      await inbox.createNotification(
        title: 'Daily Digest',
        body: 'You have 1 task due today',
        kind: 'digest',
        messageCode: NotificationMessageCode.dailyDigest,
      );

      await inbox.markAllRead();
      var list = await inbox.listNotifications();
      expect(list.single.readAt, isNotNull);

      // Re-create digest with changed content (new tasks added during the day)
      await inbox.createNotification(
        title: 'Daily Digest',
        body: 'You have 3 tasks due today',
        kind: 'digest',
        messageCode: NotificationMessageCode.dailyDigest,
      );

      list = await inbox.listNotifications();
      expect(list, hasLength(1));
      expect(list.single.body, 'You have 3 tasks due today');
      expect(
        list.single.readAt,
        isNull,
        reason: 'Digest notification with changed content should reopen to notify user of updates',
      );
    });

    test('markRead sets both readAt and updatedAt', () async {
      final planId = await createPlan('Inspection');

      await inbox.createNotification(
        title: 'Inspection due',
        body: 'Check roof',
        kind: 'task',
        planId: planId,
      );

      final row = (await inbox.listNotifications()).single;
      final beforeRead = DateTime.now();
      await inbox.markRead(row.id);

      final updated = (await inbox.listNotifications()).single;
      expect(updated.readAt, isNotNull);
      expect(
        updated.readAt!.isAfter(
          beforeRead.subtract(const Duration(seconds: 1)),
        ),
        isTrue,
      );
    });

    test(
      'plan completion marks inbox notification read and bumps updatedAt',
      () async {
        final planId = await createPlan('Annual Filter Change');

        await inbox.createNotification(
          title: 'Annual Filter Change is due today',
          body: 'Check steps',
          kind: 'task',
          planId: planId,
        );

        var unread = await inbox.unreadCount();
        expect(unread, 1);

        final task = await maintenance.getTask(planId);
        expect(task, isNotNull);

        final beforeComplete = DateTime.now();
        await maintenance.completePlanResult(
          planId,
          expectedOccurrenceId: task!.plan.currentOccurrenceId,
          completedAt: DateTime.now(),
        );

        unread = await inbox.unreadCount();
        expect(unread, 0);

        final rawNotification = await (db.select(
          db.inboxNotifications,
        )..where((row) => row.planId.equals(planId))).getSingle();
        expect(rawNotification.readAt, isNotNull);
        expect(
          rawNotification.updatedAt.isAfter(
            beforeComplete.subtract(const Duration(seconds: 1)),
          ),
          isTrue,
        );
      },
    );
  });
}
