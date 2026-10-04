import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:owntend/main.dart';
import 'package:owntend/src/core/database/app_database.dart';
import 'package:owntend/src/core/services/notification_service.dart';
import 'package:owntend/src/core/sync/local_sync_store.dart';

import 'support/widget_test_fakes.dart';

void main() {
  testWidgets('disposed notification owner cancels pending account startup', (
    tester,
  ) async {
    final account = Completer<SyncAccountData>();
    final scheduler = _OwnedScheduler();
    final backup = _CountingBackup();
    final visible = await _mountBootstrap(
      tester,
      account: account.future,
      scheduler: scheduler,
      backup: backup,
    );

    visible.value = false;
    await tester.pump();
    account.complete(_localAccount);
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(scheduler.initializeCount, 0);
    expect(scheduler.registrationCount, 0);
    expect(scheduler.refreshCount, 0);
    expect(backup.exportCount, 0);
  });

  testWidgets('disposed notification owner cannot register or start backup', (
    tester,
  ) async {
    final initialization = Completer<void>();
    final scheduler = _OwnedScheduler(initialization: initialization.future);
    final backup = _CountingBackup();
    final visible = await _mountBootstrap(
      tester,
      account: Future.value(_localAccount),
      scheduler: scheduler,
      backup: backup,
    );
    expect(scheduler.initializeCount, 1);

    visible.value = false;
    await tester.pump();
    initialization.complete();
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(scheduler.registrationCount, 0);
    expect(scheduler.refreshCount, 0);
    expect(backup.exportCount, 0);
  });

  testWidgets('notification startup owns an initial account read failure', (
    tester,
  ) async {
    final account = Completer<SyncAccountData>();
    final scheduler = _OwnedScheduler();
    final backup = _CountingBackup();
    await _mountBootstrap(
      tester,
      account: account.future,
      scheduler: scheduler,
      backup: backup,
    );

    account.completeError(StateError('account read unavailable'));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(scheduler.initializeCount, 0);
    expect(backup.exportCount, 0);
  });

  for (final phase in ['registration', 'refresh']) {
    testWidgets('disposed notification owner stops after pending $phase', (
      tester,
    ) async {
      final pending = Completer<void>();
      final scheduler = _OwnedScheduler(
        registration: phase == 'registration' ? pending.future : null,
        refresh: phase == 'refresh' ? pending.future : null,
      );
      final backup = _CountingBackup();
      final visible = await _mountBootstrap(
        tester,
        account: Future.value(_localAccount),
        scheduler: scheduler,
        backup: backup,
      );
      expect(scheduler.registrationCount, 1);
      visible.value = false;
      await tester.pump();
      pending.complete();
      await tester.pump();
      expect(scheduler.refreshCount, phase == 'refresh' ? 1 : 0);
      expect(backup.exportCount, 0);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('current notification owner still refreshes and starts backup', (
    tester,
  ) async {
    final scheduler = _OwnedScheduler();
    final backup = _CountingBackup();
    await _mountBootstrap(
      tester,
      account: Future.value(_localAccount),
      scheduler: scheduler,
      backup: backup,
    );

    expect(scheduler.initializeCount, 1);
    expect(scheduler.registrationCount, 1);
    expect(scheduler.refreshCount, 1);
    expect(backup.exportCount, 1);
    expect(tester.takeException(), isNull);
  });
}

Future<ValueNotifier<bool>> _mountBootstrap(
  WidgetTester tester, {
  required Future<SyncAccountData> account,
  required _OwnedScheduler scheduler,
  required _CountingBackup backup,
}) async {
  final store = _AccountStore();
  when(store.account).thenAnswer((_) => account);
  final visible = ValueNotifier(true);
  addTearDown(visible.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        localSyncStoreProvider.overrideWithValue(store),
        notificationSchedulerProvider.overrideWithValue(scheduler),
        notificationAutoStartProvider.overrideWithValue(true),
        notificationReconciliationConsumerProvider.overrideWithValue(null),
        authRepositoryProvider.overrideWithValue(null),
        backupRepositoryProvider.overrideWithValue(backup),
        backupAutoStartProvider.overrideWithValue(true),
      ],
      child: ValueListenableBuilder<bool>(
        valueListenable: visible,
        builder: (context, isVisible, child) => isVisible
            ? const NotificationBootstrap(child: SizedBox.shrink())
            : const SizedBox.shrink(),
      ),
    ),
  );
  await tester.pump();
  verify(store.account).called(1);
  return visible;
}

final _localAccount = SyncAccountData(
  id: 1,
  deviceId: 'local-device',
  enabled: false,
  migrationState: 'localOnly',
  restorePending: false,
  hydrationCompletedUnits: 0,
  hydrationTotalUnits: 0,
  updatedAt: DateTime.utc(2026),
);

class _AccountStore extends Mock implements LocalSyncStore {}

class _OwnedScheduler extends FakeNotificationScheduler
    implements NotificationBackgroundRegistration {
  _OwnedScheduler({this.initialization, this.registration, this.refresh});

  final Future<void>? initialization;
  final Future<void>? registration;
  final Future<void>? refresh;
  int initializeCount = 0;
  int registrationCount = 0;

  @override
  Future<void> initialize() async {
    initializeCount++;
    await initialization;
  }

  @override
  Future<void> registerBackgroundRefresh() async {
    registrationCount++;
    await registration;
  }

  @override
  Future<void> refreshSchedules() async {
    await super.refreshSchedules();
    await refresh;
  }
}

class _CountingBackup extends FakeBackupRepository {
  @override
  Future<String?> exportAutomaticBackupIfDue() async {
    exportCount++;
    return null;
  }
}
