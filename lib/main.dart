import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/foundation.dart' show ValueListenable, ValueNotifier;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:material_symbols_icons/symbols.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import 'src/core/config/app_config.dart';
import 'src/core/data/repositories.dart';
import 'src/core/data/reactive_stream.dart';
import 'src/core/database/app_database.dart';
import 'src/core/domain/categories.dart';
import 'src/core/domain/contracts.dart';
import 'src/core/domain/feature_models.dart' as features;
import 'src/core/domain/models.dart';
import 'src/core/domain/render_fingerprints.dart';
import 'src/core/domain/task_selectors.dart';
import 'src/core/observability/observability_config.dart';
import 'src/core/observability/sentry_bootstrap.dart';
import 'src/core/observability/sentry_navigation.dart';
import 'src/core/services/action_feedback_service.dart';
import 'src/core/services/feedback_messenger.dart';
export 'src/core/data/repositories.dart';
import 'src/core/services/app_permission_coordinator.dart';
import 'src/core/services/backup_service.dart';
import 'src/core/services/diagnostic_export_service.dart';
import 'src/core/services/feature_selectors.dart' as feature_selectors;
import 'src/core/services/health_score_calculator.dart';
import 'src/core/services/notification_service.dart';
import 'src/core/services/reminder_schedule_reconciler.dart';
import 'src/core/services/notification_localization.dart';
import 'src/core/services/weather_service.dart';
import 'src/core/supabase/supabase_bootstrap.dart';
import 'src/core/sync/local_sync_store.dart';
import 'src/core/sync/background_sync_scheduler.dart';
import 'src/core/sync/restore_foreground_service.dart';
import 'src/core/sync/sync_bootstrap.dart';
import 'src/core/sync/sync_coordinator.dart';
import 'src/core/sync/sync_contracts.dart';
import 'src/core/sync/sync_providers.dart';
import 'src/core/utils/app_failure.dart';
import 'src/core/utils/redacting_logger.dart';
import 'src/features/auth/domain/auth_repository.dart';
import 'src/features/auth/data/local_account_data_cleaner.dart';
import 'src/features/auth/presentation/account_screen.dart';
import 'src/features/auth/presentation/authentication_gate.dart';
import 'src/features/auth/presentation/auth_providers.dart';
import 'src/features/monetization/monetization.dart';
import 'src/features/maintenance/application/task_creation_controller.dart';
import 'src/features/maintenance/data/task_creation_operation_store.dart';
import 'src/features/maintenance/domain/task_creation.dart';
import 'src/features/maintenance/presentation/task_completion_controller.dart';
import 'src/i18n/dynamic_text.dart';
import 'src/core/utils/date_utils.dart' as hk_dates;
import 'src/ui/app_theme.dart';
import 'src/ui/components.dart' as hk_ui;
import 'src/ui/full_bleed_illustration_background.dart';
import 'src/ui/full_canvas_system_ui.dart';
import 'src/features/permissions/application/permission_education_controller.dart';
import 'src/features/permissions/domain/capability_snapshots.dart';
import 'src/features/permissions/domain/permission_capability.dart';
import 'src/features/permissions/presentation/permission_education_overlay.dart';
import 'src/features/permissions/presentation/permission_setup_screen.dart';
import 'owntend_animated_splash_screen.dart';

import 'package:owntend/l10n/app_localizations.dart';
import 'package:owntend/l10n/app_localizations_ext.dart';

part 'src/ui/enum_formatters.dart';
part 'src/ui/shared_widgets.dart';
part 'src/core/providers/app_providers.dart';
part 'src/features/startup/presentation/startup_bootstrap.dart';
part 'src/features/startup/presentation/startup_restoration_screen.dart';
part 'src/features/startup/presentation/hydration_overlay.dart';
part 'src/features/navigation/app_router.dart';
part 'src/features/navigation/home_shell.dart';
part 'src/features/dashboard/presentation/dashboard_screen.dart';
part 'src/features/rooms/presentation/rooms_screen.dart';
part 'src/features/rooms/presentation/room_detail_screen.dart';
part 'src/features/rooms/presentation/room_dialogs.dart';
part 'src/features/assets/presentation/thing_detail_screen.dart';
part 'src/features/assets/presentation/asset_dialogs.dart';
part 'src/features/maintenance/presentation/maintenance_screen.dart';
part 'src/features/maintenance/presentation/task_detail_screen.dart';
part 'src/features/maintenance/presentation/calendar_screen.dart';
part 'src/features/maintenance/presentation/maintenance_dialogs.dart';
part 'src/features/more/presentation/more_screen.dart';
part 'src/features/search/presentation/search_screen.dart';
part 'src/features/trash/presentation/trash_screen.dart';
part 'src/features/notifications/presentation/notifications_screen.dart';
part 'src/features/statistics/presentation/statistics_screen.dart';
part 'src/features/settings/presentation/settings_screen.dart';
part 'src/features/backup/presentation/backup_screen.dart';
part 'src/features/monetization/presentation/point_shortage_dialog.dart';

Future<void> main() async {
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
    _runOwntendProcess(
      _DeferredOwntendBootstrap(
        database: database,
        config: config,
        elapsedBeforeFirstFrame: startupClock.elapsed,
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

class OwntendApp extends ConsumerStatefulWidget {
  const OwntendApp({this.startupTheme, super.key});

  final ThemeStartupSettings? startupTheme;

  @override
  ConsumerState<OwntendApp> createState() => _OwntendAppState();
}

class _OwntendAppState extends ConsumerState<OwntendApp>
    with WidgetsBindingObserver {
  Locale _deviceLocale = WidgetsBinding.instance.platformDispatcher.locale;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final startup = ref.read(startupBootstrapControllerProvider);
    ref.listenManual(authStateProvider, (previous, next) {
      startup.handleAuthValue(next);
    }, fireImmediately: true);
    ref.listenManual(syncStatusProvider, (previous, next) {
      startup.handleSyncStatusValue(next);
    }, fireImmediately: true);
    ref.listenManual(streakRefreshProvider, (_, _) {});
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
        : _supportedDeviceLanguage(_deviceLocale);
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
    final themeMode = _effectiveThemeMode(
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
      themeAnimationDuration: _themeTransitionDuration,
      themeAnimationCurve: _themeTransitionCurve,
      themeMode: themeMode,
      theme: OwntendTheme.light(),
      darkTheme: OwntendTheme.dark(),
      builder: (context, child) {
        return ValueListenableBuilder<StartupBootstrapState>(
          valueListenable: startupController.stateListenable,
          builder: (context, startupState, _) {
            final effectiveStartupStatus =
                startupState.status ??
                _syntheticStartupStatus(RestoreRunState.running);
            if (startupState.kind != StartupBootstrapKind.authenticatedReady) {
              return _StartupHome(
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
