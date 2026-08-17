from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    file = Path(path)
    text = file.read_text()
    if old not in text:
        raise SystemExit(f"missing expected block in {path}")
    file.write_text(text.replace(old, new, 1))


# BUG-014: durable reconciliation queue consumer.
path = Path("lib/src/core/services/reminder_schedule_reconciler.dart")
text = path.read_text()
text = text.replace(
    "import '../database/app_database.dart';\n",
    "import '../database/app_database.dart';\nimport '../domain/contracts.dart';\n",
    1,
)
consumer = r'''

enum NotificationReconciliationDrainResult {
  noWork,
  refreshed,
  accountMismatch,
}

typedef NotificationReconciliationAccountGuard =
    Future<bool> Function(String expectedUserId);

class NotificationReconciliationConsumer {
  NotificationReconciliationConsumer({
    required AppDatabase database,
    required NotificationScheduler scheduler,
    required NotificationReconciliationAccountGuard accountGuard,
    DateTime Function()? now,
  }) : _database = database,
       _scheduler = scheduler,
       _accountGuard = accountGuard,
       _now = now ?? DateTime.now;

  static const _maxRetryDelay = Duration(hours: 1);

  final AppDatabase _database;
  final NotificationScheduler _scheduler;
  final NotificationReconciliationAccountGuard _accountGuard;
  final DateTime Function() _now;

  Future<NotificationReconciliationDrainResult> drainForAccount(
    String expectedUserId,
  ) async {
    final userId = expectedUserId.trim();
    if (userId.isEmpty || !await _accountGuard(userId)) {
      return NotificationReconciliationDrainResult.accountMismatch;
    }

    final now = _now();
    final requests =
        await (_database.select(_database.notificationReconciliationRequests)
              ..where(
                (row) =>
                    row.nextAttemptAt.isNull() |
                    row.nextAttemptAt.isSmallerOrEqualValue(now),
              )
              ..orderBy([(row) => OrderingTerm.asc(row.updatedAt)]))
            .get();
    if (requests.isEmpty) {
      return NotificationReconciliationDrainResult.noWork;
    }

    try {
      await _scheduler.refreshSchedules();
    } on Object catch (error) {
      await _recordFailure(requests, error, now);
      rethrow;
    }

    if (!await _accountGuard(userId)) {
      return NotificationReconciliationDrainResult.accountMismatch;
    }

    await _database.transaction(() async {
      for (final request in requests) {
        await (_database.delete(_database.notificationReconciliationRequests)
              ..where(
                (row) =>
                    row.scopeKey.equals(request.scopeKey) &
                    row.updatedAt.equals(request.updatedAt),
              ))
            .go();
      }
    });
    return NotificationReconciliationDrainResult.refreshed;
  }

  Future<void> _recordFailure(
    List<NotificationReconciliationRequestRow> requests,
    Object error,
    DateTime now,
  ) {
    final errorCode = error.runtimeType.toString();
    return _database.transaction(() async {
      for (final request in requests) {
        final attempts = request.attempts + 1;
        await (_database.update(_database.notificationReconciliationRequests)
              ..where(
                (row) =>
                    row.scopeKey.equals(request.scopeKey) &
                    row.updatedAt.equals(request.updatedAt),
              ))
            .write(
              NotificationReconciliationRequestsCompanion(
                attempts: Value(attempts),
                updatedAt: Value(now),
                nextAttemptAt: Value(now.add(_retryDelay(attempts))),
                lastErrorCode: Value(errorCode),
                lastErrorMessage: const Value('schedule_refresh_failed'),
              ),
            );
      }
    });
  }

  Duration _retryDelay(int attempts) {
    final exponent = attempts.clamp(1, 7).toInt() - 1;
    final delay = Duration(minutes: 1 << exponent);
    return delay > _maxRetryDelay ? _maxRetryDelay : delay;
  }
}
'''
if "class NotificationReconciliationConsumer" in text:
    raise SystemExit("consumer already present")
path.write_text(text.rstrip() + consumer + "\n")

# BUG-010: explicit account-scoped registration plus background queue drain.
path = Path("lib/src/core/services/notification_service.dart")
text = path.read_text()
insert_marker = "import 'reminder_schedule_reconciler.dart';\n\n"
support = r'''abstract interface class NotificationBackgroundRegistration {
  Future<void> registerBackgroundRefresh();
}

@visibleForTesting
bool notificationBackgroundAccountMatches({
  required String? sessionUserId,
  required String? boundUserId,
  required bool accountEnabled,
  required bool uploadProhibited,
  required String? migrationState,
}) {
  final sessionId = sessionUserId?.trim();
  final localId = boundUserId?.trim();
  return sessionId != null &&
      sessionId.isNotEmpty &&
      localId == sessionId &&
      accountEnabled &&
      !uploadProhibited &&
      migrationState != 'quarantined';
}

'''
if support.strip() not in text:
    text = text.replace(insert_marker, insert_marker + support, 1)

old_gate = """          final session = client?.auth.currentSession;
          final store = LocalSyncStore(db);
          final account = await store.existingAccount();

          if (session == null ||
              account == null ||
              !account.enabled ||
              account.boundUserId != session.user.id ||
              account.uploadProhibited ||
              account.migrationState == 'quarantined') {
"""
new_gate = """          final session = client?.auth.currentSession;
          final store = LocalSyncStore(db);
          final account = await store.existingAccount();

          if (!notificationBackgroundAccountMatches(
            sessionUserId: session?.user.id,
            boundUserId: account?.boundUserId,
            accountEnabled: account?.enabled ?? false,
            uploadProhibited: account?.uploadProhibited ?? false,
            migrationState: account?.migrationState,
          )) {
"""
if old_gate not in text:
    raise SystemExit("missing worker gate")
text = text.replace(old_gate, new_gate, 1)

old_worker_tail = """          final scheduler = OwntendNotificationScheduler(
            maintenanceRepository,
            scheduleStore: DriftReminderScheduleStore(db),
            notificationInboxRepository: inboxRepository,
            settingsRepository: settingsRepository,
            weatherRepository: weatherRepository,
            supabaseClient: client,
            localSyncStore: store,
          );
          await scheduler.initialize();
          await scheduler.refreshSchedules();
          return true;
"""
new_worker_tail = """          final scheduler = OwntendNotificationScheduler(
            maintenanceRepository,
            scheduleStore: DriftReminderScheduleStore(db),
            notificationInboxRepository: inboxRepository,
            settingsRepository: settingsRepository,
            weatherRepository: weatherRepository,
            supabaseClient: client,
            localSyncStore: store,
          );
          await scheduler.initialize();
          final consumer = NotificationReconciliationConsumer(
            database: db,
            scheduler: scheduler,
            accountGuard: (expectedUserId) async {
              final currentSession = client?.auth.currentSession;
              final currentAccount = await store.existingAccount();
              return expectedUserId == currentSession?.user.id &&
                  notificationBackgroundAccountMatches(
                    sessionUserId: currentSession?.user.id,
                    boundUserId: currentAccount?.boundUserId,
                    accountEnabled: currentAccount?.enabled ?? false,
                    uploadProhibited: currentAccount?.uploadProhibited ?? false,
                    migrationState: currentAccount?.migrationState,
                  );
            },
          );
          final reconciliation = await consumer.drainForAccount(
            session!.user.id,
          );
          if (reconciliation ==
              NotificationReconciliationDrainResult.accountMismatch) {
            await cancelAccountScopedBackgroundWork();
            return true;
          }
          if (reconciliation == NotificationReconciliationDrainResult.noWork) {
            await scheduler.refreshSchedules();
          }
          return true;
"""
if old_worker_tail not in text:
    raise SystemExit("missing worker tail")
text = text.replace(old_worker_tail, new_worker_tail, 1)

text = text.replace(
    "class OwntendNotificationScheduler implements NotificationScheduler {",
    "class OwntendNotificationScheduler\n    implements NotificationScheduler, NotificationBackgroundRegistration {",
    1,
)
old_registration = """    if (Platform.isAndroid) {
      await wm.Workmanager().initialize(owntendWorkManagerCallback);
      final session = _supabaseClient?.auth.currentSession;
      final boundUserId =
          (await _localSyncStore?.existingAccount())?.boundUserId;
      if (session != null && boundUserId == session.user.id) {
        await wm.Workmanager().registerPeriodicTask(
          dailyRefreshTask,
          dailyRefreshTask,
          frequency: const Duration(hours: 24),
          initialDelay: const Duration(hours: 1),
          existingWorkPolicy: wm.ExistingPeriodicWorkPolicy.update,
        );
      }
    }
    _initialized = true;
  }

"""
new_registration = """    _initialized = true;
  }

  @override
  Future<void> registerBackgroundRefresh() async {
    if (!Platform.isAndroid) {
      return;
    }
    final session = _supabaseClient?.auth.currentSession;
    final account = await _localSyncStore?.existingAccount();
    if (!notificationBackgroundAccountMatches(
      sessionUserId: session?.user.id,
      boundUserId: account?.boundUserId,
      accountEnabled: account?.enabled ?? false,
      uploadProhibited: account?.uploadProhibited ?? false,
      migrationState: account?.migrationState,
    )) {
      await wm.Workmanager().cancelByUniqueName(dailyRefreshTask);
      return;
    }

    final expectedUserId = session!.user.id;
    final workManager = wm.Workmanager();
    await workManager.initialize(owntendWorkManagerCallback);

    final currentSession = _supabaseClient?.auth.currentSession;
    final currentAccount = await _localSyncStore?.existingAccount();
    if (currentSession?.user.id != expectedUserId ||
        !notificationBackgroundAccountMatches(
          sessionUserId: currentSession?.user.id,
          boundUserId: currentAccount?.boundUserId,
          accountEnabled: currentAccount?.enabled ?? false,
          uploadProhibited: currentAccount?.uploadProhibited ?? false,
          migrationState: currentAccount?.migrationState,
        )) {
      await workManager.cancelByUniqueName(dailyRefreshTask);
      return;
    }

    await workManager.registerPeriodicTask(
      dailyRefreshTask,
      dailyRefreshTask,
      frequency: const Duration(hours: 24),
      initialDelay: const Duration(hours: 1),
      existingWorkPolicy: wm.ExistingPeriodicWorkPolicy.update,
    );
  }

"""
if old_registration not in text:
    raise SystemExit("missing registration block")
path.write_text(text.replace(old_registration, new_registration, 1))

# Production dependencies and the queue consumer provider.
path = Path("lib/src/core/providers/app_providers.dart")
text = path.read_text()
old_provider = """    weatherRepository: ref.watch(weatherRepositoryProvider),
    permissionGateway: ref.watch(permissionCoordinatorProvider),
    onNotificationPayload: _openNotificationPayload,
  ),
);

final notificationAutoStartProvider = Provider<bool>((ref) => true);
"""
new_provider = """    weatherRepository: ref.watch(weatherRepositoryProvider),
    permissionGateway: ref.watch(permissionCoordinatorProvider),
    supabaseClient: ref.watch(supabaseClientProvider),
    localSyncStore: ref.watch(localSyncStoreProvider),
    onNotificationPayload: _openNotificationPayload,
  ),
);

final notificationReconciliationConsumerProvider =
    Provider<NotificationReconciliationConsumer?>((ref) {
      final client = ref.watch(supabaseClientProvider);
      final store = ref.watch(localSyncStoreProvider);
      if (client == null || store == null) {
        return null;
      }
      return NotificationReconciliationConsumer(
        database: ref.watch(databaseProvider),
        scheduler: ref.watch(notificationSchedulerProvider),
        accountGuard: (expectedUserId) async {
          final session = client.auth.currentSession;
          final account = await store.existingAccount();
          return expectedUserId == session?.user.id &&
              notificationBackgroundAccountMatches(
                sessionUserId: session?.user.id,
                boundUserId: account?.boundUserId,
                accountEnabled: account?.enabled ?? false,
                uploadProhibited: account?.uploadProhibited ?? false,
                migrationState: account?.migrationState,
              );
        },
      );
    });

final notificationAutoStartProvider = Provider<bool>((ref) => true);
"""
if old_provider not in text:
    raise SystemExit("missing notification provider block")
path.write_text(text.replace(old_provider, new_provider, 1))

# Normal authenticated bootstrap explicitly registers and drains; resume reuses it.
path = Path("lib/src/features/startup/presentation/startup_restoration_screen.dart")
text = path.read_text()
old_refresh = """      final scheduler = ref.read(notificationSchedulerProvider);
      await scheduler.initialize();
      await scheduler.refreshSchedules();
"""
new_refresh = """      final scheduler = ref.read(notificationSchedulerProvider);
      await scheduler.initialize();
      if (scheduler is NotificationBackgroundRegistration) {
        await scheduler.registerBackgroundRefresh();
      }
      final session = ref.read(authRepositoryProvider)?.currentSession;
      final consumer = ref.read(notificationReconciliationConsumerProvider);
      if (session != null && consumer != null) {
        final result = await consumer.drainForAccount(session.userId);
        if (result == NotificationReconciliationDrainResult.refreshed ||
            result == NotificationReconciliationDrainResult.accountMismatch) {
          return;
        }
      }
      await scheduler.refreshSchedules();
"""
if old_refresh not in text:
    raise SystemExit("missing bootstrap refresh")
path.write_text(text.replace(old_refresh, new_refresh, 1))

# Foreground completion/sync callback drains the durable queue before fallback refresh.
path = Path("lib/src/features/startup/presentation/startup_bootstrap.dart")
text = path.read_text()
old_callback = """              maintenanceCompletionReminderReconcilerProvider.overrideWith(
                (ref) => () async {
                  await ref
                      .read(notificationSchedulerProvider)
                      .refreshSchedules();
                },
              ),
"""
new_callback = """              maintenanceCompletionReminderReconcilerProvider.overrideWith(
                (ref) => () async {
                  final scheduler = ref.read(notificationSchedulerProvider);
                  final session = ref.read(authRepositoryProvider)?.currentSession;
                  final consumer = ref.read(
                    notificationReconciliationConsumerProvider,
                  );
                  if (session != null && consumer != null) {
                    final result = await consumer.drainForAccount(
                      session.userId,
                    );
                    if (result != NotificationReconciliationDrainResult.noWork) {
                      return;
                    }
                  }
                  await scheduler.refreshSchedules();
                },
              ),
"""
if old_callback not in text:
    raise SystemExit("missing maintenance callback")
path.write_text(text.replace(old_callback, new_callback, 1))

# Changelog.
path = Path("CHANGELOG.md")
text = path.read_text()
marker = "### Fixed\n\n"
bullet = (
    "- Wired authenticated notification startup to idempotent daily background "
    "refresh registration and added a crash-safe consumer for durable notification "
    "reconciliation requests.\n"
)
if bullet not in text:
    text = text.replace(marker, marker + bullet, 1)
path.write_text(text)

# Focused regression and fault-path coverage.
Path("test/bug_010_bug_014_notification_consumers_test.dart").write_text(r'''import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:owntend/src/core/database/app_database.dart';
import 'package:owntend/src/core/domain/contracts.dart';
import 'package:owntend/src/core/services/notification_service.dart';
import 'package:owntend/src/core/services/reminder_schedule_reconciler.dart';

class _FakeNotificationScheduler implements NotificationScheduler {
  int refreshCount = 0;
  Object? failure;
  Future<void> Function()? onRefresh;

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
          reason: 'test',
          createdAt: Value(updatedAt),
          updatedAt: Value(updatedAt),
        ),
      );
}

void main() {
  group('BUG-010 background registration contract', () {
    test('requires matching enabled non-quarantined account identity', () {
      expect(
        notificationBackgroundAccountMatches(
          sessionUserId: 'user-a',
          boundUserId: 'user-a',
          accountEnabled: true,
          uploadProhibited: false,
          migrationState: 'active',
        ),
        isTrue,
      );
      for (final mismatch in <bool Function()>[
        () => notificationBackgroundAccountMatches(
          sessionUserId: null,
          boundUserId: 'user-a',
          accountEnabled: true,
          uploadProhibited: false,
          migrationState: 'active',
        ),
        () => notificationBackgroundAccountMatches(
          sessionUserId: 'user-b',
          boundUserId: 'user-a',
          accountEnabled: true,
          uploadProhibited: false,
          migrationState: 'active',
        ),
        () => notificationBackgroundAccountMatches(
          sessionUserId: 'user-a',
          boundUserId: 'user-a',
          accountEnabled: false,
          uploadProhibited: false,
          migrationState: 'active',
        ),
        () => notificationBackgroundAccountMatches(
          sessionUserId: 'user-a',
          boundUserId: 'user-a',
          accountEnabled: true,
          uploadProhibited: true,
          migrationState: 'active',
        ),
        () => notificationBackgroundAccountMatches(
          sessionUserId: 'user-a',
          boundUserId: 'user-a',
          accountEnabled: true,
          uploadProhibited: false,
          migrationState: 'quarantined',
        ),
      ]) {
        expect(mismatch(), isFalse);
      }
    });

    test('production bootstrap owns explicit idempotent registration', () async {
      String normalized(String value) => value.replaceAll('\r\n', '\n');
      final service = normalized(
        await File('lib/src/core/services/notification_service.dart').readAsString(),
      );
      final providers = normalized(
        await File('lib/src/core/providers/app_providers.dart').readAsString(),
      );
      final bootstrap = normalized(
        await File(
          'lib/src/features/startup/presentation/startup_restoration_screen.dart',
        ).readAsString(),
      );
      expect(service, contains('Future<void> registerBackgroundRefresh() async'));
      expect(
        service,
        contains('existingWorkPolicy: wm.ExistingPeriodicWorkPolicy.update'),
      );
      expect(providers, contains('supabaseClient: ref.watch(supabaseClientProvider)'));
      expect(providers, contains('localSyncStore: ref.watch(localSyncStoreProvider)'));
      expect(bootstrap, contains('await scheduler.registerBackgroundRefresh();'));
    });
  });

  group('BUG-014 durable notification reconciliation consumer', () {
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

    test('success coalesces pending requests and acknowledges after refresh', () async {
      await _insertRequest(db, scopeKey: 'plan:a', updatedAt: now);
      await _insertRequest(db, scopeKey: 'plan:b', updatedAt: now);

      final result = await consumer().drainForAccount('user-a');

      expect(result, NotificationReconciliationDrainResult.refreshed);
      expect(scheduler.refreshCount, 1);
      expect(await db.select(db.notificationReconciliationRequests).get(), isEmpty);
    });

    test('duplicate request keys remain coalesced into one refresh', () async {
      await _insertRequest(db, scopeKey: 'plan:a', updatedAt: now);
      await _insertRequest(
        db,
        scopeKey: 'plan:a',
        updatedAt: now.add(const Duration(seconds: 1)),
      );

      expect(await db.select(db.notificationReconciliationRequests).get(), hasLength(1));
      await consumer().drainForAccount('user-a');
      expect(scheduler.refreshCount, 1);
      expect(await db.select(db.notificationReconciliationRequests).get(), isEmpty);
    });

    test('scheduler failure keeps request and records bounded retry state', () async {
      await _insertRequest(db, scopeKey: 'plan:a', updatedAt: now);
      scheduler.failure = StateError('simulated scheduling failure');

      await expectLater(
        consumer().drainForAccount('user-a'),
        throwsA(isA<StateError>()),
      );

      final request =
          await db.select(db.notificationReconciliationRequests).getSingle();
      expect(request.attempts, 1);
      expect(request.lastErrorCode, 'StateError');
      expect(request.lastErrorMessage, 'schedule_refresh_failed');
      expect(request.nextAttemptAt, now.add(const Duration(minutes: 1)));
    });

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
      expect(await db.select(db.notificationReconciliationRequests).get(), isEmpty);
    });

    test('wrong account leaves durable work untouched', () async {
      await _insertRequest(db, scopeKey: 'plan:a', updatedAt: now);
      accountMatches = false;

      expect(
        await consumer().drainForAccount('user-b'),
        NotificationReconciliationDrainResult.accountMismatch,
      );
      expect(scheduler.refreshCount, 0);
      expect(await db.select(db.notificationReconciliationRequests).get(), hasLength(1));
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

      final request =
          await db.select(db.notificationReconciliationRequests).getSingle();
      expect(request.updatedAt, newer);
      expect(scheduler.refreshCount, 1);
    });

    test('daily worker source drains durable work before fallback refresh', () async {
      final source = (await File(
        'lib/src/core/services/notification_service.dart',
      ).readAsString()).replaceAll('\r\n', '\n');
      expect(source, contains('NotificationReconciliationConsumer('));
      expect(source, contains('await consumer.drainForAccount('));
      expect(
        source,
        contains('NotificationReconciliationDrainResult.accountMismatch'),
      );
    });
  });
}
''')
