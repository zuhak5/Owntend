import 'dart:convert';

class RemoteConfig {
  const RemoteConfig({
    this.configVersion = 1,
    this.adCooldownSeconds = 30,
    this.enableWeatherAlerts = true,
    this.sentryTraceSampleRate = 0.05,
    this.minSupportedBaseVersion = '1.0.0',
    this.remoteAssetManifestUrl,
  });

  const RemoteConfig.defaults() : this();

  final int configVersion;
  final int adCooldownSeconds;
  final bool enableWeatherAlerts;
  final double sentryTraceSampleRate;
  final String minSupportedBaseVersion;
  final String? remoteAssetManifestUrl;

  factory RemoteConfig.fromJson(Map<String, dynamic> json) {
    final rawVersion = json['config_version'] ?? json['configVersion'];
    final configVersion = (rawVersion is num) ? rawVersion.toInt() : 1;

    final rawAdCooldown =
        json['ad_cooldown_seconds'] ?? json['adCooldownSeconds'];
    final adCooldownSeconds = (rawAdCooldown is num)
        ? rawAdCooldown.toInt().clamp(0, 300)
        : 30;

    final rawWeather =
        json['enable_weather_alerts'] ?? json['enableWeatherAlerts'];
    final enableWeatherAlerts = rawWeather is bool ? rawWeather : true;

    final rawSentrySample =
        json['sentry_trace_sample_rate'] ?? json['sentryTraceSampleRate'];
    final sentryTraceSampleRate = (rawSentrySample is num)
        ? rawSentrySample.toDouble().clamp(0.0, 1.0)
        : 0.05;

    final rawMinBase =
        json['min_supported_base_version'] ?? json['minSupportedBaseVersion'];
    final minSupportedBaseVersion =
        (rawMinBase is String && rawMinBase.trim().isNotEmpty)
        ? rawMinBase.trim()
        : '1.0.0';

    final rawManifest =
        json['remote_asset_manifest_url'] ?? json['remoteAssetManifestUrl'];
    final remoteAssetManifestUrl =
        (rawManifest is String && rawManifest.trim().isNotEmpty)
        ? rawManifest.trim()
        : null;

    return RemoteConfig(
      configVersion: configVersion,
      adCooldownSeconds: adCooldownSeconds,
      enableWeatherAlerts: enableWeatherAlerts,
      sentryTraceSampleRate: sentryTraceSampleRate,
      minSupportedBaseVersion: minSupportedBaseVersion,
      remoteAssetManifestUrl: remoteAssetManifestUrl,
    );
  }

  factory RemoteConfig.fromJsonString(String source) {
    try {
      final map = jsonDecode(source);
      if (map is Map<String, dynamic>) {
        return RemoteConfig.fromJson(map);
      } else if (map is Map) {
        return RemoteConfig.fromJson(Map<String, dynamic>.from(map));
      }
    } catch (_) {}
    return const RemoteConfig.defaults();
  }

  Map<String, dynamic> toJson() => {
    'config_version': configVersion,
    'ad_cooldown_seconds': adCooldownSeconds,
    'enable_weather_alerts': enableWeatherAlerts,
    'sentry_trace_sample_rate': sentryTraceSampleRate,
    'min_supported_base_version': minSupportedBaseVersion,
    'remote_asset_manifest_url': remoteAssetManifestUrl,
  };

  String toJsonString() => jsonEncode(toJson());

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RemoteConfig &&
          runtimeType == other.runtimeType &&
          configVersion == other.configVersion &&
          adCooldownSeconds == other.adCooldownSeconds &&
          enableWeatherAlerts == other.enableWeatherAlerts &&
          sentryTraceSampleRate == other.sentryTraceSampleRate &&
          minSupportedBaseVersion == other.minSupportedBaseVersion &&
          remoteAssetManifestUrl == other.remoteAssetManifestUrl;

  @override
  int get hashCode => Object.hash(
    configVersion,
    adCooldownSeconds,
    enableWeatherAlerts,
    sentryTraceSampleRate,
    minSupportedBaseVersion,
    remoteAssetManifestUrl,
  );
}
