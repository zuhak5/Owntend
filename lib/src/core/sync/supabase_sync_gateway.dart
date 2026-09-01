import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../supabase/supabase_failure.dart';
import '../utils/redacting_logger.dart';
import 'change_feed_contract.dart';
import 'media_download_cache.dart';
import 'sync_dtos.dart';

class RemoteWriteResult {
  const RemoteWriteResult.applied(
    this.canonical, {
    this.cleanupObjectPaths = const [],
  }) : conflict = false;
  const RemoteWriteResult.conflict(this.canonical)
    : conflict = true,
      cleanupObjectPaths = const [];

  final bool conflict;
  final SyncRecord? canonical;
  final List<String> cleanupObjectPaths;
}

class UserChangeFeedPage {
  const UserChangeFeedPage({
    required this.entries,
    required this.highWaterSeq,
    required this.nextSeq,
    required this.hasMore,
    required this.resnapshotRequired,
    this.feedGeneration = 1,
  });

  final List<ChangeFeedEntry> entries;
  final int highWaterSeq;
  final int nextSeq;
  final bool hasMore;
  final bool resnapshotRequired;
  final int feedGeneration;
}

enum MaintenanceCompletionStatus { applied, alreadyApplied, conflict, invalid }

enum MaintenanceUndoStatus {
  applied,
  alreadyApplied,
  conflict,
  invalid,
  unauthorized,
}

class MaintenanceUndoResult {
  const MaintenanceUndoResult({
    required this.status,
    required this.retryable,
    this.plan,
    this.rewound = false,
    this.conflictReason,
  });

  final MaintenanceUndoStatus status;
  final bool retryable;
  final SyncRecord? plan;
  final bool rewound;
  final String? conflictReason;

  bool get acknowledged =>
      status == MaintenanceUndoStatus.applied ||
      status == MaintenanceUndoStatus.alreadyApplied;
}

class MaintenanceCompletionResult {
  const MaintenanceCompletionResult({
    required this.status,
    required this.retryable,
    this.plan,
    this.record,
    this.currentPlanRevision,
    this.resultingRecordId,
    this.resultingNextDueDate,
    this.rewardEligibilityToken,
    this.conflictReason,
  });

  final MaintenanceCompletionStatus status;
  final bool retryable;
  final SyncRecord? plan;
  final SyncRecord? record;
  final int? currentPlanRevision;
  final String? resultingRecordId;
  final DateTime? resultingNextDueDate;
  final String? rewardEligibilityToken;
  final String? conflictReason;

  bool get acknowledged =>
      status == MaintenanceCompletionStatus.applied ||
      status == MaintenanceCompletionStatus.alreadyApplied;
}

class MaintenanceHistoryRestoreResult {
  const MaintenanceHistoryRestoreResult({
    required this.status,
    required this.insertedCount,
    required this.existingCount,
    required this.alreadyProcessed,
    this.plan,
    this.conflictReason,
  });

  final String status;
  final int insertedCount;
  final int existingCount;
  final bool alreadyProcessed;
  final SyncRecord? plan;
  final String? conflictReason;

  bool get applied => status == 'applied';
}

enum SyncRealtimeStatus { subscribed, disconnected, failed }

abstract interface class RealtimeSyncSource {
  Future<void> startRealtime({
    required String userId,
    required String deviceId,
    required void Function(RealtimeSyncEvent event) onChange,
    required void Function(SyncEntitySpec spec, Map<String, dynamic> oldRecord)
    onDelete,
    required void Function(SyncRealtimeStatus status, Object? error) onStatus,
  });

  Future<void> stopRealtime();
}

class SupabaseSyncGateway implements RealtimeSyncSource {
  SupabaseSyncGateway(this._client, {MediaDownloadCache? mediaDownloadCache})
    : _mediaDownloadCache =
          mediaDownloadCache ??
          MediaDownloadCache(
            download: (objectPath) => _client.storage
                .from(_bucket)
                .download(objectPath)
                .timeout(_storageTimeout),
            rootProvider: getApplicationDocumentsDirectory,
          );

  final SupabaseClient _client;
  final MediaDownloadCache _mediaDownloadCache;
  RealtimeChannel? _realtimeChannel;
  static final _processInstanceId =
      'proc-${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';
  String? _channelLifecycleId;

  static const pageSize = 200;
  static const _bucket = 'user-media';
  static const _maximumMediaBytes = 10 * 1024 * 1024;
  static const _dataTimeout = Duration(seconds: 30);
  static const _storageTimeout = Duration(seconds: 120);

  @override
  Future<void> startRealtime({
    required String userId,
    required String deviceId,
    required void Function(RealtimeSyncEvent event) onChange,
    required void Function(SyncEntitySpec spec, Map<String, dynamic> oldRecord)
    onDelete,
    required void Function(SyncRealtimeStatus status, Object? error) onStatus,
  }) async {
    await stopRealtime();
    _channelLifecycleId =
        'chan-${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';
    final lifecycleId = _channelLifecycleId!;
    AppLogger.info(
      'realtime_channel_lifecycle',
      fields: {
        'process_instance_id': _processInstanceId,
        'channel_lifecycle_id': lifecycleId,
        'event': 'connecting',
        'active_channels_count': 1,
      },
    );
    var channel = _client.channel(
      'owntend-sync-$userId-$deviceId-${DateTime.now().microsecondsSinceEpoch}',
    );
    final specsByTable = {
      profileSyncSpec.remoteTable: profileSyncSpec,
      for (final spec in syncEntitySpecs) spec.remoteTable: spec,
    };
    for (final entry in specsByTable.entries) {
      final table = entry.key;
      final spec = entry.value;
      channel = channel.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: table,
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'user_id',
          value: userId,
        ),
        callback: (payload) {
          final record = payload.eventType == PostgresChangeEvent.delete
              ? payload.oldRecord
              : payload.newRecord;
          if (record['user_id'] != userId) return;
          if (spec.scope == SyncScope.deviceScoped &&
              record['device_id'] != deviceId) {
            return;
          }
          if (payload.eventType == PostgresChangeEvent.delete) {
            onDelete(spec, record);
            return;
          }
          onChange(_realtimeEvent(spec, table, payload));
        },
      );
    }
    _realtimeChannel = channel;
    channel.subscribe((status, error) {
      final syncStatus = switch (status) {
        RealtimeSubscribeStatus.subscribed => SyncRealtimeStatus.subscribed,
        RealtimeSubscribeStatus.closed ||
        RealtimeSubscribeStatus.timedOut => SyncRealtimeStatus.disconnected,
        RealtimeSubscribeStatus.channelError => SyncRealtimeStatus.failed,
      };
      AppLogger.info(
        'realtime_channel_lifecycle',
        fields: {
          'process_instance_id': _processInstanceId,
          'channel_lifecycle_id': lifecycleId,
          'event': status.name,
          'active_channels_count': syncStatus == SyncRealtimeStatus.subscribed
              ? 1
              : 0,
        },
      );
      onStatus(syncStatus, error);
    });
  }

  @override
  Future<void> stopRealtime() async {
    final channel = _realtimeChannel;
    final lifecycleId = _channelLifecycleId;
    _realtimeChannel = null;
    _channelLifecycleId = null;
    if (channel != null) {
      AppLogger.info(
        'realtime_channel_lifecycle',
        fields: {
          'process_instance_id': _processInstanceId,
          'channel_lifecycle_id': lifecycleId ?? 'unknown',
          'event': 'stopped',
          'active_channels_count': 0,
        },
      );
      await _client.removeChannel(channel);
    }
  }

  Future<List<SyncRecord>> pullAuthoritativeSnapshotPage({
    required SyncEntitySpec spec,
    required String userId,
    required String deviceId,
    String? afterRecordKey,
    void Function(int exactCount)? onExactCount,
    bool materializeMedia = true,
  }) async {
    try {
      var query = _client
          .from(spec.remoteTable)
          .select(spec.selectClause)
          .eq('user_id', userId);
      if (spec.scope == SyncScope.deviceScoped) {
        query = query.eq('device_id', deviceId);
      }
      if (afterRecordKey != null && afterRecordKey.isNotEmpty) {
        query = query.or(_keyOnlyFilter(spec, afterRecordKey));
      }
      final firstOrderColumn = spec.keyColumns.isEmpty
          ? 'user_id'
          : spec.keyColumns.first;
      var ordered = query.order(firstOrderColumn);
      for (final column in spec.keyColumns.skip(1)) {
        ordered = ordered.order(column);
      }
      final transformed = ordered.limit(pageSize);
      late final List<dynamic> response;
      if (onExactCount != null) {
        final counted = await _withDataTimeout(
          () async => transformed.count(CountOption.exact),
        );
        onExactCount(counted.count);
        response = counted.data;
      } else {
        response = await _withDataTimeout(() async => transformed);
      }
      final parsed = [
        for (final item in response)
          SyncRecord.fromRemote(spec, item as Map<String, dynamic>),
      ];
      final records = <SyncRecord>[];
      const mediaParallelism = 4;
      for (var index = 0; index < parsed.length; index += mediaParallelism) {
        final end = index + mediaParallelism < parsed.length
            ? index + mediaParallelism
            : parsed.length;
        records.addAll(
          await Future.wait([
            for (final record in parsed.sublist(index, end))
              if (record.isDeleted)
                Future<SyncRecord>.value(record)
              else if (materializeMedia)
                _materializeRemoteMedia(record, userId)
              else
                Future<SyncRecord>.value(record),
          ]),
        );
      }
      return records;
    } on Object catch (error, stackTrace) {
      Error.throwWithStackTrace(SupabaseFailure.from(error), stackTrace);
    }
  }

  Future<SyncRecord> materializeRemoteMedia(SyncRecord record, String userId) =>
      _materializeRemoteMedia(record, userId);

  Future<Set<String>> fetchAuthoritativeRecordKeys({
    required SyncEntitySpec spec,
    required String userId,
    required String deviceId,
  }) async {
    if (spec.keyColumns.isEmpty) {
      final record = await fetch(
        spec: spec,
        userId: userId,
        deviceId: deviceId,
        recordKey: spec.entity,
        materializeMedia: false,
      );
      return record == null ? const {} : {spec.entity};
    }
    final keys = <String>{};
    String? afterRecordKey;
    while (true) {
      var query = _client
          .from(spec.remoteTable)
          .select(spec.keyColumns.join(','))
          .eq('user_id', userId);
      if (spec.scope == SyncScope.deviceScoped) {
        query = query.eq('device_id', deviceId);
      }
      if (afterRecordKey != null) {
        query = query.or(_keyOnlyFilter(spec, afterRecordKey));
      }
      var ordered = query.order(spec.keyColumns.first);
      for (final column in spec.keyColumns.skip(1)) {
        ordered = ordered.order(column);
      }
      final rows = await _withDataTimeout(() => ordered.limit(pageSize));
      if (rows.isEmpty) break;
      // The pagination cursor must come from the final row of THIS fetched
      // page, never from accumulated set ordering.
      String? pageLastKey;
      for (final row in rows) {
        final key = spec.keyColumns
            .map((column) => row[column].toString())
            .join('|');
        keys.add(key);
        pageLastKey = key;
      }
      afterRecordKey = pageLastKey;
      if (rows.length < pageSize) break;
    }
    return keys;
  }

  String _keyOnlyFilter(SyncEntitySpec spec, String afterRecordKey) {
    final values = afterRecordKey.split('|');
    final branches = <String>[];
    for (
      var keyIndex = 0;
      keyIndex < spec.keyColumns.length && keyIndex < values.length;
      keyIndex++
    ) {
      final terms = <String>[];
      for (var previous = 0; previous < keyIndex; previous++) {
        terms.add('${spec.keyColumns[previous]}.eq.${values[previous]}');
      }
      terms.add('${spec.keyColumns[keyIndex]}.gt.${values[keyIndex]}');
      branches.add(
        terms.length == 1 ? terms.single : 'and(${terms.join(',')})',
      );
    }
    return branches.join(',');
  }

  Future<RemoteWriteResult> write({
    required SyncRecord record,
    required String userId,
    required String deviceId,
    required int? expectedRevision,
  }) async {
    try {
      if (record.spec.entity == 'maintenance_record') {
        throw const SupabaseFailure(
          kind: SupabaseFailureKind.permissionDenied,
          message: 'Maintenance history is server-authoritative. Use completion, undo, or validated restore.',
          retryable: false,
        );
      }
      if (record.spec.entity == 'asset_photo') {
        final photoId = record.values['id'] as String;
        final assetId = record.values['asset_id'] as String;
        if (record.isDeleted) {
          final deleteRes = await _withDataTimeout(
            () => _client.rpc<Map<String, dynamic>>(
              'delete_asset_photo',
              params: {'p_asset_id': assetId, 'p_photo_id': photoId},
            ),
          );
          final deletedPath = deleteRes['object_path'] as String?;
          return _appliedDeleteResult(
            record: record,
            userId: userId,
            deletedValues: {
              'id': photoId,
              'asset_id': assetId,
              'user_id': userId,
              'object_path': ?deletedPath,
            },
          );
        }
        if (expectedRevision == null ||
            record.values['relative_path'] != null) {
          final localPath = record.values['relative_path'] as String?;
          if (localPath != null && localPath.isNotEmpty) {
            final caption = record.values['caption'] as String?;
            final isPrimary = record.values['is_primary'] == true;
            final canonical = await _uploadMedia(
              userId: userId,
              localRelativePath: localPath,
              assetId: assetId,
              photoId: photoId,
              revision: record.revision,
              caption: caption,
              isPrimary: isPrimary,
            );
            return RemoteWriteResult.applied(
              canonical,
              cleanupObjectPaths: const [],
            );
          }
        }
        if (record.values['is_primary'] == true) {
          await _withDataTimeout(
            () => _client.rpc<Map<String, dynamic>>(
              'set_primary_asset_photo',
              params: {'p_asset_id': assetId, 'p_photo_id': photoId},
            ),
          );
          final canonical = await fetch(
            spec: record.spec,
            userId: userId,
            deviceId: deviceId,
            recordKey: record.recordKey,
          );
          if (canonical != null) {
            return RemoteWriteResult.applied(canonical);
          }
        }
        throw const SupabaseFailure(
          kind: SupabaseFailureKind.incompatibleSchema,
          message:
              'Photo metadata cannot be changed through generic cloud sync. '
              'Use the protected media operation.',
          retryable: false,
        );
      }

      // MON-001: asset creation has no direct INSERT authority. A queued
      // creation (including offline drafts replayed by sync) routes through
      // the idempotent aggregate RPC so bundled invariants and the
      // creation ledger stay authoritative.
      if (record.spec.entity == 'asset' &&
          !record.isDeleted &&
          expectedRevision == null) {
        return await _createAssetThroughAggregateRpc(record, userId);
      }

      if (record.isDeleted) {
        if (expectedRevision == null) {
          final existing = await fetch(
            spec: record.spec,
            userId: userId,
            deviceId: deviceId,
            recordKey: record.recordKey,
          );
          if (existing == null) {
            return _appliedDeleteResult(record: record, userId: userId);
          }
          return await write(
            record: record,
            userId: userId,
            deviceId: deviceId,
            expectedRevision: existing.revision,
          );
        }
        var deleteQuery = _client
            .from(record.spec.remoteTable)
            .delete()
            .eq('user_id', userId);
        if (record.spec.scope == SyncScope.deviceScoped) {
          deleteQuery = deleteQuery.eq('device_id', deviceId);
        }
        final keyValues = _keyValues(record.spec, record.recordKey);
        for (final entry in keyValues.entries) {
          deleteQuery = deleteQuery.eq(entry.key, entry.value);
        }
        final deletedRows = await _withDataTimeout(
          () async => deleteQuery
              .eq('revision', expectedRevision)
              .select(record.spec.selectClause),
        );
        final deleted = _zeroOrOneRemoteRow(deletedRows);
        if (deleted != null) {
          return _appliedDeleteResult(
            record: record,
            userId: userId,
            deletedValues: Map<String, dynamic>.from(deleted),
          );
        }
        final current = await fetch(
          spec: record.spec,
          userId: userId,
          deviceId: deviceId,
          recordKey: record.recordKey,
        );
        return RemoteWriteResult.conflict(current);
      }
      if (expectedRevision == null) {
        final payload = _prepareCreatePayload(record, userId, deviceId);
        try {
          final response = await _withDataTimeout(
            () async => _client
                .from(record.spec.remoteTable)
                .insert(payload)
                .select(record.spec.selectClause)
                .single(),
          );
          final canonical = SyncRecord.fromRemote(
            record.spec,
            Map<String, dynamic>.from(response),
          );
          return RemoteWriteResult.applied(
            canonical,
            cleanupObjectPaths: const [],
          );
        } on PostgrestException catch (error) {
          if (error.code != '23505') rethrow;
          final canonical = await fetch(
            spec: record.spec,
            userId: userId,
            deviceId: deviceId,
            recordKey: record.recordKey,
          );
          if (canonical == null) {
            throw const SupabaseFailure(
              kind: SupabaseFailureKind.conflict,
              message:
                  'A cloud uniqueness rule rejected this local record. '
                  'Check for duplicate names or multiple primary photos.',
            );
          }
          return RemoteWriteResult.conflict(canonical);
        }
      }

      final payload = _prepareUpdatePayload(record);
      var query = _client
          .from(record.spec.remoteTable)
          .update(payload)
          .eq('user_id', userId);
      if (record.spec.scope == SyncScope.deviceScoped) {
        query = query.eq('device_id', deviceId);
      }
      final keyValues = _keyValues(record.spec, record.recordKey);
      for (final entry in keyValues.entries) {
        query = query.eq(entry.key, entry.value);
      }
      final responseRows = await _withDataTimeout(
        () async => query
            .eq('revision', expectedRevision)
            .select(record.spec.selectClause),
      );
      final response = _zeroOrOneRemoteRow(responseRows);
      if (response == null) {
        return RemoteWriteResult.conflict(
          await fetch(
            spec: record.spec,
            userId: userId,
            deviceId: deviceId,
            recordKey: record.recordKey,
          ),
        );
      }
      final canonical = SyncRecord.fromRemote(
        record.spec,
        Map<String, dynamic>.from(response),
      );
      return RemoteWriteResult.applied(canonical, cleanupObjectPaths: const []);
    } on Object catch (error) {
      throw SupabaseFailure.from(error);
    }
  }

  Future<BatchWriteResult> writeNewBatch({
    required List<SyncRecord> records,
    required String userId,
    required String deviceId,
  }) async {
    if (records.isEmpty) return const BatchWriteSuccess([]);
    final spec = records.first.spec;
    if (spec.entity == 'maintenance_record') {
      throw const SupabaseFailure(
        kind: SupabaseFailureKind.permissionDenied,
        message: 'Maintenance history cannot be written through generic synchronization.',
        retryable: false,
      );
    }
    if (records.any(
      (record) =>
          record.spec.entity != spec.entity ||
          record.isDeleted ||
          record.spec.entity == 'asset_photo' ||
          record.spec.entity == 'profile',
    )) {
      return const BatchWriteUnsuitable();
    }
    try {
      final payloads = <Map<String, dynamic>>[];
      for (final record in records) {
        payloads.add(_prepareCreatePayload(record, userId, deviceId));
      }
      // Creation intents are replayed verbatim after a crash or response loss
      // between the server commit and the local acknowledgement. ON CONFLICT
      // DO NOTHING keeps that replay idempotent: already-present rows are
      // skipped instead of aborting the whole statement with 23505, and only
      // freshly inserted rows come back. The coordinator reconciles skipped
      // keys against their canonical rows without surfacing conflicts.
      final response = await _withDataTimeout(
        () async => _client
            .from(spec.remoteTable)
            .upsert(
              payloads,
              onConflict: [
                'user_id',
                if (spec.scope == SyncScope.deviceScoped) 'device_id',
                ...spec.keyColumns.map(spec.remoteColumnFor),
              ].join(','),
              ignoreDuplicates: true,
            )
            .select(spec.selectClause),
      );
      final insertedRecords = [
        for (final item in response)
          SyncRecord.fromRemote(spec, Map<String, dynamic>.from(item)),
      ];
      final insertedKeys = {
        for (final record in insertedRecords) record.recordKey,
      };
      return BatchWriteSuccess(
        insertedRecords,
        replayedRecordKeys: {
          for (final record in records)
            if (!insertedKeys.contains(record.recordKey)) record.recordKey,
        },
      );
    } on PostgrestException catch (error) {
      if (error.code == '23505') {
        final details = error.details?.toString().toLowerCase() ?? '';
        final message = error.message.toLowerCase();
        final isPkey =
            details.contains('_pkey') ||
            message.contains('_pkey') ||
            details.contains('primary key') ||
            message.contains('primary key');
        return BatchWriteConflict(
          code: error.code ?? '23505',
          message: error.message,
          details: error.details?.toString(),
          isPrimaryKeyConflict: isPkey,
        );
      }
      throw SupabaseFailure.from(error);
    } on Object catch (error) {
      throw SupabaseFailure.from(error);
    }
  }

  Future<MaintenanceCompletionResult> completeMaintenance({
    required String payloadJson,
    required String userId,
    required String deviceId,
  }) async {
    try {
      final decoded = jsonDecode(payloadJson);
      if (decoded is! Map) {
        throw const FormatException(
          'The queued maintenance completion payload is invalid.',
        );
      }
      final queuedOperation = Map<String, dynamic>.from(decoded);
      final operation = _serverMaintenanceCompletionOperation(queuedOperation);
      final Object? response = await _withDataTimeout<Object?>(
        () async => _client.rpc<Map<String, dynamic>>(
          'complete_maintenance_task',
          params: {'p_operation': operation, 'p_device_id': deviceId},
        ),
      );
      final result = parseMaintenanceCompletionResult(
        response,
        operation: operation,
        userId: userId,
      );
      AppLogger.info(
        'sync_maintenance_completion_rpc_result',
        fields: {
          'contract_version': 1,
          'rpc_status': result.status.name,
          'is_retryable': result.retryable,
          if (result.conflictReason != null)
            'reason_code': result.conflictReason!,
        },
      );
      return result;
    } on Object catch (error, stackTrace) {
      Error.throwWithStackTrace(SupabaseFailure.from(error), stackTrace);
    }
  }

  Map<String, dynamic> _serverMaintenanceCompletionOperation(
    Map<String, dynamic> queued,
  ) {
    const requiredKeys = <String>{
      'contract_version',
      'operation_id',
      'plan_id',
      'occurrence_id',
      'completed_at',
      'time_zone_id',
      'notes',
    };
    if (queued['contract_version'] != 1 ||
        requiredKeys.any((key) => !queued.containsKey(key))) {
      throw const FormatException(
        'The queued maintenance completion payload is invalid.',
      );
    }
    return <String, dynamic>{
      for (final key in requiredKeys) key: queued[key],
      'expected_plan_revision': queued['expected_plan_revision'],
    };
  }

  Future<String> prepareMaintenanceHistoryRestorePayload({
    required String payloadJson,
    required String userId,
    required String deviceId,
  }) async {
    try {
      final decoded = jsonDecode(payloadJson);
      if (decoded is! Map) {
        throw const FormatException('Invalid maintenance restore payload.');
      }
      final payload = Map<String, dynamic>.from(decoded);
      final planId = payload['plan_id'] as String?;
      if (planId == null || planId.isEmpty) {
        throw const FormatException('Maintenance restore omitted its plan.');
      }
      final existingRevision = (payload['expected_plan_revision'] as num?)
          ?.toInt();
      if (existingRevision == null || existingRevision < 1) {
        final canonical = await fetch(
          spec: syncSpecByEntity['maintenance_plan']!,
          userId: userId,
          deviceId: deviceId,
          recordKey: planId,
        );
        if (canonical == null || canonical.revision == null) {
          throw const SupabaseFailure(
            kind: SupabaseFailureKind.conflict,
            message: 'Maintenance history cannot be restored until its cloud task exists.',
            retryable: false,
          );
        }
        payload['expected_plan_revision'] = canonical.revision;
      }
      payload.remove('request_hash');
      payload['request_hash'] = sha256
          .convert(utf8.encode(jsonEncode(payload)))
          .toString();
      return jsonEncode(payload);
    } on Object catch (error) {
      throw SupabaseFailure.from(error);
    }
  }

  Future<MaintenanceHistoryRestoreResult> restoreMaintenanceHistory({
    required String payloadJson,
    required String userId,
    required String deviceId,
  }) async {
    try {
      final decoded = jsonDecode(payloadJson);
      if (decoded is! Map) {
        throw const FormatException('Invalid maintenance restore payload.');
      }
      final operation = Map<String, dynamic>.from(decoded);
      final data = await _withDataTimeout(
        () => _client.rpc<Map<String, dynamic>>(
          'restore_maintenance_history',
          params: {'p_operation': operation, 'p_device_id': deviceId},
        ),
      );
      final rawPlan = data['plan'];
      final plan = rawPlan is Map
          ? SyncRecord.fromRemote(
              syncSpecByEntity['maintenance_plan']!,
              Map<String, dynamic>.from(rawPlan),
            )
          : null;
      if (plan != null && rawPlan['user_id'] != userId) {
        throw const SupabaseFailure(
          kind: SupabaseFailureKind.permissionDenied,
          message: 'The cloud returned restore data for another account.',
          retryable: false,
        );
      }
      return MaintenanceHistoryRestoreResult(
        status: data['status'] as String? ?? 'invalid',
        insertedCount: (data['inserted_count'] as num?)?.toInt() ?? 0,
        existingCount: (data['existing_count'] as num?)?.toInt() ?? 0,
        alreadyProcessed: data['already_processed'] as bool? ?? false,
        plan: plan,
        conflictReason: data['conflict_reason'] as String?,
      );
    } on Object catch (error) {
      throw SupabaseFailure.from(error);
    }
  }

  Future<MaintenanceUndoResult> undoMaintenanceCompletion({
    required String payloadJson,
    required String userId,
    required String deviceId,
  }) async {
    try {
      final decoded = jsonDecode(payloadJson);
      if (decoded is! Map) {
        throw const FormatException(
          'The queued maintenance undo payload is invalid.',
        );
      }
      final operation = Map<String, dynamic>.from(decoded);
      final Object? response = await _withDataTimeout<Object?>(
        () async => _client.rpc<Map<String, dynamic>>(
          'undo_maintenance_completion',
          params: {'p_operation': operation, 'p_device_id': deviceId},
        ),
      );
      if (response is! Map) {
        throw const FormatException(
          'The maintenance undo RPC returned an invalid result.',
        );
      }
      final body = Map<String, dynamic>.from(response);
      final status = _maintenanceUndoStatus(body['status']);
      final rawPlan = body['plan'];
      final planData = rawPlan is Map
          ? Map<String, dynamic>.from(rawPlan)
          : null;
      if (planData != null && planData['user_id'] != userId) {
        throw const SupabaseFailure(
          kind: SupabaseFailureKind.permissionDenied,
          message: 'The cloud returned maintenance data for another account.',
        );
      }
      if ((status == MaintenanceUndoStatus.applied ||
              status == MaintenanceUndoStatus.alreadyApplied) &&
          planData == null) {
        throw const FormatException(
          'The maintenance undo RPC omitted the canonical plan.',
        );
      }
      return MaintenanceUndoResult(
        status: status,
        retryable: body['retryable'] == true,
        plan: planData == null
            ? null
            : SyncRecord.fromRemote(
                syncSpecByEntity['maintenance_plan']!,
                planData,
              ),
        rewound: body['rewound'] == true,
        conflictReason: body['conflict_reason'] as String?,
      );
    } on Object catch (error) {
      throw SupabaseFailure.from(error);
    }
  }

  Future<SyncRecord?> fetch({
    required SyncEntitySpec spec,
    required String userId,
    required String deviceId,
    required String recordKey,
    bool materializeMedia = true,
  }) async {
    try {
      var query = _client
          .from(spec.remoteTable)
          .select(spec.selectClause)
          .eq('user_id', userId);
      if (spec.scope == SyncScope.deviceScoped) {
        query = query.eq('device_id', deviceId);
      }
      final keyValues = _keyValues(spec, recordKey);
      for (final entry in keyValues.entries) {
        query = query.eq(entry.key, entry.value);
      }
      final responseRows = await _withDataTimeout(() async => query);
      final response = _zeroOrOneRemoteRow(responseRows);
      if (response == null) return null;
      var record = SyncRecord.fromRemote(
        spec,
        Map<String, dynamic>.from(response),
      );
      if (materializeMedia && !record.isDeleted) {
        record = await _materializeRemoteMedia(record, userId);
      }
      return record;
    } on Object catch (error) {
      throw SupabaseFailure.from(error);
    }
  }

  /// Creates an asset through the server-authoritative idempotent aggregate
  /// RPC. The operation id is the canonical asset identifier, so retries and
  /// response-loss replays converge on the same ledger entry instead of
  /// duplicating rows.
  Future<RemoteWriteResult> _createAssetThroughAggregateRpc(
    SyncRecord record,
    String userId,
  ) async {
    final assetValues = <String, dynamic>{};
    for (final entry in record.values.entries) {
      final remoteKey = record.spec.remoteColumnFor(entry.key);
      if (entry.value == null &&
          const {'id', 'name', 'asset_type', 'room_id'}.contains(remoteKey)) {
        continue;
      }
      assetValues[remoteKey] = entry.value;
    }
    final unsignedPayload = <String, dynamic>{
      'operation_id': record.recordKey,
      'asset': assetValues,
      'details': <String, dynamic>{},
      'initial_plans': <Map<String, dynamic>>[],
    };
    final requestHash = sha256
        .convert(utf8.encode(jsonEncode(unsignedPayload)))
        .toString();
    final data = await _withDataTimeout(
      () => _client.rpc<Map<String, dynamic>>(
        'create_asset',
        params: {
          'p_operation': {...unsignedPayload, 'request_hash': requestHash},
        },
      ),
    );
    final remoteAsset = data['asset'];
    if (remoteAsset is Map) {
      final canonical = SyncRecord.fromRemote(
        record.spec,
        Map<String, dynamic>.from(remoteAsset),
      );
      return RemoteWriteResult.applied(canonical);
    }
    // Idempotent replay without a canonical row payload: fetch the row.
    final canonical = await fetch(
      spec: record.spec,
      userId: userId,
      deviceId: '',
      recordKey: record.recordKey,
    );
    if (canonical == null) {
      throw const SupabaseFailure(
        kind: SupabaseFailureKind.incompatibleSchema,
        message:
            'The cloud did not confirm asset creation with its canonical row.',
      );
    }
    return RemoteWriteResult.applied(canonical);
  }

  Map<String, dynamic> _prepareCreatePayload(
    SyncRecord record,
    String userId,
    String deviceId,
  ) {
    final payload = record.toRemoteCreatePayload(userId, deviceId: deviceId);
    if (record.spec.entity == 'asset_photo') {
      payload.remove('object_path');
    }
    return payload;
  }

  Map<String, dynamic> _prepareUpdatePayload(SyncRecord record) {
    if (!record.spec.supportsGenericUpdate) {
      throw SupabaseFailure(
        kind: SupabaseFailureKind.incompatibleSchema,
        message:
            '${record.spec.entity} does not support generic cloud updates.',
        retryable: false,
      );
    }
    try {
      record.spec.validateUpdateContract();
    } on StateError {
      throw const SupabaseFailure(
        kind: SupabaseFailureKind.incompatibleSchema,
        message: 'The local cloud update contract is invalid for this Owntend build.',
        retryable: false,
      );
    }
    final payload = record.toRemoteUpdatePayload();
    if (payload.isEmpty) {
      throw const SupabaseFailure(
        kind: SupabaseFailureKind.incompatibleSchema,
        message:
            'The local record does not contain a valid cloud update payload.',
        retryable: false,
      );
    }
    return payload;
  }

  Future<SyncRecord> _materializeRemoteMedia(
    SyncRecord record,
    String userId,
  ) async {
    if (record.spec.entity != 'asset_photo') {
      return record;
    }
    final objectPath =
        (record.values['cloud_object_path'] ?? record.values['relative_path'])
            as String?;
    if (objectPath == null || objectPath.isEmpty) {
      // A photo row without a cloud object carries no file to download. The
      // local schema requires a non-empty relative path, so persist an empty
      // placeholder that renders as "no image" instead of failing the pull.
      return SyncRecord(
        spec: record.spec,
        recordKey: record.recordKey,
        values: {...record.values, 'relative_path': ''},
        clientModifiedAt: record.clientModifiedAt,
        originDeviceId: record.originDeviceId,
        revision: record.revision,
        serverUpdatedAt: record.serverUpdatedAt,
        deletedAt: record.deletedAt,
      );
    }
    if (!objectPath.startsWith('$userId/')) {
      throw const SupabaseFailure(
        kind: SupabaseFailureKind.storage,
        message: 'Cloud media path does not belong to this account.',
      );
    }
    final version =
        record.serverUpdatedAt?.toUtc().toIso8601String() ??
        record.revision?.toString() ??
        record.clientModifiedAt.toUtc().toIso8601String();
    final cached = await _mediaDownloadCache.materialize(
      objectPath: objectPath,
      version: version,
      assetId: record.values['asset_id'] as String,
    );
    return SyncRecord(
      spec: record.spec,
      recordKey: record.recordKey,
      values: {
        ...record.values,
        'relative_path': cached.relativePath,
        'cloud_object_path': objectPath,
      },
      clientModifiedAt: record.clientModifiedAt,
      originDeviceId: record.originDeviceId,
      revision: record.revision,
      serverUpdatedAt: record.serverUpdatedAt,
      deletedAt: record.deletedAt,
    );
  }

  Future<void> removeMediaObject(String objectPath, String userId) async {
    if (objectPath.isEmpty) return;
    if (!objectPath.startsWith('$userId/')) {
      throw const SupabaseFailure(
        kind: SupabaseFailureKind.storage,
        message: 'Cloud media path does not belong to this account.',
      );
    }
    try {
      await _client.storage
          .from(_bucket)
          .remove([objectPath])
          .timeout(_storageTimeout);
    } on StorageException catch (error) {
      if (isStorageObjectMissingStatus(error.statusCode)) return;
      rethrow;
    }
  }

  Future<SyncRecord> _uploadMedia({
    required String userId,
    required String localRelativePath,
    required String assetId,
    required String photoId,
    required int? revision,
    String? caption,
    bool isPrimary = false,
  }) async {
    final documents = await getApplicationDocumentsDirectory();
    final file = File(
      p.normalize(p.joinAll([documents.path, ...localRelativePath.split('/')])),
    );
    if (!p.isWithin(documents.path, file.path) || !await file.exists()) {
      throw const SupabaseFailure(
        kind: SupabaseFailureKind.storage,
        message: 'A local media file is missing.',
      );
    }
    final byteSize = await file.length();
    if (byteSize > _maximumMediaBytes) {
      throw const SupabaseFailure(
        kind: SupabaseFailureKind.storage,
        message: 'Cloud images must be 10 MiB or smaller.',
      );
    }
    final extension = p.extension(file.path).toLowerCase();
    final mimeType = switch (extension) {
      '.jpg' || '.jpeg' => 'image/jpeg',
      '.png' => 'image/png',
      '.webp' => 'image/webp',
      _ => throw const SupabaseFailure(
        kind: SupabaseFailureKind.storage,
        message: 'Only JPEG, PNG, and WebP images can be uploaded.',
      ),
    };
    final bytes = await file.readAsBytes();
    final digestHex = sha256.convert(bytes).toString();
    final idempotencyKey = sha256
        .convert(
          utf8.encode('$userId|$assetId|$photoId|${revision ?? 1}|$digestHex'),
        )
        .toString();
    final prepareResponse = await _withDataTimeout(
      () => _client.rpc<Map<String, dynamic>>(
        'prepare_asset_photo_upload',
        params: {
          'p_asset_id': assetId,
          'p_photo_id': photoId,
          'p_object_size': byteSize,
          'p_mime_type': mimeType,
          'p_client_sha256_digest': digestHex,
          'p_idempotency_key': idempotencyKey,
        },
      ),
    );
    final stagingId = prepareResponse['staging_id'];
    final stagingPath = prepareResponse['staging_path'];
    final stagingStatus = prepareResponse['status'];
    if (stagingId is! String ||
        stagingId.isEmpty ||
        stagingPath is! String ||
        !stagingPath.startsWith('$userId/media/') ||
        (stagingStatus != 'staged' && stagingStatus != 'finalized')) {
      throw const SupabaseFailure(
        kind: SupabaseFailureKind.incompatibleSchema,
        message: 'The cloud returned an invalid media staging contract.',
      );
    }
    if (stagingStatus == 'staged') {
      try {
        await _client.storage
            .from(_bucket)
            .upload(
              stagingPath,
              file,
              fileOptions: FileOptions(upsert: false, contentType: mimeType),
            );
      } on StorageException catch (error) {
        if (error.statusCode != '409') rethrow;
      }
    }
    final finalizeRes = await _withDataTimeout(
      () => _client.rpc<Map<String, dynamic>>(
        'finalize_asset_photo_upload',
        params: {
          'p_staging_id': stagingId,
          'p_asset_id': assetId,
          'p_photo_id': photoId,
          'p_expected_revision': revision ?? 1,
          'p_caption': caption,
          'p_is_primary': isPrimary,
        },
      ),
    );
    final finalizedPath = finalizeRes['object_path'];
    if (finalizeRes['success'] != true || finalizedPath != stagingPath) {
      throw const SupabaseFailure(
        kind: SupabaseFailureKind.incompatibleSchema,
        message: 'The cloud returned an invalid media finalization contract.',
      );
    }
    final photoRow = <String, dynamic>{
      'id': photoId,
      'asset_id': assetId,
      'user_id': userId,
      'object_path': finalizedPath as String,
      'caption': finalizeRes['caption'] ?? caption,
      'is_primary': finalizeRes['is_primary'] ?? isPrimary,
      'revision': finalizeRes['revision'] ?? revision ?? 1,
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
    return SyncRecord.fromRemote(syncSpecByEntity['asset_photo']!, photoRow);
  }

  Future<UserChangeFeedPage> fetchUserChangeFeed({
    int sinceSeq = 0,
    int limit = 100,
    int? expectedGeneration,
  }) async {
    final response = await _withDataTimeout(
      () => _client.rpc<Map<String, dynamic>>(
        'fetch_user_change_feed',
        params: {
          'p_since_seq': sinceSeq,
          'p_limit': limit,
          'p_expected_generation': expectedGeneration ?? 1,
        },
      ),
    );
    requireSyncFeedContractVersion(response['contract_version']);
    final rawChanges = response['changes'];
    final highWaterSeq = response['high_water_seq'];
    final nextSeq = response['next_seq'];
    final hasMore = response['has_more'];
    final resnapshotRequired =
        response['resnapshot_required'] ?? response['snapshot_required'];
    final feedGeneration = response['feed_generation'] as int? ?? 1;
    if (rawChanges is! List ||
        highWaterSeq is! int ||
        nextSeq is! int ||
        hasMore is! bool ||
        resnapshotRequired is! bool ||
        highWaterSeq < 0 ||
        nextSeq < sinceSeq ||
        nextSeq > highWaterSeq ||
        hasMore != (nextSeq < highWaterSeq)) {
      throw syncFeedProtocolFailure();
    }
    final entries = <ChangeFeedEntry>[];
    var previousSeq = sinceSeq;
    for (final rawChange in rawChanges) {
      if (rawChange is! Map) {
        throw syncFeedProtocolFailure();
      }
      late final ChangeFeedEntry parsed;
      try {
        parsed = parseSyncFeedChange(Map<String, dynamic>.from(rawChange));
      } on SupabaseFailure {
        rethrow;
      } on Object {
        throw syncFeedProtocolFailure();
      }
      if (parsed.changeSeq <= previousSeq || parsed.changeSeq > nextSeq) {
        throw syncFeedProtocolFailure();
      }
      previousSeq = parsed.changeSeq;
      entries.add(parsed);
    }
    if ((entries.isEmpty && nextSeq != sinceSeq) ||
        (entries.isNotEmpty && previousSeq != nextSeq)) {
      throw syncFeedProtocolFailure();
    }
    return UserChangeFeedPage(
      entries: List.unmodifiable(entries),
      highWaterSeq: highWaterSeq,
      nextSeq: nextSeq,
      hasMore: hasMore,
      resnapshotRequired: resnapshotRequired,
      feedGeneration: feedGeneration,
    );
  }

  Future<int> fetchUserChangeFeedHighWater() async {
    final rows = await _withDataTimeout(
      () => _client.rpc<List<dynamic>>('get_user_change_feed_watermark'),
    );
    if (rows.length != 1 || rows.single is! Map) {
      throw syncFeedProtocolFailure();
    }
    final highWater = (rows.single as Map)['max_change_seq'];
    if (highWater is! int || highWater < 0) {
      throw syncFeedProtocolFailure();
    }
    return highWater;
  }

  Future<Map<String, dynamic>> setPrimaryAssetPhoto({
    required String assetId,
    required String photoId,
  }) async {
    try {
      final res = await _withDataTimeout<Map<String, dynamic>>(() async {
        final result = await _client.rpc<dynamic>(
          'set_primary_asset_photo',
          params: {'p_asset_id': assetId, 'p_photo_id': photoId},
        );
        return Map<String, dynamic>.from(result as Map);
      });
      return res;
    } on Object catch (error) {
      throw SupabaseFailure.from(error);
    }
  }
}

RemoteWriteResult _appliedDeleteResult({
  required SyncRecord record,
  required String userId,
  Map<String, dynamic>? deletedValues,
}) {
  return RemoteWriteResult.applied(
    null,
    cleanupObjectPaths: deleteCleanupObjectPaths(
      record: record,
      userId: userId,
      deletedValues: deletedValues,
    ),
  );
}

@visibleForTesting
List<String> deleteCleanupObjectPaths({
  required SyncRecord record,
  required String userId,
  Map<String, dynamic>? deletedValues,
}) {
  final paths = <String>{};

  void addPath(Object? rawPath) {
    if (rawPath == null) return;
    if (rawPath is! String || rawPath.trim().isEmpty) {
      throw const SupabaseFailure(
        kind: SupabaseFailureKind.incompatibleSchema,
        message: 'Cloud media cleanup identity is malformed.',
      );
    }
    if (!rawPath.startsWith('$userId/')) {
      throw const SupabaseFailure(
        kind: SupabaseFailureKind.storage,
        message: 'Cloud media cleanup path does not belong to this account.',
      );
    }
    paths.add(rawPath);
  }

  addPath(record.values['cleanup_object_path']);
  if (deletedValues != null) {
    addPath(_remoteMediaPath(record.spec, deletedValues));
  }
  return paths.toList(growable: false);
}

@visibleForTesting
bool isStorageObjectMissingStatus(String? statusCode) {
  return int.tryParse(statusCode ?? '') == 404;
}

Map<String, dynamic>? _zeroOrOneRemoteRow(List<Map<String, dynamic>> rows) {
  if (rows.isEmpty) return null;
  if (rows.length != 1) {
    throw StateError('A uniquely filtered cloud write returned multiple rows.');
  }
  return Map<String, dynamic>.from(rows.single);
}

Future<T> _withDataTimeout<T>(Future<T> Function() action) {
  return action().timeout(SupabaseSyncGateway._dataTimeout);
}

String? _remoteMediaPath(SyncEntitySpec spec, Map<String, dynamic> values) {
  return switch (spec.entity) {
    'asset_photo' => values['object_path'] as String?,
    _ => null,
  };
}

Map<String, String> _keyValues(SyncEntitySpec spec, String recordKey) {
  if (spec.entity == 'profile') return const {};
  final parts = recordKey.split('|');
  return {
    for (var index = 0; index < spec.keyColumns.length; index++)
      spec.keyColumns[index]: parts[index],
  };
}

RealtimeSyncEvent _realtimeEvent(
  SyncEntitySpec spec,
  String table,
  dynamic payload,
) {
  final row = Map<String, dynamic>.from(payload.newRecord as Map);
  return RealtimeSyncEvent(
    table: table,
    spec: spec,
    type: _realtimeType(payload.eventType as PostgresChangeEvent),
    recordKey: _recordKeyFromRemote(spec, row),
    revision: row['revision'] is num ? (row['revision'] as num).toInt() : null,
    updatedAt: _parseUtc(row['updated_at']),
    originDeviceId: row['origin_device_id'] as String?,
  );
}

sealed class BatchWriteResult {
  const BatchWriteResult();
}

final class BatchWriteSuccess extends BatchWriteResult {
  const BatchWriteSuccess(this.records, {this.replayedRecordKeys = const {}});
  final List<SyncRecord> records;

  /// Keys the server skipped under ON CONFLICT DO NOTHING because a row with
  /// that primary key already exists: idempotent creation replays that must be
  /// reconciled against their canonical rows instead of acknowledged blindly.
  final Set<String> replayedRecordKeys;
}

final class BatchWriteUnsuitable extends BatchWriteResult {
  const BatchWriteUnsuitable();
}

final class BatchWriteConflict extends BatchWriteResult {
  const BatchWriteConflict({
    required this.code,
    required this.message,
    required this.details,
    required this.isPrimaryKeyConflict,
  });
  final String code;
  final String message;
  final String? details;
  final bool isPrimaryKeyConflict;
}

SyncRealtimeEventType _realtimeType(PostgresChangeEvent event) {
  return switch (event) {
    PostgresChangeEvent.insert => SyncRealtimeEventType.insert,
    PostgresChangeEvent.update => SyncRealtimeEventType.update,
    PostgresChangeEvent.delete => SyncRealtimeEventType.delete,
    PostgresChangeEvent.all => SyncRealtimeEventType.update,
  };
}

String? _recordKeyFromRemote(SyncEntitySpec spec, Map<String, dynamic> row) {
  if (spec.keyColumns.isEmpty) return spec.entity;
  final values = <String>[];
  for (final column in spec.keyColumns) {
    final value = row[spec.remoteColumnFor(column)];
    if (value == null) return null;
    values.add(value.toString());
  }
  return values.join('|');
}

DateTime? _parseUtc(Object? value) {
  if (value == null) return null;
  if (value is DateTime) return value.toUtc();
  return DateTime.tryParse(value.toString())?.toUtc();
}

MaintenanceCompletionStatus _maintenanceCompletionStatus(Object? value) {
  return switch (value) {
    'applied' => MaintenanceCompletionStatus.applied,
    'already_applied' => MaintenanceCompletionStatus.alreadyApplied,
    'conflict' => MaintenanceCompletionStatus.conflict,
    'invalid' => MaintenanceCompletionStatus.invalid,
    _ => throw const FormatException(
      'The maintenance completion RPC returned an unknown status.',
    ),
  };
}

const _maintenanceCompletionInvalidReasons = <String>{
  'invalid_device_id',
  'invalid_payload_version',
  'unexpected_payload_field',
  'incomplete_payload',
  'invalid_identifiers',
  'invalid_values',
  'invalid_completion',
  'invalid_time_zone',
  'invalid_recurrence',
  'plan_unavailable',
};

const _maintenanceCompletionConflictReasons = <String>{
  'operation_id_reused',
  'plan_inactive',
  'occurrence_completed_elsewhere',
  'stale_occurrence',
};

const _maintenanceCompletionConflictsWithRecord = <String>{
  'operation_id_reused',
  'occurrence_completed_elsewhere',
};

@visibleForTesting
MaintenanceCompletionResult parseMaintenanceCompletionResult(
  Object? response, {
  required Map<String, dynamic> operation,
  required String userId,
}) {
  if (response is! Map) _throwMaintenanceCompletionContractMismatch();
  final body = Map<String, dynamic>.from(response);
  const expectedKeys = <String>{
    'contract_version',
    'status',
    'retryable',
    'conflict_reason',
    'current_plan_revision',
    'resulting_record_id',
    'resulting_next_due_date',
    'reward_eligibility_token',
    'plan',
    'record',
  };
  final responseKeys = body.keys.toSet();
  if (responseKeys.difference(expectedKeys).isNotEmpty ||
      expectedKeys.difference(responseKeys).isNotEmpty ||
      body['contract_version'] != 1 ||
      body['retryable'] is! bool) {
    _throwMaintenanceCompletionContractMismatch();
  }

  MaintenanceCompletionStatus status;
  try {
    status = _maintenanceCompletionStatus(body['status']);
  } on FormatException {
    _throwMaintenanceCompletionContractMismatch();
  }
  final reason = body['conflict_reason'];
  if (reason != null &&
      (reason is! String || !RegExp(r'^[a-z0-9_]{1,64}$').hasMatch(reason))) {
    _throwMaintenanceCompletionContractMismatch();
  }
  final currentRevision = body['current_plan_revision'];
  if (currentRevision != null &&
      (currentRevision is! int || currentRevision < 1)) {
    _throwMaintenanceCompletionContractMismatch();
  }
  final resultingRecordId = body['resulting_record_id'];
  if (resultingRecordId != null &&
      (resultingRecordId is! String ||
          resultingRecordId.isEmpty ||
          resultingRecordId.length > 200)) {
    _throwMaintenanceCompletionContractMismatch();
  }
  final rawDueDate = body['resulting_next_due_date'];
  final resultingDueDate = _parseUtc(rawDueDate);
  if (rawDueDate != null &&
      (rawDueDate is! String || resultingDueDate == null)) {
    _throwMaintenanceCompletionContractMismatch();
  }
  final rewardEligibilityToken = body['reward_eligibility_token'];
  if (rewardEligibilityToken != null &&
      (rewardEligibilityToken is! String ||
          !RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
            caseSensitive: false,
          ).hasMatch(rewardEligibilityToken))) {
    _throwMaintenanceCompletionContractMismatch();
  }

  final rawPlan = body['plan'];
  final rawRecord = body['record'];
  if ((rawPlan != null && rawPlan is! Map) ||
      (rawRecord != null && rawRecord is! Map)) {
    _throwMaintenanceCompletionContractMismatch();
  }
  final planData = rawPlan == null
      ? null
      : Map<String, dynamic>.from(rawPlan as Map);
  final recordData = rawRecord == null
      ? null
      : Map<String, dynamic>.from(rawRecord as Map);
  final expectedPlanId = operation['plan_id'];
  final expectedRecordId = operation['operation_id'];
  final expectedOccurrenceId = operation['occurrence_id'];
  if (expectedPlanId is! String ||
      expectedRecordId is! String ||
      expectedOccurrenceId is! String) {
    _throwMaintenanceCompletionContractMismatch();
  }
  if ((planData != null &&
          (planData['user_id'] != userId ||
              planData['id'] != expectedPlanId)) ||
      (recordData != null &&
          (recordData['user_id'] != userId ||
              recordData['plan_id'] != expectedPlanId ||
              recordData['occurrence_id'] != expectedOccurrenceId))) {
    throw const SupabaseFailure(
      kind: SupabaseFailureKind.permissionDenied,
      message: 'The cloud returned maintenance data for another account.',
    );
  }
  final acknowledged =
      status == MaintenanceCompletionStatus.applied ||
      status == MaintenanceCompletionStatus.alreadyApplied;
  if (acknowledged &&
      (body['retryable'] == true ||
          reason != null ||
          currentRevision == null ||
          resultingDueDate == null ||
          planData == null ||
          recordData == null ||
          resultingRecordId == null ||
          recordData['id'] != resultingRecordId ||
          recordData['id'] != expectedRecordId ||
          recordData['time_zone_id'] != operation['time_zone_id'])) {
    _throwMaintenanceCompletionContractMismatch();
  }
  if (status == MaintenanceCompletionStatus.invalid &&
      (reason is! String ||
          !_maintenanceCompletionInvalidReasons.contains(reason) ||
          body['retryable'] == true ||
          currentRevision != null ||
          resultingRecordId != null ||
          resultingDueDate != null ||
          rewardEligibilityToken != null ||
          planData != null ||
          recordData != null)) {
    _throwMaintenanceCompletionContractMismatch();
  }
  if (status == MaintenanceCompletionStatus.conflict) {
    if (reason is! String ||
        !_maintenanceCompletionConflictReasons.contains(reason)) {
      _throwMaintenanceCompletionContractMismatch();
    }
    if (rewardEligibilityToken != null) {
      _throwMaintenanceCompletionContractMismatch();
    }
    final reusedAcrossPlans =
        reason == 'operation_id_reused' && planData == null;
    if (reusedAcrossPlans) {
      if (body['retryable'] == true ||
          currentRevision != null ||
          resultingRecordId != null ||
          resultingDueDate != null ||
          recordData != null) {
        _throwMaintenanceCompletionContractMismatch();
      }
    } else {
      if (currentRevision == null ||
          resultingDueDate == null ||
          planData == null) {
        _throwMaintenanceCompletionContractMismatch();
      }
      final requiresRecord = _maintenanceCompletionConflictsWithRecord.contains(
        reason,
      );
      if (requiresRecord != (recordData != null) ||
          requiresRecord != (resultingRecordId != null) ||
          (requiresRecord && recordData!['id'] != resultingRecordId) ||
          body['retryable'] == true) {
        _throwMaintenanceCompletionContractMismatch();
      }
    }
  }
  if (body['retryable'] == true) {
    _throwMaintenanceCompletionContractMismatch();
  }
  if (planData != null &&
      (planData['revision'] != currentRevision ||
          _parseUtc(planData['next_due_date']) != resultingDueDate)) {
    _throwMaintenanceCompletionContractMismatch();
  }

  try {
    return MaintenanceCompletionResult(
      status: status,
      retryable: body['retryable'] as bool,
      plan: planData == null
          ? null
          : SyncRecord.fromRemote(
              syncSpecByEntity['maintenance_plan']!,
              planData,
            ),
      record: recordData == null
          ? null
          : SyncRecord.fromRemote(
              syncSpecByEntity['maintenance_record']!,
              recordData,
            ),
      currentPlanRevision: (currentRevision as num?)?.toInt(),
      resultingRecordId: resultingRecordId as String?,
      resultingNextDueDate: resultingDueDate,
      conflictReason: reason as String?,
      rewardEligibilityToken: rewardEligibilityToken as String?,
    );
  } on Object {
    _throwMaintenanceCompletionContractMismatch();
  }
}

Never _throwMaintenanceCompletionContractMismatch() {
  throw const SupabaseFailure(
    kind: SupabaseFailureKind.incompatibleSchema,
    message:
        'This Owntend build is not compatible with the maintenance sync '
        'protocol. Install the latest release.',
    retryable: false,
    diagnosticCode: maintenanceCompletionRpcContractMismatchCode,
  );
}

MaintenanceUndoStatus _maintenanceUndoStatus(Object? value) {
  return switch (value) {
    'applied' => MaintenanceUndoStatus.applied,
    'already_applied' => MaintenanceUndoStatus.alreadyApplied,
    'conflict' => MaintenanceUndoStatus.conflict,
    'invalid' => MaintenanceUndoStatus.invalid,
    'unauthorized' => MaintenanceUndoStatus.unauthorized,
    _ => throw const FormatException(
      'The maintenance undo RPC returned an unknown status.',
    ),
  };
}
