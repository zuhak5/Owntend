import 'package:package_info_plus/package_info_plus.dart';
import 'package:shorebird_code_push/shorebird_code_push.dart';

import '../config/app_config.dart';

typedef PackageInfoLoader = Future<PackageInfo> Function();
typedef ShorebirdPatchNumberLoader = Future<int?> Function();

class ObservabilityConfig {
  const ObservabilityConfig({
    required this.enabled,
    required this.dsn,
    required this.environment,
    required this.release,
    required this.dist,
    required this.appVersion,
    required this.shorebirdPatchNumber,
    required this.tracesSampleRate,
  });

  final bool enabled;
  final String dsn;
  final String environment;
  final String release;
  final String dist;
  final String appVersion;
  final String shorebirdPatchNumber;
  final double tracesSampleRate;

  static Future<ObservabilityConfig> fromAppConfig(
    AppConfig config, {
    PackageInfoLoader packageInfoLoader = PackageInfo.fromPlatform,
    ShorebirdPatchNumberLoader patchNumberLoader = _readShorebirdPatchNumber,
  }) async {
    final packageInfo = await packageInfoLoader();
    final patchNumber = await patchNumberLoader();
    return fromPackageInfo(
      config,
      packageInfo,
      shorebirdPatchNumber: patchNumber,
    );
  }

  static ObservabilityConfig fromPackageInfo(
    AppConfig config,
    PackageInfo packageInfo, {
    int? shorebirdPatchNumber,
  }) {
    final version = packageInfo.version.trim();
    final buildNumber = packageInfo.buildNumber.trim();
    final packageName = packageInfo.packageName.trim();
    if (packageName.isEmpty || version.isEmpty || buildNumber.isEmpty) {
      throw const AppConfigException(
        'Application package, version, and build metadata are required.',
      );
    }
    return ObservabilityConfig(
      enabled: config.sentryEnabled && config.sentryDsn.isNotEmpty,
      dsn: config.sentryDsn,
      environment: config.environment.name,
      release: '$packageName@$version+$buildNumber',
      dist: buildNumber,
      appVersion: version,
      shorebirdPatchNumber: shorebirdPatchNumber == null
          ? 'base'
          : shorebirdPatchNumber.toString(),
      tracesSampleRate: config.sentryTracesSampleRate,
    );
  }

  static Future<int?> _readShorebirdPatchNumber() async {
    try {
      return (await ShorebirdUpdater().readCurrentPatch())?.number;
    } on Object {
      // Patch attribution must never prevent startup or background execution.
      return null;
    }
  }
}
