import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:owntend/l10n/app_localizations.dart';

import '../data/repositories.dart';
import '../database/app_database.dart';
import '../domain/models.dart';
import '../observability/sentry_bootstrap.dart';
import '../observability/sentry_logger_bridge.dart';
import '../observability/sentry_tracing.dart';
import '../services/notification_service.dart';
import 'background_sync_scheduler.dart';
import 'local_sync_store.dart';
import 'sync_contracts.dart';

const _restoreServiceId = 41520;

void initializeRestoreForegroundService({required String localeCode}) {
  final l10n = _restoreLocalizations(localeCode);
  FlutterForegroundTask.initCommunicationPort();
  FlutterForegroundTask.init(
    androidNotificationOptions: AndroidNotificationOptions(
      channelId: 'owntend_restore',
      channelName: l10n.restoreChannelName,
      channelDescription: l10n.restoreChannelDescription,
      onlyAlertOnce: true,
      showBadge: false,
    ),
    iosNotificationOptions: const IOSNotificationOptions(
      showNotification: false,
      playSound: false,
    ),
    foregroundTaskOptions: ForegroundTaskOptions(
      eventAction: ForegroundTaskEventAction.repeat(3000),
      autoRunOnBoot: false,
      autoRunOnMyPackageReplaced: false,
      allowWakeLock: true,
      allowWifiLock: true,
    ),
  );
}

Future<bool> startRestoreForegroundService({required String localeCode}) async {
  if (!Platform.isAndroid) return true;
  final progress = await _readProgress();
  if (progress == null || !progress.isActive) return true;
  final l10n = _restoreLocalizations(localeCode);
  final text = _notificationText(l10n, progress);
  final ServiceRequestResult result;
  if (await FlutterForegroundTask.isRunningService) {
    result = await FlutterForegroundTask.updateService(
      notificationTitle: l10n.restoringOwntend,
      notificationText: text,
    );
  } else {
    result = await FlutterForegroundTask.startService(
      serviceId: _restoreServiceId,
      serviceTypes: const [ForegroundServiceTypes.dataSync],
      notificationTitle: l10n.restoringOwntend,
      notificationText: text,
      notificationInitialRoute: '/',
      callback: owntendRestoreForegroundCallback,
    );
  }
  final started = result is ServiceRequestSuccess;
  if (!started) await enqueueRestoreRecovery();
  return started;
}

Future<void> stopRestoreForegroundService() async {
  if (Platform.isAndroid && await FlutterForegroundTask.isRunningService) {
    await FlutterForegroundTask.stopService();
  }
}

@pragma('vm:entry-point')
void owntendRestoreForegroundCallback() {
  FlutterForegroundTask.setTaskHandler(_RestoreTaskHandler());
}

class _RestoreTaskHandler extends TaskHandler {
  bool _running = false;
  Future<bool>? _sentryInitialization;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) => _run();

  @override
  void onRepeatEvent(DateTime timestamp) {
    unawaited(_run());
  }

  Future<bool> _ensureSentry() {
    return _sentryInitialization ??= initializeBackgroundSentry();
  }

  Future<void> _run() async {
    if (_running) return;
    _running = true;
    InitialHydrationStage? activeStage;
    try {
      await _ensureSentry();
      await traceOwntendOperation<void>('restore.foreground_cycle', () async {
        final initialProgress =
            await traceOwntendOperation<InitialHydrationProgress?>(
              'restore.read_progress',
              _readProgress,
              attributes: const {'execution': 'foreground_service'},
            );
        if (initialProgress == null || !initialProgress.isActive) {
          await FlutterForegroundTask.stopService();
          return;
        }
        activeStage = initialProgress.stage;
        final l10n = await _backgroundRestoreLocalizations();
        await traceOwntendOperation<void>(
          'restore.update_notification',
          () async {
            await FlutterForegroundTask.updateService(
              notificationTitle: l10n.restoringOwntend,
              notificationText: _notificationText(l10n, initialProgress),
            );
          },
          attributes: {
            'execution': 'foreground_service',
            'restore_stage': initialProgress.stage.name,
            'percentage': initialProgress.percentage,
          },
        );
        if (initialProgress.state != RestoreRunState.completed) {
          await traceOwntendOperation<void>(
            'restore.cloud_sync',
            () async {
              await runCloudSyncInBackground(leaseScope: 'restore-service');
            },
            attributes: {
              'execution': 'foreground_service',
              'restore_stage': initialProgress.stage.name,
              'lease_scope': 'restore-service',
              'percentage': initialProgress.percentage,
            },
          );
        }
        final latestProgress =
            await traceOwntendOperation<InitialHydrationProgress?>(
              'restore.read_progress',
              _readProgress,
              attributes: const {'execution': 'foreground_service'},
            );
        if (latestProgress == null || !latestProgress.isActive) {
          await traceOwntendOperation<void>('restore.finalize', () async {
            await FlutterForegroundTask.stopService();
          }, attributes: const {'execution': 'foreground_service'});
        } else {
          activeStage = latestProgress.stage;
          await traceOwntendOperation<void>(
            'restore.update_notification',
            () async {
              await FlutterForegroundTask.updateService(
                notificationTitle: l10n.restoringOwntend,
                notificationText: _notificationText(l10n, latestProgress),
              );
            },
            attributes: {
              'execution': 'foreground_service',
              'restore_stage': latestProgress.stage.name,
              'percentage': latestProgress.percentage,
            },
          );
        }
      }, attributes: const {'execution': 'foreground_service'});
    } on Object catch (error, stackTrace) {
      reportOperationFailure(
        operation: 'restore_foreground_cycle_failed',
        error: error,
        stackTrace: stackTrace,
        fields: {
          'execution': 'foreground_service',
          if (activeStage != null) 'restore_stage': activeStage!.name,
        },
      );
      try {
        await enqueueRestoreRecovery();
      } on Object catch (recoveryError, recoveryStackTrace) {
        reportOperationFailure(
          operation: 'restore_recovery_enqueue_failed',
          error: recoveryError,
          stackTrace: recoveryStackTrace,
          fields: const {'execution': 'foreground_service'},
        );
      }
      // Keep the foreground worker alive for its next scheduled retry rather
      // than rethrowing into a plugin-managed crash loop.
    } finally {
      _running = false;
    }
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}
}

Future<InitialHydrationProgress?> _readProgress() async {
  WidgetsFlutterBinding.ensureInitialized();
  final database = AppDatabase();
  try {
    return await LocalSyncStore(database).hydrationProgress();
  } finally {
    await database.close();
  }
}

Future<AppLocalizations> _backgroundRestoreLocalizations() async {
  WidgetsFlutterBinding.ensureInitialized();
  final database = AppDatabase();
  try {
    final preference = await DriftSettingsRepository(database)
        .appLocalePreference();
    final language = preference.isExplicit
        ? preference.language
        : PlatformDispatcher.instance.locale.languageCode.toLowerCase() ==
              AppLanguage.ar.name
        ? AppLanguage.ar
        : AppLanguage.en;
    return _restoreLocalizations(language.name);
  } finally {
    await database.close();
  }
}

AppLocalizations _restoreLocalizations(String localeCode) =>
    lookupAppLocalizations(
      Locale(
        localeCode.toLowerCase() == AppLanguage.ar.name
            ? AppLanguage.ar.name
            : AppLanguage.en.name,
      ),
    );

String _notificationText(
  AppLocalizations l10n,
  InitialHydrationProgress progress,
) {
  return l10n.restoreNotificationProgress(
    progress.percentage,
    _stageLabel(l10n, progress.stage),
  );
}

String _stageLabel(AppLocalizations l10n, InitialHydrationStage stage) =>
    switch (stage) {
      InitialHydrationStage.connecting => l10n.hydrationConnectingSecurely,
      InitialHydrationStage.restoringCloudData =>
        l10n.hydrationRestoringCloudData,
      InitialHydrationStage.restoringPhotos => l10n.hydrationRestoringPhotos,
      InitialHydrationStage.syncingLocalChanges =>
        l10n.hydrationSyncingLocalChanges,
      InitialHydrationStage.checkingLatestUpdates =>
        l10n.hydrationCheckingLatestUpdates,
      InitialHydrationStage.finalizing => l10n.finalizingOwntend,
    };
