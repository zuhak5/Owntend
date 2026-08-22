import 'dart:async';

import 'package:sentry_flutter/sentry_flutter.dart';

import '../utils/redacting_logger.dart';
import 'observability_config.dart';

Future<void> configureOwntendSentryScope(
  ObservabilityConfig config, {
  String? runId,
}) async {
  try {
    await Sentry.configureScope(
      (scope) =>
          applyOwntendBaseScope(scope, config, runId: runId ?? AppLogger.runId),
    );
  } on Object {
    // Scope enrichment is best-effort and must never affect application flow.
  }
}

Future<void> applyOwntendBaseScope(
  Scope scope,
  ObservabilityConfig config, {
  required String runId,
}) async {
  await scope.setUser(null);
  await scope.setTag('app_flavor', config.environment);
  await scope.setTag('app_environment', config.environment);
  await scope.setTag('app_version', config.appVersion);
  await scope.setTag('build_number', config.dist);
  await scope.setTag('shorebird_patch_number', config.shorebirdPatchNumber);
  await scope.setTag('run_id', runId);
  await scope.removeContexts('account');
}

Future<void> setSentryAuthenticated({
  required bool authenticated,
  String event = 'auth.state_changed',
}) async {
  try {
    await Sentry.configureScope(
      (scope) =>
          applySentryAuthenticatedScope(scope, authenticated: authenticated),
    );
    await Sentry.addBreadcrumb(
      Breadcrumb(
        category: 'owntend',
        message: event,
        data: {
          'event': event,
          'provider': 'google',
          'authenticated': authenticated,
        },
      ),
    );
  } on Object {
    // Observability must not change authentication outcomes.
  }
}

Future<void> clearSentryAccountScope({String event = 'auth.signed_out'}) async {
  try {
    await Sentry.configureScope(applySentryAccountClearedScope);
    await Sentry.addBreadcrumb(
      Breadcrumb(
        category: 'owntend',
        message: event,
        data: {'event': event, 'authenticated': false},
      ),
    );
  } on Object {
    // Observability must not block sign-out or account deletion cleanup.
  }
}

Future<void> applySentryAuthenticatedScope(
  Scope scope, {
  required bool authenticated,
}) async {
  await scope.setUser(null);
  await scope.removeContexts('account');
  await scope.setTag('authenticated', authenticated.toString());
}

Future<void> applySentryAccountClearedScope(Scope scope) async {
  await scope.setUser(null);
  await scope.removeTag('authenticated');
  await scope.removeContexts('account');
  await scope.setTag('authenticated', 'false');
}

Future<void> setSentryUiState({
  String? locale,
  String? theme,
  bool? syncEnabled,
}) async {
  try {
    await Sentry.configureScope((scope) async {
      if (locale != null && const {'en', 'ar'}.contains(locale)) {
        await scope.setTag('locale', locale);
      }
      if (theme != null && const {'light', 'dark', 'system'}.contains(theme)) {
        await scope.setTag('theme', theme);
      }
      if (syncEnabled != null) {
        await scope.setTag('sync_enabled', syncEnabled.toString());
      }
    });
  } on Object {
    // UI state enrichment is best-effort.
  }
}
