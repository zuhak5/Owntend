import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:owntend/src/core/observability/sentry_logger_bridge.dart';
import 'package:owntend/src/core/utils/redacting_logger.dart';

void main() {
  group('SentryLoggerBridge Concurrent Queue (BUG-04)', () {
    setUp(() {
      AppLogger.clearForTesting();
      AppLogger.clearEventSinksForTesting();
      SentryLoggerBridge.uninstall();
    });

    tearDown(() {
      SentryLoggerBridge.uninstall();
      AppLogger.clearEventSinksForTesting();
    });

    test('concurrent events are queued and not silently dropped', () async {
      final processedEvents = <String>[];
      final completer = Completer<void>();

      final bridge = SentryLoggerBridge(
        addBreadcrumb: (breadcrumb) async {
          processedEvents.add(breadcrumb.message ?? '');
          if (breadcrumb.message == 'first_event') {
            // Simulate async in-flight work:
            await completer.future;
          }
        },
        captureException:
            (
              error,
              stackTrace,
              fingerprint,
              operation,
              failureClass,
              fields,
            ) async {
              processedEvents.add('captured_exception');
            },
      );

      // Dispatch first event, which holds in addBreadcrumb:
      final future1 = bridge.handle(
        _event(level: 'INFO', event: 'first_event'),
      );

      // While first event is in-flight, dispatch second event:
      final future2 = bridge.handle(
        _event(level: 'INFO', event: 'second_event'),
      );

      // Yield to let the first event enter addBreadcrumb:
      await Future<void>.delayed(Duration.zero);

      // First is held in addBreadcrumb, second is queued:
      expect(processedEvents, ['first_event']);

      // Unblock the first event:
      completer.complete();
      await Future.wait([future1, future2]);

      // Both events must have been processed:
      expect(processedEvents, ['first_event', 'second_event']);
    });
  });
}

AppDiagnosticEvent _event({
  required String level,
  required String event,
  Object? error,
  Map<String, Object?> fields = const {},
}) {
  return AppDiagnosticEvent(
    timestamp: DateTime.utc(2026, 9, 1),
    level: level,
    event: event,
    runId: 'run-queue-test',
    fields: fields,
    errorType: error?.runtimeType.toString(),
    error: error,
    stackTrace: error == null ? null : StackTrace.current,
  );
}
