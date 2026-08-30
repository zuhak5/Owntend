import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/widgets.dart';

import '../data/reactive_stream.dart';
import '../data/repositories.dart';
import '../database/app_database.dart';
import '../domain/contracts.dart';
import '../domain/models.dart';
import '../domain/render_fingerprints.dart';
import '../services/app_permission_coordinator.dart';
import '../services/backup_service.dart';
import '../services/health_score_calculator.dart';
import '../services/notification_service.dart';
import '../services/reminder_schedule_reconciler.dart';
import '../services/restore_journal.dart';
import '../services/weather_service.dart';
import '../sync/sync_providers.dart';
import '../../features/auth/presentation/auth_providers.dart';
import '../../features/navigation/app_navigation.dart';
import '../../features/startup/domain/initial_home_snapshot.dart';

final assetRepositoryProvider = Provider<AssetRepository>(
  (ref) => DriftAssetRepository(ref.watch(databaseProvider)),
);

final calendarRepositoryProvider = Provider<CalendarRepository>(
  (ref) => ref.watch(maintenanceRepositoryProvider) as CalendarRepository,
);

final streakServiceProvider = Provider<StreakService>(
  (ref) => DatabaseStreakService(ref.watch(databaseProvider)),
);

final statisticsRepositoryProvider = Provider<StatisticsRepository>(
  (ref) => DriftStatisticsRepository(
    ref.watch(databaseProvider),
    ref.watch(maintenanceRepositoryProvider),
    ref.watch(streakServiceProvider),
    healthScoreCalculator: const WeightedHealthScoreCalculator(),
  ),
);

final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => DriftSettingsRepository(ref.watch(databaseProvider)),
);

final permissionCoordinatorProvider = Provider<AppPermissionGateway>(
  (ref) => AppPermissionCoordinator(ref.watch(databaseProvider)),
);

final permissionEducationSeenProvider = StreamProvider<bool>((ref) {
  return ref.watch(settingsRepositoryProvider).watchPermissionEducationSeen();
});

class ThemeStartupSettings {
  const ThemeStartupSettings({
    required this.preference,
    required this.timeOfDayEnabled,
  });

  final ThemePreference preference;
  final bool timeOfDayEnabled;
}

final startupThemeSettingsProvider = Provider<ThemeStartupSettings>(
  (ref) => const ThemeStartupSettings(
    preference: ThemePreference.light,
    timeOfDayEnabled: false,
  ),
);

final themePreferenceProvider = StreamProvider<ThemePreference>((ref) {
  return ref.watch(settingsRepositoryProvider).watchThemePreference();
});

final timeOfDayThemeEnabledProvider = StreamProvider<bool>((ref) {
  return ref.watch(settingsRepositoryProvider).watchTimeOfDayThemeEnabled();
});

typedef LocalNow = DateTime Function();

final localNowProvider = Provider<LocalNow>(
  (ref) =>
      () => DateTime.now().toLocal(),
);

/// Shared local wall clock for date- and time-dependent presentation.
///
/// It emits on the next local minute boundary (which includes midnight), and
/// immediately on resume so a suspended app observes clock or time-zone
/// changes without waiting for unrelated provider activity.
final localClockProvider = StreamProvider<DateTime>((ref) {
  final now = ref.watch(localNowProvider);
  final controller = StreamController<DateTime>();
  Timer? timer;

  void emitAndSchedule() {
    if (controller.isClosed) return;
    timer?.cancel();
    final current = now().toLocal();
    controller.add(current);
    timer = Timer(nextLocalClockDelay(current), emitAndSchedule);
  }

  final observer = _LocalClockLifecycleObserver(emitAndSchedule);
  WidgetsBinding.instance.addObserver(observer);
  emitAndSchedule();
  ref.onDispose(() {
    timer?.cancel();
    WidgetsBinding.instance.removeObserver(observer);
    unawaited(controller.close());
  });
  return controller.stream;
});

Duration nextLocalClockDelay(DateTime now) {
  final local = now.toLocal();
  final nextMinute = DateTime(
    local.year,
    local.month,
    local.day,
    local.hour,
    local.minute + 1,
  );
  final delay = nextMinute.difference(local);
  if (delay <= Duration.zero || delay > const Duration(minutes: 2)) {
    return const Duration(minutes: 1);
  }
  return delay + const Duration(milliseconds: 25);
}

class _LocalClockLifecycleObserver extends WidgetsBindingObserver {
  _LocalClockLifecycleObserver(this.onResume);

  final VoidCallback onResume;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) onResume();
  }
}

final appLocalePreferenceProvider = StreamProvider<AppLocalePreference>((ref) {
  return ref.watch(settingsRepositoryProvider).watchAppLocalePreference();
});

final notificationInboxRepositoryProvider =
    Provider<NotificationInboxRepository>(
      (ref) => DriftNotificationInboxRepository(ref.watch(databaseProvider)),
    );

final weatherRepositoryProvider = Provider<WeatherRepository>(
  (ref) => OpenMeteoWeatherRepository(
    db: ref.watch(databaseProvider),
    settingsRepository: ref.watch(settingsRepositoryProvider),
  ),
);

final restoreJournalStoreProvider = Provider<RestoreJournalStore>(
  (ref) => RestoreJournalStore(),
);

final backupRepositoryProvider = Provider<BackupRepository>(
  (ref) => OwntendBackupService(
    ref.watch(databaseProvider),
    journalStore: ref.watch(restoreJournalStoreProvider),
    // WP-005 (F-007): the service reports verified restore commits; the
    // provider layer owns the single epoch publication boundary.
    onRestoreCommit: () =>
        ref.read(databaseRestoreEpochProvider.notifier).bump(),
  ),
);

final backupStateProvider = FutureProvider<BackupState>(
  (ref) => ref.watch(backupRepositoryProvider).backupState(),
);

final searchRepositoryProvider = Provider<SearchRepository>(
  (ref) => DriftSearchRepository(ref.watch(databaseProvider)),
);

final notificationSchedulerProvider = Provider<NotificationScheduler>(
  (ref) => OwntendNotificationScheduler(
    ref.watch(maintenanceRepositoryProvider),
    scheduleStore: DriftReminderScheduleStore(ref.watch(databaseProvider)),
    notificationInboxRepository: ref.watch(notificationInboxRepositoryProvider),
    settingsRepository: ref.watch(settingsRepositoryProvider),
    weatherRepository: ref.watch(weatherRepositoryProvider),
    permissionGateway: ref.watch(permissionCoordinatorProvider),
    supabaseClient: ref.watch(supabaseClientProvider),
    localSyncStore: ref.watch(localSyncStoreProvider),
    onNotificationPayload: openNotificationPayload,
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
              );
        },
      );
    });

final notificationAutoStartProvider = Provider<bool>((ref) => true);

final backupAutoStartProvider = Provider<bool>((ref) => true);

final profileProvider = StreamProvider<AppProfile>(
  (ref) => ref.watch(settingsRepositoryProvider).watchProfile(),
);

final homeLocationProvider = StreamProvider<HomeLocation?>(
  (ref) => ref.watch(settingsRepositoryProvider).watchHomeLocation(),
);

final weatherProvider = StreamProvider<WeatherSnapshot?>(
  (ref) => ref.watch(weatherRepositoryProvider).watchWeather(),
);

final notificationsProvider = StreamProvider<List<InboxNotification>>(
  (ref) => ref.watch(notificationInboxRepositoryProvider).watchNotifications(),
);

final unreadNotificationsProvider = StreamProvider<int>(
  (ref) => ref.watch(notificationInboxRepositoryProvider).watchUnreadCount(),
);

final initialHomeSnapshotProvider =
    Provider<ValueNotifier<InitialHomeSnapshot?>>((ref) {
      final notifier = ValueNotifier<InitialHomeSnapshot?>(null);
      ref.onDispose(notifier.dispose);
      return notifier;
    });

enum StartupBootstrapKind {
  checkingStoredSession,
  unauthenticated,
  authenticatedHydrating,
  authenticatedReady,
  startupFailed,
}

enum StartupFailureKind { failed, timedOut }

final notificationPreferencesProvider = StreamProvider<NotificationPreferences>(
  (ref) => ref.watch(settingsRepositoryProvider).watchNotificationPreferences(),
);

final notificationPermissionStateProvider =
    FutureProvider.autoDispose<NotificationPermissionState>(
      (ref) => ref.watch(notificationSchedulerProvider).permissionState(),
    );

final assetsProvider = StreamProvider<List<Asset>>(
  (ref) => ref
      .watch(assetRepositoryProvider)
      .watchAssets()
      .distinctByFingerprint(assetListFingerprint),
);

final roomAssetsProvider = StreamProvider.family<List<Asset>, String>(
  (ref, roomId) => ref
      .watch(assetRepositoryProvider)
      .watchAssets(roomId: roomId)
      .distinctByFingerprint(assetListFingerprint),
);

final areasProvider = StreamProvider<List<Area>>(
  (ref) => ref
      .watch(assetRepositoryProvider)
      .watchAreas()
      .distinctByFingerprint(areaListFingerprint),
);

final roomsProvider = StreamProvider<List<Room>>(
  (ref) => ref
      .watch(assetRepositoryProvider)
      .watchRooms()
      .distinctByFingerprint(roomListFingerprint),
);

final tasksProvider = StreamProvider<List<TaskItem>>(
  (ref) => ref
      .watch(maintenanceRepositoryProvider)
      .watchTasks()
      .distinctByFingerprint(taskListFingerprint),
);

final taskDetailProvider = StreamProvider.autoDispose.family<TaskItem?, String>(
  (ref, planId) => ref
      .watch(maintenanceRepositoryProvider)
      .watchTask(planId)
      .distinctByFingerprint(
        (task) => task == null ? 0 : taskFingerprint(task),
      ),
);

final taskRecordsProvider = StreamProvider.autoDispose
    .family<List<MaintenanceRecord>, String>((ref, planId) {
      return ref
          .watch(maintenanceRepositoryProvider)
          .watchRecordsForPlan(planId)
          .distinctByFingerprint(maintenanceRecordListFingerprint);
    });

final assetDetailProvider = StreamProvider.autoDispose.family<Asset?, String>((
  ref,
  assetId,
) {
  return ref
      .watch(assetRepositoryProvider)
      .watchAsset(assetId)
      .distinctByFingerprint(
        (asset) => asset == null ? 0 : assetFingerprint(asset),
      );
});

final assetTasksProvider = StreamProvider.autoDispose
    .family<List<TaskItem>, String>((ref, assetId) {
      return ref
          .watch(maintenanceRepositoryProvider)
          .watchTasksForAsset(assetId)
          .distinctByFingerprint(taskListFingerprint);
    });

final assetSavedTasksProvider = StreamProvider.autoDispose
    .family<List<TaskItem>, String>((ref, assetId) {
      return ref
          .watch(maintenanceRepositoryProvider)
          .watchSavedTasksForAsset(assetId)
          .distinctByFingerprint(taskListFingerprint);
    });

final assetTagsProvider = StreamProvider.autoDispose.family<List<Tag>, String>((
  ref,
  assetId,
) {
  return ref
      .watch(assetRepositoryProvider)
      .watchTagsForAsset(assetId)
      .distinctByFingerprint(tagListFingerprint);
});

final assetPhotosProvider = StreamProvider.autoDispose
    .family<List<AssetPhoto>, String>((ref, assetId) {
      return ref
          .watch(assetRepositoryProvider)
          .watchPhotosForAsset(assetId)
          .distinctByFingerprint(assetPhotoListFingerprint);
    });

final archivedAreasProvider = StreamProvider.autoDispose<List<Area>>((ref) {
  return ref
      .watch(assetRepositoryProvider)
      .watchArchivedAreas()
      .distinctByFingerprint(areaListFingerprint);
});

final archivedRoomsProvider = StreamProvider.autoDispose<List<Room>>((ref) {
  return ref
      .watch(assetRepositoryProvider)
      .watchArchivedRooms()
      .distinctByFingerprint(roomListFingerprint);
});

final archivedAssetsProvider = StreamProvider.autoDispose<List<Asset>>((ref) {
  return ref
      .watch(assetRepositoryProvider)
      .watchArchivedAssets()
      .distinctByFingerprint(assetListFingerprint);
});

final archivedTasksProvider = StreamProvider.autoDispose<List<TaskItem>>((ref) {
  return ref
      .watch(maintenanceRepositoryProvider)
      .watchArchivedTasks()
      .distinctByFingerprint(taskListFingerprint);
});

final assetRecordsProvider = StreamProvider.autoDispose
    .family<List<MaintenanceRecord>, String>((ref, assetId) {
      return ref
          .watch(maintenanceRepositoryProvider)
          .watchRecordsForAsset(assetId)
          .distinctByFingerprint(maintenanceRecordListFingerprint);
    });

final dashboardProvider = StreamProvider.autoDispose<DashboardSummary>((ref) {
  return ref
      .watch(statisticsRepositoryProvider)
      .watchDashboardSummary()
      .distinctByFingerprint(dashboardSummaryFingerprint);
});

final statisticsProvider = StreamProvider.autoDispose<StatisticsSummary>(
  (ref) => ref
      .watch(statisticsRepositoryProvider)
      .watchStatisticsSummary()
      .distinctByFingerprint(statisticsSummaryFingerprint),
);

final streakRefreshProvider = FutureProvider.autoDispose<StreakState>((
  ref,
) async {
  return ref.watch(streakServiceProvider).refresh(DateTime.now());
});
