import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:owntend/src/core/domain/contracts.dart';
import 'package:owntend/src/core/services/automatic_backup_coordinator.dart';

void main() {
  test(
    'post-ready triggers a due check while pre-ready resume does not',
    () async {
      final repository = _FakeBackupRepository();
      final coordinator = AutomaticBackupCoordinator(
        backupRepository: repository,
      );

      await coordinator.onAppResumed();
      expect(repository.automaticChecks, 0);

      await coordinator.onPostReady();
      expect(repository.automaticChecks, 1);
    },
  );

  test('successful due checks throttle repeated foreground resumes', () async {
    final repository = _FakeBackupRepository();
    var now = DateTime.utc(2026, 8, 18, 1);
    final coordinator = AutomaticBackupCoordinator(
      backupRepository: repository,
      foregroundThrottle: const Duration(minutes: 10),
      now: () => now,
    );

    await coordinator.onPostReady();
    expect(repository.automaticChecks, 1);

    now = now.add(const Duration(minutes: 5));
    await coordinator.onAppResumed();
    expect(repository.automaticChecks, 1);

    now = now.add(const Duration(minutes: 6));
    await coordinator.onAppResumed();
    expect(repository.automaticChecks, 2);
  });

  test('failed due checks remain immediately retryable', () async {
    final repository = _FakeBackupRepository()
      ..failNext = StateError('simulated backup failure');
    final coordinator = AutomaticBackupCoordinator(
      backupRepository: repository,
      foregroundThrottle: const Duration(hours: 1),
    );

    await coordinator.onPostReady();
    expect(repository.automaticChecks, 1);

    await coordinator.onAppResumed();
    expect(repository.automaticChecks, 2);
  });

  test('concurrent lifecycle triggers share one in-flight due check', () async {
    final repository = _FakeBackupRepository();
    final pending = Completer<String?>();
    repository.pendingAutomaticCheck = pending;
    final coordinator = AutomaticBackupCoordinator(
      backupRepository: repository,
    );

    final postReady = coordinator.onPostReady();
    final resumed = coordinator.onAppResumed();

    expect(repository.automaticChecks, 1);
    pending.complete(null);
    await Future.wait([postReady, resumed]);
  });

  test(
    'app wiring defers startup backup until after ready frame and resumes',
    () {
      final source = File('lib/main.dart').readAsStringSync().replaceAll(
        '\r\n',
        '\n',
      );

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
    },
  );
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
