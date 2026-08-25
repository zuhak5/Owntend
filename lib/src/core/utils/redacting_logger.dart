import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

typedef AppDiagnosticEventSink = void Function(AppDiagnosticEvent event);

class AppDiagnosticEvent {
  const AppDiagnosticEvent({
    required this.timestamp,
    required this.level,
    required this.event,
    required this.runId,
    required this.fields,
    this.errorType,
    this.error,
    this.stackTrace,
  });

  final DateTime timestamp;
  final String level;
  final String event;
  final String runId;
  final Map<String, Object?> fields;
  final String? errorType;
  final Object? error;
  final StackTrace? stackTrace;

  Map<String, Object?> toJson() => {
    'timestamp': timestamp.toUtc().toIso8601String(),
    'level': level,
    'event': event,
    'runId': runId,
    if (fields.isNotEmpty) 'metadata': fields,
    if (errorType != null) 'errorType': errorType,
  };
}

abstract final class AppLogger {
  static const maximumRetainedEvents = 512;
  static final String runId =
      'run-${DateTime.now().toUtc().microsecondsSinceEpoch.toRadixString(36)}';
  static final List<AppDiagnosticEvent> _events = [];
  static final Set<AppDiagnosticEventSink> _eventSinks = {};

  static void info(String event, {Map<String, Object?> fields = const {}}) {
    _write('INFO', event, fields: fields);
  }

  static void warning(
    String event, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?> fields = const {},
  }) {
    _write('WARN', event, error: error, stackTrace: stackTrace, fields: fields);
  }

  static void error(
    String event, {
    required Object error,
    StackTrace? stackTrace,
    Map<String, Object?> fields = const {},
  }) {
    _write(
      'ERROR',
      event,
      error: error,
      stackTrace: stackTrace,
      fields: fields,
    );
  }

  static List<AppDiagnosticEvent> snapshot({bool errorsOnly = false}) {
    return List.unmodifiable(
      errorsOnly
          ? _events.where(
              (event) => event.level == 'WARN' || event.level == 'ERROR',
            )
          : _events,
    );
  }

  static void addEventSink(AppDiagnosticEventSink eventSink) {
    _eventSinks.add(eventSink);
  }

  static void removeEventSink(AppDiagnosticEventSink eventSink) {
    _eventSinks.remove(eventSink);
  }

  @visibleForTesting
  static void clearForTesting() => _events.clear();

  @visibleForTesting
  static void clearEventSinksForTesting() {
    _eventSinks.clear();
  }

  static void _write(
    String level,
    String event, {
    Object? error,
    StackTrace? stackTrace,
    required Map<String, Object?> fields,
  }) {
    final safeEvent = _safeToken(event);
    final safeFields = <String, Object?>{
      for (final entry in fields.entries)
        _safeToken(entry.key): redactDiagnosticValue(
          entry.value,
          key: entry.key,
        ),
    };
    final diagnostic = AppDiagnosticEvent(
      timestamp: DateTime.now().toUtc(),
      level: level,
      event: safeEvent,
      runId: runId,
      fields: safeFields,
      errorType: error?.runtimeType.toString(),
      error: error,
      stackTrace: stackTrace,
    );
    _events.add(diagnostic);
    if (_events.length > maximumRetainedEvents) {
      _events.removeRange(0, _events.length - maximumRetainedEvents);
    }
    for (final eventSink in _eventSinks.toList(growable: false)) {
      try {
        eventSink(diagnostic);
      } on Object {
        // Diagnostics must never interfere with application behavior or with
        // other independently registered sinks.
      }
    }

    final printableFields = safeFields.entries
        .where((entry) => entry.value is num || entry.value is bool)
        .map((entry) => '${entry.key}=${entry.value}')
        .join(' ');
    final errorType = error == null ? '' : ' error=${error.runtimeType}';
    debugPrint(
      '[Owntend][$level] $safeEvent'
      '${printableFields.isEmpty ? '' : ' $printableFields'}$errorType',
    );
  }

  static String _safeToken(String value) =>
      value.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');
}

Object? redactDiagnosticValue(Object? value, {String? key}) {
  final normalizedKey = key?.toLowerCase() ?? '';
  if (_sensitiveKeys.any(normalizedKey.contains)) {
    return '[redacted]';
  }
  if (value == null || value is bool) return value;
  if (value is num) {
    if (_coordinateKeys.any(normalizedKey.contains)) return '[redacted]';
    return value;
  }
  if (value is Map) {
    return <String, Object?>{
      for (final entry in value.entries)
        entry.key.toString(): redactDiagnosticValue(
          entry.value,
          key: entry.key.toString(),
        ),
    };
  }
  if (value is Iterable) {
    return [for (final item in value) redactDiagnosticValue(item, key: key)];
  }
  final text = value.toString();
  if (_email.hasMatch(text)) return '[redacted-email]';
  if (_url.hasMatch(text)) return '[redacted-url]';
  if (_uuid.hasMatch(text)) return '[redacted-id]';
  if (_token.hasMatch(text)) return '[redacted-token]';
  if (text.contains('/') || text.contains(r'\')) return '[redacted-path]';
  return text.length <= 80 ? text : '${text.substring(0, 77)}...';
}

const _sensitiveKeys = [
  'token',
  'authorization',
  'password',
  'secret',
  'email',
  'serial',
  'object_path',
  'relative_path',
];
const _coordinateKeys = ['latitude', 'longitude', ' lat', ' lng'];
final _email = RegExp(
  r'[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}',
  caseSensitive: false,
);
final _url = RegExp(r'https?://', caseSensitive: false);
final _uuid = RegExp(
  r'\b[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\b',
  caseSensitive: false,
);
final _token = RegExp(r'\beyJ[A-Za-z0-9_-]{20,}\b');

class AppDiagnosticFileStore {
  AppDiagnosticFileStore(
    this.directory, {
    this.maximumFileBytes = 256 * 1024,
    this.maximumFiles = 3,
  });

  final Directory directory;
  final int maximumFileBytes;
  final int maximumFiles;
  Future<void> _writes = Future.value();
  AppDiagnosticEventSink? _eventSink;

  Future<void> initialize() async {
    await directory.create(recursive: true);
    final previous = _eventSink;
    if (previous != null) AppLogger.removeEventSink(previous);
    void sink(AppDiagnosticEvent event) {
      _writes = _writes.then((_) => _append(event)).catchError((Object _) {});
    }

    _eventSink = sink;
    AppLogger.addEventSink(sink);
  }

  Future<void> flush() => _writes;

  Future<void> dispose() async {
    final sink = _eventSink;
    _eventSink = null;
    if (sink != null) AppLogger.removeEventSink(sink);
    await flush();
  }

  Future<List<File>> files() async {
    await flush();
    final result = <File>[];
    for (var index = 0; index < maximumFiles; index++) {
      final file = File(p.join(directory.path, 'events.$index.jsonl'));
      if (await file.exists()) result.add(file);
    }
    return result;
  }

  /// Owner-level retention: deletes diagnostic files older than [retention].
  /// Called by startup; the store owns its own expiry.
  Future<void> cleanupExpired({
    DateTime? now,
    Duration retention = const Duration(hours: 24),
  }) async {
    final cutoff = (now ?? DateTime.now()).toUtc().subtract(retention);
    for (final file in await files()) {
      try {
        final modified = await file.lastModified();
        if (modified.isBefore(cutoff)) {
          await file.delete();
        }
      } on Object {
        // Best-effort expiry must never break startup.
      }
    }
  }

  Future<void> _append(AppDiagnosticEvent event) async {
    final current = File(p.join(directory.path, 'events.0.jsonl'));
    final line = '${jsonEncode(event.toJson())}\n';
    if (await current.exists() &&
        await current.length() + utf8.encode(line).length > maximumFileBytes) {
      await _rotate();
    }
    await current.writeAsString(line, mode: FileMode.append, flush: false);
  }

  Future<void> _rotate() async {
    for (var index = maximumFiles - 1; index >= 1; index--) {
      final previous = File(
        p.join(directory.path, 'events.${index - 1}.jsonl'),
      );
      final target = File(p.join(directory.path, 'events.$index.jsonl'));
      if (await target.exists()) await target.delete();
      if (await previous.exists()) await previous.rename(target.path);
    }
  }
}
