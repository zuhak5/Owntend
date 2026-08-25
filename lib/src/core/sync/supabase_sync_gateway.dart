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

enum MaintenanceCompletionStatus {
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

  final MaintenanceCompletionStatus status;
  final bool retryable;
  final SyncRecord? plan;
  final bool rewound;
  final String? conflictReason;

  bool get acknowledged =>
      status == MaintenanceCompletionStatus.applied ||
      status == MaintenanceCompletionStatus.alreadyApplied;
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
    this.conflictReason,
  });

  final MaintenanceCompletionStatus status;
  final bool retryable;
  final SyncRecord? plan;
  final SyncRecord? record;
  final int? currentPlanRevision;
  final String? resultingRecordId;
  final DateTime? resultingNextDueDate;
  final String? conflictReason;

  bool get acknowledged =>
      status == MaintenanceCompletionStatus.applied ||
      status == MaintenanceCompletionStatus.alreadyApplied;
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
    } on Object catch (error) {
      throw SupabaseFailure.from(error);
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

      final payload = await _preparePayload(record, userId, deviceId);
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
        payloads.add(await _preparePayload(record, userId, deviceId));
      }
      final response = await _withDataTimeout(
        () async => _client
            .from(spec.remoteTable)
            .insert(payloads)
            .select(spec.selectClause),
      );
      return BatchWriteSuccess([
        for (final item in response)
          SyncRecord.fromRemote(spec, Map<String, dynamic>.from(item)),
      ]);
    } on PostgrestException catch (error) {
      if (error.code == '23505') {
        final details = error.details?.toString().toLowerCase() ?? '';
        final message = error.message.toLowerCase();
        final isPkey =
            details.contains('_pkey') ||
            message.contains('_pkey') ||
            details.contains('primary key') ||
            message.contains('primary key') ||
            error.details == null;
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
      final operation = Map<String, dynamic>.from(decoded);
      final Object? response = await _withDataTimeout<Object?>(
        () async => _client.rpc<Map<String, dynamic>>(
          'complete_maintenance_task',
          params: {'p_operation': operation, 'p_device_id': deviceId},
        ),
      );
      if (response is! Map) {
        throw const FormatException(
          'The maintenance completion RPC returned an invalid result.',
        );
      }

      final body = Map<String, dynamic>.from(response);
      final status = _maintenanceCompletionStatus(body['status']);
      final rawPlan = body['plan'];
      final rawRecord = body['record'];
      final planData = rawPlan is Map
          ? Map<String, dynamic>.from(rawPlan)
          : null;
      final recordData = rawRecord is Map
          ? Map<String, dynamic>.from(rawRecord)
          : null;
      if ((planData != null && planData['user_id'] != userId) ||
          (recordData != null && recordData['user_id'] != userId)) {
        throw const SupabaseFailure(
          kind: SupabaseFailureKind.permissionDenied,
          message: 'The cloud returned maintenance data for another account.',
        );
      }
      if ((status == MaintenanceCompletionStatus.applied ||
              status == MaintenanceCompletionStatus.alreadyApplied) &&
          (planData == null || recordData == null)) {
        throw const FormatException(
          'The maintenance completion RPC omitted canonical records.',
        );
      }

      return MaintenanceCompletionResult(
        status: status,
        retryable: body['retryable'] == true,
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
        currentPlanRevision: (body['current_plan_revision'] as num?)?.toInt(),
        resultingRecordId: body['resulting_record_id'] as String?,
        resultingNextDueDate: _parseUtc(body['resulting_next_due_date']),
        conflictReason: body['conflict_reason'] as String?,
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
      final status = _maintenanceCompletionStatus(body['status']);
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
      if ((status == MaintenanceCompletionStatus.applied ||
              status == MaintenanceCompletionStatus.alreadyApplied) &&
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

  Future<Map<String, dynamic>> _preparePayload(
    SyncRecord record,
    String userId,
    String deviceId,
  ) async {
    final payload = record.toRemotePayload(userId, deviceId: deviceId);
    if (record.isDeleted) {
      return payload;
    }
    if (record.spec.entity == 'asset_photo') {
      payload.remove('object_path');
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
  const BatchWriteSuccess(this.records);
  final List<SyncRecord> records;
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
    'unauthorized' => MaintenanceCompletionStatus.unauthorized,
    _ => throw const FormatException(
      'The maintenance completion RPC returned an unknown status.',
    ),
  };
}
