part of '../../../../main.dart';

class _OwntendBootstrapState extends State<OwntendBootstrap> {
  @override
  Widget build(BuildContext context) {
    final database = widget.database;
    final appBuilder = widget.appBuilder;
    final startupThemeLoader =
        widget.startupThemeLoader ??
        (database == null ? null : () => _loadStartupTheme(database));
    return ProviderScope(
      overrides: database == null
          ? const []
          : [
              databaseProvider.overrideWithValue(database),
              appConfigProvider.overrideWithValue(
                widget.appConfig ?? AppConfig.test(),
              ),
              supabaseClientProvider.overrideWithValue(widget.supabaseClient),
              localSyncStoreProvider.overrideWithValue(
                LocalSyncStore(database),
              ),
              maintenanceCompletionReminderReconcilerProvider.overrideWith(
                (ref) => () async {
                  await ref
                      .read(notificationSchedulerProvider)
                      .refreshSchedules();
                },
              ),
              accountDeletionPrepareProvider.overrideWith(
                (ref) => (userId) async {
                  await ref
                      .read(syncCoordinatorProvider)
                      ?.prepareForAccountDeletion(userId);
                },
              ),
              accountDeletionCancelProvider.overrideWith(
                (ref) => (userId) async {
                  await ref
                      .read(syncCoordinatorProvider)
                      ?.cancelAccountDeletion(userId);
                  await ref
                      .read(notificationSchedulerProvider)
                      .refreshSchedules();
                },
              ),
              accountDeletionLocalCleanupProvider.overrideWith(
                (ref) => (userId) async {
                  await LocalAccountDataCleaner(LocalSyncStore(database))
                      .clearAfterCloudDeletion(
                        userId,
                        additionalCleanup: (accountId) async {
                          await ref
                              .read(offlineCreationDraftStoreProvider)
                              .clearForAccount(accountId);
                          await ref
                              .read(taskCreationOperationStoreProvider)
                              .clearOperationsForAccount(accountId);
                        },
                      );
                  await ref
                      .read(notificationSchedulerProvider)
                      .clearAllScheduledReminders();
                  await cancelAccountScopedBackgroundWork();
                  ref.read(initialHomeSnapshotProvider).value = null;
                },
              ),
            ],
      child: _HomeStartupGate(
        startupThemeLoader: startupThemeLoader!,
        appBuilder:
            appBuilder ??
            (startupTheme) => OwntendApp(startupTheme: startupTheme),
      ),
    );
  }
}

class _HomeStartupGate extends ConsumerStatefulWidget {
  const _HomeStartupGate({
    required this.startupThemeLoader,
    required this.appBuilder,
  });

  final StartupThemeLoader startupThemeLoader;
  final BootstrappedAppBuilder appBuilder;

  @override
  ConsumerState<_HomeStartupGate> createState() => _HomeStartupGateState();
}

class _HomeStartupGateState extends ConsumerState<_HomeStartupGate> {
  static const _preferenceTimeout = Duration(seconds: 4);

  ThemeStartupSettings? _startupTheme;
  late final Future<void> _startup = _initialize();

  @override
  void initState() {
    super.initState();
    unawaited(_startup);
  }

  Future<void> _initialize() async {
    final startupTheme =
        await _guard(
          'startup preferences',
          widget.startupThemeLoader,
          timeout: _preferenceTimeout,
        ) ??
        const ThemeStartupSettings(
          preference: ThemePreference.light,
          timeOfDayEnabled: false,
        );
    if (!mounted) return;
    setState(() => _startupTheme = startupTheme);
  }

  Future<T?> _guard<T>(
    String label,
    Future<T> Function() operation, {
    required Duration timeout,
  }) async {
    try {
      return await operation().timeout(timeout);
    } on Object catch (error) {
      AppLogger.warning('startup_${label.replaceAll(' ', '_')}', error: error);
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final startupTheme = _startupTheme;
    if (startupTheme == null) {
      return const OwntendStartupSurface(
        key: ValueKey('startup-theme-loading'),
      );
    }
    return widget.appBuilder(startupTheme);
  }
}

void _openNotificationPayload(String payload) {
  final route = _validatedNotificationRoute(payload);
  if (route == null) {
    return;
  }
  WidgetsBinding.instance.addPostFrameCallback((_) {
    final context = _rootNavigatorKey.currentContext;
    if (context == null || !context.mounted) {
      return;
    }
    context.push(route);
  });
}

String? _validatedNotificationRoute(String payload) {
  final route = payload.trim();
  if (route.isEmpty || !route.startsWith('/')) {
    return null;
  }
  final uri = Uri.tryParse(route);
  if (uri == null || uri.hasFragment) {
    return null;
  }
  const allowedPrefixes = [
    '/maintenance',
    '/notifications',
    '/assets',
    '/calendar',
    '/search',
    '/settings',
    '/account',
    '/backup',
    '/trash',
    '/statistics',
    '/more',
    '/permissions/setup',
  ];
  if (!allowedPrefixes.any((prefix) => uri.path.startsWith(prefix))) {
    return null;
  }
  return uri.toString();
}

Future<void> _removeUnsupportedCloudSession(
  SupabaseClient? client,
  AppDatabase database,
) async {
  final session = client?.auth.currentSession;
  if (session == null) return;
  final providers = {
    for (final identity in session.user.identities ?? const <UserIdentity>[])
      identity.provider,
    if (session.user.appMetadata['provider'] case final String provider)
      provider,
  };
  if (providers.contains('google')) return;

  final store = LocalSyncStore(database);
  if (!await store.isDomainDataPristine()) {
    await ZipBackupService(database)
        .exportBackup(trigger: BackupTrigger.preRestore);
  }
  await client!.auth.signOut(scope: SignOutScope.local);
  await store.clearBinding();
}

class _DeferredOwntendBootstrap extends StatefulWidget {
  const _DeferredOwntendBootstrap({
    required this.database,
    required this.config,
    required this.elapsedBeforeFirstFrame,
  });

  final AppDatabase database;
  final AppConfig config;
  final Duration elapsedBeforeFirstFrame;

  @override
  State<_DeferredOwntendBootstrap> createState() =>
      _DeferredOwntendBootstrapState();
}

class _DeferredOwntendBootstrapState extends State<_DeferredOwntendBootstrap> {
  SupabaseClient? _supabaseClient;
  Object? _accountCleanupRecoveryFailure;
  bool _accountCleanupRetrying = false;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      AppLogger.info(
        'startup_first_frame',
        fields: {'elapsed_ms': widget.elapsedBeforeFirstFrame.inMilliseconds},
      );
      unawaited(_initializeAfterFirstFrame());
    });
  }

  Future<bool> _resumePendingAccountCleanup() async {
    try {
      final resumed =
          await LocalAccountDataCleaner(LocalSyncStore(widget.database))
              .resumePendingCleanup(
                additionalCleanup: (accountId) async {
                  await const OfflineCreationDraftStore().clearForAccount(
                    accountId,
                  );
                  await TaskCreationOperationStore(
                    storage: const FlutterSecureStorage(),
                  ).clearOperationsForAccount(accountId);
                },
              );
      if (resumed) AppLogger.info('account_deletion_local_cleanup_resumed');
      if (mounted && _accountCleanupRecoveryFailure != null) {
        setState(() => _accountCleanupRecoveryFailure = null);
      }
      return true;
    } on Object catch (error) {
      AppLogger.warning(
        'account_deletion_local_cleanup_resume_blocked',
        error: error,
      );
      if (mounted) {
        setState(() => _accountCleanupRecoveryFailure = error);
      }
      return false;
    }
  }

  Future<void> _retryPendingAccountCleanup() async {
    if (_accountCleanupRetrying) return;
    setState(() => _accountCleanupRetrying = true);
    try {
      await _initializeAfterFirstFrame();
    } finally {
      if (mounted) {
        setState(() => _accountCleanupRetrying = false);
      }
    }
  }

  Future<void> _initializeAfterFirstFrame() async {
    final deviceLanguage = _supportedDeviceLanguage(
      WidgetsBinding.instance.platformDispatcher.locale,
    );
    initializeRestoreForegroundService(localeCode: deviceLanguage.name);
    if (!await _resumePendingAccountCleanup()) return;
    try {
      final support = await getApplicationSupportDirectory();
      final diagnosticStore = AppDiagnosticFileStore(
        Directory(p.join(support.path, 'diagnostics')),
      );
      await diagnosticStore.initialize();
      AppDiagnosticRuntime.fileStore = diagnosticStore;
      unawaited(
        DiagnosticExportService(fileStore: diagnosticStore).cleanupExpired(),
      );
    } on Object catch (error) {
      AppLogger.warning('startup_diagnostics', error: error);
    }

    final cloud = SupabaseBootstrap.initialize(widget.config);
    final locale = DriftSettingsRepository(widget.database)
        .appLocalePreference();

    SupabaseClient? client;
    try {
      client = await cloud;
    } on Object catch (error) {
      AppLogger.warning('startup_cloud_initialization', error: error);
    }

    var restoreLanguage = deviceLanguage;
    try {
      final restorePreference = await locale;
      restoreLanguage = restorePreference.isExplicit
          ? restorePreference.language
          : deviceLanguage;
    } on Object catch (error) {
      AppLogger.warning('startup_locale_preference', error: error);
    }
    if (restoreLanguage != deviceLanguage) {
      initializeRestoreForegroundService(localeCode: restoreLanguage.name);
    }

    if (client != null) {
      try {
        await _removeUnsupportedCloudSession(client, widget.database);
      } on Object catch (error) {
        AppLogger.warning('unsupported_cloud_session_cleanup', error: error);
      }
    }
    if (!mounted) return;
    setState(() {
      _supabaseClient = client;
      _ready = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_accountCleanupRecoveryFailure != null) {
      return OwntendStartupFailure(
        accountCleanupBlocked: true,
        onRetry: _accountCleanupRetrying ? null : _retryPendingAccountCleanup,
      );
    }
    if (!_ready) {
      return const OwntendStartupSurface(
        key: ValueKey('deferred-startup-loading'),
      );
    }
    return OwntendBootstrap(
      database: widget.database,
      appConfig: widget.config,
      supabaseClient: _supabaseClient,
    );
  }
}

class OwntendStartupFailure extends StatelessWidget {
  const OwntendStartupFailure({
    this.cloudUnavailable = false,
    this.accountCleanupBlocked = false,
    this.onRetry,
    super.key,
  });

  final bool cloudUnavailable;
  final bool accountCleanupBlocked;
  final Future<void> Function()? onRetry;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Owntend',
      debugShowCheckedModeBanner: false,
      locale: Locale(
        _supportedDeviceLanguage(
          WidgetsBinding.instance.platformDispatcher.locale,
        ).name,
      ),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: OwntendTheme.light(),
      home: Builder(
        builder: (context) => Scaffold(
          body: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.warning_amber_rounded, size: 48),
                      const SizedBox(height: 16),
                      Text(
                        accountCleanupBlocked
                            ? context.l10n.accountDeletionFailed
                            : cloudUnavailable
                            ? context
                                  .l10n
                                  .cloudServicesAreUnavailablePleaseTryAgainLater
                            : context.l10n.thisBuildIsNotConfiguredCorrectly,
                        textAlign: TextAlign.center,
                      ),
                      if (accountCleanupBlocked) ...[
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: onRetry == null
                              ? null
                              : () => unawaited(onRetry!()),
                          child: Text(context.l10n.retry),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

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

class StartupFailure {
  const StartupFailure({
    required this.stage,
    required this.kind,
    this.operation,
    this.message,
    this.allowConnectionCheck = true,
  });

  final InitialHydrationStage stage;
  final StartupFailureKind kind;
  final String? operation;
  final String? message;
  final bool allowConnectionCheck;

  bool get timedOut => kind == StartupFailureKind.timedOut;
}

class StartupStepException implements Exception {
  const StartupStepException({
    required this.stage,
    required this.kind,
    required this.operation,
    required this.cause,
  });

  final InitialHydrationStage stage;
  final StartupFailureKind kind;
  final String operation;
  final Object cause;
}

class StartupBootstrapState {
  const StartupBootstrapState._({
    required this.kind,
    this.session,
    this.snapshot,
    this.status,
    this.canContinueOffline = false,
    this.offline = false,
    this.failure,
  });

  const StartupBootstrapState.checkingStoredSession()
    : this._(kind: StartupBootstrapKind.checkingStoredSession);

  const StartupBootstrapState.unauthenticated()
    : this._(kind: StartupBootstrapKind.unauthenticated);

  const StartupBootstrapState.authenticatedHydrating({
    required AuthSession session,
    required SyncStatus status,
    required bool canContinueOffline,
  }) : this._(
         kind: StartupBootstrapKind.authenticatedHydrating,
         session: session,
         status: status,
         canContinueOffline: canContinueOffline,
       );

  StartupBootstrapState.authenticatedReady({
    required InitialHomeSnapshot snapshot,
    bool offline = false,
  }) : this._(
         kind: StartupBootstrapKind.authenticatedReady,
         session: snapshot.session,
         snapshot: snapshot,
         offline: offline,
       );

  const StartupBootstrapState.startupFailed({
    required AuthSession session,
    required SyncStatus status,
    required bool canContinueOffline,
    required StartupFailure failure,
  }) : this._(
         kind: StartupBootstrapKind.startupFailed,
         session: session,
         status: status,
         canContinueOffline: canContinueOffline,
         failure: failure,
       );

  final StartupBootstrapKind kind;
  final AuthSession? session;
  final InitialHomeSnapshot? snapshot;
  final SyncStatus? status;
  final bool canContinueOffline;
  final bool offline;
  final StartupFailure? failure;

  bool get isHydrating =>
      kind == StartupBootstrapKind.authenticatedHydrating ||
      kind == StartupBootstrapKind.startupFailed;

  StartupBootstrapState withStatus(SyncStatus nextStatus) {
    return switch (kind) {
      StartupBootstrapKind.authenticatedHydrating =>
        StartupBootstrapState.authenticatedHydrating(
          session: session!,
          status: nextStatus,
          canContinueOffline: canContinueOffline,
        ),
      StartupBootstrapKind.startupFailed => StartupBootstrapState.startupFailed(
        session: session!,
        status: nextStatus,
        canContinueOffline: canContinueOffline,
        failure:
            failure ??
            const StartupFailure(
              stage: InitialHydrationStage.connecting,
              kind: StartupFailureKind.failed,
            ),
      ),
      _ => this,
    };
  }
}

class InitialHomeSnapshot {
  const InitialHomeSnapshot({
    required this.session,
    required this.profile,
    required this.tasks,
    required this.assets,
    required this.rooms,
    required this.backupState,
    required this.unreadNotifications,
    required this.syncStatus,
    required this.loadedAt,
    this.homeLocation,
    this.weather,
    this.avatarProvider,
    this.offline = false,
  });

  final AuthSession session;
  final AppProfile profile;
  final List<TaskItem> tasks;
  final List<Asset> assets;
  final List<Room> rooms;
  final BackupState backupState;
  final int unreadNotifications;
  final HomeLocation? homeLocation;
  final WeatherSnapshot? weather;
  final SyncStatus syncStatus;
  final ImageProvider<Object>? avatarProvider;
  final DateTime loadedAt;
  final bool offline;

  InitialHomeSnapshot copyWithOffline(bool value) {
    return InitialHomeSnapshot(
      session: session,
      profile: profile,
      tasks: tasks,
      assets: assets,
      rooms: rooms,
      backupState: backupState,
      unreadNotifications: unreadNotifications,
      homeLocation: homeLocation,
      weather: weather,
      syncStatus: syncStatus,
      avatarProvider: avatarProvider,
      loadedAt: loadedAt,
      offline: value,
    );
  }
}

final startupRestoreTimeoutProvider = Provider<Duration>(
  (ref) => const Duration(seconds: 140),
);

final startupRestoreServiceStopperProvider = Provider<Future<void> Function()>(
  (ref) => stopRestoreForegroundService,
);

final startupBootstrapControllerProvider = Provider<StartupBootstrapController>(
  (ref) {
    final controller = StartupBootstrapController(ref);
    ref.onDispose(controller.dispose);
    return controller;
  },
);

class StartupBootstrapController {
  StartupBootstrapController(this._ref);

  static const _startupProviderTimeout = Duration(seconds: 4);
  static const _startupAvatarTimeout = Duration(seconds: 2);
  static const _avatarDownloadTimeout = Duration(milliseconds: 1400);
  static const _restoreServiceStopTimeout = Duration(seconds: 2);

  final Ref _ref;
  final _state = ValueNotifier<StartupBootstrapState>(
    const StartupBootstrapState.checkingStoredSession(),
  );

  ValueListenable<StartupBootstrapState> get stateListenable => _state;

  StartupBootstrapState get currentState => _state.value;

  var _startupGeneration = 0;
  var _routeHomeAfterReady = false;
  var _disposed = false;
  var _navigationCompleted = false;
  String? _activeUserId;
  Future<void>? _activeBootstrap;
  InitialHomeSnapshot? _offlineSnapshotCandidate;
  Future<void>? _restoreServiceStopWork;

  void dispose() {
    _disposed = true;
    _startupGeneration += 1;
    _offlineSnapshotCandidate = null;
    _state.dispose();
  }

  void handleAuthValue(AsyncValue<AuthStateChange> next) {
    final authState = next.value;
    if (authState != null) {
      unawaited(handleAuthState(authState));
    } else if (next.hasError) {
      unawaited(_bootstrapFromRepositorySession());
    }
  }

  void handleSyncStatusValue(AsyncValue<SyncStatus> next) {
    final status = next.value;
    if (status == null) return;
    final current = _state.value;
    if (!current.isHydrating) return;
    _publishStartupState(
      current.withStatus(_mergeStartupSyncStatus(current.status, status)),
    );
  }

  Future<void> handleAuthState(AuthStateChange state) async {
    final session = state.session;
    if (session == null) {
      await _transitionSignedOut();
      return;
    }

    final current = _state.value;
    final alreadyReadyForUser =
        current.kind == StartupBootstrapKind.authenticatedReady &&
        current.session?.userId == session.userId;
    if (state.event == AuthEventType.signedIn && !alreadyReadyForUser) {
      _routeHomeAfterReady = true;
      _navigationCompleted = false;
    }

    if (_activeBootstrap != null && _activeUserId == session.userId) {
      AppLogger.info('startup_restore_reused_active');
      return _activeBootstrap;
    }

    if (current.session?.userId == session.userId &&
        current.kind == StartupBootstrapKind.authenticatedReady) {
      _goHomeAfterReadyIfRequested(session);
      return;
    }

    if (current.session?.userId == session.userId &&
        current.kind == StartupBootstrapKind.startupFailed) {
      AppLogger.info('startup_restore_waiting_for_retry');
      return;
    }

    if (state.event != AuthEventType.signedIn &&
        current.session?.userId == session.userId &&
        current.kind != StartupBootstrapKind.checkingStoredSession) {
      return;
    }

    await _bootstrapForSession(session);
  }

  Future<void> retryStartupRestore() async {
    final session =
        _state.value.session ??
        _ref.read(authRepositoryProvider)?.currentSession;
    if (session == null) {
      _publishStartupState(const StartupBootstrapState.unauthenticated());
      return;
    }
    if (_activeBootstrap != null && _activeUserId == session.userId) {
      AppLogger.info('startup_restore_retry_reused_active');
      return _activeBootstrap;
    }
    AppLogger.info('startup_restore_retry');
    await _bootstrapForSession(session, forceRestore: true);
  }

  Future<void> continueStartupOffline() async {
    final session = _state.value.session;
    if (session == null) return;
    final snapshot = _offlineSnapshotCandidate;
    if (snapshot == null || snapshot.session.userId != session.userId) {
      return;
    }

    final generation = ++_startupGeneration;
    if (!_isCurrentStartup(generation, session)) return;
    _ref.read(initialHomeSnapshotProvider).value = snapshot;
    _publishReady(snapshot, offline: true);
  }

  Future<void> signOutFromStartup() async {
    final session = _state.value.session;
    _startupGeneration += 1;
    _activeBootstrap = null;
    _activeUserId = null;
    _routeHomeAfterReady = false;
    _navigationCompleted = false;
    _offlineSnapshotCandidate = null;
    try {
      if (session != null) {
        await _ref
            .read(notificationSchedulerProvider)
            .clearAllScheduledReminders();
        await _ref.read(notificationInboxRepositoryProvider).clear();
        await _ref
            .read(localSyncStoreProvider)
            ?.clearPartialBootstrapForUser(session.userId);
      }
      await _ref.read(authRepositoryProvider)?.signOut();
    } on Object catch (error) {
      AppLogger.warning('startup_sign_out', error: error);
    }
    _ref.read(initialHomeSnapshotProvider).value = null;
    _publishStartupState(const StartupBootstrapState.unauthenticated());
    _scheduleRestoreServiceStop();
  }

  Future<void> _bootstrapFromRepositorySession() async {
    final session = _ref.read(authRepositoryProvider)?.currentSession;
    if (session == null) {
      await _transitionSignedOut();
      return;
    }
    await _bootstrapForSession(session);
  }

  Future<void> _transitionSignedOut() async {
    _startupGeneration += 1;
    _activeBootstrap = null;
    _activeUserId = null;
    _routeHomeAfterReady = false;
    _navigationCompleted = false;
    _offlineSnapshotCandidate = null;
    unawaited(
      _ref.read(notificationSchedulerProvider).clearAllScheduledReminders(),
    );
    unawaited(_ref.read(notificationInboxRepositoryProvider).clear());
    _ref.read(initialHomeSnapshotProvider).value = null;
    _publishStartupState(const StartupBootstrapState.unauthenticated());
    _scheduleRestoreServiceStop();
  }

  Future<void> _bootstrapForSession(
    AuthSession session, {
    bool forceRestore = false,
  }) {
    if (_activeBootstrap != null && _activeUserId == session.userId) {
      AppLogger.info('startup_restore_reused_active');
      return _activeBootstrap!;
    }

    final generation = ++_startupGeneration;
    _activeUserId = session.userId;
    final work =
        Future<void>.microtask(
          () => _runBootstrapForSession(
            session,
            generation: generation,
            forceRestore: forceRestore,
          ),
        ).whenComplete(() {
          if (generation == _startupGeneration) {
            _activeBootstrap = null;
            _activeUserId = null;
          }
        });
    _activeBootstrap = work;
    return work;
  }

  Future<void> _runBootstrapForSession(
    AuthSession session, {
    required int generation,
    required bool forceRestore,
  }) async {
    AppLogger.info('startup_restore_start');
    final previousFailure = _state.value.failure;
    final store = _ref.read(localSyncStoreProvider);
    if (_state.value.session?.userId != session.userId) {
      _offlineSnapshotCandidate = null;
    }
    _offlineSnapshotCandidate = await _verifiedOfflineSnapshot(
      session,
      store: store,
    );
    if (!_isCurrentStartup(generation, session)) return;

    final offlineSnapshot = _offlineSnapshotCandidate;
    final resumeValidatedFinalization =
        forceRestore &&
        previousFailure?.stage == InitialHydrationStage.finalizing &&
        previousFailure?.allowConnectionCheck == false &&
        offlineSnapshot != null;
    if ((!forceRestore || resumeValidatedFinalization) &&
        offlineSnapshot != null) {
      _ref.read(initialHomeSnapshotProvider).value = offlineSnapshot;
      _publishReady(
        offlineSnapshot.copyWithOffline(false),
        refreshCloudAfterReady: !resumeValidatedFinalization,
      );
      return;
    }

    final startingStatus = _hydrationStatusFor(
      _ref.read(syncStatusProvider).value,
      _syntheticStartupStatus(RestoreRunState.running),
    );
    _publishStartupState(
      StartupBootstrapState.authenticatedHydrating(
        session: session,
        status: startingStatus,
        canContinueOffline: offlineSnapshot != null,
      ),
    );

    try {
      await _runCloudRestore(generation);
      if (!_isCurrentStartup(generation, session)) return;
      final snapshot = await _buildInitialHomeSnapshot(
        session,
        generation: generation,
      );
      if (!_isCurrentStartup(generation, session)) return;
      _ref.read(initialHomeSnapshotProvider).value = snapshot;
      _publishReady(snapshot);
    } on Object catch (error) {
      if (!_isCurrentStartup(generation, session)) return;
      final observedFailureStatus = await _guardStartup(
        'failed sync status',
        () => _ref.read(cloudSyncRepositoryProvider).status(),
        timeout: _startupProviderTimeout,
      );
      if (!_isCurrentStartup(generation, session)) return;
      _offlineSnapshotCandidate ??= await _verifiedOfflineSnapshot(
        session,
        store: store,
      );
      if (!_isCurrentStartup(generation, session)) return;
      final failureContextStatus = observedFailureStatus == null
          ? _state.value.status
          : _mergeStartupSyncStatus(_state.value.status, observedFailureStatus);
      final failure = _startupFailureFor(error, failureContextStatus);
      final fallback = _syntheticStartupStatus(
        RestoreRunState.failed,
        phase: failure.allowConnectionCheck
            ? SyncPhase.offline
            : SyncPhase.error,
        message: failure.message,
        stage: failure.stage,
        failure: failure.message,
      );
      final failureStatus =
          observedFailureStatus != null &&
              const {
                SyncPhase.error,
                SyncPhase.offline,
                SyncPhase.blocked,
              }.contains(observedFailureStatus.phase)
          ? observedFailureStatus
          : fallback;
      final status = _mergeStartupSyncStatus(
        _state.value.status,
        failureStatus,
      );
      _publishStartupState(
        StartupBootstrapState.startupFailed(
          session: session,
          status: status,
          canContinueOffline: _offlineSnapshotCandidate != null,
          failure: failure,
        ),
      );
      AppLogger.warning('startup_restore_failed', error: error);
    }
  }

  Future<InitialHomeSnapshot?> _verifiedOfflineSnapshot(
    AuthSession session, {
    required LocalSyncStore? store,
  }) async {
    if (store == null ||
        !await store.hasCompleteSnapshotForUser(session.userId)) {
      return null;
    }
    try {
      return await _buildInitialHomeSnapshot(session, offline: true);
    } on Object catch (error) {
      AppLogger.warning('startup_cached_snapshot_invalid', error: error);
      return null;
    }
  }

  Future<InitialHomeSnapshot> _buildInitialHomeSnapshot(
    AuthSession session, {
    bool offline = false,
    int? generation,
  }) async {
    final profileFuture = _requiredStartup<AppProfile>(
      'load_profile',
      () => _ref.read(settingsRepositoryProvider).profile(),
    );
    final tasksFuture = _requiredStartup<List<TaskItem>>(
      'load_tasks',
      () => _ref.read(maintenanceRepositoryProvider).listTasks(),
    );
    final assetsFuture = _requiredStartup<List<Asset>>(
      'load_assets',
      () => _ref.read(assetRepositoryProvider).listAssets(),
    );
    final roomsFuture = _requiredStartup<List<Room>>(
      'load_rooms',
      () => _ref.read(assetRepositoryProvider).listRooms(),
    );
    final profile = await profileFuture;
    final tasks = await tasksFuture;
    final rawAssets = await assetsFuture;
    final rooms = await roomsFuture;
    final roomIds = {for (final room in rooms) room.id};
    final assets = <Asset>[];
    for (final asset in rawAssets) {
      if (roomIds.contains(asset.roomId)) {
        assets.add(asset);
      } else {
        AppLogger.warning(
          'startup_orphaned_asset_sanitized',
          fields: {'asset_id': asset.id, 'room_id': asset.roomId},
        );
      }
    }
    await _criticalStartup<void>(
      'validate_first_home_frame',
      () async {
        if (generation != null && !_isCurrentStartup(generation, session)) {
          throw StateError('A newer startup attempt replaced this one.');
        }
      },
      timeout: _startupProviderTimeout,
      stage: InitialHydrationStage.finalizing,
    );
    final backupState =
        _ref.read(backupStateProvider).value ?? const BackupState();
    final unreadNotifications =
        _ref.read(unreadNotificationsProvider).value ?? 0;
    final homeLocation = _ref.read(homeLocationProvider).value;
    final weather = _ref.read(weatherProvider).value;
    final syncStatus =
        _ref.read(syncStatusProvider).value ??
        const SyncStatus(phase: SyncPhase.ready);
    final avatarProvider = await _guardStartup<ImageProvider<Object>?>(
      'profile_avatar',
      () => _resolveStartupAvatar(profile, session),
      timeout: _startupAvatarTimeout,
    );
    return InitialHomeSnapshot(
      session: session,
      profile: profile,
      tasks: List.unmodifiable(tasks),
      assets: List.unmodifiable(assets),
      rooms: List.unmodifiable(rooms),
      backupState: backupState,
      unreadNotifications: unreadNotifications,
      homeLocation: homeLocation,
      weather: weather,
      syncStatus: syncStatus,
      avatarProvider: avatarProvider,
      loadedAt: DateTime.now(),
      offline: offline,
    );
  }

  Future<void> _runCloudRestore(int generation) async {
    final repository = _ref.read(cloudSyncRepositoryProvider);
    if (repository is! SyncCoordinator) {
      return _criticalStartup<void>(
        'cloud_restore',
        repository.enable,
        timeout: _ref.read(startupRestoreTimeoutProvider),
        stage: InitialHydrationStage.connecting,
      );
    }
    final stopwatch = Stopwatch()..start();
    AppLogger.info(
      'startup_step_start_cloud_restore',
      fields: {'attempt': generation},
    );
    final cloudRestoreTimeout = _ref.read(startupRestoreTimeoutProvider);
    try {
      await repository.enable().timeout(cloudRestoreTimeout);
      AppLogger.info(
        'startup_step_completed_cloud_restore',
        fields: {
          'attempt': generation,
          'elapsed_ms': stopwatch.elapsedMilliseconds,
        },
      );
    } on TimeoutException catch (error) {
      AppLogger.warning(
        'startup_step_timeout_cloud_restore',
        error: error,
        fields: {
          'attempt': generation,
          'elapsed_ms': stopwatch.elapsedMilliseconds,
          'timeout_ms': cloudRestoreTimeout.inMilliseconds,
        },
      );
      throw StartupStepException(
        stage: InitialHydrationStage.connecting,
        kind: StartupFailureKind.timedOut,
        operation: 'cloud_restore',
        cause: TimeoutException(
          'Cloud restore timed out.',
          cloudRestoreTimeout,
        ),
      );
    } on Object catch (error) {
      AppLogger.warning(
        'startup_step_failed_cloud_restore',
        error: error,
        fields: {
          'attempt': generation,
          'elapsed_ms': stopwatch.elapsedMilliseconds,
        },
      );
      throw StartupStepException(
        stage: InitialHydrationStage.connecting,
        kind: StartupFailureKind.failed,
        operation: 'cloud_restore',
        cause: error,
      );
    }
  }

  Future<T> _requiredStartup<T>(String label, Future<T> Function() operation) {
    return _criticalStartup(
      label,
      operation,
      timeout: _startupProviderTimeout,
      stage: InitialHydrationStage.finalizing,
    );
  }

  Future<T> _criticalStartup<T>(
    String label,
    Future<T> Function() operation, {
    required Duration timeout,
    required InitialHydrationStage stage,
  }) async {
    final stopwatch = Stopwatch()..start();
    AppLogger.info(
      'startup_step_start_${label.replaceAll(' ', '_')}',
      fields: {
        'attempt': _startupGeneration,
        'timeout_ms': timeout.inMilliseconds,
      },
    );
    try {
      final value = await operation().timeout(timeout);
      AppLogger.info(
        'startup_step_completed_${label.replaceAll(' ', '_')}',
        fields: {
          'attempt': _startupGeneration,
          'elapsed_ms': stopwatch.elapsedMilliseconds,
        },
      );
      return value;
    } on TimeoutException catch (error) {
      AppLogger.warning(
        'startup_step_timeout_${label.replaceAll(' ', '_')}',
        error: error,
        fields: {
          'attempt': _startupGeneration,
          'elapsed_ms': stopwatch.elapsedMilliseconds,
          'timeout_ms': timeout.inMilliseconds,
        },
      );
      throw StartupStepException(
        stage: stage,
        kind: StartupFailureKind.timedOut,
        operation: label,
        cause: TimeoutException('Startup step timed out.', timeout),
      );
    } on Object catch (error) {
      AppLogger.warning(
        'startup_step_failed_${label.replaceAll(' ', '_')}',
        error: error,
        fields: {
          'attempt': _startupGeneration,
          'elapsed_ms': stopwatch.elapsedMilliseconds,
        },
      );
      throw StartupStepException(
        stage: stage,
        kind: StartupFailureKind.failed,
        operation: label,
        cause: error,
      );
    }
  }

  Future<T?> _guardStartup<T>(
    String label,
    Future<T> Function() operation, {
    required Duration timeout,
  }) async {
    final stopwatch = Stopwatch()..start();
    AppLogger.info(
      'startup_optional_start_${label.replaceAll(' ', '_')}',
      fields: {
        'attempt': _startupGeneration,
        'timeout_ms': timeout.inMilliseconds,
      },
    );
    try {
      final result = await operation().timeout(timeout);
      AppLogger.info(
        'startup_optional_completed_${label.replaceAll(' ', '_')}',
        fields: {
          'attempt': _startupGeneration,
          'elapsed_ms': stopwatch.elapsedMilliseconds,
        },
      );
      return result;
    } on Object catch (error) {
      AppLogger.warning(
        'startup_optional_failed_${label.replaceAll(' ', '_')}',
        error: error,
        fields: {
          'attempt': _startupGeneration,
          'elapsed_ms': stopwatch.elapsedMilliseconds,
        },
      );
      return null;
    }
  }

  Future<ImageProvider<Object>?> _resolveStartupAvatar(
    AppProfile profile,
    AuthSession session,
  ) async {
    final localPath = profile.avatarPath?.trim();
    if (localPath != null && localPath.isNotEmpty) {
      final file = File(localPath);
      if (await file.exists()) {
        final provider = FileImage(file);
        if (await _warmImageProvider(provider)) return provider;
      }
    }
    final avatarUrl = session.avatarUrl?.trim();
    if (avatarUrl == null || avatarUrl.isEmpty) {
      return null;
    }
    final cached = await _cachedAvatarFile(session.userId, avatarUrl);
    if (await cached.exists()) {
      final provider = FileImage(cached);
      if (await _warmImageProvider(provider)) return provider;
    }
    try {
      final response = await http
          .get(Uri.parse(avatarUrl))
          .timeout(_avatarDownloadTimeout);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        await cached.parent.create(recursive: true);
        await cached.writeAsBytes(response.bodyBytes, flush: true);
        final provider = FileImage(cached);
        if (await _warmImageProvider(provider)) return provider;
      }
    } on Object catch (error) {
      AppLogger.warning('startup_avatar_download', error: error);
    }
    return null;
  }

  Future<File> _cachedAvatarFile(String userId, String avatarUrl) async {
    final digest = sha1.convert(utf8.encode(userId)).toString();
    final directory = await getApplicationCacheDirectory();
    return File(p.join(directory.path, 'avatars', '$digest.avatar'));
  }

  Future<bool> _warmImageProvider(ImageProvider<Object> provider) async {
    final stream = provider.resolve(ImageConfiguration.empty);
    final completer = Completer<bool>();
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (image, synchronousCall) {
        if (!completer.isCompleted) completer.complete(true);
      },
      onError: (Object error, StackTrace? stackTrace) {
        if (!completer.isCompleted) completer.complete(false);
      },
    );
    stream.addListener(listener);
    try {
      return await completer.future.timeout(
        _avatarDownloadTimeout,
        onTimeout: () => false,
      );
    } finally {
      stream.removeListener(listener);
    }
  }

  StartupFailure _startupFailureFor(Object error, SyncStatus? status) {
    final progress = status?.initialHydrationProgress;
    final stepError = error is StartupStepException ? error : null;
    final errorStage = stepError?.stage ?? InitialHydrationStage.finalizing;
    final observedStage = progress?.stage;
    final stage =
        observedStage != null && observedStage.index > errorStage.index
        ? observedStage
        : errorStage;
    final statusFailed =
        status != null &&
        const {
          SyncPhase.error,
          SyncPhase.offline,
          SyncPhase.blocked,
          SyncPhase.signedOut,
        }.contains(status.phase);
    final detail = progress?.failure?.trim().isNotEmpty == true
        ? progress!.failure!.trim()
        : statusFailed && status.message?.trim().isNotEmpty == true
        ? status.message!.trim()
        : null;
    final finalizationOperation = stage == InitialHydrationStage.finalizing
        ? _finalizationOperationFromDetail(detail)
        : null;
    final kind =
        stepError?.kind == StartupFailureKind.timedOut ||
            detail?.toLowerCase().contains('timed out') == true
        ? StartupFailureKind.timedOut
        : StartupFailureKind.failed;
    return StartupFailure(
      stage: stage,
      kind: kind,
      operation: finalizationOperation ?? stepError?.operation,
      message: detail,
      allowConnectionCheck:
          stage != InitialHydrationStage.finalizing &&
          (status?.phase == SyncPhase.offline ||
              stepError?.operation == 'cloud_restore'),
    );
  }

  String? _finalizationOperationFromDetail(String? detail) {
    final normalized = detail?.toLowerCase() ?? '';
    if (normalized.contains('commit local home snapshot')) {
      return 'commit_local_home_snapshot';
    }
    if (normalized.contains('validate local home')) {
      return 'validate_local_home';
    }
    return null;
  }

  void _schedulePostReadySync({required bool refreshCloud}) {
    scheduleMicrotask(() async {
      await WidgetsBinding.instance.endOfFrame;
      if (_disposed) return;
      _ref.read(syncCoordinatorProvider)?.startPostReadyWork();
      try {
        if (refreshCloud) {
          await _ref.read(cloudSyncRepositoryProvider).syncNow();
        }
      } on Object {
        // The ready Home snapshot remains authoritative while background sync
        // reports its own status through syncStatusProvider.
      }
      final location = _ref.read(homeLocationProvider).value;
      if (location != null) {
        try {
          await _ref.read(weatherRepositoryProvider).refreshWeather();
        } on Object catch (error) {
          AppLogger.warning('startup_post_ready_weather_failed', error: error);
        }
      }
    });
  }

  void _scheduleRestoreServiceStop() {
    if (_restoreServiceStopWork != null) return;
    final completion = Completer<void>();
    _restoreServiceStopWork = completion.future;
    scheduleMicrotask(() async {
      try {
        await _ref
            .read(startupRestoreServiceStopperProvider)()
            .timeout(_restoreServiceStopTimeout);
      } on Object catch (error) {
        AppLogger.warning('startup_restore_service_stop', error: error);
      } finally {
        completion.complete();
        if (identical(_restoreServiceStopWork, completion.future)) {
          _restoreServiceStopWork = null;
        }
      }
    });
  }

  bool _isCurrentStartup(int generation, AuthSession session) {
    return !_disposed &&
        generation == _startupGeneration &&
        _isCurrentSession(session);
  }

  bool _isCurrentSession(AuthSession session) {
    final currentSession =
        _ref.read(authSessionProvider).value ??
        _ref.read(authRepositoryProvider)?.currentSession;
    return currentSession?.userId == session.userId;
  }

  void _publishReady(
    InitialHomeSnapshot snapshot, {
    bool offline = false,
    bool refreshCloudAfterReady = false,
  }) {
    final current = _state.value;
    if (current.kind == StartupBootstrapKind.authenticatedReady &&
        current.session?.userId == snapshot.session.userId) {
      _goHomeAfterReadyIfRequested(snapshot.session);
      return;
    }
    final stopwatch = Stopwatch()..start();
    AppLogger.info(
      'startup_finalization_publish_ready_start',
      fields: {'attempt': _startupGeneration},
    );
    AppLogger.info('startup_restore_completed');
    _publishStartupState(
      StartupBootstrapState.authenticatedReady(
        snapshot: snapshot,
        offline: offline,
      ),
    );
    AppLogger.info(
      'startup_finalization_publish_ready_completed',
      fields: {
        'attempt': _startupGeneration,
        'elapsed_ms': stopwatch.elapsedMilliseconds,
      },
    );
    _goHomeAfterReadyIfRequested(snapshot.session);
    unawaited(
      _ref.read(settingsRepositoryProvider).setOnboardingCompleted(true),
    );
    if (!offline) {
      _schedulePostReadySync(refreshCloud: refreshCloudAfterReady);
    }
    _scheduleRestoreServiceStop();
  }

  void _publishStartupState(StartupBootstrapState state) {
    if (_disposed) return;
    _state.value = state;
  }

  void _goHomeAfterReadyIfRequested(AuthSession session) {
    if (!_routeHomeAfterReady || _navigationCompleted) return;
    _routeHomeAfterReady = false;
    _navigationCompleted = true;
    AppLogger.info(
      'startup_finalization_navigation_scheduled',
      fields: {'attempt': _startupGeneration},
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_disposed || !_isCurrentSession(session)) return;
      _ref.read(routerProvider).go('/');
      AppLogger.info(
        'startup_navigation_home',
        fields: {'attempt': _startupGeneration},
      );
    });
  }
}
