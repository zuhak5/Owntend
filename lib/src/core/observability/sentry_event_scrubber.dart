// ignore_for_file: deprecated_member_use

import 'dart:async';

import 'package:sentry_flutter/sentry_flutter.dart';

import '../supabase/supabase_failure.dart';
import '../utils/redacting_logger.dart';
import 'sentry_navigation.dart';
import 'sentry_tracing.dart';

const allowedSentryTags = <String>{
  'app_flavor',
  'app_environment',
  'app_version',
  'build_number',
  'shorebird_patch_number',
  'locale',
  'operation',
  'sync_mode',
  'restore_stage',
  'failure_kind',
  'is_retryable',
  'connectivity_state',
  'permission_type',
  'run_id',
  'execution',
  'authenticated',
  'sync_enabled',
  'permission_state',
  'theme',
  'provider',
};

const allowedSentryExtras = <String>{
  'elapsed_ms',
  'attempt',
  'pending_count',
  'pull_table_count',
  'conflict_count',
  'retry_count',
  'percentage',
  'http_status_class',
};

FutureOr<SentryEvent?> scrubSentryEvent(SentryEvent event, Hint hint) {
  // Sentry's unknown protocol fields cannot be sanitized safely; clear them
  // rather than dropping the entire crash or diagnostic event.
  // ignore: invalid_use_of_internal_member
  event.unknown?.clear();
  if (_isExpectedOperationalEvent(event)) return null;

  event
    ..user = null
    ..request = null
    ..serverName = null
    ..culprit = null
    ..tags = _sanitizeTags(event.tags)
    ..extra = _sanitizeExtras(event.extra)
    ..breadcrumbs = _sanitizeBreadcrumbs(event.breadcrumbs)
    ..contexts = _sanitizeContexts(event.contexts)
    ..transaction = event.transaction == null
        ? null
        : normalizeSentryRoute(event.transaction!);

  final message = event.message;
  if (message != null) {
    final safeMessage = event.exceptions?.isNotEmpty == true
        ? 'Owntend exception'
        : _safeText(message.formatted);
    event.message = SentryMessage(safeMessage);
  }
  for (final exception in event.exceptions ?? const <SentryException>[]) {
    exception.value = _safeExceptionValue(exception.value, exception.type);
    exception.module = null;
    exception.stackTrace = _sanitizeStackTrace(exception.stackTrace);
  }
  for (final thread in event.threads ?? const <SentryThread>[]) {
    thread.stacktrace = _sanitizeStackTrace(thread.stacktrace);
  }
  return event;
}

FutureOr<SentryTransaction?> scrubSentryTransaction(
  SentryTransaction transaction,
  Hint hint,
) {
  final scrubbed = scrubSentryEvent(transaction, hint);
  if (scrubbed == null) return null;

  transaction.transaction = normalizeSentryRoute(
    transaction.transaction ?? 'app.operation',
  );
  transaction.measurements.removeWhere(
    (key, _) => !allowedSentryExtras.contains(key),
  );
  for (final span in transaction.spans) {
    span.tags.removeWhere((key, _) => !allowedSentryTags.contains(key));
    span.data.removeWhere((key, _) => !allowedSentryExtras.contains(key));
    final description = span.context.description;
    span.context.description = description?.startsWith('/') == true
        ? normalizeSentryRoute(description!)
        : normalizeTraceOperation(description ?? span.context.operation);
  }
  return transaction;
}

Breadcrumb? scrubSentryBreadcrumb(Breadcrumb? breadcrumb, Hint hint) {
  if (breadcrumb == null) return null;
  final category = breadcrumb.category ?? '';
  if (category == 'navigation') {
    final data = breadcrumb.data ?? const <String, dynamic>{};
    return Breadcrumb(
      category: 'navigation',
      type: 'navigation',
      level: breadcrumb.level,
      timestamp: breadcrumb.timestamp,
      data: {
        if (data['state'] case final String state) 'state': _safeToken(state),
        if (data['from'] case final String from)
          'from': normalizeSentryRoute(from),
        if (data['to'] case final String to) 'to': normalizeSentryRoute(to),
      },
    );
  }
  if (category == 'owntend' || category == 'app.lifecycle') {
    return Breadcrumb(
      message: breadcrumb.message == null
          ? null
          : _safeToken(breadcrumb.message!),
      category: category,
      type: 'default',
      level: breadcrumb.level,
      timestamp: breadcrumb.timestamp,
      data: _sanitizeBreadcrumbData(breadcrumb.data),
    );
  }
  return null;
}

bool _isExpectedOperationalEvent(SentryEvent event) {
  final throwable = event.throwable;
  if (throwable is SupabaseFailure) {
    final classification = classifyTelemetryFailure(throwable);
    return classification == TelemetryFailureClass.expected ||
        classification == TelemetryFailureClass.recoverable;
  }
  return const {
    'cancelled',
    'offline',
    'authentication',
    'permission_denied',
    'conflict',
    'expected',
    'recoverable',
  }.contains(event.tags?['failure_kind']);
}

Map<String, String> _sanitizeTags(Map<String, String>? tags) {
  final result = <String, String>{};
  for (final entry in tags?.entries ?? const <MapEntry<String, String>>[]) {
    if (!allowedSentryTags.contains(entry.key)) continue;
    final value = redactDiagnosticValue(entry.value, key: entry.key);
    if (value is! String || value.startsWith('[redacted')) continue;
    result[entry.key] = _safeText(value);
  }
  return result;
}

Map<String, dynamic> _sanitizeExtras(Map<String, dynamic>? extras) {
  final result = <String, dynamic>{};
  for (final entry in extras?.entries ?? const <MapEntry<String, dynamic>>[]) {
    if (!allowedSentryExtras.contains(entry.key)) continue;
    final value = entry.value;
    if (value is num || value is bool) {
      result[entry.key] = value;
    } else if (entry.key == 'http_status_class' &&
        value is String &&
        RegExp(r'^(?:[1-5]xx|timeout|network)$').hasMatch(value)) {
      result[entry.key] = value;
    }
  }
  return result;
}

Map<String, dynamic> _sanitizeBreadcrumbData(Map<String, dynamic>? data) {
  final result = <String, dynamic>{};
  for (final entry in data?.entries ?? const <MapEntry<String, dynamic>>[]) {
    if (entry.key == 'event') {
      result['event'] = _safeToken(entry.value.toString());
      continue;
    }
    if (entry.key == 'level') {
      result['level'] = _safeToken(entry.value.toString());
      continue;
    }
    if (allowedSentryTags.contains(entry.key)) {
      final value = entry.value;
      if (value is bool || value is num) result[entry.key] = value;
      if (value is String) result[entry.key] = _safeText(value);
      continue;
    }
    if (allowedSentryExtras.contains(entry.key)) {
      final value = entry.value;
      if (value is bool || value is num) result[entry.key] = value;
    }
  }
  return result;
}

List<Breadcrumb> _sanitizeBreadcrumbs(List<Breadcrumb>? breadcrumbs) {
  final result = <Breadcrumb>[];
  for (final breadcrumb in breadcrumbs ?? const <Breadcrumb>[]) {
    final sanitized = scrubSentryBreadcrumb(breadcrumb, Hint());
    if (sanitized != null) result.add(sanitized);
  }
  return result;
}

Contexts _sanitizeContexts(Contexts contexts) {
  final app = contexts.app;
  final device = contexts.device;
  final os = contexts.operatingSystem;
  return Contexts(
    app: app == null
        ? null
        : SentryApp(
            name: _nullableSafeText(app.name),
            version: _nullableSafeText(app.version),
            identifier: _nullableSafeText(app.identifier),
            build: _nullableSafeText(app.build),
            buildType: _nullableSafeText(app.buildType),
            inForeground: app.inForeground,
            viewNames: app.viewNames
                ?.map(normalizeSentryRoute)
                .toList(growable: false),
          ),
    device: device == null
        ? null
        : SentryDevice(
            family: _nullableSafeText(device.family),
            model: _nullableSafeText(device.model),
            arch: _nullableSafeText(device.arch),
            manufacturer: _nullableSafeText(device.manufacturer),
            brand: _nullableSafeText(device.brand),
            orientation: device.orientation,
            simulator: device.simulator,
            deviceType: _nullableSafeText(device.deviceType),
          ),
    operatingSystem: os == null
        ? null
        : SentryOperatingSystem(
            name: _nullableSafeText(os.name),
            version: _nullableSafeText(os.version),
            build: _nullableSafeText(os.build),
            rooted: os.rooted,
            theme: _nullableSafeText(os.theme),
          ),
    runtimes: [
      for (final runtime in contexts.runtimes)
        SentryRuntime(
          name: _nullableSafeText(runtime.name),
          version: _nullableSafeText(runtime.version),
          compiler: _nullableSafeText(runtime.compiler),
          build: _nullableSafeText(runtime.build),
        ),
    ],
    trace: contexts.trace,
  );
}

SentryStackTrace? _sanitizeStackTrace(SentryStackTrace? stackTrace) {
  if (stackTrace == null) return null;
  return SentryStackTrace(
    lang: stackTrace.lang,
    snapshot: stackTrace.snapshot,
    frames: [
      for (final frame in stackTrace.frames)
        SentryStackFrame(
          fileName: _sanitizeFrameFileName(frame.fileName),
          function: _nullableSafeText(frame.function),
          module: _nullableSafeText(frame.module),
          lineNo: frame.lineNo,
          colNo: frame.colNo,
          inApp: frame.inApp,
          package: _nullableSafeText(frame.package),
          native: frame.native,
          platform: _nullableSafeText(frame.platform),
          imageAddr: frame.imageAddr,
          symbolAddr: frame.symbolAddr,
          instructionAddr: frame.instructionAddr,
          rawFunction: _nullableSafeText(frame.rawFunction),
          stackStart: frame.stackStart,
          symbol: _nullableSafeText(frame.symbol),
        ),
    ],
  );
}

String? _sanitizeFrameFileName(String? value) {
  if (value == null) return null;
  final normalized = value.replaceAll('\\', '/');
  if (normalized.startsWith('package:') || normalized.startsWith('dart:')) {
    return _safePackageUri(normalized);
  }
  final libIndex = normalized.lastIndexOf('/lib/');
  if (libIndex != -1) {
    return _safePackageUri(
      'package:owntend/${normalized.substring(libIndex + 5)}',
    );
  }
  final testIndex = normalized.lastIndexOf('/test/');
  if (testIndex != -1) {
    return _safePackageUri('test/${normalized.substring(testIndex + 6)}');
  }
  final pieces = normalized.split('/');
  return _safeText(pieces.last);
}

String _safePackageUri(String uri) {
  final sanitized = uri.replaceAll(RegExp(r'[^A-Za-z0-9_.:/-]'), '_');
  return sanitized.length <= 120 ? sanitized : sanitized.substring(0, 120);
}

/// Exception payloads never reach Sentry: only a sanitized, bounded
/// exception TYPE is reported, because free-form values may embed user
/// content, paths, or tokens that pattern-based redaction cannot guarantee
/// to catch.
String _safeExceptionValue(String? value, String? type) {
  return 'Owntend ${_safeToken(type ?? 'exception')}';
}

String? _nullableSafeText(String? value) =>
    value == null ? null : _safeText(value);

String _safeText(String value) {
  final redacted = redactDiagnosticValue(value);
  if (redacted is! String || redacted.startsWith('[redacted')) {
    return '[redacted]';
  }
  return redacted.length <= 80 ? redacted : redacted.substring(0, 80);
}

String _safeToken(String value) {
  final sanitized = value.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');
  return sanitized.length <= 80 ? sanitized : sanitized.substring(0, 80);
}
