import 'dart:async';

import 'package:sentry_flutter/sentry_flutter.dart';

import '../supabase/supabase_failure.dart';
import '../utils/redacting_logger.dart';
import 'sentry_event_scrubber.dart';
import 'sentry_tracing.dart';

typedef SentryBreadcrumbWriter = Future<void> Function(Breadcrumb breadcrumb);
typedef SentryExceptionWriter = Future<void> Function(
  Object error,
  StackTrace? stackTrace,
  String fingerprint,
  String operation,
  TelemetryFailureClass failureClass,
  Map<String, Object?> fields,
);

class SentryLoggerBridge {
  SentryLoggerBridge({
    SentryBreadcrumbWriter? addBreadcrumb,
    SentryExceptionWriter? captureException,
    DateTime Function()? clock,
    this.deduplicationWindow = const Duration(minutes: 5),
  }) : _addBreadcrumb = addBreadcrumb ?? Sentry.addBreadcrumb,
       _captureException = captureException ?? _captureWithSentry,
       _clock = clock ?? DateTime.now;

  final SentryBreadcrumbWriter _addBreadcrumb;
  final SentryExceptionWriter _captureException;
  final DateTime Function() _clock;
  final Duration deduplicationWindow;
  final Map<String, DateTime> _recentCaptures = {};
  bool _inSentryCallback = false;
  Future<void> _drain = Future<void>.value();

  static SentryLoggerBridge? _installed;
  static AppDiagnosticEventSink? _installedSink;

  static SentryLoggerBridge install() {
    final existing = _installed;
    if (existing != null) return existing;
    final bridge = SentryLoggerBridge();
    void sink(AppDiagnosticEvent event) {
      unawaited(bridge.handle(event));
    }

    _installed = bridge;
    _installedSink = sink;
    AppLogger.addEventSink(sink);
    return bridge;
  }

  static void uninstall() {
    final sink = _installedSink;
    if (sink != null) AppLogger.removeEventSink(sink);
    _installed = null;
    _installedSink = null;
  }

  Future<void> handle(AppDiagnosticEvent event) {
    if (_inSentryCallback) return Future<void>.value();
    return _drain = _drain.then((_) => _processEvent(event), onError: (_) {});
  }

  Future<void> _processEvent(AppDiagnosticEvent event) async {
    try {
      _inSentryCallback = true;
      try {
        await _addBreadcrumb(_breadcrumbFor(event));
      } finally {
        _inSentryCallback = false;
      }

      final error = event.error;
      if (event.level != 'ERROR' || error == null) return;

      final failureClass = classifyTelemetryFailure(error);
      if (failureClass == TelemetryFailureClass.expected ||
          failureClass == TelemetryFailureClass.recoverable) {
        return;
      }
      final fingerprint = _fingerprint(event.event, failureClass, error);
      final now = _clock().toUtc();
      final lastCapture = _recentCaptures[fingerprint];
      if (lastCapture != null &&
          now.difference(lastCapture) < deduplicationWindow) {
        return;
      }
      _recentCaptures[fingerprint] = now;
      _recentCaptures.removeWhere(
        (_, capturedAt) => now.difference(capturedAt) >= deduplicationWindow,
      );

      _inSentryCallback = true;
      try {
        await _captureException(
          error,
          event.stackTrace,
          fingerprint,
          event.event,
          failureClass,
          _safeFields(event.fields),
        );
      } finally {
        _inSentryCallback = false;
      }
    } on Object {
      // Sentry failures are intentionally isolated from application logging.
    }
  }

  Breadcrumb _breadcrumbFor(AppDiagnosticEvent event) {
    return Breadcrumb(
      category: 'owntend',
      message: event.event,
      level: switch (event.level) {
        'ERROR' => SentryLevel.error,
        'WARN' => SentryLevel.warning,
        _ => SentryLevel.info,
      },
      timestamp: event.timestamp,
      data: {
        'event': event.event,
        'level': event.level.toLowerCase(),
        'run_id': event.runId,
        ..._safeFields(event.fields),
      },
    );
  }

  static Map<String, Object?> _safeFields(Map<String, Object?> fields) {
    return <String, Object?>{
      for (final entry in fields.entries)
        if ((allowedSentryTags.contains(entry.key) ||
                allowedSentryExtras.contains(entry.key)) &&
            (entry.value is num ||
                entry.value is bool ||
                entry.value is String))
          entry.key: entry.value,
    };
  }

  static String _fingerprint(
    String operation,
    TelemetryFailureClass failureClass,
    Object error,
  ) {
    final boundedOperation = operation.length <= 80
        ? operation
        : operation.substring(0, 80);
    final diagnosticCode = error is SupabaseFailure
        ? error.diagnosticCode
        : null;
    return [
      'owntend',
      boundedOperation,
      failureClass.name,
      ?diagnosticCode,
    ].join('::');
  }

  static Future<void> _captureWithSentry(
    Object error,
    StackTrace? stackTrace,
    String fingerprint,
    String operation,
    TelemetryFailureClass failureClass,
    Map<String, Object?> fields,
  ) async {
    await Sentry.captureException(
      error,
      stackTrace: stackTrace,
      withScope: (scope) async {
        scope.fingerprint = [fingerprint];
        await scope.setTag('operation', operation);
        await scope.setTag('failure_kind', failureClass.name);
        for (final entry in fields.entries) {
          if (allowedSentryTags.contains(entry.key)) {
            await scope.setTag(entry.key, entry.value.toString());
          } else if (allowedSentryExtras.contains(entry.key)) {
            // ignore: deprecated_member_use
            await scope.setExtra(entry.key, entry.value);
          }
        }
      },
    );
  }
}

void reportOperationFailure({
  required String operation,
  required Object error,
  StackTrace? stackTrace,
  Map<String, Object?> fields = const {},
  bool fatal = false,
}) {
  final failureClass = fatal
      ? TelemetryFailureClass.fatal
      : classifyTelemetryFailure(error);
  final safeFields = <String, Object?>{
    ...fields,
    'failure_kind': failureClass.name,
    'is_retryable': _isRetryable(error),
    if (error is SupabaseFailure && error.diagnosticCode != null)
      'diagnostic_code': error.diagnosticCode!,
    if (error is SupabaseFailure && error.sqlState != null)
      'sql_state': error.sqlState!,
  };
  if (failureClass == TelemetryFailureClass.reportable ||
      failureClass == TelemetryFailureClass.fatal) {
    AppLogger.error(
      operation,
      error: error,
      stackTrace: stackTrace,
      fields: safeFields,
    );
  } else {
    AppLogger.warning(
      operation,
      error: error,
      stackTrace: stackTrace,
      fields: safeFields,
    );
  }
}

bool _isRetryable(Object error) {
  return error is SupabaseFailure && error.retryable;
}
