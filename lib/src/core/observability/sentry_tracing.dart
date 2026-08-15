import 'dart:async';
import 'dart:io';

import 'package:sentry_flutter/sentry_flutter.dart';

import '../supabase/supabase_failure.dart';
import 'observability_config.dart';

enum TelemetryFailureClass { expected, recoverable, reportable, fatal }

TelemetryFailureClass classifyTelemetryFailure(Object error) {
  if (error is SupabaseFailure) {
    return switch (error.kind) {
      SupabaseFailureKind.cancelled ||
      SupabaseFailureKind.permissionDenied ||
      SupabaseFailureKind.conflict => TelemetryFailureClass.expected,
      SupabaseFailureKind.authentication ||
      SupabaseFailureKind.offline => TelemetryFailureClass.recoverable,
      SupabaseFailureKind.storage when error.retryable =>
        TelemetryFailureClass.recoverable,
      SupabaseFailureKind.unknown when error.retryable =>
        TelemetryFailureClass.recoverable,
      SupabaseFailureKind.configuration ||
      SupabaseFailureKind.incompatibleSchema ||
      SupabaseFailureKind.storage ||
      SupabaseFailureKind.unknown => TelemetryFailureClass.reportable,
    };
  }
  if (error is SocketException || error is TimeoutException) {
    return TelemetryFailureClass.recoverable;
  }
  if (error is StateError || error is AssertionError) {
    return TelemetryFailureClass.reportable;
  }
  return TelemetryFailureClass.reportable;
}

double traceSampleRateFor(ObservabilityConfig config, String operation) {
  if (!config.enabled || config.tracesSampleRate == 0) return 0;
  if (config.environment != 'prod') return config.tracesSampleRate;

  final baseRate = config.tracesSampleRate;
  if (operation.startsWith('auth.account_delete')) return 1;
  if (operation.startsWith('sync.initial_hydration') ||
      operation.startsWith('restore.')) {
    return 0.25;
  }
  if (operation.startsWith('app.start') ||
      operation.startsWith('app.first_frame')) {
    return 0.10;
  }
  if (operation.startsWith('sync.manual')) return 0.10;
  if (operation.startsWith('sync.automatic') ||
      operation.startsWith('sync.resume')) {
    return 0.03;
  }
  if (operation.startsWith('/')) return 0.02;
  return baseRate;
}

TracesSamplerCallback owntendTracesSampler(ObservabilityConfig config) {
  return (samplingContext) {
    final customOperation =
        samplingContext.customSamplingContext['operation'] as String?;
    final operation =
        customOperation ??
        (samplingContext.traceLifecycle == SentryTraceLifecycle.stream
            ? samplingContext.spanContext.name
            : samplingContext.transactionContext.name);
    return traceSampleRateFor(config, operation);
  };
}

const owntendTraceOperations = <String>{
  'app.start',
  'app.sentry_init',
  'app.first_frame',
  'app.deferred_bootstrap',
  'diagnostics.initialize',
  'local_cleanup.resume',
  'supabase.initialize',
  'locale.load',
  'unsupported_session.cleanup',
  'sync.run',
  'sync.automatic',
  'sync.manual',
  'sync.retry',
  'sync.full_reconcile',
  'sync.initial_hydration',
  'sync.resume',
  'sync.pause',
  'sync.acquire_lease',
  'sync.prepare',
  'sync.push',
  'sync.pull',
  'sync.apply_remote',
  'sync.media_cleanup',
  'sync.reminders_reconcile',
  'sync.realtime_connect',
  'restore.background_init',
  'restore.foreground_cycle',
  'restore.read_progress',
  'restore.update_notification',
  'restore.cloud_sync',
  'restore.finalize',
  'auth.initial_session',
  'auth.signed_in',
  'auth.signed_out',
  'auth.token_refreshed',
  'auth.google_sign_in',
  'auth.supabase_token_exchange',
  'auth.sign_out',
  'auth.account_delete',
  'auth.account_delete.local_cleanup',
  'notifications.refresh',
  'backup.export',
  'backup.restore',
};

String normalizeTraceOperation(String operation) {
  final normalized = operation.trim().toLowerCase().replaceAll(
    RegExp(r'[^a-z0-9._/]'),
    '_',
  );
  if (normalized.startsWith('/')) return normalized;
  return owntendTraceOperations.contains(normalized)
      ? normalized
      : 'app.operation';
}

Future<T> traceOwntendOperation<T>(
  String operation,
  Future<T> Function() callback, {
  Map<String, Object?> attributes = const {},
}) async {
  if (!Sentry.isEnabled) return callback();

  final safeOperation = normalizeTraceOperation(operation);
  final parent = Sentry.getSpan();
  final span =
      parent?.startChild('task', description: safeOperation) ??
      Sentry.startTransaction(
        safeOperation,
        'task',
        bindToScope: true,
        customSamplingContext: {'operation': safeOperation},
      );
  for (final entry in attributes.entries) {
    final value = entry.value;
    if (_traceTagKeys.contains(entry.key) &&
        (value is bool || value is num || value is String)) {
      span.setTag(entry.key, value.toString());
    } else if (_traceMeasurementKeys.contains(entry.key) && value is num) {
      span.setMeasurement(entry.key, value);
    }
  }
  try {
    final result = await callback();
    span.status = const SpanStatus.ok();
    return result;
  } on Object catch (error) {
    span
      ..throwable = error
      ..status = const SpanStatus.internalError();
    rethrow;
  } finally {
    await span.finish();
  }
}

const _traceTagKeys = {
  'sync_mode',
  'restore_stage',
  'is_retryable',
  'connectivity_state',
  'failure_kind',
  'execution',
  'lease_scope',
  'authenticated',
  'provider',
};

const _traceMeasurementKeys = {
  'elapsed_ms',
  'pending_count',
  'pull_table_count',
  'conflict_count',
  'retry_count',
  'percentage',
};
