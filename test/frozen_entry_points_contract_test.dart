import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Frozen Background Entry-Point Contract (SB-008)', () {
    test('WorkManager and Foreground Service declare exact frozen vm:entry-points', () {
      final notifService = File(
        'lib/src/core/services/notification_service.dart',
      ).readAsStringSync().replaceAll('\r\n', '\n');
      final restoreService = File(
        'lib/src/core/sync/restore_foreground_service.dart',
      ).readAsStringSync().replaceAll('\r\n', '\n');

      expect(
        notifService,
        contains(
          "@pragma('vm:entry-point')\nvoid owntendWorkManagerCallback()",
        ),
      );
      // WP-010 (D2): the legacy homeKeeper alias is deleted; only the
      // canonical entry point may exist.
      expect(notifService, isNot(contains('homeKeeperWorkManagerCallback')));
      expect(
        notifService,
        contains(
          "@pragma('vm:entry-point')\nFuture<bool> runCloudSyncInBackground(",
        ),
      );
      expect(
        restoreService,
        contains(
          "@pragma('vm:entry-point')\nvoid owntendRestoreForegroundCallback()",
        ),
      );
    });

    test('Background WorkManager isolates guarantee database close in finally block', () {
      final notifService = File(
        'lib/src/core/services/notification_service.dart',
      ).readAsStringSync().replaceAll('\r\n', '\n');

      expect(
        notifService,
        contains('finally {\n      await db.close();\n    }'),
        reason: 'WorkManager callback must release SQLite database lock.',
      );
    });

    test('WorkManager initialization binds to frozen callback dispatcher', () {
      final notifService = File(
        'lib/src/core/services/notification_service.dart',
      ).readAsStringSync().replaceAll('\r\n', '\n');

      expect(
        notifService,
        contains('await workManager.initialize(owntendWorkManagerCallback);'),
      );
    });

    test('WorkManager unique task names remain frozen to prevent orphan background jobs (SB-031)', () {
      final scheduler = File('lib/src/core/sync/background_sync_scheduler.dart')
          .readAsStringSync()
          .replaceAll('\r\n', '\n');

      expect(
        scheduler,
        contains("const dailyRefreshTask = 'owntend.daily_refresh';"),
      );
      expect(
        scheduler,
        contains("const cloudSyncBackgroundTask = 'owntend.cloud_sync';"),
      );
      expect(
        scheduler,
        contains("const restoreRecoveryTask = 'owntend.restore_recovery';"),
      );
    });
  });
}
