import 'dart:io';

import 'package:workmanager/workmanager.dart' as wm;

const dailyRefreshTask = 'owntend.daily_refresh';
const cloudSyncBackgroundTask = 'owntend.cloud_sync';
const restoreRecoveryTask = 'owntend.restore_recovery';

Future<void> configureCloudSyncBackgroundTask(bool _) async {
  if (!Platform.isAndroid) return;

  // Cloud synchronization is foreground-only. Cancel periodic work
  // that may have been registered by an older application version.
  await wm.Workmanager().cancelByUniqueName(cloudSyncBackgroundTask);
}

Future<void> cancelAccountScopedBackgroundWork() async {
  if (!Platform.isAndroid) return;
  final workManager = wm.Workmanager();
  await workManager.cancelByUniqueName(cloudSyncBackgroundTask);
  await workManager.cancelByUniqueName(restoreRecoveryTask);
  await workManager.cancelByUniqueName(dailyRefreshTask);
}

Future<void> enqueueRestoreRecovery() async {
  if (!Platform.isAndroid) return;
  await wm.Workmanager().registerOneOffTask(
    restoreRecoveryTask,
    cloudSyncBackgroundTask,
    constraints: wm.Constraints(networkType: wm.NetworkType.connected),
    existingWorkPolicy: wm.ExistingWorkPolicy.replace,
    backoffPolicy: wm.BackoffPolicy.exponential,
    backoffPolicyDelay: const Duration(seconds: 15),
  );
}
