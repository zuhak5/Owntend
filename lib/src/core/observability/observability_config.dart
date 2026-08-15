import 'package:package_info_plus/package_info_plus.dart';

import '../config/app_config.dart';

typedef PackageInfoLoader = Future<PackageInfo> Function();

class ObservabilityConfig {
  const ObservabilityConfig({
    required this.enabled,
    required this.dsn,
    required this.environment,
    required this.release,
    required this.dist,
    required this.appVersion,
    required this.tracesSampleRate,
  });

  final bool enabled;
  final String dsn;
  final String environment;
  final String release;
  final String dist;
  final String appVersion;
  final double tracesSampleRate;

  static Future<ObservabilityConfig> fromAppConfig(
    AppConfig config, {
    PackageInfoLoader packageInfoLoader = PackageInfo.fromPlatform,
  }) async {
    final packageInfo = await packageInfoLoader();
    return fromPackageInfo(config, packageInfo);
  }

  static ObservabilityConfig fromPackageInfo(
    AppConfig config,
    PackageInfo packageInfo,
  ) {
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
      tracesSampleRate: config.sentryTracesSampleRate,
    );
  }
}
