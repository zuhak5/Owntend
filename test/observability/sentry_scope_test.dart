import 'package:flutter_test/flutter_test.dart';
import 'package:owntend/src/core/observability/observability_config.dart';
import 'package:owntend/src/core/observability/sentry_scope.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

void main() {
  const config = ObservabilityConfig(
    enabled: true,
    dsn: 'redacted',
    environment: 'prod',
    release: 'app.owntend.mobile@1.3.4+19',
    dist: '19',
    appVersion: '1.3.4',
    shorebirdPatchNumber: '7',
    tracesSampleRate: 0.05,
  );

  test(
    'base scope contains only stable application tags and no user',
    () async {
      final scope = Scope(SentryOptions());
      await scope.setUser(
        SentryUser(id: 'user-id', email: 'person@example.com'),
      );
      await scope.setContexts('account', {'id': 'user-id'});

      await applyOwntendBaseScope(scope, config, runId: 'run-test');

      expect(scope.user, isNull);
      expect(scope.contexts.containsKey('account'), isFalse);
      expect(scope.tags, {
        'app_flavor': 'prod',
        'app_environment': 'prod',
        'app_version': '1.3.4',
        'build_number': '19',
        'shorebird_patch_number': '7',
        'run_id': 'run-test',
      });
    },
  );

  test('sign-out and account deletion clear account scope', () async {
    final scope = Scope(SentryOptions());
    await scope.setUser(SentryUser(id: 'user-id'));
    await scope.setContexts('account', {'id': 'user-id'});
    await scope.setTag('authenticated', 'true');

    await applySentryAccountClearedScope(scope);

    expect(scope.user, isNull);
    expect(scope.contexts.containsKey('account'), isFalse);
    expect(scope.tags['authenticated'], 'false');
  });

  test('authenticated scope never sets a Sentry user', () async {
    final scope = Scope(SentryOptions());

    await applySentryAuthenticatedScope(scope, authenticated: true);

    expect(scope.user, isNull);
    expect(scope.tags['authenticated'], 'true');
  });
}
