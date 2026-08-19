// ignore_for_file: prefer_initializing_formals

import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:workmanager/workmanager.dart' as wm;
import 'package:owntend/l10n/app_localizations.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/repositories.dart';
import '../config/app_config.dart';
import '../database/app_database.dart';
import '../domain/contracts.dart';
import '../domain/models.dart';
import 'app_permission_coordinator.dart';
import '../domain/task_selectors.dart';
import '../observability/sentry_bootstrap.dart';
import '../observability/sentry_logger_bridge.dart';
import '../observability/sentry_tracing.dart';
import '../supabase/supabase_bootstrap.dart';
import '../sync/background_sync_scheduler.dart';
import '../sync/local_sync_store.dart';
import '../sync/supabase_sync_gateway.dart';
import '../sync/sync_connectivity.dart';
import '../sync/sync_coordinator.dart';
import '../utils/redacting_logger.dart';
import '../utils/user_facing_errors.dart';
import '../../features/auth/data/native_google_sign_in.dart';
import '../../features/auth/data/supabase_auth_repository.dart';
import 'weather_service.dart';
import 'reminder_schedule_reconciler.dart';

abstract interface class NotificationBackgroundRegistration {
  Future<void> registerBackgroundRefresh();
}

bool notificationBackgroundAccountMatches({
  required String? sessionUserId,
  required String? boundUserId,
  required bool accountEnabled,
  required bool uploadProhibited,
  required String? migrationState,
}) {
  final sessionId = sessionUserId?.trim();
  final localId = boundUserId?.trim();
  return sessionId != null &&
      sessionId.isNotEmpty &&
      localId == sessionId &&
      accountEnabled &&
      !uploadProhibited &&
      migrationState != 'quarantined';
}

@pragma('vm:entry-point')
void owntendWorkManagerCallback() {
  wm.Workmanager().executeTask((taskName, inputData) async {
    await initializeBackgroundSentry();
    final db = AppDatabase();
    try {
      if (taskName == cloudSyncBackgroundTask) {
        return await runCloudSyncInBackground(leaseScope: 'work-manager');
      }
      if (taskName != dailyRefreshTask) return true;

      return await traceOwntendOperation<bool>(
        'notifications.refresh',
        () async {
          SupabaseClient? client;
          try {
            final config = AppConfig.fromEnvironment();
            client = await SupabaseBootstrap.initialize(config);
          } on Object {
            // Assume uninitialized or unauthenticated
          }

          final session = client?.auth.currentSession;
          final store = LocalSyncStore(db);
          final account = await store.existingAccount();

          if (!notificationBackgroundAccountMatches(
            sessionUserId: session?.user.id,
            boundUserId: account?.boundUserId,
            accountEnabled: account?.enabled ?? false,
            uploadProhibited: account?.uploadProhibited ?? false,
            migrationState: account?.migrationState,
          )) {
            AppLogger.info(
              'background_worker_rejected_unauthenticated_or_mismatched',
            );
            await cancelAccountScopedBackgroundWork();
            return true;
          }

          final streakService = DatabaseStreakService(db);
          final maintenanceRepository = DriftMaintenanceRepository(db);
          final settingsRepository = DriftSettingsRepository(db);
          final inboxRepository = DriftNotificationInboxRepository(db);
          final weatherRepository = OpenMeteoWeatherRepository(
            db: db,
            settingsRepository: settingsRepository,
          );
          await streakService.refresh(DateTime.now());
          final scheduler = OwntendNotificationScheduler(
            maintenanceRepository,
            scheduleStore: DriftReminderScheduleStore(db),
            notificationInboxRepository: inboxRepository,
            settingsRepository: settingsRepository,
            weatherRepository: weatherRepository,
            supabaseClient: client,
            localSyncStore: store,
          );
          await scheduler.initialize();
          final consumer = NotificationReconciliationConsumer(
            database: db,
            scheduler: scheduler,
            accountGuard: (expectedUserId) async {
              final currentSession = client?.auth.currentSession;
              final currentAccount = await store.existingAccount();
              return expectedUserId == currentSession?.user.id &&
                  notificationBackgroundAccountMatches(
                    sessionUserId: currentSession?.user.id,
                    boundUserId: currentAccount?.boundUserId,
                    accountEnabled: currentAccount?.enabled ?? false,
                    uploadProhibited: currentAccount?.uploadProhibited ?? false,
                    migrationState: currentAccount?.migrationState,
                  );
            },
          );
          final reconciliation = await consumer.drainForAccount(
            session!.user.id,
          );
          if (reconciliation ==
              NotificationReconciliationDrainResult.accountMismatch) {
            await cancelAccountScopedBackgroundWork();
            return true;
          }
          if (reconciliation == NotificationReconciliationDrainResult.noWork) {
            await scheduler.refreshSchedules();
          }
          return true;
        },
        attributes: const {'execution': 'work_manager'},
      );
    } catch (error, stackTrace) {
      reportOperationFailure(
        operation: 'workmanager_task_failed',
        error: error,
        stackTrace: stackTrace,
        fields: const {'execution': 'work_manager'},
      );
      return false;
    } finally {
      await db.close();
    }
  });
}

@pragma('vm:entry-point')
void homeKeeperWorkManagerCallback() => owntendWorkManagerCallback();

@pragma('vm:entry-point')
Future<bool> runCloudSyncInBackground({
  String leaseScope = 'background',
}) async {
  await initializeBackgroundSentry();
  final db = AppDatabase();
  final store = LocalSyncStore(db);
  SyncCoordinator? coordinator;
  try {
    AppConfig config;
    try {
      config = AppConfig.fromEnvironment();
    } on Object {
      await cancelAccountScopedBackgroundWork();
      return true;
    }
    final client = await SupabaseBootstrap.initialize(config);
    final session = client.auth.currentSession;
    if (session == null) {
      await cancelAccountScopedBackgroundWork();
      return true;
    }
    final account = await store.existingAccount();
    if (account == null ||
        !account.enabled ||
        account.boundUserId != session.user.id ||
        account.uploadProhibited ||
        account.migrationState == 'quarantined') {
      await cancelAccountScopedBackgroundWork();
      return true;
    }
    final auth = SupabaseAuthRepository(
      client,
      NativeGoogleSignInGateway(serverClientId: config.googleWebClientId),
      onAccountDeletionPrepared: (_) async {},
      onAccountDeletionCancelled: (_) async {},
      onAccountDeleted: (_) async {},
    );
    final gateway = SupabaseSyncGateway(client);
    coordinator = SyncCoordinator(
      auth,
      store,
      gateway,
      connectivity: const AlwaysOnlineSyncConnectivity(),
      leaseScope: leaseScope,
      listenToAuthChanges: false,
    );
    await traceOwntendOperation<void>(
      'sync.automatic',
      () async => coordinator!.syncIncremental(),
      attributes: {'sync_mode': 'background', 'execution': leaseScope},
    );
    await store.recordBackgroundResult('success');
    return true;
  } on Object catch (error, stackTrace) {
    reportOperationFailure(
      operation: 'background_sync_failed',
      error: error,
      stackTrace: stackTrace,
      fields: {'sync_mode': 'background', 'execution': leaseScope},
    );
    await store.recordBackgroundResult(syncDiagnosticMessage(error));
    return false;
  } finally {
    await coordinator?.dispose();
    await db.close();
  }
}

class OwntendNotificationScheduler
    implements NotificationScheduler, NotificationBackgroundRegistration {
  // Public parameter names are clearer for callers while the stored fields stay private.
  OwntendNotificationScheduler(
    this.maintenanceRepository, {
    ReminderScheduleStore? scheduleStore,
    NotificationInboxRepository? notificationInboxRepository,
    SettingsRepository? settingsRepository,
    WeatherRepository? weatherRepository,
    AppPermissionGateway? permissionGateway,
    FlutterLocalNotificationsPlugin? plugin,
    SupabaseClient? supabaseClient,
    LocalSyncStore? localSyncStore,
    void Function(String payload)? onNotificationPayload,
  }) : _notificationInboxRepository = notificationInboxRepository,
       _scheduleStore = scheduleStore ?? MemoryReminderScheduleStore(),
       _settingsRepository = settingsRepository,
       _weatherRepository = weatherRepository,
       _permissionGateway = permissionGateway,
       _plugin = plugin ?? FlutterLocalNotificationsPlugin(),
       _supabaseClient = supabaseClient,
       _localSyncStore = localSyncStore,
       _onNotificationPayload = onNotificationPayload;

  final MaintenanceRepository maintenanceRepository;
  final ReminderScheduleStore _scheduleStore;
  final NotificationInboxRepository? _notificationInboxRepository;
  final SettingsRepository? _settingsRepository;
  final WeatherRepository? _weatherRepository;
  final AppPermissionGateway? _permissionGateway;
  final FlutterLocalNotificationsPlugin _plugin;
  final SupabaseClient? _supabaseClient;
  final LocalSyncStore? _localSyncStore;
  final void Function(String payload)? _onNotificationPayload;
  bool _initialized = false;
  Future<void>? _refreshInFlight;
  bool _refreshRequestedWhileInFlight = false;

  static const _dueChannelId = 'owntend_due';
  static const _overdueChannelId = 'owntend_overdue';
  static const _criticalChannelId = 'owntend_critical';
  static const _digestChannelId = 'owntend_digest';
  static const _maintenanceGroupKey = 'owntend_maintenance';
  static const _maintenanceIdBase = 10000;
  static const _snoozeIdBase = 500000000;
  static const _notificationIdRange = 100000000;
  static const _digestNotificationId = 9000;
  static const _testNotificationId = 9001;
  static const _maxScheduledReminders = 96;

  @override
  Future<void> initialize() async {
    if (_initialized) {
      return;
    }
    await _configureTimezone();
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        if (payload != null && payload.isNotEmpty) {
          _onNotificationPayload?.call(payload);
        }
      },
    );
    final launchDetails = await _plugin.getNotificationAppLaunchDetails();
    final launchPayload =
        launchDetails?.notificationResponse?.payload?.trim() ?? '';
    if (launchPayload.isNotEmpty &&
        launchDetails?.didNotificationLaunchApp == true) {
      scheduleMicrotask(() => _onNotificationPayload?.call(launchPayload));
    }
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    final l10n = await _localizations();
    final dueChannel = _dueChannel(l10n);
    final overdueChannel = _overdueChannel(l10n);
    final criticalChannel = _criticalChannel(l10n);
    final digestChannel = _digestChannel(l10n);
    await android?.createNotificationChannel(dueChannel);
    await android?.createNotificationChannel(overdueChannel);
    await android?.createNotificationChannel(criticalChannel);
    await android?.createNotificationChannel(digestChannel);
    _initialized = true;
  }

  @override
  Future<void> registerBackgroundRefresh() async {
    if (!Platform.isAndroid) {
      return;
    }
    final session = _supabaseClient?.auth.currentSession;
    final account = await _localSyncStore?.existingAccount();
    if (!notificationBackgroundAccountMatches(
      sessionUserId: session?.user.id,
      boundUserId: account?.boundUserId,
      accountEnabled: account?.enabled ?? false,
      uploadProhibited: account?.uploadProhibited ?? false,
      migrationState: account?.migrationState,
    )) {
      await wm.Workmanager().cancelByUniqueName(dailyRefreshTask);
      return;
    }

    final expectedUserId = session!.user.id;
    final workManager = wm.Workmanager();
    await workManager.initialize(owntendWorkManagerCallback);

    final currentSession = _supabaseClient?.auth.currentSession;
    final currentAccount = await _localSyncStore?.existingAccount();
    if (currentSession?.user.id != expectedUserId ||
        !notificationBackgroundAccountMatches(
          sessionUserId: currentSession?.user.id,
          boundUserId: currentAccount?.boundUserId,
          accountEnabled: currentAccount?.enabled ?? false,
          uploadProhibited: currentAccount?.uploadProhibited ?? false,
          migrationState: currentAccount?.migrationState,
        )) {
      await workManager.cancelByUniqueName(dailyRefreshTask);
      return;
    }

    await workManager.registerPeriodicTask(
      dailyRefreshTask,
      dailyRefreshTask,
      frequency: const Duration(hours: 24),
      initialDelay: const Duration(hours: 1),
      existingWorkPolicy: wm.ExistingPeriodicWorkPolicy.update,
    );
  }

  @override
  Future<void> requestPermissions({bool exactAlarms = false}) async {
    final gateway = _permissionGateway;
    if (gateway == null) {
      throw StateError('Permission requests require an AppPermissionGateway.');
    }
    await gateway.request(AppPermissionKind.notifications);
    if (exactAlarms) {
      await gateway.request(AppPermissionKind.exactAlarms);
    }
  }

  @override
  Future<NotificationPermissionState> permissionState() async {
    if (!_initialized) {
      await initialize();
    }
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    final notificationsEnabled =
        await android?.areNotificationsEnabled() ?? true;
    final canScheduleExact =
        await android?.canScheduleExactNotifications() ?? true;
    return NotificationPermissionState(
      notificationsEnabled: notificationsEnabled,
      canScheduleExact: canScheduleExact,
    );
  }

  @override
  Future<void> refreshSchedules() {
    final active = _refreshInFlight;
    if (active != null) {
      _refreshRequestedWhileInFlight = true;
      return active;
    }
    final refresh = _runRefreshLoop();
    _refreshInFlight = refresh;
    return refresh.whenComplete(() {
      if (identical(_refreshInFlight, refresh)) {
        _refreshInFlight = null;
      }
    });
  }

  Future<void> _runRefreshLoop() async {
    do {
      _refreshRequestedWhileInFlight = false;
      await _refreshSchedulesNow();
    } while (_refreshRequestedWhileInFlight);
  }

  @override
  Future<void> clearAllScheduledReminders() async {
    if (!_initialized) {
      await initialize();
    }
    final pending = await _plugin.pendingNotificationRequests();
    for (final request in pending) {
      await _plugin.cancel(id: request.id);
    }
    await _scheduleStore.replaceAll(const []);
  }

  Future<void> _refreshSchedulesNow() async {
    if (!_initialized) {
      await initialize();
    }
    await _configureTimezone();
    final preferences = await _preferences();
    final current = await _scheduleStore.readAll();
    if (!preferences.enabled) {
      await _applyScheduleDiff(current: current, desired: const []);
      await _cancelSnoozes();
      return;
    }
    final tasks = await maintenanceRepository.listTasks();
    final now = DateTime.now();
    final tasksById = {for (final task in tasks) task.plan.id: task};
    final activeSnoozes = <String, ReminderScheduleEntry>{};
    for (final entry in current) {
      if (!entry.identity.startsWith('snooze:')) continue;
      final planId = entry.identity.substring('snooze:'.length);
      final task = tasksById[planId];
      if (task == null) continue;
      final currentRevision = task.plan.updatedAt.toUtc().toIso8601String();
      if (entry.planRevision == currentRevision &&
          entry.scheduledAt.isAfter(now.toUtc())) {
        activeSnoozes[planId] = entry;
      }
    }
    final buckets = getTaskBuckets(tasks, now);
    if (preferences.allowsInbox) {
      await _refreshDueTaskInbox(buckets, preferences, now);
    }
    if (!preferences.allowsLocalReminders) {
      await _applyScheduleDiff(current: current, desired: const []);
      await _cancelSnoozes();
      await _refreshWeatherAlerts(preferences);
      return;
    }
    final scheduleMode = await _taskScheduleMode(preferences);
    final desired = <_DesiredReminder>[];
    var scheduledCount = 0;
    final scheduledByDay = <String, int>{};
    final horizon = now.add(const Duration(days: 90));
    for (final task in tasks.take(128)) {
      if (scheduledCount >= _maxScheduledReminders) {
        break;
      }
      final activeSnooze = activeSnoozes[task.plan.id];
      if (activeSnooze != null) {
        desired.add(_DesiredReminder(activeSnooze, () async {}));
        scheduledCount++;
        continue;
      }
      final critical = task.plan.priority == PriorityLevel.critical;
      final reminderTime = _adjustForQuietHours(
        _reminderTimeFor(task, preferences),
        preferences,
        critical: critical,
      );
      if (reminderTime.isBefore(now.subtract(const Duration(minutes: 1)))) {
        continue;
      }
      if (reminderTime.isAfter(horizon)) {
        continue;
      }
      if (!_reserveReminderSlot(
        reminderTime,
        scheduledByDay,
        preferences,
        critical: critical,
      )) {
        continue;
      }
      desired.add(
        _desiredTaskReminder(
          task,
          scheduledFor: reminderTime,
          preferences: preferences,
          scheduleMode: scheduleMode,
        ),
      );
      scheduledCount++;
    }
    final digest = await _desiredDailyDigest(
      buckets,
      preferences,
      now,
      scheduleMode,
    );
    if (digest != null) desired.add(digest);
    await _applyScheduleDiff(current: current, desired: desired);
    await _refreshWeatherAlerts(preferences);
  }

  @override
  Future<void> snoozePlan(String planId, Duration duration) async {
    if (!_initialized) {
      await initialize();
    }
    await _configureTimezone();
    final preferences = await _preferences();
    if (!preferences.allowsLocalReminders) {
      return;
    }
    final task = await maintenanceRepository.getTask(planId);
    if (task == null || !task.plan.isEnabled) {
      return;
    }
    final scheduledFor = _adjustForQuietHours(
      DateTime.now().add(duration),
      preferences,
      critical: task.plan.priority == PriorityLevel.critical,
    );
    final scheduleMode = await _taskScheduleMode(preferences);
    final snoozeId = _stableNotificationId('snooze:$planId', _snoozeIdBase);
    await _scheduleTaskReminder(
      task,
      scheduledFor: scheduledFor,
      preferences: preferences,
      scheduleMode: scheduleMode,
      snoozed: true,
    );
    try {
      await _plugin.cancel(
        id: _stableNotificationId('task:$planId', _maintenanceIdBase),
      );
    } on Object {
      await _plugin.cancel(id: snoozeId);
      rethrow;
    }
    final current = await _scheduleStore.readAll();
    final snapshot = _scheduleSnapshot(
      identity: 'snooze:$planId',
      notificationId: snoozeId,
      planRevision: task.plan.updatedAt.toUtc().toIso8601String(),
      scheduledFor: scheduledFor,
      scheduleMode: scheduleMode,
      contentVersion:
          '${task.plan.title}|${task.plan.priority.name}|snoozed|'
          '${preferences.privacyMode}',
    );
    await _scheduleStore.replaceAll([
      for (final entry in current)
        if (entry.identity != 'task:$planId' &&
            entry.identity != 'snooze:$planId')
          entry,
      snapshot,
    ]);
  }

  @override
  Future<void> cancelPlanReminders(String planId) async {
    if (!_initialized) {
      await initialize();
    }
    await _plugin.cancel(
      id: _stableNotificationId('task:$planId', _maintenanceIdBase),
    );
    await _plugin.cancel(
      id: _stableNotificationId('snooze:$planId', _snoozeIdBase),
    );
  }

  AndroidNotificationChannel _dueChannel(AppLocalizations l10n) =>
      AndroidNotificationChannel(
        _dueChannelId,
        l10n.notificationChannelDueName,
        description: l10n.notificationChannelDueDescription,
        importance: Importance.defaultImportance,
      );

  AndroidNotificationChannel _overdueChannel(AppLocalizations l10n) =>
      AndroidNotificationChannel(
        _overdueChannelId,
        l10n.notificationChannelOverdueName,
        description: l10n.notificationChannelOverdueDescription,
        importance: Importance.high,
      );

  AndroidNotificationChannel _criticalChannel(AppLocalizations l10n) =>
      AndroidNotificationChannel(
        _criticalChannelId,
        l10n.notificationChannelCriticalName,
        description: l10n.notificationChannelCriticalDescription,
        importance: Importance.high,
      );

  AndroidNotificationChannel _digestChannel(AppLocalizations l10n) =>
      AndroidNotificationChannel(
        _digestChannelId,
        l10n.notificationChannelDigestName,
        description: l10n.notificationChannelDigestDescription,
        importance: Importance.defaultImportance,
      );

  AndroidNotificationChannel _channelFor(AppLocalizations l10n, TaskItem task) {
    if (task.plan.priority == PriorityLevel.critical) {
      return _criticalChannel(l10n);
    }
    if (task.status == TaskStatus.overdue) {
      return _overdueChannel(l10n);
    }
    return _dueChannel(l10n);
  }

  Future<void> _refreshWeatherAlerts(
    NotificationPreferences preferences,
  ) async {
    final inbox = _notificationInboxRepository;
    final weatherRepository = _weatherRepository;
    if (!preferences.allowsWeatherAlerts ||
        inbox == null ||
        weatherRepository == null) {
      return;
    }
    final weather =
        await weatherRepository.refreshWeather() ??
        await weatherRepository.cachedWeather();
    if (weather == null || weather.forecast.isEmpty) {
      return;
    }
    final today = weather.forecast.first;
    if (today.precipitationProbabilityMax < 60 &&
        today.windSpeedMax < 40 &&
        today.weatherCode < 80) {
      return;
    }
    final l10n = await _localizations();
    final messageArgs = <String, dynamic>{
      'location': weather.location.label,
      'precipitation': today.precipitationProbabilityMax,
      'wind': today.windSpeedMax.round(),
      'weatherCode': today.weatherCode,
    };
    await inbox.createNotification(
      title: l10n.notificationWeatherAlertTitle,
      body: l10n.notificationWeatherAlertBody(
        weather.location.label,
        today.precipitationProbabilityMax,
        today.windSpeedMax.round(),
      ),
      kind: 'weather',
      route: '/maintenance',
      messageCode: NotificationMessageCode.weatherAlert,
      messageArgs: messageArgs,
    );
  }

  Future<void> _refreshDueTaskInbox(
    TaskBuckets buckets,
    NotificationPreferences preferences,
    DateTime now,
  ) async {
    final inbox = _notificationInboxRepository;
    if (inbox == null) {
      return;
    }
    final actionable = [...buckets.overdue, ...buckets.today];
    final l10n = await _localizations();
    for (final task in actionable.take(preferences.maxRemindersPerDay)) {
      final status = getTaskBucketStatus(task, now);
      final code = status == TaskBucketStatus.overdue
          ? NotificationMessageCode.taskOverdue
          : NotificationMessageCode.taskDueToday;
      await inbox.createNotification(
        title: status == TaskBucketStatus.overdue
            ? l10n.notificationTaskOverdueTitle(task.plan.title)
            : l10n.notificationTaskDueTodayTitle(task.plan.title),
        body: l10n.notificationTaskBody,
        kind: 'task',
        route: _taskRoute(task.plan.id),
        planId: task.plan.id,
        messageCode: code,
        messageArgs: {'task': task.plan.title},
      );
    }
  }

  Future<_DesiredReminder?> _desiredDailyDigest(
    TaskBuckets buckets,
    NotificationPreferences preferences,
    DateTime now,
    AndroidScheduleMode scheduleMode,
  ) async {
    if (!preferences.allowsDailyDigest) {
      return null;
    }
    final overdue = buckets.overdueCount;
    final dueToday = buckets.todayCount;
    final upcoming = buckets.next7DaysCount;
    if (overdue == 0 && dueToday == 0 && upcoming == 0) {
      return null;
    }
    final l10n = await _localizations();
    final body = l10n.notificationDailyDigestBody(overdue, dueToday, upcoming);
    if (preferences.allowsInbox && (overdue > 0 || dueToday > 0)) {
      await _notificationInboxRepository?.createNotification(
        title: l10n.notificationDailyDigestTitle,
        body: body,
        kind: 'digest',
        route: '/maintenance',
        messageCode: NotificationMessageCode.dailyDigest,
        messageArgs: {
          'overdue': overdue,
          'dueToday': dueToday,
          'upcoming': upcoming,
        },
      );
    }
    if (!preferences.allowsLocalReminders) {
      return null;
    }
    final digestChannel = _digestChannel(l10n);
    final scheduledFor = _adjustForQuietHours(
      _nextDigestTime(now, preferences),
      preferences,
      critical: false,
    );
    final title = preferences.privacyMode
        ? l10n.owntendReminder
        : l10n.notificationDailyDigestTitle;
    final visibleBody = preferences.privacyMode
        ? l10n.notificationGenericBody
        : body;
    final snapshot = _scheduleSnapshot(
      identity: 'digest:daily',
      notificationId: _digestNotificationId,
      planRevision: '$overdue:$dueToday:$upcoming',
      scheduledFor: scheduledFor,
      scheduleMode: scheduleMode,
      contentVersion: '$title|$visibleBody|${preferences.privacyMode}',
    );
    return _DesiredReminder(
      snapshot,
      () => _plugin.zonedSchedule(
        id: _digestNotificationId,
        title: title,
        body: visibleBody,
        scheduledDate: notificationDateInConfiguredTimezone(scheduledFor),
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            digestChannel.id,
            digestChannel.name,
            channelDescription: digestChannel.description,
            importance: digestChannel.importance,
            priority: Priority.defaultPriority,
            category: AndroidNotificationCategory.status,
            groupKey: _maintenanceGroupKey,
            styleInformation: BigTextStyleInformation(visibleBody),
            visibility: preferences.privacyMode
                ? NotificationVisibility.private
                : NotificationVisibility.public,
          ),
        ),
        androidScheduleMode: scheduleMode,
        payload: '/maintenance',
      ),
    );
  }

  _DesiredReminder _desiredTaskReminder(
    TaskItem task, {
    required DateTime scheduledFor,
    required NotificationPreferences preferences,
    required AndroidScheduleMode scheduleMode,
  }) {
    final notificationId = _stableNotificationId(
      'task:${task.plan.id}',
      _maintenanceIdBase,
    );
    final snapshot = _scheduleSnapshot(
      identity: 'task:${task.plan.id}',
      notificationId: notificationId,
      planRevision: task.plan.updatedAt.toUtc().toIso8601String(),
      scheduledFor: scheduledFor,
      scheduleMode: scheduleMode,
      contentVersion:
          '${task.plan.title}|${task.plan.priority.name}|'
          '${task.status.name}|${preferences.privacyMode}',
    );
    return _DesiredReminder(
      snapshot,
      () => _scheduleTaskReminder(
        task,
        scheduledFor: scheduledFor,
        preferences: preferences,
        scheduleMode: scheduleMode,
      ),
    );
  }

  ReminderScheduleEntry _scheduleSnapshot({
    required String identity,
    required int notificationId,
    required String planRevision,
    required DateTime scheduledFor,
    required AndroidScheduleMode scheduleMode,
    required String contentVersion,
  }) {
    final configured = notificationDateInConfiguredTimezone(scheduledFor);
    return ReminderScheduleEntry(
      identity: identity,
      notificationId: notificationId,
      planRevision: planRevision,
      scheduledAt: configured.toUtc(),
      timezone: configured.location.name,
      localComponents:
          '${configured.year.toString().padLeft(4, '0')}-'
          '${configured.month.toString().padLeft(2, '0')}-'
          '${configured.day.toString().padLeft(2, '0')}T'
          '${configured.hour.toString().padLeft(2, '0')}:'
          '${configured.minute.toString().padLeft(2, '0')}:'
          '${configured.second.toString().padLeft(2, '0')}',
      scheduleMode: scheduleMode.name,
      contentVersion: contentVersion,
    );
  }

  Future<void> _applyScheduleDiff({
    required List<ReminderScheduleEntry> current,
    required List<_DesiredReminder> desired,
  }) async {
    final desiredSnapshots = [
      for (final reminder in desired) reminder.snapshot,
    ];
    final diff = diffReminderSchedules(
      current: current,
      desired: desiredSnapshots,
    );
    final desiredByIdentity = {
      for (final reminder in desired) reminder.snapshot.identity: reminder,
    };
    for (final removed in diff.removed) {
      await _plugin.cancel(id: removed.notificationId);
    }
    for (final entry in [...diff.added, ...diff.changed]) {
      await desiredByIdentity[entry.identity]!.schedule();
    }
    await _scheduleStore.replaceAll(desiredSnapshots);
    AppLogger.info(
      'reminder_reconciliation_completed',
      fields: {
        'desired': desiredSnapshots.length,
        'added': diff.added.length,
        'changed': diff.changed.length,
        'removed': diff.removed.length,
        'unchanged': diff.unchanged.length,
      },
    );
  }

  Future<void> _scheduleTaskReminder(
    TaskItem task, {
    required DateTime scheduledFor,
    required NotificationPreferences preferences,
    required AndroidScheduleMode scheduleMode,
    bool snoozed = false,
  }) async {
    final l10n = await _localizations();
    final channel = _channelFor(l10n, task);
    final title = preferences.privacyMode
        ? l10n.owntendReminder
        : snoozed
        ? l10n.snoozedReminderTask(task.plan.title)
        : task.status == TaskStatus.overdue
        ? l10n.notificationTaskOverdueTitle(task.plan.title)
        : l10n.notificationTaskDueTodayTitle(task.plan.title);
    final body = preferences.privacyMode
        ? l10n.openOwntendToViewThisReminder
        : l10n.notificationTaskBody;
    await _plugin.zonedSchedule(
      id: _stableNotificationId(
        '${snoozed ? 'snooze' : 'task'}:${task.plan.id}',
        snoozed ? _snoozeIdBase : _maintenanceIdBase,
      ),
      title: title,
      body: body,
      scheduledDate: notificationDateInConfiguredTimezone(scheduledFor),
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          channel.id,
          channel.name,
          channelDescription: channel.description,
          importance: channel.importance,
          priority: task.plan.priority == PriorityLevel.critical
              ? Priority.high
              : Priority.defaultPriority,
          category: AndroidNotificationCategory.reminder,
          groupKey: _maintenanceGroupKey,
          ticker: l10n.owntendReminderTicker,
          styleInformation: BigTextStyleInformation(
            body,
            contentTitle: title,
            summaryText: _localizedPriorityLabel(l10n, task.plan.priority),
          ),
          visibility: preferences.privacyMode
              ? NotificationVisibility.private
              : NotificationVisibility.public,
        ),
      ),
      androidScheduleMode: scheduleMode,
      payload: _taskRoute(task.plan.id),
    );
  }

  @override
  Future<void> sendTestReminder() async {
    if (!_initialized) {
      await initialize();
    }
    final preferences = await _preferences();
    final l10n = await _localizations();
    final dueChannel = _dueChannel(l10n);
    final scheduleMode = await _taskScheduleMode(preferences);
    final scheduledFor = DateTime.now().add(const Duration(seconds: 10));
    await _plugin.zonedSchedule(
      id: _testNotificationId,
      title: l10n.owntendTestReminder,
      body: preferences.privacyMode
          ? l10n.openOwntendToViewThisReminder
          : l10n.notificationsAreReadyThisScheduledTestShouldArriveNow,
      scheduledDate: notificationDateInConfiguredTimezone(scheduledFor),
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          dueChannel.id,
          dueChannel.name,
          channelDescription: dueChannel.description,
          importance: dueChannel.importance,
          priority: Priority.defaultPriority,
          category: AndroidNotificationCategory.reminder,
          visibility: preferences.privacyMode
              ? NotificationVisibility.private
              : NotificationVisibility.public,
        ),
      ),
      androidScheduleMode: scheduleMode,
      payload: '/notifications',
    );
  }

  Future<void> _cancelSnoozes() async {
    final pending = await _plugin.pendingNotificationRequests();
    for (final request in pending) {
      if (request.id >= _snoozeIdBase &&
          request.id < _snoozeIdBase + _notificationIdRange) {
        await _plugin.cancel(id: request.id);
      }
    }
  }

  Future<NotificationPreferences> _preferences() async {
    try {
      return await _settingsRepository?.notificationPreferences() ??
          const NotificationPreferences();
    } catch (_) {
      return const NotificationPreferences();
    }
  }

  Future<void> _configureTimezone() async {
    tz.initializeTimeZones();
    String? timezone;
    try {
      timezone = (await _settingsRepository?.homeLocation())?.timezone;
      timezone ??=
          (await _weatherRepository?.cachedWeather())?.location.timezone;
    } catch (_) {
      timezone = null;
    }
    if (timezone == null || timezone.trim().isEmpty) {
      return;
    }
    try {
      tz.setLocalLocation(tz.getLocation(timezone));
    } catch (_) {
      // Unknown IANA timezone strings should not break reminder scheduling.
    }
  }

  DateTime _reminderTimeFor(
    TaskItem task,
    NotificationPreferences preferences,
  ) {
    final nextDue = task.plan.nextDueDate;
    final scheduledDate = DateTime(
      nextDue.year,
      nextDue.month,
      nextDue.day - task.plan.reminderDaysBefore,
    );
    final hasPlanTime = nextDue.hour != 0 || nextDue.minute != 0;
    return DateTime(
      scheduledDate.year,
      scheduledDate.month,
      scheduledDate.day,
      hasPlanTime ? nextDue.hour : preferences.reminderHour,
      hasPlanTime ? nextDue.minute : 0,
    );
  }

  DateTime _adjustForQuietHours(
    DateTime value,
    NotificationPreferences preferences, {
    required bool critical,
  }) {
    if (!preferences.quietHoursEnabled ||
        preferences.quietHoursStartMinutes ==
            preferences.quietHoursEndMinutes ||
        (critical && preferences.criticalBypassQuietHours)) {
      return value;
    }
    final minutes = value.hour * 60 + value.minute;
    final start = preferences.quietHoursStartMinutes;
    final end = preferences.quietHoursEndMinutes;
    final inQuietHours = start < end
        ? minutes >= start && minutes < end
        : minutes >= start || minutes < end;
    if (!inQuietHours) {
      return value;
    }
    final quietEndDate = start < end || minutes < end
        ? DateTime(value.year, value.month, value.day)
        : DateTime(value.year, value.month, value.day + 1);
    return DateTime(
      quietEndDate.year,
      quietEndDate.month,
      quietEndDate.day,
      end ~/ 60,
      end % 60,
    );
  }

  bool _reserveReminderSlot(
    DateTime scheduledFor,
    Map<String, int> scheduledByDay,
    NotificationPreferences preferences, {
    required bool critical,
  }) {
    if (critical) {
      return true;
    }
    final key = _dateKey(scheduledFor);
    final current = scheduledByDay[key] ?? 0;
    if (current >= preferences.maxRemindersPerDay) {
      return false;
    }
    scheduledByDay[key] = current + 1;
    return true;
  }

  DateTime _nextDigestTime(DateTime now, NotificationPreferences preferences) {
    var digest = DateTime(now.year, now.month, now.day, preferences.digestHour);
    if (digest.isBefore(now.add(const Duration(minutes: 5)))) {
      digest = DateTime(
        now.year,
        now.month,
        now.day + 1,
        preferences.digestHour,
      );
    }
    return digest;
  }

  Future<AppLocalizations> _localizations() async {
    final preference = await _settingsRepository?.appLocalePreference();
    final deviceLanguage = WidgetsBinding
        .instance
        .platformDispatcher
        .locale
        .languageCode
        .toLowerCase();
    final language = preference?.isExplicit == true
        ? preference!.language.name
        : deviceLanguage == AppLanguage.ar.name
        ? AppLanguage.ar.name
        : AppLanguage.en.name;
    return lookupAppLocalizations(Locale(language));
  }

  String _localizedPriorityLabel(
    AppLocalizations l10n,
    PriorityLevel priority,
  ) {
    return switch (priority) {
      PriorityLevel.low => l10n.low,
      PriorityLevel.medium => l10n.medium,
      PriorityLevel.high => l10n.high,
      PriorityLevel.critical => l10n.critical,
    };
  }

  String _taskRoute(String planId) =>
      '/maintenance/${Uri.encodeComponent(planId)}';

  String _dateKey(DateTime value) {
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '${value.year}-$month-$day';
  }

  int _stableNotificationId(String key, int base) {
    var hash = 0;
    for (final codeUnit in key.codeUnits) {
      hash = ((hash * 31) + codeUnit) & 0x7fffffff;
    }
    return base + (hash % _notificationIdRange);
  }

  Future<AndroidScheduleMode> _taskScheduleMode(
    NotificationPreferences preferences,
  ) async {
    if (!preferences.preferExactReminders) {
      return AndroidScheduleMode.inexactAllowWhileIdle;
    }
    final state = await permissionState();
    return state.canScheduleExact
        ? AndroidScheduleMode.exactAllowWhileIdle
        : AndroidScheduleMode.inexactAllowWhileIdle;
  }
}

@visibleForTesting
tz.TZDateTime notificationDateInConfiguredTimezone(DateTime value) {
  return tz.TZDateTime.from(value.toUtc(), tz.local);
}

class _DesiredReminder {
  const _DesiredReminder(this.snapshot, this.schedule);

  final ReminderScheduleEntry snapshot;
  final Future<void> Function() schedule;
}

class NotificationMessageGenerator {
  const NotificationMessageGenerator();

  String taskMessage({
    required TaskItem task,
    required DateTime now,
    StreakState? streak,
    DashboardSummary? dashboard,
  }) {
    final overdue = now.difference(task.plan.nextDueDate);
    final overdueText = overdue.isNegative ? null : _durationLabel(overdue);
    if (overdueText != null) {
      return _limit(
        '${task.plan.title} is $overdueText overdue for ${task.asset.name}.',
      );
    }
    final streakText = streak == null || streak.currentStreak == 0
        ? null
        : '${streak.currentStreak}-day streak';
    final progressText = dashboard == null
        ? null
        : '${(dashboard.completionRate * 100).round()}% monthly';
    final timeText = _timeOfDay(now);
    final templates = [
      '$timeText reminder: ${task.asset.name} needs ${task.plan.title}.',
      overdueText == null
          ? '${task.plan.title} is due for ${task.asset.name}.'
          : '${task.plan.title} is $overdueText overdue for ${task.asset.name}.',
      streakText == null
          ? '${task.asset.name}: ${task.plan.title}.'
          : '${task.plan.title} is ready. Current streak: $streakText.',
      progressText == null
          ? 'Task ready: ${task.plan.title}.'
          : '$progressText complete. Next up: ${task.plan.title}.',
      '${task.asset.name} has a ${_assetTypeCareLabel(task.asset.assetType)} task due.',
    ];
    final seed = [
      task.plan.id,
      task.plan.nextDueDate.hour,
      now.day,
      now.hour ~/ 4,
      task.status.name,
    ].join(':');
    final index = _stableIndex(seed, templates.length);
    return _limit(templates[index]);
  }

  int _stableIndex(String value, int modulo) {
    var hash = 0;
    for (final codeUnit in value.codeUnits) {
      hash = ((hash * 31) + codeUnit) & 0x7fffffff;
    }
    return hash % modulo;
  }

  String _timeOfDay(DateTime now) {
    if (now.hour < 12) {
      return 'morning';
    }
    if (now.hour < 17) {
      return 'afternoon';
    }
    return 'evening';
  }

  String _assetTypeCareLabel(AssetType type) {
    return switch (type) {
      AssetType.safety => 'safety',
      AssetType.pet => 'pet care',
      AssetType.device => 'appliance',
      AssetType.plant => 'plant',
      AssetType.general => 'home',
    };
  }

  String _durationLabel(Duration duration) {
    final minutes = duration.inMinutes;
    if (minutes < 60) {
      return '${minutes.clamp(1, 59)}m';
    }
    final hours = duration.inHours;
    if (hours < 48) {
      final remainder = minutes.remainder(60);
      return remainder == 0 ? '${hours}h' : '${hours}h ${remainder}m';
    }
    final days = duration.inDays;
    return '$days day${days == 1 ? '' : 's'}';
  }

  String _limit(String value) {
    final normalized = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.length <= 110) {
      return normalized;
    }
    return '${normalized.substring(0, 107).trimRight()}...';
  }
}
