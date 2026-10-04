part of 'startup_presentation.dart';

class StartupHome extends StatelessWidget {
  const StartupHome({
    required this.state,
    required this.status,
    required this.language,
    required this.onLanguageChanged,
    required this.onRetry,
    required this.onCheckConnection,
    required this.onContinueOffline,
    required this.onSignOut,
    super.key,
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
      StartupBootstrapKind.authenticatedReady => Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: const SizedBox.expand(),
      ),
    };
  }
}

class _StartupRestorationScreen extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return _InitialCloudHydrationOverlay(
      status: status,
      failure: failure,
      canContinueOffline: canContinueOffline,
      onRetry: onRetry,
      onCheckConnection: onCheckConnection,
      onContinueOffline: onContinueOffline,
      onSignOut: onSignOut,
    );
  }
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

SyncStatus syntheticStartupStatus(
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
    if (_started || !mounted) {
      return;
    }
    _started = true;
    try {
      final syncAccount = await ref.read(localSyncStoreProvider)?.account();
      if (!mounted) return;
      await configureCloudSyncBackgroundTask(syncAccount?.enabled ?? false);
      if (!mounted) return;
      await _refreshNotifications();
      if (!mounted) return;
      await _runAutomaticBackup();
    } on Object catch (error) {
      AppLogger.warning('notification_bootstrap', error: error);
    }
  }

  Future<void> _refreshNotifications() async {
    if (!mounted) return;
    try {
      if (!ref.read(notificationAutoStartProvider)) return;
      final scheduler = ref.read(notificationSchedulerProvider);
      await scheduler.initialize();
      if (!mounted) return;
      if (scheduler is NotificationBackgroundRegistration) {
        final backgroundRegistration =
            scheduler as NotificationBackgroundRegistration;
        await backgroundRegistration.registerBackgroundRefresh();
        if (!mounted) return;
      }
      final session = ref.read(authRepositoryProvider)?.currentSession;
      final consumer = ref.read(notificationReconciliationConsumerProvider);
      if (session != null && consumer != null) {
        final result = await consumer.drainForAccount(session.userId);
        if (!mounted) return;
        if (result == NotificationReconciliationDrainResult.refreshed ||
            result == NotificationReconciliationDrainResult.accountMismatch) {
          return;
        }
      }
      await scheduler.refreshSchedules();
    } on Object catch (error) {
      AppLogger.warning('notification_refresh', error: error);
    }
  }

  Future<void> _runAutomaticBackup() async {
    if (!mounted) return;
    try {
      if (!ref.read(backupAutoStartProvider)) return;
      await ref.read(backupRepositoryProvider).exportAutomaticBackupIfDue();
    } catch (_) {
      // Backup status is persisted by the backup service; startup should continue.
    }
  }
}
