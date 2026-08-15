import 'package:flutter_test/flutter_test.dart';
import 'package:owntend/src/core/observability/sentry_logger_bridge.dart';
import 'package:owntend/src/core/observability/sentry_tracing.dart';
import 'package:owntend/src/core/supabase/supabase_failure.dart';
import 'package:owntend/src/core/utils/redacting_logger.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

void main() {
  setUp(() {
    AppLogger.clearForTesting();
    AppLogger.clearEventSinksForTesting();
    SentryLoggerBridge.uninstall();
  });

  tearDown(() {
    SentryLoggerBridge.uninstall();
    AppLogger.clearEventSinksForTesting();
  });

  test('independent logger sinks coexist', () {
    final first = <AppDiagnosticEvent>[];
    final second = <AppDiagnosticEvent>[];
    AppLogger.addEventSink(first.add);
    AppLogger.addEventSink(second.add);

    AppLogger.info('sync_started');

    expect(first, hasLength(1));
    expect(second, hasLength(1));
  });

  test('info and expected warnings create breadcrumbs only', () async {
    final breadcrumbs = <Breadcrumb>[];
    var captures = 0;
    final bridge = SentryLoggerBridge(
      addBreadcrumb: (breadcrumb) async => breadcrumbs.add(breadcrumb),
      captureException:
          (
            error,
            stackTrace,
            fingerprint,
            operation,
            failureClass,
            fields,
          ) async {
            captures++;
          },
    );

    await bridge.handle(_event(level: 'INFO', event: 'sync_started'));
    await bridge.handle(
      _event(
        level: 'WARN',
        event: 'sync_offline',
        error: const SupabaseFailure(
          kind: SupabaseFailureKind.offline,
          message: 'offline',
          retryable: true,
        ),
      ),
    );

    expect(breadcrumbs, hasLength(2));
    expect(captures, 0);
  });

  test('reportable duplicate failures create one issue', () async {
    final fingerprints = <String>[];
    final bridge = SentryLoggerBridge(
      addBreadcrumb: (_) async {},
      captureException:
          (
            error,
            stackTrace,
            fingerprint,
            operation,
            failureClass,
            fields,
          ) async {
            expect(failureClass, TelemetryFailureClass.reportable);
            fingerprints.add(fingerprint);
          },
      clock: () => DateTime.utc(2026, 8, 3),
    );
    final event = _event(
      level: 'ERROR',
      event: 'sync_run_failed',
      error: StateError('invariant'),
    );

    await bridge.handle(event);
    await bridge.handle(event);

    expect(fingerprints, ['owntend::sync_run_failed::reportable']);
  });

  test('recursion guard suppresses bridge re-entry', () async {
    late SentryLoggerBridge bridge;
    var breadcrumbs = 0;
    bridge = SentryLoggerBridge(
      addBreadcrumb: (_) async {
        breadcrumbs++;
        await bridge.handle(_event(level: 'INFO', event: 'recursive'));
      },
      captureException: (
        error,
        stackTrace,
        fingerprint,
        operation,
        failureClass,
        fields,
      ) async {},
    );

    await bridge.handle(_event(level: 'INFO', event: 'outer'));

    expect(breadcrumbs, 1);
  });
}

AppDiagnosticEvent _event({
  required String level,
  required String event,
  Object? error,
}) {
  return AppDiagnosticEvent(
    timestamp: DateTime.utc(2026, 8, 3),
    level: level,
    event: event,
    runId: 'run-test',
    fields: const {},
    errorType: error?.runtimeType.toString(),
    error: error,
    stackTrace: error == null ? null : StackTrace.current,
  );
}
