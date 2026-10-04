import 'dart:io';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:owntend/src/core/database/app_database.dart';
import 'package:owntend/src/core/domain/contracts.dart';
import 'package:owntend/src/core/services/notification_service.dart';
import 'package:owntend/src/core/services/reminder_schedule_reconciler.dart';
import 'package:owntend/src/core/sync/local_sync_store.dart';

class _FakeNotificationScheduler implements NotificationScheduler {
  int refreshCount = 0;
  Object? failure;
  Future<void> Function()? onRefresh;
  Future<void> Function()? onInitialize;

  @override
  Future<void> initialize() async => onInitialize?.call();

  @override
  Future<void> refreshSchedules() async {
    refreshCount++;
    await onRefresh?.call();
    final error = failure;
    if (error != null) throw error;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _insertRequest(
  AppDatabase db, {
  required String scopeKey,
  required DateTime updatedAt,
}) {
  return db
      .into(db.notificationReconciliationRequests)
      .insertOnConflictUpdate(
        NotificationReconciliationRequestsCompanion.insert(
          scopeKey: scopeKey,
          planId: Value(scopeKey.replaceFirst('plan:', '')),
          reason: 'local_completion',
          createdAt: Value(updatedAt),
          updatedAt: Value(updatedAt),
        ),
      );
}

void main() {
  test(
    'request versions survive reopen and protect independent connections',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'owntend-reminder-version-',
      );
      final file = File('${directory.path}/reminders.sqlite');
      var writer = AppDatabase(executor: NativeDatabase(file));
      AppDatabase? reader;
      try {
        final now = DateTime.utc(2026, 8, 17, 20);
        await _insertRequest(writer, scopeKey: 'plan:a', updatedAt: now);
        final original = await writer
            .select(writer.notificationReconciliationRequests)
            .getSingle();
        await writer.close();
        writer = AppDatabase(executor: NativeDatabase(file));
        final reopened = await writer
            .select(writer.notificationReconciliationRequests)
            .getSingle();
        expect(reopened.requestVersion, original.requestVersion);
        reader = AppDatabase(executor: NativeDatabase(file));
        final scheduler = _FakeNotificationScheduler()
          ..onRefresh = () => writer.customStatement(
            "UPDATE notification_reconciliation_requests SET reason = 'schedule_inputs_changed' WHERE scope_key = 'plan:a'",
          );
        final consumer = NotificationReconciliationConsumer(
          database: reader,
          scheduler: scheduler,
          accountGuard: (_) async => true,
          now: () => now,
        );
        expect(
          await consumer.drainForAccount('user-a'),
          NotificationReconciliationDrainResult.refreshed,
        );
        final replacement = await writer
            .select(writer.notificationReconciliationRequests)
            .getSingle();
        expect(replacement.requestVersion, isNot(original.requestVersion));
        expect(replacement.updatedAt, original.updatedAt);
        scheduler.onRefresh = null;
        await consumer.drainForAccount('user-a');
        expect(
          await writer.select(writer.notificationReconciliationRequests).get(),
          isEmpty,
        );
      } finally {
        await reader?.close();
        await writer.close();
        await directory.delete(recursive: true);
      }
    },
  );

  group('daily background notification execution', () {
    late AppDatabase db;
    late _FakeNotificationScheduler scheduler;
    String? userId;

    setUp(() {
      db = AppDatabase(executor: NativeDatabase.memory());
      scheduler = _FakeNotificationScheduler();
      userId = null;
    });
    tearDown(() => db.close());

    Future<NotificationReconciliationDrainResult> runWorker() =>
        refreshBackgroundNotifications(
          database: db,
          scheduler: scheduler,
          currentUserId: () => userId,
        );

    test(
      'local worker refreshes and drains durable work without a session',
      () async {
        await _insertRequest(db, scopeKey: 'plan:a', updatedAt: DateTime.now());
        expect(
          await runWorker(),
          NotificationReconciliationDrainResult.refreshed,
        );
        expect(scheduler.refreshCount, 1);
        expect(
          await db.select(db.notificationReconciliationRequests).get(),
          isEmpty,
        );
      },
    );

    test('local worker refreshes when no durable request is queued', () async {
      expect(await runWorker(), NotificationReconciliationDrainResult.noWork);
      expect(scheduler.refreshCount, 1);
    });

    test('signed-out bound account cannot execute local work', () async {
      await LocalSyncStore(db).bindIdentity('user-a');
      expect(
        await runWorker(),
        NotificationReconciliationDrainResult.accountMismatch,
      );
      expect(scheduler.refreshCount, 0);
    });

    test('matching authenticated worker drains account work', () async {
      await LocalSyncStore(db).bindIdentity('user-a');
      userId = 'user-a';
      await _insertRequest(db, scopeKey: 'plan:a', updatedAt: DateTime.now());
      expect(
        await runWorker(),
        NotificationReconciliationDrainResult.refreshed,
      );
      expect(scheduler.refreshCount, 1);
      expect(
        await db.select(db.notificationReconciliationRequests).get(),
        isEmpty,
      );
    });

    test('identity change during initialization prevents scheduling', () async {
      scheduler.onInitialize = () async => userId = 'user-a';
      expect(
        await runWorker(),
        NotificationReconciliationDrainResult.accountMismatch,
      );
      expect(scheduler.refreshCount, 0);
    });

    test(
      'identity change during local refresh preserves pending work',
      () async {
        await _insertRequest(db, scopeKey: 'plan:a', updatedAt: DateTime.now());
        scheduler.onRefresh = () async => userId = 'user-a';
        expect(
          await runWorker(),
          NotificationReconciliationDrainResult.accountMismatch,
        );
        expect(
          await db.select(db.notificationReconciliationRequests).get(),
          hasLength(1),
        );
      },
    );
  });

  group('background registration contract', () {
    test('requires a matching enabled account identity', () {
      expect(
        notificationBackgroundAccountMatches(
          sessionUserId: 'user-a',
          boundUserId: 'user-a',
          accountEnabled: true,
        ),
        isTrue,
      );
      for (final mismatch in <bool Function()>[
        () => notificationBackgroundAccountMatches(
          sessionUserId: null,
          boundUserId: 'user-a',
          accountEnabled: true,
        ),
        () => notificationBackgroundAccountMatches(
          sessionUserId: 'user-b',
          boundUserId: 'user-a',
          accountEnabled: true,
        ),
        () => notificationBackgroundAccountMatches(
          sessionUserId: 'user-a',
          boundUserId: 'user-a',
          accountEnabled: false,
        ),
      ]) {
        expect(mismatch(), isFalse);
      }
    });

    test(
      'production bootstrap owns explicit idempotent registration',
      () async {
        String normalized(String value) => value.replaceAll('\r\n', '\n');
        final service = normalized(
          await File('lib/src/core/services/notification_service.dart')
              .readAsString(),
        );
        final providers = normalized(
          await File('lib/src/core/providers/app_providers.dart')
              .readAsString(),
        );
        final bootstrap = normalized(
          await File(
            'lib/src/features/startup/presentation/startup_restoration_screen.dart',
          ).readAsString(),
        );
        expect(
          service,
          contains('Future<void> registerBackgroundRefresh() async'),
        );
        expect(
          service,
          contains('existingWorkPolicy: wm.ExistingPeriodicWorkPolicy.update'),
        );
        expect(
          providers,
          contains('supabaseClient: ref.watch(supabaseClientProvider)'),
        );
        expect(
          providers,
          contains('localSyncStore: ref.watch(localSyncStoreProvider)'),
        );
        expect(
          bootstrap,
          contains('await backgroundRegistration.registerBackgroundRefresh();'),
        );
      },
    );
  });

  group('durable notification reconciliation consumer', () {
    late AppDatabase db;
    late _FakeNotificationScheduler scheduler;
    late DateTime now;
    var accountMatches = true;

    setUp(() {
      db = AppDatabase(executor: NativeDatabase.memory());
      scheduler = _FakeNotificationScheduler();
      now = DateTime.utc(2026, 8, 17, 20);
      accountMatches = true;
    });

    tearDown(() => db.close());

    NotificationReconciliationConsumer consumer() {
      return NotificationReconciliationConsumer(
        database: db,
        scheduler: scheduler,
        accountGuard: (_) async => accountMatches,
        now: () => now,
      );
    }

    test(
      'success coalesces pending requests and acknowledges after refresh',
      () async {
        await _insertRequest(db, scopeKey: 'plan:a', updatedAt: now);
        await _insertRequest(db, scopeKey: 'plan:b', updatedAt: now);

        final result = await consumer().drainForAccount('user-a');

        expect(result, NotificationReconciliationDrainResult.refreshed);
        expect(scheduler.refreshCount, 1);
        expect(
          await db.select(db.notificationReconciliationRequests).get(),
          isEmpty,
        );
      },
    );

    test('duplicate request keys remain coalesced into one refresh', () async {
      await _insertRequest(db, scopeKey: 'plan:a', updatedAt: now);
      await _insertRequest(
        db,
        scopeKey: 'plan:a',
        updatedAt: now.add(const Duration(seconds: 1)),
      );

      expect(
        await db.select(db.notificationReconciliationRequests).get(),
        hasLength(1),
      );
      await consumer().drainForAccount('user-a');
      expect(scheduler.refreshCount, 1);
      expect(
        await db.select(db.notificationReconciliationRequests).get(),
        isEmpty,
      );
    });

    test(
      'scheduler failure keeps request and records bounded retry state',
      () async {
        await _insertRequest(db, scopeKey: 'plan:a', updatedAt: now);
        scheduler.failure = StateError('simulated scheduling failure');

        await expectLater(
          consumer().drainForAccount('user-a'),
          throwsA(isA<StateError>()),
        );

        final request = await db
            .select(db.notificationReconciliationRequests)
            .getSingle();
        expect(request.attempts, 1);
        expect(request.lastErrorCode, 'StateError');
        expect(request.lastErrorMessage, 'schedule_refresh_failed');
        expect(
          request.nextAttemptAt?.toUtc(),
          now.add(const Duration(minutes: 1)),
        );
      },
    );

    test('request survives consumer restart and is replayed', () async {
      await _insertRequest(db, scopeKey: 'plan:a', updatedAt: now);
      scheduler.failure = StateError('first attempt fails');
      await expectLater(
        consumer().drainForAccount('user-a'),
        throwsA(isA<StateError>()),
      );

      scheduler.failure = null;
      now = now.add(const Duration(minutes: 1));
      expect(
        await consumer().drainForAccount('user-a'),
        NotificationReconciliationDrainResult.refreshed,
      );
      expect(scheduler.refreshCount, 2);
      expect(
        await db.select(db.notificationReconciliationRequests).get(),
        isEmpty,
      );
    });

    test('wrong account leaves durable work untouched', () async {
      await _insertRequest(db, scopeKey: 'plan:a', updatedAt: now);
      accountMatches = false;

      expect(
        await consumer().drainForAccount('user-b'),
        NotificationReconciliationDrainResult.accountMismatch,
      );
      expect(scheduler.refreshCount, 0);
      expect(
        await db.select(db.notificationReconciliationRequests).get(),
        hasLength(1),
      );
    });

    test('newer request written during refresh is not acknowledged', () async {
      await _insertRequest(db, scopeKey: 'plan:a', updatedAt: now);
      final newer = now.add(const Duration(seconds: 2));
      scheduler.onRefresh = () =>
          _insertRequest(db, scopeKey: 'plan:a', updatedAt: newer);

      expect(
        await consumer().drainForAccount('user-a'),
        NotificationReconciliationDrainResult.refreshed,
      );

      final request = await db
          .select(db.notificationReconciliationRequests)
          .getSingle();
      expect(request.updatedAt.toUtc(), newer);
      expect(scheduler.refreshCount, 1);
    });

    test(
      'request replaced within the same second survives acknowledgement',
      () async {
        await _insertRequest(db, scopeKey: 'plan:a', updatedAt: now);
        var replaced = false;
        scheduler.onRefresh = () async {
          if (replaced) return;
          replaced = true;
          await _insertRequest(
            db,
            scopeKey: 'plan:a',
            updatedAt: now.add(const Duration(milliseconds: 125)),
          );
        };
        await consumer().drainForAccount('user-a');
        expect(
          await db.select(db.notificationReconciliationRequests).get(),
          hasLength(1),
        );
        await consumer().drainForAccount('user-a');
        expect(scheduler.refreshCount, 2);
        expect(
          await db.select(db.notificationReconciliationRequests).get(),
          isEmpty,
        );
      },
    );

    test(
      'deleted and recreated request is not acknowledged by an older drain',
      () async {
        await _insertRequest(db, scopeKey: 'plan:a', updatedAt: now);
        scheduler.onRefresh = () async {
          await db.delete(db.notificationReconciliationRequests).go();
          await _insertRequest(db, scopeKey: 'plan:a', updatedAt: now);
        };

        await consumer().drainForAccount('user-a');

        expect(
          await db.select(db.notificationReconciliationRequests).get(),
          hasLength(1),
        );
      },
    );

    test(
      'failure cannot back off a replacement request from the same second',
      () async {
        await _insertRequest(db, scopeKey: 'plan:a', updatedAt: now);
        scheduler.onRefresh = () =>
            _insertRequest(db, scopeKey: 'plan:a', updatedAt: now);
        scheduler.failure = StateError('platform unavailable');

        await expectLater(
          consumer().drainForAccount('user-a'),
          throwsA(isA<StateError>()),
        );

        final request = await db
            .select(db.notificationReconciliationRequests)
            .getSingle();
        expect(request.attempts, 0);
        expect(request.nextAttemptAt, isNull);
      },
    );

    test(
      'daily worker source drains durable work before fallback refresh',
      () async {
        final source = (await File(
          'lib/src/core/services/notification_service.dart',
        ).readAsString()).replaceAll('\r\n', '\n');
        expect(source, contains('NotificationReconciliationConsumer('));
        expect(source, contains('await consumer.drainForAccount('));
        expect(
          source,
          contains('NotificationReconciliationDrainResult.accountMismatch'),
        );
      },
    );
  });

  group('NotificationChannelRegistry frozen contract', () {
    test('freezes canonical channel IDs', () {
      expect(NotificationChannelRegistry.dueChannelId, 'owntend_due');
      expect(NotificationChannelRegistry.overdueChannelId, 'owntend_overdue');
      expect(NotificationChannelRegistry.criticalChannelId, 'owntend_critical');
      expect(NotificationChannelRegistry.digestChannelId, 'owntend_digest');
      expect(NotificationChannelRegistry.allChannelIds, [
        'owntend_due',
        'owntend_overdue',
        'owntend_critical',
        'owntend_digest',
      ]);
    });
  });
}
