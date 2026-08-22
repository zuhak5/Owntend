part of '../local_sync_store.dart';

mixin _LocalSyncMediaStore on _LocalSyncStoreBase {
  Future<void> enqueueMediaCleanup({
    required String objectPath,
    required String userId,
    required String entity,
    required String recordKey,
  }) async {
    if (objectPath.isEmpty || !objectPath.startsWith('$userId/')) return;
    await db
        .into(db.syncMediaCleanup)
        .insertOnConflictUpdate(
          SyncMediaCleanupCompanion.insert(
            objectPath: objectPath,
            userId: userId,
            entity: entity,
            recordKey: recordKey,
          ),
        );
  }

  Future<List<SyncMediaCleanupData>> pendingMediaCleanup({int limit = 50}) {
    final now = DateTime.now();
    final query = db.select(db.syncMediaCleanup)
      ..where(
        (row) =>
            row.attempts.isBiggerOrEqualValue(0) &
            (row.nextAttemptAt.isNull() |
                row.nextAttemptAt.isSmallerOrEqualValue(now)),
      )
      ..orderBy([(row) => OrderingTerm.asc(row.createdAt)])
      ..limit(limit);
    return query.get();
  }

  Future<void> markMediaCleanupSucceeded(String objectPath) async {
    await (db.delete(
      db.syncMediaCleanup,
    )..where((row) => row.objectPath.equals(objectPath))).go();
  }

  Future<void> markMediaCleanupFailed(
    SyncMediaCleanupData cleanup,
    String message,
  ) async {
    final attempts = cleanup.attempts + 1;
    final seconds = math
        .min(15 * math.pow(2, attempts - 1).toInt(), 3600)
        .toInt();
    await (db.update(
      db.syncMediaCleanup,
    )..where((row) => row.objectPath.equals(cleanup.objectPath))).write(
      SyncMediaCleanupCompanion(
        attempts: Value(attempts),
        nextAttemptAt: Value(DateTime.now().add(Duration(seconds: seconds))),
        lastError: Value(message),
      ),
    );
  }

  Future<void> markMediaCleanupTerminal(
    SyncMediaCleanupData cleanup,
    String message,
  ) async {
    await (db.update(
      db.syncMediaCleanup,
    )..where((row) => row.objectPath.equals(cleanup.objectPath))).write(
      SyncMediaCleanupCompanion(
        attempts: const Value(-1),
        nextAttemptAt: const Value(null),
        lastError: Value(message),
      ),
    );
  }

  @override
  Future<void> _saveShadow(SyncRecord record) async {
    if (record.revision == null) return;
    await db
        .into(db.syncShadows)
        .insertOnConflictUpdate(
          SyncShadowsCompanion.insert(
            entity: record.spec.entity,
            recordKey: record.recordKey,
            remoteRevision: record.revision!,
            remoteModifiedAt: Value(record.clientModifiedAt),
            payloadHash: Value(_payloadHash(record.values)),
            lastSyncedAt: Value(DateTime.now()),
          ),
        );
  }

  @override
  Future<T> withOutboxSuppressed<T>(Future<T> Function() action) async {
    await _setOutboxSuppressed(true);
    try {
      return await action();
    } finally {
      await _setOutboxSuppressed(false);
    }
  }

  Future<void> _setOutboxSuppressed(bool suppressed) {
    return (db.update(db.syncRuntime)..where((row) => row.id.equals(1))).write(
      SyncRuntimeCompanion(suppressOutbox: Value(suppressed)),
    );
  }

  @override
  Future<void> _enqueueLocalMediaCleanup(String relativePath) async {
    await db
        .into(db.localMediaCleanup)
        .insertOnConflictUpdate(
          LocalMediaCleanupCompanion.insert(relativePath: relativePath),
        );
  }

  Future<int> processLocalMediaCleanup({int limit = 50}) async {
    final now = DateTime.now();
    final rows =
        await (db.select(db.localMediaCleanup)
              ..where(
                (row) =>
                    row.attempts.isBiggerOrEqualValue(0) &
                    (row.nextAttemptAt.isNull() |
                        row.nextAttemptAt.isSmallerOrEqualValue(now)),
              )
              ..orderBy([(row) => OrderingTerm.asc(row.createdAt)])
              ..limit(limit))
            .get();
    if (rows.isEmpty) return 0;
    final documents = await _documentsDirectory();
    for (final row in rows) {
      final file = File(
        p.normalize(
          p.joinAll([documents.path, ...row.relativePath.split('/')]),
        ),
      );
      if (!p.isWithin(documents.path, file.path)) {
        await _markLocalMediaCleanupTerminal(row, 'invalid_path');
        continue;
      }
      try {
        if (await file.exists()) {
          await _deleteFile(file);
        }
        await (db.delete(
          db.localMediaCleanup,
        )..where((item) => item.relativePath.equals(row.relativePath))).go();
      } on Object {
        final attempts = row.attempts + 1;
        final seconds = math
            .min(15 * math.pow(2, attempts - 1).toInt(), 3600)
            .toInt();
        await (db.update(
          db.localMediaCleanup,
        )..where((item) => item.relativePath.equals(row.relativePath))).write(
          LocalMediaCleanupCompanion(
            attempts: Value(attempts),
            nextAttemptAt: Value(
              DateTime.now().add(Duration(seconds: seconds)),
            ),
            lastErrorCode: const Value('filesystem_error'),
          ),
        );
      }
    }
    return rows.length;
  }

  Future<void> _markLocalMediaCleanupTerminal(
    LocalMediaCleanupData cleanup,
    String errorCode,
  ) {
    return (db.update(
      db.localMediaCleanup,
    )..where((row) => row.relativePath.equals(cleanup.relativePath))).write(
      LocalMediaCleanupCompanion(
        attempts: const Value(-1),
        nextAttemptAt: const Value(null),
        lastErrorCode: Value(errorCode),
      ),
    );
  }
}

Map<String, dynamic>? _decodeMaintenancePayload(String payloadJson) {
  try {
    final decoded = jsonDecode(payloadJson);
    if (decoded is! Map) return null;
    return Map<String, dynamic>.from(decoded);
  } on Object {
    return null;
  }
}

Map<String, dynamic>? _maintenanceCompletionPlanPreimage(
  Map<String, dynamic> payload,
) {
  final rawPreimage = payload['preimage'];
  if (rawPreimage is Map) {
    final rawPlan = rawPreimage['plan'];
    if (rawPlan is Map) {
      return Map<String, dynamic>.from(rawPlan);
    }
  }

  final rawPlan = payload['plan'];
  final expectedDueDate = payload['expected_next_due_date'];
  if (rawPlan is! Map || expectedDueDate == null) return null;
  return {
    ...Map<String, dynamic>.from(rawPlan),
    'next_due_date': expectedDueDate,
  };
}

String _stringValue(Map<String, dynamic> values, String key, String fallback) {
  final value = values[key];
  return value == null ? fallback : value.toString();
}

String? _nullableStringValue(
  Map<String, dynamic> values,
  String key,
  String? fallback,
) {
  if (!values.containsKey(key)) return fallback;
  final value = values[key];
  return value?.toString();
}

int _intValue(Map<String, dynamic> values, String key, int fallback) {
  final value = values[key];
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? fallback;
  return fallback;
}

bool _boolValue(Map<String, dynamic> values, String key, bool fallback) {
  final value = values[key];
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) return value.toLowerCase() == 'true';
  return fallback;
}

DateTime _dateValue(
  Map<String, dynamic> values,
  String key,
  DateTime fallback,
) {
  return _nullableDateValue(values, key, fallback) ?? fallback;
}

DateTime? _nullableDateValue(
  Map<String, dynamic> values,
  String key,
  DateTime? fallback,
) {
  if (!values.containsKey(key)) return fallback;
  final value = values[key];
  if (value == null) return null;
  if (value is DateTime) return value.toUtc();
  return DateTime.tryParse(value.toString())?.toUtc() ?? fallback;
}

DateTime? _dateTimeFromStorage(dynamic value) {
  if (value == null) return null;
  if (value is DateTime) return value.toUtc();
  if (value is int) {
    return DateTime.fromMillisecondsSinceEpoch(value * 1000, isUtc: true);
  }
  return DateTime.tryParse(value.toString())?.toUtc();
}

DateTime? _semanticClientModifiedAt(
  SyncEntitySpec spec,
  Map<String, dynamic> values,
) {
  final expression = spec.modifiedExpression.trim();
  if (!RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(expression)) {
    return null;
  }
  return _dateTimeFromStorage(values[expression]);
}

Map<String, dynamic> _toRemoteCompatible(
  SyncEntitySpec spec,
  Map<String, dynamic> source,
) {
  return {
    for (final entry in source.entries)
      entry.key: spec.dateColumns.contains(entry.key)
          ? _dateToIso(entry.value)
          : spec.boolColumns.contains(entry.key)
          ? entry.value == true || entry.value == 1
          : spec.jsonColumns.contains(entry.key) && entry.value is String
          ? jsonDecode(entry.value as String)
          : entry.value,
  };
}

String? _dateToIso(dynamic value) {
  if (value == null) return null;
  if (value is DateTime) return value.toUtc().toIso8601String();
  if (value is int) {
    return DateTime.fromMillisecondsSinceEpoch(
      value * 1000,
      isUtc: true,
    ).toIso8601String();
  }
  return DateTime.parse(value.toString()).toUtc().toIso8601String();
}

Object? _toLocalValue(SyncEntitySpec spec, String column, dynamic value) {
  if (value == null) return null;
  if (spec.dateColumns.contains(column)) {
    final date = value is DateTime ? value : DateTime.parse(value.toString());
    return date.toUtc().millisecondsSinceEpoch ~/ 1000;
  }
  if (spec.boolColumns.contains(column)) {
    return value == true ? 1 : 0;
  }
  if (spec.jsonColumns.contains(column)) {
    return jsonEncode(value);
  }
  return value as Object;
}

String _payloadHash(Map<String, dynamic> values) {
  final keys = values.keys.toList()..sort();
  final canonical = jsonEncode({for (final key in keys) key: values[key]});
  return sha256.convert(utf8.encode(canonical)).toString();
}

const _seedValues = <String, Map<String, Map<String, Object?>>>{
  'user_setting': {
    'theme': {'key': 'theme', 'value': 'system'},
    'app_language': {'key': 'app_language', 'value': 'en'},
    'app_language_explicit': {'key': 'app_language_explicit', 'value': 'false'},
    'theme_time_of_day_enabled': {
      'key': 'theme_time_of_day_enabled',
      'value': 'false',
    },
    'notification_preferences': {
      'key': 'notification_preferences',
      'value': '{"enabled":true}',
    },
    'onboarding_completed': {'key': 'onboarding_completed', 'value': 'false'},
    'permission_education_seen': {
      'key': 'permission_education_seen',
      'value': 'false',
    },
  },
  'streak': {
    'default': {
      'id': 'default',
      'current_streak': 0,
      'best_streak': 0,
      'last_completed_date': null,
    },
  },
};
