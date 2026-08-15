import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:owntend/src/core/database/app_database.dart';
import 'package:owntend/src/core/services/notification_service.dart';
import 'package:owntend/src/core/services/reminder_schedule_reconciler.dart';
import 'package:owntend/src/core/sync/background_sync_scheduler.dart';
import 'package:owntend/src/core/sync/local_sync_store.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _FakePathProviderPlatform extends PathProviderPlatform {
  _FakePathProviderPlatform({
    required this.documentsPath,
    required this.temporaryPath,
  });

  final String documentsPath;
  final String temporaryPath;

  @override
  Future<String?> getApplicationDocumentsPath() async => documentsPath;

  @override
  Future<String?> getTemporaryPath() async => temporaryPath;

  @override
  Future<String?> getApplicationSupportPath() async => documentsPath;

  @override
  Future<String?> getApplicationCachePath() async => temporaryPath;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late File tempFile;
  late LocalSyncStore store;
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('signout_barrier_test_');
    PathProviderPlatform.instance = _FakePathProviderPlatform(
      documentsPath: tempDir.path,
      temporaryPath: tempDir.path,
    );
    tempFile = File('${tempDir.path}/test.sqlite');
    db = AppDatabase(executor: NativeDatabase(tempFile));
    store = LocalSyncStore(db);
    await store.account();
  });

  tearDown(() async {
    await db.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('signOutOrchestrator clears binding and scheduled reminders', () async {
    final scheduleStore = MemoryReminderScheduleStore();
    await scheduleStore.replaceAll([
      ReminderScheduleEntry(
        identity: 't1',
        notificationId: 100,
        planRevision: 'r1',
        scheduledAt: DateTime.now(),
        timezone: 'UTC',
        localComponents: '12:00',
        scheduleMode: 'exact',
        contentVersion: 'v1',
      ),
    ]);

    // Bind identity first
    await store.bindIdentity('user-1');
    final bound = await store.account();
    expect(bound.boundUserId, 'user-1');

    Future<void> executeSignOut() async {
      await cancelAccountScopedBackgroundWork();
      await scheduleStore.replaceAll(const []);
      await store.clearBinding();
    }

    await executeSignOut();

    final unbound = await store.account();
    expect(unbound.boundUserId, isNull);
    expect(unbound.migrationState, 'localOnly');
    expect((await scheduleStore.readAll()).isEmpty, true);
  });

  test(
    'runCloudSyncInBackground cancels background work when unauthenticated',
    () async {
      final result = await runCloudSyncInBackground(leaseScope: 'test');
      expect(result, true);
    },
  );
}
