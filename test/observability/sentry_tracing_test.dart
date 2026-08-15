import 'package:flutter_test/flutter_test.dart';
import 'package:owntend/src/core/observability/observability_config.dart';
import 'package:owntend/src/core/observability/sentry_tracing.dart';
import 'package:owntend/src/core/supabase/supabase_failure.dart';

void main() {
  const prod = ObservabilityConfig(
    enabled: true,
    dsn: 'redacted',
    environment: 'prod',
    release: 'app.owntend.mobile@1.3.4+19',
    dist: '19',
    appVersion: '1.3.4',
    tracesSampleRate: 0.05,
  );
  const staging = ObservabilityConfig(
    enabled: true,
    dsn: 'redacted',
    environment: 'staging',
    release: 'app.owntend.mobile.staging@1.3.4+19',
    dist: '19',
    appVersion: '1.3.4',
    tracesSampleRate: 1,
  );

  test('production sampling is operation-based and identity-free', () {
    expect(traceSampleRateFor(prod, 'app.start'), 0.10);
    expect(traceSampleRateFor(prod, 'sync.initial_hydration'), 0.25);
    expect(traceSampleRateFor(prod, 'restore.foreground_cycle'), 0.25);
    expect(traceSampleRateFor(prod, 'auth.account_delete'), 1);
    expect(traceSampleRateFor(prod, 'sync.manual'), 0.10);
    expect(traceSampleRateFor(prod, 'sync.automatic'), 0.03);
    expect(traceSampleRateFor(prod, 'sync.resume'), 0.03);
    expect(traceSampleRateFor(prod, '/account'), 0.02);
    expect(traceSampleRateFor(prod, 'app.operation'), 0.05);
  });

  test('staging samples every configured trace', () {
    expect(traceSampleRateFor(staging, 'app.operation'), 1);
    expect(traceSampleRateFor(staging, 'auth.account_delete'), 1);
  });

  test('failure classification suppresses expected operational states', () {
    expect(
      classifyTelemetryFailure(
        const SupabaseFailure(
          kind: SupabaseFailureKind.conflict,
          message: 'safe',
        ),
      ),
      TelemetryFailureClass.expected,
    );
    expect(
      classifyTelemetryFailure(
        const SupabaseFailure(
          kind: SupabaseFailureKind.offline,
          message: 'safe',
          retryable: true,
        ),
      ),
      TelemetryFailureClass.recoverable,
    );
    expect(
      classifyTelemetryFailure(StateError('invariant')),
      TelemetryFailureClass.reportable,
    );
  });

  test('unknown transaction names collapse to a bounded operation', () {
    expect(normalizeTraceOperation('sync.run'), 'sync.run');
    expect(normalizeTraceOperation('sync.resume'), 'sync.resume');
    expect(
      normalizeTraceOperation('auth.google_sign_in'),
      'auth.google_sign_in',
    );
    expect(normalizeTraceOperation('room-user-value'), 'app.operation');
  });
}
