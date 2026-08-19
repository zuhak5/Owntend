part of '../../../main.dart';

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

final localThemeClockProvider = StreamProvider<DateTime>((ref) async* {
  yield DateTime.now().toLocal();
  yield* Stream.periodic(
    const Duration(minutes: 1),
    (_) => DateTime.now().toLocal(),
  );
});

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
  (ref) => ZipBackupService(
    ref.watch(databaseProvider),
    journalStore: ref.watch(restoreJournalStoreProvider),
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

Page<void> _appRoutePage(
  BuildContext context,
  GoRouterState state,
  Widget child, {
  bool bodyHasBackdrop = false,
}) {
  final routeChild = bodyHasBackdrop ? child : _AppRouteBackdrop(child: child);
  if (_prefersReducedMotion(context)) {
    return NoTransitionPage<void>(
      key: state.pageKey,
      name: normalizeSentryRoute(state.fullPath ?? state.uri.path),
      child: routeChild,
    );
  }
  return CustomTransitionPage<void>(
    key: state.pageKey,
    name: normalizeSentryRoute(state.fullPath ?? state.uri.path),
    child: routeChild,
    transitionDuration: _routeTransitionDuration,
    reverseTransitionDuration: _routeTransitionReverseDuration,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.018),
            end: Offset.zero,
          ).animate(curved),
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.992, end: 1).animate(curved),
            child: child,
          ),
        ),
      );
    },
  );
}
