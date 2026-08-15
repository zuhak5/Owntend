import 'dart:convert';

enum AppEnvironment {
  dev,
  staging,
  prod;

  static AppEnvironment parse(String value) {
    return switch (value.trim().toLowerCase()) {
      'dev' => AppEnvironment.dev,
      'staging' => AppEnvironment.staging,
      'prod' => AppEnvironment.prod,
      _ => throw const AppConfigException(
        'APP_ENV must be dev, staging, or prod.',
      ),
    };
  }
}

enum AdConsentDebugGeography {
  eea,
  regulatedUsState,
  other;

  static AdConsentDebugGeography? parse(String value) {
    return switch (value.trim().toLowerCase()) {
      '' || 'disabled' => null,
      'eea' => AdConsentDebugGeography.eea,
      'regulated_us_state' ||
      'regulated-us-state' => AdConsentDebugGeography.regulatedUsState,
      'other' => AdConsentDebugGeography.other,
      _ => throw const AppConfigException(
        'ADMOB_CONSENT_DEBUG_GEOGRAPHY must be empty, eea, '
        'regulated_us_state, or other.',
      ),
    };
  }
}

class AppConfigException implements Exception {
  const AppConfigException(this.message);

  final String message;

  @override
  String toString() => 'App configuration is invalid: $message';
}

class AppConfig {
  const AppConfig._({
    required this.environment,
    required this.supabaseUrl,
    required this.supabasePublishableKey,
    required this.googleWebClientId,
    required this.adMobTestDeviceIds,
    required this.adConsentDebugGeography,
    required this.sentryDsn,
    required this.sentryEnabled,
    required this.sentryTracesSampleRate,
  });

  factory AppConfig.fromEnvironment() {
    const environmentValue = String.fromEnvironment(
      'APP_ENV',
      defaultValue: 'dev',
    );
    const urlValue = String.fromEnvironment('SUPABASE_URL');
    const keyValue = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
    const googleWebClientIdValue = String.fromEnvironment(
      'GOOGLE_WEB_CLIENT_ID',
    );
    const adMobTestDeviceIdsValue = String.fromEnvironment(
      'ADMOB_TEST_DEVICE_IDS',
      defaultValue: '',
    );
    const adConsentDebugGeographyValue = String.fromEnvironment(
      'ADMOB_CONSENT_DEBUG_GEOGRAPHY',
      defaultValue: '',
    );
    const sentryDsnValue = String.fromEnvironment('SENTRY_DSN');
    const sentryEnabledValue = bool.fromEnvironment(
      'SENTRY_ENABLED',
      defaultValue: true,
    );
    const sentryTracesSampleRateValue = String.fromEnvironment(
      'SENTRY_TRACES_SAMPLE_RATE',
      defaultValue: '',
    );
    final environment = AppEnvironment.parse(environmentValue);
    return AppConfig.configured(
      environment: environment,
      supabaseUrl: urlValue,
      supabasePublishableKey: keyValue,
      googleWebClientId: googleWebClientIdValue,
      adMobTestDeviceIds: adMobTestDeviceIdsValue,
      adConsentDebugGeography: adConsentDebugGeographyValue,
      sentryDsn: sentryDsnValue,
      sentryEnabled: sentryEnabledValue,
      sentryTracesSampleRate: sentryTracesSampleRateValue,
    );
  }

  factory AppConfig.test({AppEnvironment environment = AppEnvironment.dev}) {
    return AppConfig._(
      environment: environment,
      supabaseUrl: Uri.parse('http://127.0.0.1:54321'),
      supabasePublishableKey: 'sb_publishable_test',
      googleWebClientId: '123-example.apps.googleusercontent.com',
      adMobTestDeviceIds: const [],
      adConsentDebugGeography: null,
      sentryDsn: '',
      sentryEnabled: false,
      sentryTracesSampleRate: 1,
    );
  }

  factory AppConfig.configured({
    required AppEnvironment environment,
    required String supabaseUrl,
    required String supabasePublishableKey,
    required String googleWebClientId,
    String adMobTestDeviceIds = '',
    String? adConsentDebugGeography,
    String sentryDsn = '',
    bool sentryEnabled = true,
    String? sentryTracesSampleRate,
  }) {
    final url = Uri.tryParse(supabaseUrl.trim());
    if (url == null || !url.hasScheme || url.host.isEmpty) {
      throw const AppConfigException('SUPABASE_URL must be an absolute URL.');
    }
    final isLocalDev =
        environment == AppEnvironment.dev &&
        (url.host == '127.0.0.1' || url.host == 'localhost');
    if (url.scheme != 'https' && !(isLocalDev && url.scheme == 'http')) {
      throw const AppConfigException(
        'SUPABASE_URL must use HTTPS outside local development.',
      );
    }

    final key = supabasePublishableKey.trim();
    if (key.isEmpty) {
      throw const AppConfigException(
        'SUPABASE_PUBLISHABLE_KEY must not be empty.',
      );
    }
    if (key.startsWith('sb_secret_') || _jwtRole(key) == 'service_role') {
      throw const AppConfigException(
        'A privileged Supabase key cannot be used by the app.',
      );
    }

    final webClientId = googleWebClientId.trim();
    if (!RegExp(r'^[A-Za-z0-9_-]+\.apps\.googleusercontent\.com$')
        .hasMatch(webClientId)) {
      throw const AppConfigException(
        'GOOGLE_WEB_CLIENT_ID must be a Google Web OAuth client ID.',
      );
    }

    final parsedAdMobTestDeviceIds = adMobTestDeviceIds
        .split(',')
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toList(growable: false);
    if (parsedAdMobTestDeviceIds.any((id) => !_isValidAdTestDeviceId(id))) {
      throw const AppConfigException(
        'ADMOB_TEST_DEVICE_IDS must contain only comma-separated test device '
        'identifiers.',
      );
    }
    final parsedAdConsentDebugGeography = AdConsentDebugGeography.parse(
      adConsentDebugGeography ?? '',
    );
    if (environment == AppEnvironment.prod &&
        parsedAdMobTestDeviceIds.isNotEmpty) {
      throw const AppConfigException(
        'ADMOB_TEST_DEVICE_IDS must be empty in production builds.',
      );
    }
    if (environment == AppEnvironment.prod &&
        parsedAdConsentDebugGeography != null) {
      throw const AppConfigException(
        'ADMOB_CONSENT_DEBUG_GEOGRAPHY must be empty in production builds.',
      );
    }

    final dsn = sentryDsn.trim();
    if (environment != AppEnvironment.dev && !sentryEnabled) {
      throw const AppConfigException(
        'SENTRY_ENABLED must be true outside development.',
      );
    }
    if (environment != AppEnvironment.dev && dsn.isEmpty) {
      throw const AppConfigException(
        'SENTRY_DSN must not be empty outside development.',
      );
    }
    if (dsn.isNotEmpty) {
      final sentryUri = Uri.tryParse(dsn);
      final isSentryIngestHost =
          sentryUri != null &&
          RegExp(
            r'(^|\.)ingest(?:\.[a-z0-9-]+)?\.sentry\.io$',
            caseSensitive: false,
          ).hasMatch(sentryUri.host);
      if (sentryUri == null ||
          sentryUri.scheme != 'https' ||
          sentryUri.userInfo.isEmpty ||
          !isSentryIngestHost) {
        throw const AppConfigException(
          'SENTRY_DSN must be an HTTPS Sentry ingest URL.',
        );
      }
    }

    final defaultTraceRate = switch (environment) {
      AppEnvironment.dev || AppEnvironment.staging => 1.0,
      AppEnvironment.prod => 0.05,
    };
    final traceRateValue = sentryTracesSampleRate?.trim() ?? '';
    final traceRate = traceRateValue.isEmpty
        ? defaultTraceRate
        : double.tryParse(traceRateValue);
    if (traceRate == null || traceRate < 0 || traceRate > 1) {
      throw const AppConfigException(
        'SENTRY_TRACES_SAMPLE_RATE must be between 0.0 and 1.0.',
      );
    }
    return AppConfig._(
      environment: environment,
      supabaseUrl: url,
      supabasePublishableKey: key,
      googleWebClientId: webClientId,
      adMobTestDeviceIds: List.unmodifiable(parsedAdMobTestDeviceIds),
      adConsentDebugGeography: parsedAdConsentDebugGeography,
      sentryDsn: dsn,
      sentryEnabled: sentryEnabled && dsn.isNotEmpty,
      sentryTracesSampleRate: traceRate,
    );
  }

  final AppEnvironment environment;
  final Uri supabaseUrl;
  final String supabasePublishableKey;
  final String googleWebClientId;
  final List<String> adMobTestDeviceIds;
  final AdConsentDebugGeography? adConsentDebugGeography;
  final String sentryDsn;
  final bool sentryEnabled;
  final double sentryTracesSampleRate;

  String get storageNamespace {
    final projectHost = supabaseUrl.host;
    return 'owntend.supabase.${environment.name}.$projectHost';
  }

  String get redactedDescription =>
      'environment=${environment.name}, '
      'host=${supabaseUrl.host}, '
      'adsDebug=${adMobTestDeviceIds.isNotEmpty || adConsentDebugGeography != null ? 'enabled' : 'disabled'}, '
      'sentry=${sentryEnabled ? 'enabled' : 'disabled'}';
}

bool _isValidAdTestDeviceId(String value) {
  return RegExp(r'^[A-Za-z0-9_-]{16,200}$').hasMatch(value);
}

String? _jwtRole(String token) {
  final parts = token.split('.');
  if (parts.length != 3) {
    return null;
  }
  try {
    final normalized = base64Url.normalize(parts[1]);
    final payload = jsonDecode(
      utf8.decode(base64Url.decode(normalized)),
    ) as Map<String, dynamic>;
    return payload['role'] as String?;
  } on Object {
    return null;
  }
}
