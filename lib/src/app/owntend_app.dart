import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:sentry_flutter/sentry_flutter.dart';

import '../core/config/app_config.dart';
import '../core/database/app_database.dart';
import '../core/domain/models.dart';
import '../core/observability/observability_config.dart';
import '../core/observability/sentry_bootstrap.dart';
import 'app_dependencies.dart';
export 'app_dependencies.dart';
import '../core/services/feedback_messenger.dart';
export '../core/data/repositories.dart';
import '../core/services/automatic_backup_coordinator.dart';
import '../core/services/restore_journal.dart';
import '../core/sync/local_sync_store.dart';
import '../core/sync/sync_bootstrap.dart';
import '../core/sync/sync_contracts.dart';
import '../core/utils/redacting_logger.dart';
export '../features/backup/presentation/backup_screen.dart';
export '../features/assets/presentation/assets_presentation.dart';
export '../features/dashboard/presentation/dashboard_presentation.dart';
import '../features/monetization/monetization.dart';
export '../features/monetization/presentation/monetization_presentation.dart';
export '../features/rooms/presentation/room_dialogs.dart';
export '../features/rooms/presentation/rooms_presentation.dart';
export '../features/maintenance/presentation/daily_completion_reward_sheet.dart';
export '../features/maintenance/presentation/complete_task_dialog.dart';
export '../features/maintenance/presentation/task_actions.dart';
export '../features/maintenance/presentation/maintenance_dialogs.dart';
export '../features/maintenance/presentation/maintenance_presentation.dart';
export '../features/more/presentation/more_screen.dart';
export '../features/search/presentation/search_screen.dart';
export '../features/settings/presentation/location_picker_sheet.dart';
export '../features/settings/presentation/settings_screen.dart';
export '../features/notifications/presentation/notifications_screen.dart';
export '../features/statistics/presentation/statistics_screen.dart';
export '../features/trash/presentation/trash_screen.dart';
import '../features/navigation/navigation_presentation.dart';
export '../features/navigation/navigation_presentation.dart';
import '../features/startup/presentation/startup_route_host.dart';
import '../features/startup/presentation/startup_presentation.dart';
export '../features/startup/presentation/startup_presentation.dart';
export '../features/startup/domain/initial_home_snapshot.dart';
import '../ui/app_theme.dart';
import 'app_orientation.dart';
export 'app_orientation.dart';
import '../ui/full_canvas_system_ui.dart';
import '../ui/motion.dart';
import '../ui/presentation_formatters.dart';
import '../../owntend_animated_splash_screen.dart';

import 'package:owntend/l10n/app_localizations.dart';
import 'package:owntend/l10n/app_localizations_ext.dart';

Future<void> runOwntendApplication() async {
  final startupClock = Stopwatch()..start();
  SentryWidgetsFlutterBinding.ensureInitialized();
  await configurePreferredOrientations();
  late final AppConfig config;
  try {
    config = AppConfig.fromEnvironment();
  } on AppConfigException catch (error, stackTrace) {
    AppLogger.warning(
      'startup_configuration',
      error: error,
      stackTrace: stackTrace,
    );
    _runOwntendProcess(const OwntendStartupFailure());
    return;
  }

  Future<void> runOwntend() async {
    final database = AppDatabase();
    final restoreJournalStore = RestoreJournalStore();
    _runOwntendProcess(
      _RestoreRecoveryGate(
        recover: () => RestoreRecoveryCoordinator(
          journalStore: restoreJournalStore,
          localSyncStore: LocalSyncStore(database),
        ).recover(),
        child: DeferredOwntendBootstrap(
          database: database,
          config: config,
          elapsedBeforeFirstFrame: startupClock.elapsed,
          appBuilder: (startupTheme) => OwntendApp(startupTheme: startupTheme),
        ),
      ),
    );
  }

  try {
    final observability = await ObservabilityConfig.fromAppConfig(config);
    if (!observability.enabled) {
      await runOwntend();
      return;
    }
    await initializeOwntendSentry(config: observability, appRunner: runOwntend);
  } on Object catch (error, stackTrace) {
    AppLogger.warning(
      'sentry_configuration_failed',
      error: error,
      stackTrace: stackTrace,
    );
    await runOwntend();
  }
}

void _runOwntendProcess(Widget child) {
  runApp(OwntendProcessSplash(child: child));
}

class _RestoreRecoveryGate extends StatefulWidget {
  const _RestoreRecoveryGate({required this.recover, required this.child});

  final Future<void> Function() recover;
  final Widget child;

  @override
  State<_RestoreRecoveryGate> createState() => _RestoreRecoveryGateState();
}

class _RestoreRecoveryGateState extends State<_RestoreRecoveryGate> {
  Object? _failure;
  bool _retrying = false;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_recover()));
  }

  Future<void> _recover() async {
    try {
      await widget.recover();
      if (!mounted) return;
      setState(() {
        _failure = null;
        _ready = true;
      });
    } on Object catch (error, stackTrace) {
      AppLogger.warning(
        'startup_restore_recovery_blocked',
        error: error,
        stackTrace: stackTrace,
      );
      if (!mounted) return;
      setState(() => _failure = error);
    }
  }

  Future<void> _retry() async {
    if (_retrying) return;
    setState(() => _retrying = true);
    try {
      await _recover();
    } finally {
      if (mounted) setState(() => _retrying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_ready) return widget.child;
    if (_failure == null) {
      return const OwntendStartupSurface(
        key: ValueKey('restore-recovery-loading'),
      );
    }

    final deviceLocale = WidgetsBinding.instance.platformDispatcher.locale;
    final locale = deviceLocale.languageCode == 'ar'
        ? const Locale('ar')
        : const Locale('en');
    return MaterialApp(
      title: 'Owntend',
      debugShowCheckedModeBanner: false,
      locale: locale,
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
                        context.l10n.recovery,
                        style: Theme.of(context).textTheme.headlineSmall,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        context.l10n.needsAttention,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: _retrying ? null : () => unawaited(_retry()),
                        child: Text(context.l10n.retry),
                      ),
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

class OwntendApp extends ConsumerStatefulWidget {
  const OwntendApp({this.startupTheme, super.key});

  final ThemeStartupSettings? startupTheme;

  @override
  ConsumerState<OwntendApp> createState() => _OwntendAppState();
}

class _OwntendAppState extends ConsumerState<OwntendApp>
    with WidgetsBindingObserver {
  Locale _deviceLocale = WidgetsBinding.instance.platformDispatcher.locale;
  late final StartupBootstrapController _startupController;
  late final AutomaticBackupCoordinator _automaticBackupCoordinator;
  String? _automaticBackupReadyUserId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final startup = ref.read(startupBootstrapControllerProvider);
    _startupController = startup;
    _automaticBackupCoordinator = AutomaticBackupCoordinator(
      backupRepositoryFactory: () => ref.read(backupRepositoryProvider),
      automaticStartEnabled: () => ref.read(backupAutoStartProvider),
    );
    startup.stateListenable.addListener(_handleAutomaticBackupStartupState);
    _handleAutomaticBackupStartupState();
    ref.listenManual(authStateProvider, (previous, next) {
      startup.handleAuthValue(next);
    }, fireImmediately: true);
    ref.listenManual(syncStatusProvider, (previous, next) {
      startup.handleSyncStatusValue(next);
    }, fireImmediately: true);
    ref.listenManual(streakRefreshProvider, (_, _) {});
  }

  void _handleAutomaticBackupStartupState() {
    final state = _startupController.currentState;
    final readyUserId = state.kind == StartupBootstrapKind.authenticatedReady
        ? state.session?.userId
        : null;
    if (readyUserId == null) {
      _automaticBackupReadyUserId = null;
      _automaticBackupCoordinator.reset();
      return;
    }
    if (_automaticBackupReadyUserId == readyUserId) return;
    _automaticBackupReadyUserId = readyUserId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final current = _startupController.currentState;
      if (current.kind != StartupBootstrapKind.authenticatedReady ||
          current.session?.userId != readyUserId) {
        return;
      }
      unawaited(_automaticBackupCoordinator.onPostReady());
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_automaticBackupCoordinator.onAppResumed());
    }
  }

  @override
  void didChangeLocales(List<Locale>? locales) {
    final next =
        locales?.firstOrNull ??
        WidgetsBinding.instance.platformDispatcher.locale;
    if (next == _deviceLocale) return;
    setState(() => _deviceLocale = next);
  }

  @override
  void dispose() {
    _startupController.stateListenable.removeListener(
      _handleAutomaticBackupStartupState,
    );
    _automaticBackupCoordinator.reset();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final localePreference =
        ref.watch(appLocalePreferenceProvider).value ??
        AppLocalePreference(
          language: AppLanguage.en,
          isExplicit: false,
          updatedAt: DateTime.fromMillisecondsSinceEpoch(0),
        );
    final appLanguage = localePreference.isExplicit
        ? localePreference.language
        : supportedDeviceLanguage(_deviceLocale);
    final startupTheme =
        widget.startupTheme ??
        ref.watch(startupThemeSettingsProvider) ??
        const ThemeStartupSettings(
          preference: ThemePreference.light,
          timeOfDayEnabled: false,
        );
    final themePreference =
        ref.watch(themePreferenceProvider).value ?? startupTheme.preference;
    final timeOfDayThemeEnabled =
        ref.watch(timeOfDayThemeEnabledProvider).value ??
        startupTheme.timeOfDayEnabled;
    final themeNow =
        ref.watch(localThemeClockProvider).value ?? DateTime.now().toLocal();
    final themeMode = effectiveThemeMode(
      themePreference,
      timeOfDayThemeEnabled: timeOfDayThemeEnabled,
      now: themeNow,
    );
    final locale = Locale(appLanguage.name);
    Intl.defaultLocale = locale.toLanguageTag();

    const localizationsDelegates = <LocalizationsDelegate<dynamic>>[
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ];
    final startupController = ref.watch(startupBootstrapControllerProvider);
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'Owntend',
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: hkRootScaffoldMessengerKey,
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: localizationsDelegates,
      routerConfig: router,
      themeAnimationDuration: themeTransitionDuration,
      themeAnimationCurve: themeTransitionCurve,
      themeMode: themeMode,
      theme: OwntendTheme.light(),
      darkTheme: OwntendTheme.dark(),
      builder: (context, child) {
        return ValueListenableBuilder<StartupBootstrapState>(
          valueListenable: startupController.stateListenable,
          builder: (context, startupState, _) {
            final effectiveStartupStatus =
                startupState.status ??
                syntheticStartupStatus(RestoreRunState.running);
            if (startupState.kind != StartupBootstrapKind.authenticatedReady) {
              return StartupRouteHost(
                child: StartupHome(
                  state: startupState,
                  status: effectiveStartupStatus,
                  language: appLanguage,
                  onLanguageChanged: (language) => ref
                      .read(settingsRepositoryProvider)
                      .setAppLocalePreference(language),
                  onRetry: startupController.retryStartupRestore,
                  onCheckConnection: startupController.retryStartupRestore,
                  onContinueOffline: startupState.canContinueOffline
                      ? startupController.continueStartupOffline
                      : null,
                  onSignOut: startupController.signOutFromStartup,
                ),
              );
            }
            return MonetizationBootstrap(
              child: CloudSyncBootstrap(
                child: NotificationBootstrap(
                  child: StandardSystemUi(
                    child: child ?? const SizedBox.shrink(),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
