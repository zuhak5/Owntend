import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'WP-007 schedule ownership: queued-work state lives only in the schedule '
    'controller',
    () async {
      final controller = await _read('lib/src/core/sync/sync_coordinator.dart');
      final scheduleController = await _read(
        'lib/src/core/sync/coordinator/schedule_controller.dart',
      );
      final runtime = await _read(
        'lib/src/core/sync/coordinator/runtime_coordinator.dart',
      );
      final run = await _read(
        'lib/src/core/sync/coordinator/run_coordinator.dart',
      );

      // The controller is the single owner of the automatic-sync timer and
      // the queued-work request flags.
      expect(scheduleController, contains('_automaticSyncTimer'));
      for (final field in [
        '_pendingTargetTables',
        '_pushOnlyRequested',
        '_broadPullRequested',
        '_syncRequestedWhileActive',
        '_fullSyncRequestedWhileActive',
      ]) {
        expect(
          controller.contains('final Set<String> $field') ||
              controller.contains('bool $field'),
          isFalse,
          reason: '$field must be owned by _SyncScheduleController',
        );
        expect(scheduleController, contains(field));
      }

      // The runtime part schedules through the facade wrapper; it never
      // mutates queue flags directly.
      expect(runtime, contains("_schedule.cancelQueuedWork()"));
      expect(runtime.contains('_pendingTargetTables'), isFalse);
      expect(run.contains('_pendingTargetTables'), isFalse);

      // The facade answers environment queries instead of owning decisions.
      expect(controller, contains('_SyncScheduleEnv'));
      expect(controller, contains('late final _SyncScheduleController'));
    },
  );

  test('WP-007 repair ownership: drain and integrity workers live in their own '
      'coordinator part', () async {
    final repair = await _read(
      'lib/src/core/sync/coordinator/repair_coordinator.dart',
    );
    final run = await _read(
      'lib/src/core/sync/coordinator/run_coordinator.dart',
    );

    expect(repair, contains('_drainSkippedFeedEntries'));
    expect(repair, contains('_materializeFeedPhotoWithDeferral'));
    expect(repair, contains('_reconcileMissedRemoteDeletes'));
    expect(run.contains('Future<void> _drainSkippedFeedEntries'), isFalse);
    expect(
      run.contains('Future<SyncRecord> _materializeFeedPhotoWithDeferral'),
      isFalse,
    );
  });
}

Future<String> _read(String path) async {
  final file = File(path);
  return file.readAsString();
}
