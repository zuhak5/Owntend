library;

import 'dart:math' as math;

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../../../../owntend_animated_splash_screen.dart';
import '../../../ui/components.dart' as hk_ui;
import '../../../ui/presentation_support.dart';
import '../../auth/presentation/authentication_gate.dart';
import '../../maintenance/data/task_creation_operation_store.dart';
import '../../navigation/navigation_presentation.dart';

part 'hydration_overlay.dart';
part 'startup_bootstrap.dart';
part 'startup_restoration_screen.dart';

typedef StartupThemeLoader = Future<ThemeStartupSettings> Function();
typedef BootstrappedAppBuilder = Widget Function(
  ThemeStartupSettings startupTheme,
);

Future<ThemeStartupSettings> _loadStartupTheme(AppDatabase database) async {
  final settings = DriftSettingsRepository(database);
  return ThemeStartupSettings(
    preference: await settings.themePreference(),
    timeOfDayEnabled: await settings.timeOfDayThemeEnabled(),
  );
}

class OwntendBootstrap extends StatefulWidget {
  const OwntendBootstrap({
    required this.appBuilder,
    this.database,
    this.appConfig,
    this.supabaseClient,
    this.startupThemeLoader,
    super.key,
  }) : assert(database != null || startupThemeLoader != null);

  final AppDatabase? database;
  final AppConfig? appConfig;
  final SupabaseClient? supabaseClient;
  final StartupThemeLoader? startupThemeLoader;
  final BootstrappedAppBuilder appBuilder;

  @override
  State<OwntendBootstrap> createState() => _OwntendBootstrapState();
}
