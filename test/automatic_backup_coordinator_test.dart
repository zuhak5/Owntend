import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:owntend/src/core/domain/contracts.dart';
import 'package:owntend/src/core/services/automatic_backup_coordinator.dart';

void main() {
  test('post-ready runs; pre-ready resume does not', () async {
    final repo = _FakeBackupRepository();
    final coordinator = AutomaticBackupCoordinator(
      backupRepository: repo,
    );

    await coordinator.onAppResumed();
    expect(repo.automaticChecks, 0);

    await coordinator.onPostReady();
    expect(repo.automaticChecks, 1);
  });

  test('successful checks throttle foreground resumes', () async {
    final repo = _FakeBackupRepository();
    var now = DateTime.utc(2026, 8, 18, 1);
    final coordinator = AutomaticBackupCoordinator(
      backupRepository: repo,
      foregroundThrottle: const Duration(minutes: 10),
      now: () => now,
    );

    await coordinator.onPostReady();
    expect(repo.automaticChecks, 1);

    now = now.add(const Duration(minutes: 5));
    await coordinator.onAppResumed();
    expect(repo.automaticChecks, 1);

    now = now.add(const Duration(minutes: 6));
    await coordinator.onAppResumed();
    expect(repo.automaticChecks, 2);
  });

  test('failed checks remain retryable', () async {
    final repo = _FakeBackupRepository();
    repo.failNext = StateError('simulated backup failure');
    final coordinator = AutomaticBackupCoordinator(
      backupRepository: repo,
      foregroundThrottle: const Duration(hours: 1),
    );

    await coordinator.onPostReady();
    expect(repo.automaticChecks, 1);

    await coordinator.onAppResumed();
    expect(repo.automaticChecks, 2);
  });

  test('concurrent triggers share one due check', () async {
    final repo = _FakeBackupRepository();
    final pending = Completer<String?>();
    repo.pendingAutomaticCheck = pending;
    final coordinator = AutomaticBackupCoordinator(
      backupRepository: repo,
    );

    final postReady = coordinator.onPostReady();
    final resumed = coordinator.onAppResumed();

    expect(repo.automaticChecks, 1);
    pending.complete(null);
    await Future.wait([postReady, resumed]);
  });

  test('startup wiring defers backup until ready and resume', () {
    final rawSource = File('lib/main.dart').readAsStringSync();
    final source = rawSource.replaceAll('\r\n', '\n');

    expect(
      source,
      contains(
        'startup.stateListenable.addListener('
        '_handleAutomaticBackupStartupState);',
      ),
    );
    expect(
      source,
      contains('WidgetsBinding.instance.addPostFrameCallback((_) {'),
    );
    expect(source, contains('_automaticBackupCoordinator.onPostReady()'));
    expect(source, contains('state == AppLifecycleState.resumed'));
    expect(source, contains('_automaticBackupCoordinator.onAppResumed()'));
  });
}

class _FakeBackupRepository implements BackupRepository {
  int automaticChecks = 0;
  Object? failNext;
  Completer<String?>? pendingAutomaticCheck;

  @override
  Future<String?> exportAutomaticBackupIfDue() {
    automaticChecks += 1;
    final failure = failNext;
    if (failure != null) {
      failNext = null;
      return Future<String?>.error(failure);
    }
    final pending = pendingAutomaticCheck;
    if (pending != null) {
      return pending.future;
    }
    return Future<String?>.value(null);
  }

  @override
  Future<BackupState> backupState() => Future.value(const BackupState());

  @override
  Future<String> exportBackup({BackupTrigger trigger = BackupTrigger.manual}) {
    throw UnimplementedError();
  }

  @override
  Future<BackupPreview> inspectBackup(String zipPath) {
    throw UnimplementedError();
  }

  @override
  Future<void> restoreBackup(String zipPath) {
    throw UnimplementedError();
  }

  @override
  Future<void> setAutomaticBackupsEnabled(bool enabled) {
    throw UnimplementedError();
  }
}
