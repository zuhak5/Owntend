part of '../../../../main.dart';

class _StartupHome extends StatelessWidget {
  const _StartupHome({
    required this.state,
    required this.status,
    required this.language,
    required this.onLanguageChanged,
    required this.onRetry,
    required this.onCheckConnection,
    required this.onContinueOffline,
    required this.onSignOut,
  });

  final StartupBootstrapState state;
  final SyncStatus status;
  final AppLanguage language;
  final ValueChanged<AppLanguage> onLanguageChanged;
  final Future<void> Function() onRetry;
  final Future<void> Function() onCheckConnection;
  final Future<void> Function()? onContinueOffline;
  final Future<void> Function() onSignOut;

  @override
  Widget build(BuildContext context) {
    return switch (state.kind) {
      StartupBootstrapKind.unauthenticated => AuthenticationGate(
        language: language,
        onLanguageChanged: onLanguageChanged,
        child: const SizedBox.shrink(),
      ),
      StartupBootstrapKind.authenticatedHydrating ||
      StartupBootstrapKind.startupFailed => _StartupRestorationScreen(
        status: status,
        failure: state.failure,
        canContinueOffline: state.canContinueOffline,
        onRetry: onRetry,
        onCheckConnection: onCheckConnection,
        onContinueOffline: onContinueOffline,
        onSignOut: onSignOut,
      ),
      StartupBootstrapKind.checkingStoredSession ||
      StartupBootstrapKind.authenticatedReady => const Scaffold(
        backgroundColor: HkColors.appBackground,
        body: SizedBox.expand(),
      ),
    };
  }
}

class _StartupRestorationScreen extends ConsumerStatefulWidget {
  const _StartupRestorationScreen({
    required this.status,
    required this.failure,
    required this.canContinueOffline,
    required this.onRetry,
    required this.onCheckConnection,
    required this.onContinueOffline,
    required this.onSignOut,
  });

  final SyncStatus status;
  final StartupFailure? failure;
  final bool canContinueOffline;
  final Future<void> Function() onRetry;
  final Future<void> Function() onCheckConnection;
  final Future<void> Function()? onContinueOffline;
  final Future<void> Function() onSignOut;

  @override
  ConsumerState<_StartupRestorationScreen> createState() =>
      _StartupRestorationScreenState();
}

class _StartupRestorationScreenState
    extends ConsumerState<_StartupRestorationScreen> {
  bool _restoreServiceRequested = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_restoreServiceRequested) {
      _restoreServiceRequested = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          unawaited(_startStartupRestoreService(context));
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return _InitialCloudHydrationOverlay(
      status: widget.status,
      failure: widget.failure,
      canContinueOffline: widget.canContinueOffline,
      onRetry: widget.onRetry,
      onCheckConnection: widget.onCheckConnection,
      onContinueOffline: widget.onContinueOffline,
      onSignOut: widget.onSignOut,
    );
  }
}

Future<void> _startStartupRestoreService(BuildContext context) async {
  if (!context.mounted || !Platform.isAndroid) return;
  final localeCode = Localizations.localeOf(context).languageCode;
  await startRestoreForegroundService(localeCode: localeCode);
}

SyncStatus _hydrationStatusFor(SyncStatus? observed, SyncStatus fallback) {
  if (observed?.initialHydrationProgress != null) {
    return _mergeStartupSyncStatus(fallback, observed!);
  }
  if (observed != null &&
      const {
        SyncPhase.error,
        SyncPhase.offline,
        SyncPhase.blocked,
      }.contains(observed.phase)) {
    return SyncStatus(
      phase: observed.phase,
      enabled: observed.enabled,
      pendingChanges: observed.pendingChanges,
      pendingMediaCleanup: observed.pendingMediaCleanup,
      lastSyncedAt: observed.lastSyncedAt,
      lastSyncAttemptAt: observed.lastSyncAttemptAt,
      lastSyncFailureAt: observed.lastSyncFailureAt,
      message: observed.message,
      boundUserId: observed.boundUserId,
      realtime: observed.realtime,
      nextRetryAt: observed.nextRetryAt,
      initialHydrationProgress:
          fallback.initialHydrationProgress ??
          _syntheticStartupProgress(RestoreRunState.failed),
      mergeConfirmationRequired: observed.mergeConfirmationRequired,
      blockedReason: observed.blockedReason,
      migrationState: observed.migrationState,
      restorePending: observed.restorePending,
      backgroundResult: observed.backgroundResult,
      clockSkewConflicts: observed.clockSkewConflicts,
    );
  }
  return fallback;
}

SyncStatus _mergeStartupSyncStatus(SyncStatus? current, SyncStatus next) {
  final currentProgress = current?.initialHydrationProgress;
  final nextProgress = next.initialHydrationProgress;
  if (currentProgress == null) return next;
  if (nextProgress == null) {
    return _syncStatusWithHydration(next, currentProgress);
  }
  final progress = _isHydrationProgressBefore(nextProgress, currentProgress)
      ? currentProgress
      : nextProgress;
  return _syncStatusWithHydration(next, progress);
}

bool _isHydrationProgressBefore(
  InitialHydrationProgress candidate,
  InitialHydrationProgress floor,
) {
  if (floor.state == RestoreRunState.completed &&
      candidate.state != RestoreRunState.completed) {
    return true;
  }
  if (candidate.state == RestoreRunState.completed) return false;
  if (floor.state == RestoreRunState.failed &&
      candidate.state == RestoreRunState.running) {
    return candidate.percentage < floor.percentage;
  }
  if (candidate.stage.index < floor.stage.index) return true;
  if (candidate.stage.index > floor.stage.index) return false;
  return candidate.percentage < floor.percentage;
}

SyncStatus _syncStatusWithHydration(
  SyncStatus status,
  InitialHydrationProgress progress,
) {
  return SyncStatus(
    phase: status.phase,
    enabled: status.enabled,
    pendingChanges: status.pendingChanges,
    pendingMediaCleanup: status.pendingMediaCleanup,
    lastSyncedAt: status.lastSyncedAt,
    lastSyncAttemptAt: status.lastSyncAttemptAt,
    lastSyncFailureAt: status.lastSyncFailureAt,
    message: status.message,
    boundUserId: status.boundUserId,
    realtime: status.realtime,
    nextRetryAt: status.nextRetryAt,
    initialHydrationProgress: progress,
    mergeConfirmationRequired: status.mergeConfirmationRequired,
    blockedReason: status.blockedReason,
    migrationState: status.migrationState,
    restorePending: status.restorePending,
    backgroundResult: status.backgroundResult,
    clockSkewConflicts: status.clockSkewConflicts,
  );
}

SyncStatus _syntheticStartupStatus(
  RestoreRunState state, {
  SyncPhase phase = SyncPhase.initializing,
  String? message,
  InitialHydrationStage stage = InitialHydrationStage.connecting,
  String? failure,
}) {
  return SyncStatus(
    phase: phase,
    message: message,
    initialHydrationProgress: _syntheticStartupProgress(
      state,
      stage: stage,
      failure: failure,
    ),
  );
}

InitialHydrationProgress _syntheticStartupProgress(
  RestoreRunState state, {
  InitialHydrationStage stage = InitialHydrationStage.connecting,
  String? failure,
}) {
  final now = DateTime.now();
  return InitialHydrationProgress(
    runId: 'startup',
    state: state,
    stage: stage,
    completedUnits: 0,
    totalUnits: 1,
    startedAt: now,
    updatedAt: now,
    failure: state == RestoreRunState.failed
        ? failure ?? 'Startup restore failed.'
        : null,
  );
}

AppLanguage _supportedDeviceLanguage(Locale locale) {
  return locale.languageCode.toLowerCase() == AppLanguage.ar.name
      ? AppLanguage.ar
      : AppLanguage.en;
}

String _failureMessage(
  BuildContext context,
  Object error, {
  AppFailureCode fallback = AppFailureCode.general,
}) => localizedFailureMessage(
  context.l10n,
  appFailureCodeFor(error, fallback: fallback),
);

String _localeTag(BuildContext context) =>
    Localizations.localeOf(context).toLanguageTag();

String _formatShortDate(BuildContext context, DateTime value) =>
    DateFormat.yMMMd(_localeTag(context)).format(value);

String _formatLongDate(BuildContext context, DateTime value) =>
    DateFormat.yMMMMEEEEd(_localeTag(context)).format(value);

String _formatShortTime(BuildContext context, DateTime value) =>
    DateFormat.jm(_localeTag(context)).format(value);

String _formatShortDateTime(BuildContext context, DateTime value) =>
    DateFormat.yMMMd(_localeTag(context)).add_jm().format(value);

String _formatMonthDay(BuildContext context, DateTime value) =>
    DateFormat.MMMd(_localeTag(context)).format(value);

String _formatInteger(BuildContext context, num value) =>
    NumberFormat.decimalPattern(_localeTag(context)).format(value);

String _localizedFeatureMessage(BuildContext context, String value) {
  final l10n = context.l10n;
  final countMatch = RegExp(
    r'^(\d+) (overdue task\(s\)|item\(s\)|due today|warranty alert\(s\))\.$',
  ).firstMatch(value);
  if (countMatch != null) {
    final count = int.parse(countMatch.group(1)!);
    return switch (countMatch.group(2)) {
      'overdue task(s)' => l10n.overdueTaskSentence(count),
      'item(s)' => l10n.itemCountSentence(count),
      'due today' => l10n.dueTodayTaskSentence(count),
      'warranty alert(s)' => l10n.warrantyAlertSentence(count),
      _ => value,
    };
  }
  return switch (value) {
    'No maintenance plan yet.' => l10n.noMaintenancePlanYet,
    'Add a maintenance task.' => l10n.addAMaintenanceTask,
    'Critical task due today.' => l10n.criticalTaskDueToday,
    'Critical care is due soon.' => l10n.criticalCareIsDueSoon,
    'Warranty has expired.' => l10n.warrantyHasExpired,
    'Warranty expires within 30 days.' => l10n.warrantyExpiresWithin30Days,
    'Maintenance is on track.' => l10n.maintenanceIsOnTrack,
    'Review upcoming maintenance.' => l10n.reviewUpcomingMaintenance,
    'No items in this room yet.' => l10n.noItemsInThisRoomYet,
    'Add the first item.' => l10n.addTheFirstItem,
    'Room is on track.' => l10n.roomIsOnTrack,
    'Add maintenance tasks for this room.' =>
      l10n.addMaintenanceTasksForThisRoom,
    'Home setup is incomplete.' => l10n.homeSetupIsIncomplete,
    'No successful backup yet.' => l10n.noSuccessfulBackupYet,
    'Home maintenance is ready.' => l10n.homeMaintenanceIsReady,
    'Review upcoming tasks.' => l10n.reviewUpcomingTasks,
    _ => value,
  };
}

ThemeMode _effectiveThemeMode(
  ThemePreference preference, {
  required bool timeOfDayThemeEnabled,
  required DateTime now,
}) {
  final automaticUsesLocalClock =
      preference == ThemePreference.system || timeOfDayThemeEnabled;
  return switch (preference) {
    ThemePreference.light => ThemeMode.light,
    ThemePreference.dark => ThemeMode.dark,
    ThemePreference.system =>
      automaticUsesLocalClock && _isLocalDaytime(now)
          ? ThemeMode.light
          : ThemeMode.dark,
  };
}

bool _isLocalDaytime(DateTime value) {
  final local = value.toLocal();
  return local.hour >= 6 && local.hour < 18;
}

class NotificationBootstrap extends ConsumerStatefulWidget {
  const NotificationBootstrap({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<NotificationBootstrap> createState() =>
      _NotificationBootstrapState();
}

class _NotificationBootstrapState extends ConsumerState<NotificationBootstrap>
    with WidgetsBindingObserver {
  bool _started = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    scheduleMicrotask(_initializeNotifications);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      scheduleMicrotask(_refreshNotifications);
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;

  Future<void> _initializeNotifications() async {
    if (_started) {
      return;
    }
    _started = true;
    final syncAccount = await ref.read(localSyncStoreProvider)?.account();
    await configureCloudSyncBackgroundTask(syncAccount?.enabled ?? false);
    await _refreshNotifications();
    unawaited(_runAutomaticBackup());
  }

  Future<void> _refreshNotifications() async {
    if (!ref.read(notificationAutoStartProvider)) {
      return;
    }
    try {
      final scheduler = ref.read(notificationSchedulerProvider);
      await scheduler.initialize();
      await scheduler.refreshSchedules();
    } on Object catch (error) {
      AppLogger.warning('notification_refresh', error: error);
    }
  }

  Future<void> _runAutomaticBackup() async {
    if (!ref.read(backupAutoStartProvider)) {
      return;
    }
    try {
      await ref.read(backupRepositoryProvider).exportAutomaticBackupIfDue();
    } catch (_) {
      // Backup status is persisted by the backup service; startup should continue.
    }
  }
}
