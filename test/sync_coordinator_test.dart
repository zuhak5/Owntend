import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/wait_for.dart';

import 'package:owntend/src/core/data/repositories.dart';
import 'package:owntend/src/core/database/app_database.dart';
import 'package:owntend/src/core/domain/contracts.dart';
import 'package:owntend/src/core/domain/models.dart';
import 'package:owntend/src/core/supabase/supabase_failure.dart';
import 'package:owntend/src/core/sync/change_feed_contract.dart';
import 'package:owntend/src/core/sync/local_sync_store.dart';
import 'package:owntend/src/core/sync/supabase_sync_gateway.dart';
import 'package:owntend/src/core/sync/sync_coordinator.dart';
import 'package:owntend/src/core/sync/sync_connectivity.dart';

import 'support/maintenance_test_extensions.dart';

import 'package:owntend/src/core/sync/sync_contracts.dart';
import 'package:owntend/src/core/sync/sync_dtos.dart';
import 'package:owntend/src/features/auth/domain/auth_repository.dart';
import 'package:mocktail/mocktail.dart';

class _MockGateway extends Mock implements SupabaseSyncGateway {}

class _StatefulGateway implements SupabaseSyncGateway {
  final List<_StoredRecord> _records = [];
  final List<_StoredRecord> _feed = [];
  final Map<String, int> pullCalls = {};
  final Map<String, int> writeCalls = {};
  var batchWriteCalls = 0;
  Set<String> batchPreexistingKeys = const {};
  var materializeMediaCalls = 0;
  var startRealtimeCalls = 0;
  var maintenanceCompletionCalls = 0;
  var maintenanceUndoCalls = 0;
  var maintenanceHistoryRestoreCalls = 0;
  MaintenanceHistoryRestoreResult? maintenanceHistoryRestoreResult;
  String? _activeUserId = 'user-1';
  Completer<void>? maintenanceCompletionGate;
  int? failMaintenanceCompletionCall;
  MaintenanceCompletionResult? forcedMaintenanceCompletionResult;
  final queuedMaintenanceCompletionResults = <MaintenanceCompletionResult>[];
  bool maintenanceConflictWithCanonicalPlan = false;
  Completer<void>? materializeMediaGate;
  Completer<void>? pullGate;
  Completer<void>? startRealtimeGate;
  Completer<void>? feedGate;
  var fetchFeedCalls = 0;

  void seedMaintenancePlan({
    required String userId,
    required String planId,
    required String assetId,
    required String currentOccurrenceId,
    required DateTime nextDueDate,
    int recurrenceInterval = 1,
    String recurrenceUnit = 'months',
    bool isEnabled = true,
  }) {
    final canonicalAt = nextDueDate.subtract(const Duration(days: 1));
    _records.add(
      _StoredRecord(
        userId: userId,
        deviceId: null,
        record: SyncRecord(
          spec: syncSpecByEntity['maintenance_plan']!,
          recordKey: planId,
          values: {
            'id': planId,
            'asset_id': assetId,
            'title': 'Remote maintenance task',
            'instructions': null,
            'recurrence_interval': recurrenceInterval,
            'recurrence_unit': recurrenceUnit,
            'priority': 'medium',
            'current_occurrence_id': currentOccurrenceId,
            'next_due_date': nextDueDate.toUtc().toIso8601String(),
            'is_enabled': isEnabled,
            'reminder_days_before': 0,
            'created_at': canonicalAt.toIso8601String(),
            'updated_at': canonicalAt.toIso8601String(),
            'archived_at': null,
          },
          clientModifiedAt: canonicalAt,
          originDeviceId: 'remote-device',
          revision: 1,
          serverUpdatedAt: canonicalAt,
        ),
        changeSeq: _syncSeq,
      ),
    );
  }

  @override
  Future<String> prepareMaintenanceHistoryRestorePayload({
    required String payloadJson,
    required String userId,
    required String deviceId,
  }) async => payloadJson;

  @override
  Future<MaintenanceHistoryRestoreResult> restoreMaintenanceHistory({
    required String payloadJson,
    required String userId,
    required String deviceId,
  }) async {
    maintenanceHistoryRestoreCalls += 1;
    return maintenanceHistoryRestoreResult ??
        const MaintenanceHistoryRestoreResult(
          status: 'applied',
          insertedCount: 0,
          existingCount: 0,
          alreadyProcessed: false,
        );
  }

  @override
  Future<Set<String>> fetchAuthoritativeRecordKeys({
    required SyncEntitySpec spec,
    required String userId,
    required String deviceId,
  }) async {
    return {
      for (final stored in _records)
        if (stored.userId == userId &&
            stored.record.spec.entity == spec.entity &&
            (spec.scope != SyncScope.deviceScoped ||
                stored.deviceId == deviceId) &&
            !stored.record.isDeleted)
          stored.record.recordKey,
    };
  }

  var _syncSeq = 0;
  void Function(RealtimeSyncEvent)? onRealtimeChange;
  void Function(SyncEntitySpec, Map<String, dynamic>)? onRealtimeDelete;

  @override
  Future<UserChangeFeedPage> fetchUserChangeFeed({
    int sinceSeq = 0,
    int limit = 100,
    int? expectedGeneration,
  }) async {
    fetchFeedCalls++;
    await feedGate?.future;
    final activeUserId = _activeUserId;
    final feedRecords = _feed
        .where(
          (item) => item.userId == activeUserId && item.changeSeq > sinceSeq,
        )
        .take(limit)
        .toList();
    final userHighWater = _feed
        .where((item) => item.userId == activeUserId)
        .fold<int>(0, (value, item) => math.max(value, item.changeSeq));
    final nextSeq = feedRecords.isEmpty ? sinceSeq : feedRecords.last.changeSeq;
    return UserChangeFeedPage(
      entries: [
        for (final item in feedRecords)
          ChangeFeedEntry(
            changeSeq: item.changeSeq,
            record: item.record,
            operation: item.record.isDeleted ? 'DELETE' : 'UPDATE',
          ),
      ],
      highWaterSeq: userHighWater,
      nextSeq: nextSeq,
      hasMore: nextSeq < userHighWater,
      resnapshotRequired: false,
    );
  }

  @override
  Future<UserChangeFeedWatermark> fetchUserChangeFeedHighWater() async =>
      UserChangeFeedWatermark(highWaterSeq: _syncSeq);

  @override
  Future<BatchWriteResult> writeNewBatch({
    required List<SyncRecord> records,
    required String userId,
    required String deviceId,
  }) async {
    batchWriteCalls++;
    // Simulate PostgREST `Prefer: resolution=ignore-duplicates`: keys listed
    // in [batchPreexistingKeys] are skipped by the server instead of aborting
    // the statement, and only freshly inserted rows are returned.
    final canonical = <SyncRecord>[];
    final replayedKeys = <String>{};
    for (final record in records) {
      if (batchPreexistingKeys.contains(record.recordKey)) {
        final existing = await fetch(
          spec: record.spec,
          userId: userId,
          deviceId: deviceId,
          recordKey: record.recordKey,
        );
        if (existing == null) {
          return const BatchWriteConflict(
            code: '23505',
            message: 'Conflict',
            details: 'primary key',
            isPrimaryKeyConflict: true,
          );
        }
        replayedKeys.add(record.recordKey);
        continue;
      }
      final result = await write(
        record: record,
        userId: userId,
        deviceId: deviceId,
        expectedRevision: null,
      );
      if (result.conflict || result.canonical == null) {
        return const BatchWriteConflict(
          code: '23505',
          message: 'Conflict',
          details: 'primary key',
          isPrimaryKeyConflict: true,
        );
      }
      canonical.add(result.canonical!);
    }
    return BatchWriteSuccess(canonical, replayedRecordKeys: replayedKeys);
  }

  @override
  Future<MaintenanceCompletionResult> completeMaintenance({
    required String payloadJson,
    required String userId,
    required String deviceId,
  }) async {
    maintenanceCompletionCalls++;
    await maintenanceCompletionGate?.future;

    if (maintenanceCompletionCalls == failMaintenanceCompletionCall) {
      throw const SupabaseFailure(
        kind: SupabaseFailureKind.conflict,
        message: 'This maintenance completion conflicts with newer cloud data.',
      );
    }
    if (queuedMaintenanceCompletionResults.isNotEmpty) {
      return queuedMaintenanceCompletionResults.removeAt(0);
    }
    final forcedResult = forcedMaintenanceCompletionResult;
    if (forcedResult != null) return forcedResult;

    final payload = Map<String, dynamic>.from(jsonDecode(payloadJson) as Map);
    final planSpec = syncSpecByEntity['maintenance_plan']!;
    final recordSpec = syncSpecByEntity['maintenance_record']!;
    final planId = payload['plan_id']! as String;
    final operationId = payload['operation_id']! as String;
    final occurrenceId = payload['occurrence_id']! as String;
    final completedAt = DateTime.parse(payload['completed_at']! as String)
        .toUtc();
    final timeZoneId = payload['time_zone_id']! as String;

    final existingRecord = await fetch(
      spec: recordSpec,
      userId: userId,
      deviceId: deviceId,
      recordKey: operationId,
    );
    if (existingRecord != null) {
      final existingPlan = await fetch(
        spec: planSpec,
        userId: userId,
        deviceId: deviceId,
        recordKey: planId,
      );
      if (existingPlan == null) {
        throw StateError('The idempotent completion lost its plan.');
      }
      final sameIntent =
          existingRecord.values['plan_id'] == planId &&
          existingRecord.values['occurrence_id'] == occurrenceId &&
          existingRecord.values['completed_at'] ==
              completedAt.toIso8601String() &&
          existingRecord.values['time_zone_id'] == timeZoneId &&
          existingRecord.values['notes'] == payload['notes'];
      return MaintenanceCompletionResult(
        status: sameIntent
            ? MaintenanceCompletionStatus.alreadyApplied
            : MaintenanceCompletionStatus.conflict,
        retryable: false,
        conflictReason: sameIntent ? null : 'operation_id_reused',
        plan: existingPlan,
        record: existingRecord,
      );
    }

    final existingPlan = await fetch(
      spec: planSpec,
      userId: userId,
      deviceId: deviceId,
      recordKey: planId,
    );
    if (existingPlan == null) {
      return const MaintenanceCompletionResult(
        status: MaintenanceCompletionStatus.invalid,
        retryable: false,
        conflictReason: 'plan_unavailable',
      );
    }
    if (maintenanceConflictWithCanonicalPlan ||
        existingPlan.values['current_occurrence_id'] != occurrenceId) {
      final matchingOccurrence = _records
          .where(
            (item) =>
                item.userId == userId &&
                item.record.spec.entity == 'maintenance_record' &&
                item.record.values['plan_id'] == planId &&
                item.record.values['occurrence_id'] == occurrenceId,
          )
          .map((item) => item.record)
          .firstOrNull;
      return MaintenanceCompletionResult(
        status: MaintenanceCompletionStatus.conflict,
        retryable: false,
        plan: existingPlan,
        record: matchingOccurrence,
        currentPlanRevision: existingPlan.revision,
        resultingRecordId: matchingOccurrence?.recordKey,
        resultingNextDueDate: DateTime.parse(
          existingPlan.values['next_due_date']! as String,
        ).toUtc(),
        conflictReason: matchingOccurrence == null
            ? 'stale_occurrence'
            : 'occurrence_completed_elsewhere',
      );
    }

    SyncRecord storeCanonical(SyncRecord local) {
      final storedIndex = _records.indexWhere(
        (item) =>
            item.userId == userId &&
            item.record.spec.entity == local.spec.entity &&
            item.record.recordKey == local.recordKey,
      );
      final existing = storedIndex < 0 ? null : _records[storedIndex].record;
      final canonical = _canonical(
        local,
        existing: existing,
        revision: (existing?.revision ?? 0) + 1,
      );
      final stored = _StoredRecord(
        userId: userId,
        deviceId: null,
        record: canonical,
        changeSeq: _syncSeq,
      );
      if (storedIndex < 0) {
        _records.add(stored);
      } else {
        _records[storedIndex] = stored;
      }
      _feed.add(stored);
      return canonical;
    }

    final nextDue = _advanceTestRecurrence(
      completedAt,
      existingPlan.values['recurrence_interval']! as int,
      existingPlan.values['recurrence_unit']! as String,
    );
    final canonicalAt = completedAt.add(const Duration(seconds: 1));
    final plan = storeCanonical(
      SyncRecord(
        spec: planSpec,
        recordKey: planId,
        values: {
          ...existingPlan.values,
          'current_occurrence_id': 'next:$operationId',
          'next_due_date': nextDue.toIso8601String(),
          'updated_at': canonicalAt.toIso8601String(),
        },
        clientModifiedAt: canonicalAt,
        originDeviceId: deviceId,
      ),
    );
    final record = storeCanonical(
      SyncRecord(
        spec: recordSpec,
        recordKey: operationId,
        values: {
          'id': operationId,
          'plan_id': planId,
          'occurrence_id': occurrenceId,
          'due_date': existingPlan.values['next_due_date'],
          'completed_at': completedAt.toIso8601String(),
          'accepted_at': canonicalAt.toIso8601String(),
          'time_zone_id': timeZoneId,
          'notes': payload['notes'],
          'operation_id': operationId,
        },
        clientModifiedAt: completedAt,
        originDeviceId: deviceId,
      ),
    );

    return MaintenanceCompletionResult(
      status: MaintenanceCompletionStatus.applied,
      retryable: false,
      plan: plan,
      record: record,
    );
  }

  DateTime _advanceTestRecurrence(
    DateTime completedAt,
    int interval,
    String unit,
  ) {
    return switch (unit) {
      'hours' => completedAt.add(Duration(hours: interval)),
      'days' => completedAt.add(Duration(days: interval)),
      'weeks' => completedAt.add(Duration(days: interval * 7)),
      'months' => _addTestCalendarMonths(completedAt, interval),
      'years' => _addTestCalendarMonths(completedAt, interval * 12),
      _ => throw StateError('Unsupported recurrence unit: $unit'),
    };
  }

  DateTime _addTestCalendarMonths(DateTime value, int months) {
    final monthIndex = value.month - 1 + months;
    final year = value.year + monthIndex ~/ 12;
    final month = monthIndex % 12 + 1;
    final lastDay = DateTime.utc(year, month + 1, 0).day;
    return DateTime.utc(
      year,
      month,
      math.min(value.day, lastDay),
      value.hour,
      value.minute,
      value.second,
    );
  }

  @override
  Future<MaintenanceUndoResult> undoMaintenanceCompletion({
    required String payloadJson,
    required String userId,
    required String deviceId,
  }) async {
    maintenanceUndoCalls++;
    final payload = Map<String, dynamic>.from(jsonDecode(payloadJson) as Map);
    final planId = payload['plan_id']! as String;
    final completionId = payload['completion_id']! as String;
    final previousDue = DateTime.parse(payload['previous_due_date']! as String)
        .toUtc();
    final expectedCurrent = DateTime.parse(
      payload['expected_current_next_due_date']! as String,
    ).toUtc();
    final planIndex = _records.indexWhere(
      (item) =>
          item.userId == userId &&
          item.record.spec.entity == 'maintenance_plan' &&
          item.record.recordKey == planId,
    );
    if (planIndex < 0) {
      return const MaintenanceUndoResult(
        status: MaintenanceUndoStatus.invalid,
        retryable: false,
        conflictReason: 'plan_missing',
      );
    }
    final completionIndex = _records.indexWhere(
      (item) =>
          item.userId == userId &&
          item.record.spec.entity == 'maintenance_record' &&
          item.record.recordKey == completionId,
    );
    if (completionIndex >= 0) {
      _records.removeAt(completionIndex);
    }
    var plan =
        _records[planIndex > completionIndex && completionIndex >= 0
                ? planIndex - 1
                : planIndex]
            .record;
    final currentDue = DateTime.parse(plan.values['next_due_date']! as String)
        .toUtc();
    var rewound = false;
    final newerCompletionExists = _records.any(
      (item) =>
          item.userId == userId &&
          item.record.spec.entity == 'maintenance_record' &&
          item.record.values['plan_id'] == planId,
    );
    if (!newerCompletionExists &&
        currentDue.isAtSameMomentAs(expectedCurrent)) {
      final updated = SyncRecord(
        spec: plan.spec,
        recordKey: plan.recordKey,
        values: {
          ...plan.values,
          'next_due_date': previousDue.toIso8601String(),
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
        clientModifiedAt: DateTime.now().toUtc(),
        originDeviceId: deviceId,
      );
      final result = await write(
        record: updated,
        userId: userId,
        deviceId: deviceId,
        expectedRevision: plan.revision,
      );
      plan = result.canonical!;
      rewound = true;
    }
    return MaintenanceUndoResult(
      status: MaintenanceUndoStatus.applied,
      retryable: false,
      plan: plan,
      rewound: rewound,
    );
  }

  @override
  Future<void> startRealtime({
    required String userId,
    required String deviceId,
    required void Function(RealtimeSyncEvent event) onChange,
    required void Function(SyncEntitySpec spec, Map<String, dynamic> oldRecord)
    onDelete,
    required void Function(SyncRealtimeStatus status, Object? error) onStatus,
  }) async {
    startRealtimeCalls++;
    _activeUserId = userId;
    await startRealtimeGate?.future;
    onRealtimeChange = onChange;
    onRealtimeDelete = onDelete;
    onStatus(SyncRealtimeStatus.subscribed, null);
  }

  @override
  Future<void> stopRealtime() async {
    onRealtimeChange = null;
    onRealtimeDelete = null;
  }

  @override
  Future<List<SyncRecord>> pullAuthoritativeSnapshotPage({
    required SyncEntitySpec spec,
    required String userId,
    required String deviceId,
    String? afterRecordKey,
    void Function(int exactCount)? onExactCount,
    bool materializeMedia = true,
  }) async {
    _activeUserId = userId;
    pullCalls[spec.entity] = (pullCalls[spec.entity] ?? 0) + 1;
    await pullGate?.future;
    final records =
        _records
            .where(
              (item) =>
                  item.userId == userId &&
                  item.record.spec.entity == spec.entity &&
                  (spec.scope != SyncScope.deviceScoped ||
                      item.deviceId == deviceId) &&
                  item.record.recordKey.compareTo(afterRecordKey ?? '') > 0,
            )
            .map((item) => item.record)
            .toList()
          ..sort((a, b) => a.recordKey.compareTo(b.recordKey));
    onExactCount?.call(records.length);
    return records.take(SupabaseSyncGateway.pageSize).toList();
  }

  @override
  Future<SyncRecord> materializeRemoteMedia(
    SyncRecord record,
    String userId,
  ) async {
    materializeMediaCalls++;
    await materializeMediaGate?.future;
    return SyncRecord(
      spec: record.spec,
      recordKey: record.recordKey,
      values: {...record.values, 'relative_path': 'C:\\cache\\restored.jpg'},
      clientModifiedAt: record.clientModifiedAt,
      originDeviceId: record.originDeviceId,
      revision: record.revision,
      serverUpdatedAt: record.serverUpdatedAt,
      deletedAt: record.deletedAt,
    );
  }

  @override
  Future<RemoteWriteResult> write({
    required SyncRecord record,
    required String userId,
    required String deviceId,
    required int? expectedRevision,
    Map<String, dynamic>? bundledPayload,
  }) async {
    writeCalls[record.spec.entity] = (writeCalls[record.spec.entity] ?? 0) + 1;
    final index = _records.indexWhere(
      (item) =>
          item.userId == userId &&
          item.record.spec.entity == record.spec.entity &&
          item.record.recordKey == record.recordKey &&
          (record.spec.scope != SyncScope.deviceScoped ||
              item.deviceId == deviceId),
    );
    final existing = index < 0 ? null : _records[index].record;
    if (expectedRevision == null && existing != null) {
      return RemoteWriteResult.conflict(existing);
    }
    if (expectedRevision != null &&
        (existing == null || existing.revision != expectedRevision)) {
      return RemoteWriteResult.conflict(existing);
    }
    final canonical = _canonical(
      record,
      existing: existing,
      revision: (existing?.revision ?? 0) + 1,
    );
    final stored = _StoredRecord(
      userId: userId,
      deviceId: record.spec.scope == SyncScope.deviceScoped ? deviceId : null,
      record: canonical,
      changeSeq: _syncSeq,
    );
    if (index < 0) {
      _records.add(stored);
    } else {
      _records[index] = stored;
    }
    _feed.add(stored);
    return RemoteWriteResult.applied(canonical);
  }

  @override
  Future<SyncRecord?> fetch({
    required SyncEntitySpec spec,
    required String userId,
    required String deviceId,
    required String recordKey,
    bool materializeMedia = true,
  }) async {
    for (final item in _records) {
      if (item.userId == userId &&
          item.record.spec.entity == spec.entity &&
          item.record.recordKey == recordKey &&
          (spec.scope != SyncScope.deviceScoped || item.deviceId == deviceId)) {
        return item.record;
      }
    }
    return null;
  }

  @override
  Future<void> removeMediaObject(String objectPath, String userId) async {}

  @override
  Future<Map<String, dynamic>> setPrimaryAssetPhoto({
    required String assetId,
    required String photoId,
  }) async => {
    'success': true,
    'asset_id': assetId,
    'primary_photo_id': photoId,
  };

  SyncRecord _canonical(
    SyncRecord record, {
    required SyncRecord? existing,
    required int revision,
  }) {
    ++_syncSeq;
    return SyncRecord(
      spec: record.spec,
      recordKey: record.recordKey,
      values: {...?existing?.values, ...record.values},
      clientModifiedAt: record.clientModifiedAt,
      originDeviceId: record.originDeviceId,
      revision: revision,
      serverUpdatedAt: DateTime.now().toUtc(),
      deletedAt: record.deletedAt,
    );
  }

  void hardDelete({
    required String userId,
    required SyncEntitySpec spec,
    required String recordKey,
    String? deviceId,
  }) {
    final deleted = _records
        .where(
          (item) =>
              item.userId == userId &&
              item.record.spec.entity == spec.entity &&
              item.record.recordKey == recordKey &&
              (spec.scope != SyncScope.deviceScoped ||
                  item.deviceId == deviceId),
        )
        .firstOrNull;
    _records.removeWhere(
      (item) =>
          item.userId == userId &&
          item.record.spec.entity == spec.entity &&
          item.record.recordKey == recordKey &&
          (spec.scope != SyncScope.deviceScoped || item.deviceId == deviceId),
    );
    final deletedAt = DateTime.now().toUtc();
    _feed.add(
      _StoredRecord(
        userId: userId,
        deviceId: deviceId,
        changeSeq: ++_syncSeq,
        record: SyncRecord(
          spec: spec,
          recordKey: recordKey,
          values: {
            for (var index = 0; index < spec.keyColumns.length; index++)
              spec.keyColumns[index]: recordKey.split('|')[index],
          },
          clientModifiedAt: deletedAt,
          originDeviceId: deleted?.record.originDeviceId ?? 'remote-device',
          revision: deleted?.record.revision ?? 1,
          serverUpdatedAt: deletedAt,
          deletedAt: deletedAt,
        ),
      ),
    );
    final keyParts = recordKey.split('|');
    onRealtimeDelete!(spec, {
      'user_id': userId,
      if (spec.scope == SyncScope.deviceScoped) 'device_id': deviceId,
      for (var index = 0; index < spec.keyColumns.length; index++)
        spec.remoteColumnFor(spec.keyColumns[index]): keyParts[index],
    });
  }
}

class _FailingOnceGateway extends _StatefulGateway {
  var failNextPull = true;

  @override
  Future<List<SyncRecord>> pullAuthoritativeSnapshotPage({
    required SyncEntitySpec spec,
    required String userId,
    required String deviceId,
    String? afterRecordKey,
    void Function(int exactCount)? onExactCount,
    bool materializeMedia = true,
  }) async {
    if (failNextPull) {
      failNextPull = false;
      throw const SupabaseFailure(
        kind: SupabaseFailureKind.offline,
        message: 'Temporary restore interruption.',
        retryable: true,
      );
    }
    return super.pullAuthoritativeSnapshotPage(
      spec: spec,
      userId: userId,
      deviceId: deviceId,
      afterRecordKey: afterRecordKey,
      onExactCount: onExactCount,
      materializeMedia: materializeMedia,
    );
  }
}

class _StackFailureGateway extends _StatefulGateway {
  @override
  Future<List<SyncRecord>> pullAuthoritativeSnapshotPage({
    required SyncEntitySpec spec,
    required String userId,
    required String deviceId,
    String? afterRecordKey,
    void Function(int exactCount)? onExactCount,
    bool materializeMedia = true,
  }) {
    throw StateError('synthetic stack-preservation failure');
  }
}

class _DelayedFinalizationStore extends LocalSyncStore {
  _DelayedFinalizationStore(super.db);

  final releaseCommit = Completer<void>();

  @override
  Future<void> completeInitialHydration(
    DateTime completedAt, {
    required String expectedRunId,
  }) async {
    await releaseCommit.future;
    await super.completeInitialHydration(
      completedAt,
      expectedRunId: expectedRunId,
    );
  }
}

class _StoredRecord {
  const _StoredRecord({
    required this.userId,
    required this.deviceId,
    required this.record,
    this.changeSeq = 0,
  });

  final String userId;
  final String? deviceId;
  final SyncRecord record;
  final int changeSeq;
}

class _FakeAuthRepository implements AuthRepository {
  _FakeAuthRepository(this.session);

  AuthSession? session;
  final controller = StreamController<AuthStateChange>.broadcast();

  @override
  AuthSession? get currentSession => session;

  @override
  Future<void> deleteAccount() async {}

  @override
  Future<void> signInWithGoogle() async {}

  @override
  Future<void> signOut({bool allDevices = false}) async {
    session = null;
    controller.add(
      const AuthStateChange(event: AuthEventType.signedOut, session: null),
    );
  }

  @override
  Stream<AuthStateChange> watchAuthState() => controller.stream;

  void emit(AuthEventType event, AuthSession? nextSession) {
    session = nextSession;
    controller.add(AuthStateChange(event: event, session: nextSession));
  }
}

class _FakeConnectivity implements SyncConnectivity {
  _FakeConnectivity(this.online);

  bool online;
  final controller = StreamController<bool>.broadcast();

  @override
  Future<bool> isOnline() async => online;

  @override
  Stream<bool> watchOnline() async* {
    yield online;
    yield* controller.stream;
  }

  void setOnline(bool value) {
    online = value;
    controller.add(value);
  }
}

Future<void> _waitFor(FutureOr<bool> Function() condition) async =>
    // WP-015 (F-024): shared bounded helper replaces the wall-clock loop.
    waitFor(() async => await condition());

void main() {
  setUpAll(() {
    registerFallbackValue(syncEntitySpecs.first);
    registerFallbackValue(
      SyncRecord(
        spec: syncEntitySpecs.first,
        recordKey: 'fallback',
        values: const {},
        clientModifiedAt: DateTime.utc(2026),
        originDeviceId: 'fallback',
      ),
    );
  });

  test('blocks a different account from claiming bound local data', () async {
    final db = AppDatabase(executor: NativeDatabase.memory());
    addTearDown(db.close);
    final store = LocalSyncStore(db);
    await store.account();
    await store.setEnabled(enabled: false, boundUserId: 'original-user');
    final auth = _FakeAuthRepository(
      const AuthSession(userId: 'different-user'),
    );
    addTearDown(auth.controller.close);
    final coordinator = SyncCoordinator(auth, store, _MockGateway());
    addTearDown(coordinator.dispose);

    expect(
      coordinator.enable,
      throwsA(
        isA<SupabaseFailure>().having(
          (failure) => failure.kind,
          'kind',
          SupabaseFailureKind.permissionDenied,
        ),
      ),
    );
  });

  test('generic enable cannot bypass a paused local restore', () async {
    final db = AppDatabase(executor: NativeDatabase.memory());
    addTearDown(db.close);
    final store = LocalSyncStore(db);
    await store.account();
    await store.pauseAfterLocalRestore();
    final auth = _FakeAuthRepository(const AuthSession(userId: 'user-1'));
    addTearDown(auth.controller.close);
    final coordinator = SyncCoordinator(auth, store, _MockGateway());
    addTearDown(coordinator.dispose);

    await expectLater(
      coordinator.enable(),
      throwsA(
        isA<SupabaseFailure>()
            .having(
              (failure) => failure.kind,
              'kind',
              SupabaseFailureKind.conflict,
            )
            .having(
              (failure) => failure.diagnosticCode,
              'diagnosticCode',
              'restore_sync_confirmation_required',
            ),
      ),
    );

    final account = await store.account();
    expect(account.enabled, isFalse);
    expect(account.boundUserId, isNull);
    expect(account.migrationState, 'restorePaused');
    expect(account.restorePending, isTrue);
  });

  test('account deletion barrier discards late active pull results', () async {
    final db = AppDatabase(executor: NativeDatabase.memory());
    addTearDown(db.close);
    final store = LocalSyncStore(db);
    final initialAccount = await store.account();
    await store.setEnabled(
      enabled: true,
      boundUserId: 'user-1',
      migrationState: 'active',
    );
    await store.recordSyncSuccess(DateTime.utc(2026, 8, 3, 10));
    final auth = _FakeAuthRepository(const AuthSession(userId: 'user-1'));
    addTearDown(auth.controller.close);
    final gateway = _StatefulGateway()..feedGate = Completer<void>();
    await gateway.write(
      record: SyncRecord(
        spec: syncSpecByEntity['area']!,
        recordKey: 'remote-area-after-delete',
        values: {
          'id': 'remote-area-after-delete',
          'name': 'Late remote area',
          'kind': 'indoor',
          'sort_order': 0,
          'created_at': DateTime.utc(2026, 8, 3, 9),
          'updated_at': DateTime.utc(2026, 8, 3, 9),
          'archived_at': null,
        },
        clientModifiedAt: DateTime.utc(2026, 8, 3, 9),
        originDeviceId: 'remote-device',
      ),
      userId: 'user-1',
      deviceId: initialAccount.deviceId,
      expectedRevision: null,
    );
    final coordinator = SyncCoordinator(
      auth,
      store,
      gateway,
      connectivity: _FakeConnectivity(true),
      listenToAuthChanges: false,
    );
    addTearDown(coordinator.dispose);

    final syncFuture = coordinator.syncIncremental();
    await _waitFor(() => gateway.fetchFeedCalls > 0);

    final prepareFuture = coordinator.prepareForAccountDeletion('user-1');
    await _waitFor(() async {
      final status = await coordinator.status();
      return status.message == 'Account deletion is in progress.';
    });

    await store.clearAllAccountData(expectedUserId: 'user-1');
    gateway.feedGate!.complete();

    await syncFuture;
    await prepareFuture;

    expect(
      await (db.select(
        db.areas,
      )..where((area) => area.id.equals('remote-area-after-delete'))).get(),
      isEmpty,
    );
    expect(await db.select(db.syncCursors).get(), isEmpty);
    expect(await db.select(db.syncOutbox).get(), isEmpty);
    expect(await store.existingAccount(), isNull);
  });

  test(
    'local snapshot commit has its own bounded finalization timeout',
    () async {
      final db = AppDatabase(executor: NativeDatabase.memory());
      addTearDown(db.close);
      final store = _DelayedFinalizationStore(db);
      await store.account();
      final auth = _FakeAuthRepository(
        const AuthSession(userId: 'finalization-timeout-user'),
      );
      addTearDown(auth.controller.close);
      final coordinator = SyncCoordinator(
        auth,
        store,
        _StatefulGateway(),
        localFinalizationTimeout: const Duration(milliseconds: 40),
      );
      addTearDown(coordinator.dispose);
      addTearDown(() {
        if (!store.releaseCommit.isCompleted) store.releaseCommit.complete();
      });

      await expectLater(
        coordinator.enable(),
        throwsA(
          isA<SupabaseFailure>()
              .having(
                (failure) => failure.message,
                'message',
                contains('commit local home snapshot'),
              )
              .having((failure) => failure.retryable, 'retryable', isTrue),
        ),
      );

      final failed = await store.hydrationProgress();
      expect(failed?.stage, InitialHydrationStage.finalizing);
      expect(failed?.state, RestoreRunState.failed);
      expect((await store.account()).lastSyncedAt, isNull);

      store.releaseCommit.complete();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(
        (await store.account()).lastSyncedAt,
        isNull,
        reason: 'the timed-out commit may not publish success later',
      );
    },
  );

  test('fresh sign-in automatically performs cloud-first hydration', () async {
    final db = AppDatabase(executor: NativeDatabase.memory());
    addTearDown(db.close);
    final store = LocalSyncStore(db);
    await store.account();
    final auth = _FakeAuthRepository(null);
    addTearDown(auth.controller.close);
    final gateway = _StatefulGateway();
    final now = DateTime.utc(2026, 6, 30);
    await gateway.write(
      record: SyncRecord(
        spec: syncSpecByEntity['area']!,
        recordKey: 'area_first_floor',
        values: {
          'id': 'area_first_floor',
          'name': 'First Floor',
          'kind': 'indoor',
          'sort_order': 0,
          'created_at': now.toIso8601String(),
          'updated_at': now.toIso8601String(),
          'archived_at': null,
        },
        clientModifiedAt: now,
        originDeviceId: 'existing-device',
      ),
      userId: 'fresh-user',
      deviceId: 'existing-device',
      expectedRevision: null,
    );
    await gateway.write(
      record: SyncRecord(
        spec: syncSpecByEntity['room']!,
        recordKey: 'cloud-room',
        values: {
          'id': 'cloud-room',
          'area_id': 'area_first_floor',
          'name': 'Existing cloud room',
          'room_type': 'office',
          'notes': null,
          'sort_order': 0,
          'created_at': now.toIso8601String(),
          'updated_at': now.toIso8601String(),
          'archived_at': null,
        },
        clientModifiedAt: now,
        originDeviceId: 'existing-device',
      ),
      userId: 'fresh-user',
      deviceId: 'existing-device',
      expectedRevision: null,
    );
    await gateway.write(
      record: SyncRecord(
        spec: syncSpecByEntity['asset']!,
        recordKey: 'cloud-asset',
        values: {
          'id': 'cloud-asset',
          'name': 'Existing cloud asset',
          'asset_type': 'general',
          'room_id': 'cloud-room',
          'placement': null,
          'notes': null,
          'purchase_date': null,
          'created_at': now.toIso8601String(),
          'updated_at': now.toIso8601String(),
          'archived_at': null,
        },
        clientModifiedAt: now,
        originDeviceId: 'existing-device',
      ),
      userId: 'fresh-user',
      deviceId: 'existing-device',
      expectedRevision: null,
    );
    await gateway.write(
      record: SyncRecord(
        spec: syncSpecByEntity['asset_photo']!,
        recordKey: 'cloud-photo',
        values: {
          'id': 'cloud-photo',
          'asset_id': 'cloud-asset',
          'relative_path': 'fresh-user/cloud-photo.jpg',
          'caption': null,
          'is_primary': true,
          'created_at': now.toIso8601String(),
        },
        clientModifiedAt: now,
        originDeviceId: 'existing-device',
      ),
      userId: 'fresh-user',
      deviceId: 'existing-device',
      expectedRevision: null,
    );
    gateway.pullCalls.clear();
    gateway.writeCalls.clear();
    gateway.batchWriteCalls = 0;
    gateway.materializeMediaGate = Completer<void>();
    final coordinator = SyncCoordinator(
      auth,
      store,
      gateway,
      realtime: gateway,
    );
    addTearDown(coordinator.dispose);
    final hydrationStages = <InitialHydrationStage>[];
    final statusSubscription = coordinator.watchStatus().listen((status) {
      final stage = status.initialHydrationProgress?.stage;
      if (stage != null &&
          (hydrationStages.isEmpty || hydrationStages.last != stage)) {
        hydrationStages.add(stage);
      }
    });
    addTearDown(statusSubscription.cancel);

    auth.emit(AuthEventType.signedIn, const AuthSession(userId: 'fresh-user'));

    await _eventually(() async {
      final account = await store.account();
      return account.enabled &&
          account.boundUserId == 'fresh-user' &&
          account.lastSyncedAt != null;
    });
    final status = await coordinator.status();
    expect(status.initialHydrationProgress, isNull);
    expect(hydrationStages, InitialHydrationStage.values);
    expect(status.mergeConfirmationRequired, isFalse);
    expect(
      gateway._records.where((item) => item.userId == 'fresh-user'),
      isNotEmpty,
    );
    expect(
      await (db.select(
        db.rooms,
      )..where((row) => row.id.equals('cloud-room'))).getSingleOrNull(),
      isNotNull,
    );
    expect(gateway.writeCalls['area'] ?? 0, 0);
    expect(gateway.batchWriteCalls, 0);
    expect(gateway.pullCalls['area'], 1);
    expect(coordinator.lastCloudAccountWasExisting, isTrue);
    expect(
      gateway.materializeMediaCalls,
      0,
      reason: 'asset media is optional for the first Home frame',
    );

    coordinator.startPostReadyWork();
    await _eventually(() async => gateway.materializeMediaCalls > 0);
    gateway.materializeMediaGate!.complete();
  });

  test('fresh hydration does not sync hardcoded categories', () async {
    final db = AppDatabase(executor: NativeDatabase.memory());
    addTearDown(db.close);
    final store = LocalSyncStore(db);
    await store.account();
    final auth = _FakeAuthRepository(const AuthSession(userId: 'fresh-user'));
    addTearDown(auth.controller.close);
    final gateway = _StatefulGateway();
    final coordinator = SyncCoordinator(auth, store, gateway);
    addTearDown(coordinator.dispose);

    await coordinator.enable();

    expect(coordinator.lastCloudAccountWasExisting, isFalse);
    expect(gateway.writeCalls['category'] ?? 0, 0);
    expect(gateway.pullCalls['category'] ?? 0, 0);
  });

  test('fresh hydration with trigger-seeded profile is classified as non-existing account', () async {
    final db = AppDatabase(executor: NativeDatabase.memory());
    addTearDown(db.close);
    final store = LocalSyncStore(db);
    await store.account();
    final now = DateTime.utc(2026, 8, 14);
    final auth = _FakeAuthRepository(
      const AuthSession(userId: 'trigger-fresh-user'),
    );
    addTearDown(auth.controller.close);
    final gateway = _StatefulGateway();
    gateway._records.add(
      _StoredRecord(
        userId: 'trigger-fresh-user',
        deviceId: 'cloud-server',
        record: SyncRecord(
          spec: profileSyncSpec,
          recordKey: 'trigger-fresh-user',
          values: {
            'user_id': 'trigger-fresh-user',
            'nickname': null,
            'avatar_path': null,
            'created_at': now.toIso8601String(),
            'updated_at': now.toIso8601String(),
          },
          clientModifiedAt: now,
          originDeviceId: 'cloud-server',
        ),
      ),
    );
    final coordinator = SyncCoordinator(auth, store, gateway);
    addTearDown(coordinator.dispose);

    await coordinator.enable();

    expect(coordinator.lastCloudAccountWasExisting, isFalse);
  });

  test('hydration retains its failed stage and completes on retry', () async {
    final db = AppDatabase(executor: NativeDatabase.memory());
    addTearDown(db.close);
    final store = LocalSyncStore(db);
    await store.account();
    final auth = _FakeAuthRepository(null);
    addTearDown(auth.controller.close);
    final gateway = _FailingOnceGateway();
    final coordinator = SyncCoordinator(auth, store, gateway);
    addTearDown(coordinator.dispose);

    auth.emit(AuthEventType.signedIn, const AuthSession(userId: 'retry-user'));
    await _eventually(() async {
      final status = await coordinator.status();
      return status.phase == SyncPhase.offline;
    });

    final failed = await coordinator.status();
    expect(failed.initialHydrationProgress?.state, RestoreRunState.failed);
    expect(
      failed.initialHydrationProgress?.stage,
      InitialHydrationStage.restoringCloudData,
    );
    expect(failed.message, 'Temporary restore interruption.');

    final retryStages = <InitialHydrationStage>[];
    final subscription = coordinator.watchStatus().listen((status) {
      final stage = status.initialHydrationProgress?.stage;
      if (stage != null && (retryStages.isEmpty || retryStages.last != stage)) {
        retryStages.add(stage);
      }
    });
    addTearDown(subscription.cancel);
    await coordinator.retry();

    final completed = await coordinator.status();
    expect(completed.phase, SyncPhase.ready);
    expect(completed.initialHydrationProgress, isNull);
    expect(
      retryStages,
      containsAllInOrder([
        InitialHydrationStage.restoringCloudData,
        InitialHydrationStage.restoringPhotos,
        InitialHydrationStage.syncingLocalChanges,
        InitialHydrationStage.checkingLatestUpdates,
        InitialHydrationStage.finalizing,
      ]),
    );
  });

  test('Google sign-in safely auto-merges modified local data', () async {
    final db = AppDatabase(executor: NativeDatabase.memory());
    addTearDown(db.close);
    final store = LocalSyncStore(db);
    await store.account();
    await DriftSettingsRepository(db).setThemePreference(ThemePreference.dark);
    final auth = _FakeAuthRepository(null);
    addTearDown(auth.controller.close);
    final gateway = _StatefulGateway();
    final coordinator = SyncCoordinator(
      auth,
      store,
      gateway,
      realtime: gateway,
    );
    addTearDown(coordinator.dispose);

    auth.emit(
      AuthEventType.signedIn,
      const AuthSession(userId: 'existing-local-user'),
    );

    await _eventually(() async {
      final account = await store.account();
      return account.enabled &&
          account.boundUserId == 'existing-local-user' &&
          account.lastSyncedAt != null;
    });
    final account = await store.account();
    expect(account.enabled, isTrue);
    expect(account.boundUserId, 'existing-local-user');
    expect(
      gateway._records.where(
        (record) => record.userId == 'existing-local-user',
      ),
      isNotEmpty,
    );
    expect((await coordinator.status()).mergeConfirmationRequired, isFalse);
  });

  test(
    'acknowledges an equivalent row already accepted by the cloud',
    () async {
      final db = AppDatabase(executor: NativeDatabase.memory());
      addTearDown(db.close);
      final store = LocalSyncStore(db);
      await store.account();
      await db.delete(db.syncOutbox).go();
      await db
          .into(db.tags)
          .insert(TagsCompanion.insert(id: 'tag-home', name: 'Home'));
      await store.setEnabled(enabled: true, boundUserId: 'user-1');
      await store.recordSyncSuccess(DateTime.utc(2026, 6, 30));

      final auth = _FakeAuthRepository(const AuthSession(userId: 'user-1'));
      addTearDown(auth.controller.close);
      final gateway = _MockGateway();
      when(
        () => gateway.fetchUserChangeFeed(
          sinceSeq: any(named: 'sinceSeq'),
          limit: any(named: 'limit'),
          expectedGeneration: any(named: 'expectedGeneration'),
        ),
      ).thenAnswer(
        (_) async => const UserChangeFeedPage(
          entries: [],
          highWaterSeq: 0,
          nextSeq: 0,
          hasMore: false,
          resnapshotRequired: false,
        ),
      );
      when(
        () => gateway.fetchAuthoritativeRecordKeys(
          spec: any(named: 'spec'),
          userId: any(named: 'userId'),
          deviceId: any(named: 'deviceId'),
        ),
      ).thenAnswer((_) async => const {});
      when(
        () => gateway.writeNewBatch(
          records: any(named: 'records'),
          userId: any(named: 'userId'),
          deviceId: any(named: 'deviceId'),
        ),
      ).thenAnswer((_) async => const BatchWriteUnsuitable());
      when(
        () => gateway.pullAuthoritativeSnapshotPage(
          spec: any(named: 'spec'),
          userId: any(named: 'userId'),
          deviceId: any(named: 'deviceId'),
          afterRecordKey: any(named: 'afterRecordKey'),
          onExactCount: any(named: 'onExactCount'),
          materializeMedia: any(named: 'materializeMedia'),
        ),
      ).thenAnswer((_) async => const []);
      when(
        () => gateway.write(
          record: any(named: 'record'),
          userId: any(named: 'userId'),
          deviceId: any(named: 'deviceId'),
          expectedRevision: any(named: 'expectedRevision'),
        ),
      ).thenAnswer((invocation) async {
        final local =
            invocation.namedArguments[const Symbol('record')] as SyncRecord;
        return RemoteWriteResult.conflict(
          SyncRecord(
            spec: local.spec,
            recordKey: local.recordKey,
            values: {
              ...local.values,
              'created_at': DateTime.parse(local.values['created_at'] as String)
                  .toUtc()
                  .toIso8601String()
                  .replaceFirst('Z', '+00:00'),
            },
            clientModifiedAt: local.clientModifiedAt.subtract(
              const Duration(minutes: 1),
            ),
            originDeviceId: 'remote-device',
            revision: 1,
            serverUpdatedAt: DateTime.utc(2026, 6, 29),
          ),
        );
      });

      final coordinator = SyncCoordinator(auth, store, gateway);
      addTearDown(coordinator.dispose);
      await coordinator.syncIncremental();

      expect(await store.pendingCount(), 0);
      verify(
        () => gateway.write(
          record: any(named: 'record'),
          userId: 'user-1',
          deviceId: any(named: 'deviceId'),
          expectedRevision: null,
        ),
      ).called(1);
    },
  );

  test(
    'acknowledges a batch creation replay skipped by idempotent insert',
    () async {
      final db = AppDatabase(executor: NativeDatabase.memory());
      addTearDown(db.close);
      final store = LocalSyncStore(db);
      await store.account();
      await db.delete(db.syncOutbox).go();
      final createdAt = DateTime.utc(2026, 8, 26, 9);
      await db
          .into(db.tags)
          .insert(
            TagsCompanion.insert(
              id: 'tag-replay',
              name: 'Home',
              createdAt: Value(createdAt),
            ),
          );
      await store.setEnabled(enabled: true, boundUserId: 'user-1');
      await store.recordSyncSuccess(DateTime.utc(2026, 8, 26));

      final auth = _FakeAuthRepository(const AuthSession(userId: 'user-1'));
      addTearDown(auth.controller.close);
      final gateway = _StatefulGateway();
      // The prior push attempt committed server-side but its acknowledgement
      // was lost, so the remote row already exists when the intent replays.
      gateway._records.add(
        _StoredRecord(
          userId: 'user-1',
          deviceId: null,
          record: SyncRecord(
            spec: syncSpecByEntity['tag']!,
            recordKey: 'tag-replay',
            values: {
              'user_id': 'user-1',
              'id': 'tag-replay',
              'name': 'Home',
              'created_at': createdAt.toIso8601String(),
              'revision': 1,
              'updated_at': createdAt.toIso8601String(),
            },
            clientModifiedAt: createdAt,
            originDeviceId: 'device-under-test',
            revision: 1,
            serverUpdatedAt: createdAt,
          ),
        ),
      );
      gateway.batchPreexistingKeys = {'tag-replay'};
      final coordinator = SyncCoordinator(auth, store, gateway);
      addTearDown(coordinator.dispose);

      await coordinator.syncIncremental();

      expect(gateway.batchWriteCalls, 1);
      expect(await store.pendingCount(), 0);
      expect(await store.listSyncConflicts(), isEmpty);
      // The skipped row must not be duplicated remotely.
      expect(
        gateway._records.where((item) => item.record.recordKey == 'tag-replay'),
        hasLength(1),
      );
    },
  );

  test('keeps a divergent batch replay as a durable conflict', () async {
    final db = AppDatabase(executor: NativeDatabase.memory());
    addTearDown(db.close);
    final store = LocalSyncStore(db);
    await store.account();
    await db.delete(db.syncOutbox).go();
    final createdAt = DateTime.utc(2026, 8, 26, 9);
    await db
        .into(db.tags)
        .insert(
          TagsCompanion.insert(
            id: 'tag-divergent',
            name: 'Local Name',
            createdAt: Value(createdAt),
          ),
        );
    await store.setEnabled(enabled: true, boundUserId: 'user-1');
    await store.recordSyncSuccess(DateTime.utc(2026, 8, 26));

    final auth = _FakeAuthRepository(const AuthSession(userId: 'user-1'));
    addTearDown(auth.controller.close);
    final gateway = _StatefulGateway();
    // Same primary key, but the cloud row carries different data created by
    // another device: the replay must never silently overwrite it.
    gateway._records.add(
      _StoredRecord(
        userId: 'user-1',
        deviceId: null,
        record: SyncRecord(
          spec: syncSpecByEntity['tag']!,
          recordKey: 'tag-divergent',
          values: {
            'user_id': 'user-1',
            'id': 'tag-divergent',
            'name': 'Remote Name',
            'created_at': createdAt.toIso8601String(),
            'revision': 4,
            'updated_at': DateTime.utc(2026, 8, 26, 10).toIso8601String(),
          },
          clientModifiedAt: DateTime.utc(2026, 8, 26, 10),
          originDeviceId: 'another-device',
          revision: 4,
          serverUpdatedAt: DateTime.utc(2026, 8, 26, 10),
        ),
      ),
    );
    gateway.batchPreexistingKeys = {'tag-divergent'};
    final coordinator = SyncCoordinator(auth, store, gateway);
    addTearDown(coordinator.dispose);

    await coordinator.syncIncremental();

    expect(gateway.batchWriteCalls, 1);
    expect(await store.pendingCount(), 0);
    final conflicts = await store.listSyncConflicts();
    expect(conflicts, hasLength(1));
    // The cloud row stays authoritative remotely and locally; the local
    // intent survives only in the durable conflict ledger.
    expect(
      gateway._records
          .firstWhere((item) => item.record.recordKey == 'tag-divergent')
          .record
          .values['name'],
      'Remote Name',
    );
    expect(
      (await (db.select(
        db.tags,
      )..where((row) => row.id.equals('tag-divergent'))).getSingle()).name,
      'Remote Name',
    );
  });

  test(
    'two devices recover cloud data without sharing operational state',
    () async {
      final firstDb = AppDatabase(executor: NativeDatabase.memory());
      final secondDb = AppDatabase(executor: NativeDatabase.memory());
      addTearDown(firstDb.close);
      addTearDown(secondDb.close);
      final firstStore = LocalSyncStore(firstDb);
      final secondStore = LocalSyncStore(secondDb);
      await firstStore.account();
      await secondStore.account();
      final firstAuth = _FakeAuthRepository(
        const AuthSession(userId: 'shared-user'),
      );
      final secondAuth = _FakeAuthRepository(
        const AuthSession(userId: 'shared-user'),
      );
      addTearDown(firstAuth.controller.close);
      addTearDown(secondAuth.controller.close);
      final gateway = _StatefulGateway();
      final firstCoordinator = SyncCoordinator(firstAuth, firstStore, gateway);
      final secondCoordinator = SyncCoordinator(
        secondAuth,
        secondStore,
        gateway,
      );
      addTearDown(firstCoordinator.dispose);
      addTearDown(secondCoordinator.dispose);
      expect(
        (await firstStore.account()).deviceId,
        isNot((await secondStore.account()).deviceId),
      );

      final firstSettings = DriftSettingsRepository(firstDb);
      final firstInbox = DriftNotificationInboxRepository(firstDb);
      await firstSettings.setThemePreference(ThemePreference.dark);
      await firstSettings.setHomeLocation(
        const HomeLocation(
          label: 'Baghdad',
          latitude: 33.3152,
          longitude: 44.3661,
          source: 'manual',
        ),
      );
      await firstDb
          .into(firstDb.streaks)
          .insertOnConflictUpdate(
            StreaksCompanion.insert(
              id: 'default',
              currentStreak: const Value(3),
              bestStreak: const Value(5),
              lastCompletedDate: Value(DateTime.utc(2026, 6, 28)),
              updatedAt: Value(DateTime.utc(2026, 6, 29, 9)),
            ),
          );
      await firstDb
          .into(firstDb.settings)
          .insertOnConflictUpdate(
            SettingsCompanion.insert(
              key: 'weather_cache',
              value: '{"temperature":42}',
            ),
          );
      await firstInbox.createNotification(
        title: 'Filter reminder',
        body: 'Replace the filter',
        kind: 'task',
      );

      await firstCoordinator.enable();
      await secondCoordinator.enable();

      final secondSettings = DriftSettingsRepository(secondDb);
      expect(await secondSettings.themePreference(), ThemePreference.dark);
      expect((await secondSettings.homeLocation())?.label, 'Baghdad');
      expect(
        (await secondDb.select(secondDb.streaks).getSingle()).currentStreak,
        3,
      );
      final secondNotifications = await DriftNotificationInboxRepository(
        secondDb,
      ).listNotifications();
      expect(secondNotifications, hasLength(1));
      expect(
        await (secondDb.select(
          secondDb.settings,
        )..where((row) => row.key.equals('weather_cache'))).getSingleOrNull(),
        isNull,
      );

      await DriftNotificationInboxRepository(secondDb)
          .markRead(secondNotifications.single.id);
      await secondCoordinator.syncNow();
      await firstCoordinator.syncNow();

      final firstNotifications = await firstInbox.listNotifications();
      expect(firstNotifications.single.readAt, isNotNull);

      final baseTime = DateTime.utc(2026, 7, 1, 12);
      final laterTime = baseTime.add(const Duration(seconds: 1));
      await (firstDb.update(
        firstDb.settings,
      )..where((row) => row.key.equals('theme'))).write(
        SettingsCompanion(
          value: const Value('light'),
          updatedAt: Value(baseTime),
        ),
      );
      await (secondDb.update(
        secondDb.settings,
      )..where((row) => row.key.equals('theme'))).write(
        SettingsCompanion(
          value: const Value('system'),
          updatedAt: Value(laterTime),
        ),
      );
      await firstDb.customStatement(
        'UPDATE offline_mutation_queue SET changed_at = ? '
        'WHERE entity = ? AND record_key = ?',
        [baseTime.millisecondsSinceEpoch ~/ 1000, 'user_setting', 'theme'],
      );
      await secondDb.customStatement(
        'UPDATE offline_mutation_queue SET changed_at = ? '
        'WHERE entity = ? AND record_key = ?',
        [laterTime.millisecondsSinceEpoch ~/ 1000, 'user_setting', 'theme'],
      );

      await firstCoordinator.syncNow();
      await secondCoordinator.syncNow();
      await firstCoordinator.syncNow();

      expect(await firstSettings.themePreference(), ThemePreference.system);
      expect(await secondSettings.themePreference(), ThemePreference.system);
      final cloudTheme = await gateway.fetch(
        spec: syncSpecByEntity['user_setting']!,
        userId: 'shared-user',
        deviceId: (await firstStore.account()).deviceId,
        recordKey: 'theme',
      );
      expect(cloudTheme?.values['value'], 'system');
    },
  );

  test('maintenance arriving in the feed republishes streaks', () async {
    final db = AppDatabase(executor: NativeDatabase.memory());
    addTearDown(db.close);
    final store = LocalSyncStore(db);
    await store.account();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    await store.withOutboxSuppressed(() async {
      await DriftAssetRepository(db).saveArea(
        id: 'area_first_floor',
        name: 'First Floor',
        kind: AreaKind.indoor,
        sortOrder: 0,
      );
    });
    await db
        .into(db.rooms)
        .insert(
          RoomsCompanion.insert(
            id: 'late-room',
            areaId: 'area_first_floor',
            name: 'Late room',
          ),
        );
    await db
        .into(db.assets)
        .insert(
          AssetsCompanion.insert(
            id: 'late-asset',
            name: 'Late asset',
            roomId: 'late-room',
          ),
        );
    await db
        .into(db.maintenancePlans)
        .insert(
          MaintenancePlansCompanion.insert(
            id: 'late-plan',
            assetId: 'late-asset',
            title: 'Late plan',
            recurrenceInterval: 1,
            recurrenceUnit: 'days',
            priority: 'medium',
            nextDueDate: today.add(const Duration(days: 1)),
          ),
        );
    await db.delete(db.syncOutbox).go();
    await store.setEnabled(enabled: true, boundUserId: 'user-1');
    await store.recordSyncSuccess(DateTime.now().toUtc());
    final auth = _FakeAuthRepository(const AuthSession(userId: 'user-1'));
    addTearDown(auth.controller.close);
    final gateway = _MockGateway();
    when(
      () => gateway.fetchUserChangeFeedHighWater(),
    ).thenAnswer((_) async => const UserChangeFeedWatermark(highWaterSeq: 0));
    when(
      () => gateway.fetchUserChangeFeed(
        sinceSeq: any(named: 'sinceSeq'),
        limit: any(named: 'limit'),
        expectedGeneration: any(named: 'expectedGeneration'),
      ),
    ).thenAnswer((invocation) async {
      final sinceSeq = invocation.namedArguments[#sinceSeq] as int;
      final record = SyncRecord(
        spec: syncSpecByEntity['maintenance_record']!,
        recordKey: 'late-record',
        values: {
          'id': 'late-record',
          'plan_id': 'late-plan',
          'occurrence_id': 'late-occurrence',
          'due_date': today.toUtc().toIso8601String(),
          'completed_at': now.toUtc().toIso8601String(),
          'accepted_at': now.toUtc().toIso8601String(),
          'time_zone_id': 'UTC',
          'notes': null,
        },
        clientModifiedAt: now.toUtc(),
        originDeviceId: 'remote-device',
        revision: 1,
        serverUpdatedAt: now.toUtc(),
      );
      return UserChangeFeedPage(
        entries: sinceSeq < 90
            ? [
                ChangeFeedEntry(
                  changeSeq: 90,
                  record: record,
                  operation: 'INSERT',
                ),
              ]
            : const [],
        highWaterSeq: 90,
        nextSeq: sinceSeq < 90 ? 90 : sinceSeq,
        hasMore: false,
        resnapshotRequired: false,
      );
    });
    when(
      () => gateway.fetchAuthoritativeRecordKeys(
        spec: any(named: 'spec'),
        userId: any(named: 'userId'),
        deviceId: any(named: 'deviceId'),
      ),
    ).thenAnswer((invocation) async {
      final spec = invocation.namedArguments[#spec] as SyncEntitySpec;
      return switch (spec.entity) {
        'area' => {'area_first_floor'},
        'room' => {'late-room'},
        'asset' => {'late-asset'},
        'maintenance_plan' => {'late-plan'},
        'maintenance_record' => {'late-record'},
        _ => <String>{},
      };
    });
    when(
      () => gateway.writeNewBatch(
        records: any(named: 'records'),
        userId: any(named: 'userId'),
        deviceId: any(named: 'deviceId'),
      ),
    ).thenAnswer((_) async => const BatchWriteUnsuitable());
    final pulls = <String, int>{};
    when(
      () => gateway.pullAuthoritativeSnapshotPage(
        spec: any(named: 'spec'),
        userId: any(named: 'userId'),
        deviceId: any(named: 'deviceId'),
        afterRecordKey: any(named: 'afterRecordKey'),
        onExactCount: any(named: 'onExactCount'),
        materializeMedia: any(named: 'materializeMedia'),
      ),
    ).thenAnswer((invocation) async {
      final spec =
          invocation.namedArguments[const Symbol('spec')] as SyncEntitySpec;
      final count = (pulls[spec.entity] ?? 0) + 1;
      pulls[spec.entity] = count;
      if (spec.entity != 'maintenance_record' || count != 1) {
        return const [];
      }
      return [
        SyncRecord(
          spec: spec,
          recordKey: 'late-record',
          values: {
            'id': 'late-record',
            'plan_id': 'late-plan',
            'occurrence_id': 'late-occurrence',
            'due_date': today.toUtc().toIso8601String(),
            'completed_at': now.toUtc().toIso8601String(),
            'accepted_at': now.toUtc().toIso8601String(),
            'time_zone_id': 'UTC',
            'notes': null,
          },
          clientModifiedAt: now.toUtc(),
          originDeviceId: 'remote-device',
          revision: 1,
          serverUpdatedAt: now.toUtc(),
        ),
      ];
    });
    when(
      () => gateway.write(
        record: any(named: 'record'),
        userId: any(named: 'userId'),
        deviceId: any(named: 'deviceId'),
        expectedRevision: any(named: 'expectedRevision'),
      ),
    ).thenAnswer((invocation) async {
      final local =
          invocation.namedArguments[const Symbol('record')] as SyncRecord;
      return RemoteWriteResult.applied(
        SyncRecord(
          spec: local.spec,
          recordKey: local.recordKey,
          values: local.values,
          clientModifiedAt: local.clientModifiedAt,
          originDeviceId: local.originDeviceId,
          revision: 1,
          serverUpdatedAt: now.toUtc(),
          deletedAt: local.deletedAt,
        ),
      );
    });
    final coordinator = SyncCoordinator(auth, store, gateway);
    addTearDown(coordinator.dispose);

    await coordinator.syncIncremental();

    final streak = await db.select(db.streaks).getSingle();
    expect(streak.currentStreak, 1);
    verify(
      () => gateway.write(
        record: any(
          named: 'record',
          that: isA<SyncRecord>().having(
            (record) => record.spec.entity,
            'entity',
            'streak',
          ),
        ),
        userId: 'user-1',
        deviceId: any(named: 'deviceId'),
        expectedRevision: any(named: 'expectedRevision'),
      ),
    ).called(1);
  });

  test('online local writes automatically wake and upload', () async {
    final db = AppDatabase(executor: NativeDatabase.memory());
    addTearDown(db.close);
    final store = LocalSyncStore(db);
    final account = await store.account();
    await store.setEnabled(enabled: true, boundUserId: 'user-1');
    await db.delete(db.syncOutbox).go();
    final auth = _FakeAuthRepository(const AuthSession(userId: 'user-1'));
    addTearDown(auth.controller.close);
    final connectivity = _FakeConnectivity(true);
    addTearDown(connectivity.controller.close);
    final gateway = _StatefulGateway();
    final coordinator = SyncCoordinator(
      auth,
      store,
      gateway,
      connectivity: connectivity,
      realtime: gateway,
    );
    addTearDown(coordinator.dispose);

    await DriftSettingsRepository(db).setThemePreference(ThemePreference.dark);

    await _eventually(() async {
      return await gateway.fetch(
            spec: syncSpecByEntity['user_setting']!,
            userId: 'user-1',
            deviceId: account.deviceId,
            recordKey: 'theme',
          ) !=
          null;
    });
  });

  test('local maintenance completion uses one composite mutation', () async {
    final db = AppDatabase(executor: NativeDatabase.memory());
    addTearDown(db.close);
    final store = LocalSyncStore(db);
    await store.account();
    await store.setEnabled(enabled: true, boundUserId: 'user-1');
    await store.recordSyncSuccess(DateTime.utc(2026, 6, 30));
    await store.withOutboxSuppressed(() async {
      await DriftAssetRepository(db).saveArea(
        id: 'area_first_floor',
        name: 'First Floor',
        kind: AreaKind.indoor,
        sortOrder: 0,
      );
      await db
          .into(db.rooms)
          .insert(
            RoomsCompanion.insert(
              id: 'maintenance-room',
              areaId: 'area_first_floor',
              name: 'Maintenance room',
            ),
          );
      await db
          .into(db.assets)
          .insert(
            AssetsCompanion.insert(
              id: 'maintenance-asset',
              name: 'Maintenance asset',
              roomId: 'maintenance-room',
            ),
          );
      await db
          .into(db.maintenancePlans)
          .insert(
            MaintenancePlansCompanion.insert(
              id: 'maintenance-plan',
              assetId: 'maintenance-asset',
              title: 'Replace filter',
              recurrenceInterval: 1,
              recurrenceUnit: 'months',
              priority: 'medium',
              nextDueDate: DateTime.utc(2026, 7),
            ),
          );
    });
    await db.delete(db.syncOutbox).go();

    final remotePlan = await (db.select(
      db.maintenancePlans,
    )..where((row) => row.id.equals('maintenance-plan'))).getSingle();
    final completed = await DriftMaintenanceRepository(db)
        .completeCurrentOccurrence(
          'maintenance-plan',
          completedAt: DateTime.utc(2026, 7),
        );
    expect(
      completed.status,
      LocalMaintenanceCompletionStatus.appliedPendingSync,
    );

    final queuedBeforeSync = await db.select(db.syncOutbox).get();
    final completionMutations = queuedBeforeSync
        .where((row) => row.entity == 'maintenance_completion')
        .toList();
    expect(completionMutations, hasLength(1));
    expect(completionMutations.single.operation, 'execute');
    expect(completionMutations.single.payloadJson, isNotNull);
    final completionPayload = jsonDecode(
      completionMutations.single.payloadJson!,
    ) as Map<String, dynamic>;
    expect(
      completionPayload['operation_id'],
      completionMutations.single.recordKey,
    );
    expect(completionPayload['contract_version'], 1);
    expect(completionPayload['occurrence_id'], remotePlan.currentOccurrenceId);
    expect(completionPayload['local_preimage'], isA<Map<String, dynamic>>());
    expect(completionPayload.containsKey('plan'), isFalse);
    expect(completionPayload.containsKey('record'), isFalse);
    expect(
      queuedBeforeSync.where(
        (row) =>
            row.entity == 'maintenance_plan' ||
            row.entity == 'maintenance_record',
      ),
      isEmpty,
    );

    final auth = _FakeAuthRepository(const AuthSession(userId: 'user-1'));
    addTearDown(auth.controller.close);
    final connectivity = _FakeConnectivity(true);
    addTearDown(connectivity.controller.close);
    final gateway = _StatefulGateway()
      ..seedMaintenancePlan(
        userId: 'user-1',
        planId: remotePlan.id,
        assetId: remotePlan.assetId,
        currentOccurrenceId: remotePlan.currentOccurrenceId,
        nextDueDate: remotePlan.nextDueDate,
        recurrenceInterval: remotePlan.recurrenceInterval,
        recurrenceUnit: remotePlan.recurrenceUnit,
      );
    var reminderReconciliations = 0;
    final coordinator = SyncCoordinator(
      auth,
      store,
      gateway,
      connectivity: connectivity,
      reconcileMaintenanceCompletionReminders: () async {
        reminderReconciliations += 1;
      },
    );
    addTearDown(coordinator.dispose);

    await _eventually(() async {
      return gateway.maintenanceCompletionCalls == 1 &&
          await store.pendingCount() == 0;
    });

    expect(gateway.pullCalls, isEmpty);
    expect(gateway.maintenanceCompletionCalls, 1);
    expect(reminderReconciliations, 1);
    expect(gateway.writeCalls['maintenance_plan'] ?? 0, 0);
    expect(gateway.writeCalls['maintenance_record'] ?? 0, 0);
    expect(
      gateway._records.any(
        (item) =>
            item.userId == 'user-1' &&
            item.record.spec.entity == 'maintenance_plan',
      ),
      isTrue,
    );
    expect(
      gateway._records.any(
        (item) =>
            item.userId == 'user-1' &&
            item.record.spec.entity == 'maintenance_record',
      ),
      isTrue,
    );
    expect(await store.pendingCount(), 0);
  });

  test(
    'canonical occurrence loser reconciles once and keeps sync ready',
    () async {
      final db = AppDatabase(executor: NativeDatabase.memory());
      addTearDown(db.close);

      final store = LocalSyncStore(db);
      await store.account();
      await store.setEnabled(enabled: true, boundUserId: 'user-1');
      await store.recordSyncSuccess(DateTime.utc(2026, 6, 30));
      await store.withOutboxSuppressed(() async {
        await DriftAssetRepository(db).saveArea(
          id: 'stale-race-area',
          name: 'Stale race area',
          kind: AreaKind.indoor,
          sortOrder: 0,
        );
        await db
            .into(db.rooms)
            .insert(
              RoomsCompanion.insert(
                id: 'stale-race-room',
                areaId: 'stale-race-area',
                name: 'Stale race room',
              ),
            );
        await db
            .into(db.assets)
            .insert(
              AssetsCompanion.insert(
                id: 'stale-race-asset',
                name: 'Stale race asset',
                roomId: 'stale-race-room',
              ),
            );
        await db
            .into(db.maintenancePlans)
            .insert(
              MaintenancePlansCompanion.insert(
                id: 'stale-race-plan',
                assetId: 'stale-race-asset',
                title: 'Stale race plan',
                recurrenceInterval: 1,
                recurrenceUnit: 'months',
                priority: 'medium',
                nextDueDate: DateTime.utc(2026, 7),
              ),
            );
      });
      await db.delete(db.syncOutbox).go();
      expect(
        (await DriftMaintenanceRepository(db).completeCurrentOccurrence(
          'stale-race-plan',
          completedAt: DateTime.utc(2026, 7),
        )).status,
        LocalMaintenanceCompletionStatus.appliedPendingSync,
      );

      final mutation =
          await (db.select(db.syncOutbox)
                ..where((row) => row.entity.equals('maintenance_completion')))
              .getSingle();
      final payload = Map<String, dynamic>.from(
        jsonDecode(mutation.payloadJson!) as Map,
      );
      final localPlan = await (db.select(
        db.maintenancePlans,
      )..where((row) => row.id.equals('stale-race-plan'))).getSingle();
      final localRecord = await (db.select(
        db.maintenanceRecords,
      )..where((row) => row.id.equals(mutation.recordKey))).getSingle();
      final completedOccurrenceId = payload['occurrence_id']! as String;
      final planSpec = syncSpecByEntity['maintenance_plan']!;
      final recordSpec = syncSpecByEntity['maintenance_record']!;
      final winnerPlan = SyncRecord(
        spec: planSpec,
        recordKey: 'stale-race-plan',
        values: {
          'id': localPlan.id,
          'asset_id': localPlan.assetId,
          'title': localPlan.title,
          'instructions': localPlan.instructions,
          'recurrence_interval': localPlan.recurrenceInterval,
          'recurrence_unit': localPlan.recurrenceUnit,
          'priority': localPlan.priority,
          'current_occurrence_id': 'next:peer-completion',
          'next_due_date': localPlan.nextDueDate.toIso8601String(),
          'is_enabled': localPlan.isEnabled,
          'reminder_days_before': localPlan.reminderDaysBefore,
          'created_at': localPlan.createdAt.toIso8601String(),
          'updated_at': localPlan.updatedAt.toIso8601String(),
          'archived_at': localPlan.archivedAt?.toIso8601String(),
        },
        clientModifiedAt: localPlan.updatedAt,
        originDeviceId: 'peer-device',
        revision: 8,
        serverUpdatedAt: localPlan.updatedAt,
      );
      final winnerRecord = SyncRecord(
        spec: recordSpec,
        recordKey: 'peer-completion',
        values: {
          'id': 'peer-completion',
          'plan_id': localRecord.planId,
          'occurrence_id': completedOccurrenceId,
          'completed_at': localRecord.completedAt.toIso8601String(),
          'accepted_at': localRecord.completedAt.toIso8601String(),
          'time_zone_id': localRecord.timeZoneId,
          'notes': localRecord.notes,
          'due_date': localRecord.dueDate.toIso8601String(),
          'operation_id': 'peer-completion',
        },
        clientModifiedAt: localRecord.completedAt,
        originDeviceId: 'peer-device',
        revision: 1,
      );

      final gateway = _StatefulGateway()
        ..queuedMaintenanceCompletionResults.addAll([
          MaintenanceCompletionResult(
            status: MaintenanceCompletionStatus.conflict,
            retryable: false,
            conflictReason: 'occurrence_completed_elsewhere',
            currentPlanRevision: 8,
            resultingRecordId: 'peer-completion',
            plan: winnerPlan,
            record: winnerRecord,
          ),
        ]);
      final auth = _FakeAuthRepository(const AuthSession(userId: 'user-1'));
      addTearDown(auth.controller.close);
      var reminderReconciliations = 0;
      final coordinator = SyncCoordinator(
        auth,
        store,
        gateway,
        connectivity: _FakeConnectivity(true),
        reconcileMaintenanceCompletionReminders: () async {
          reminderReconciliations += 1;
        },
        listenToAuthChanges: false,
      );
      addTearDown(coordinator.dispose);

      await coordinator.syncNow();

      expect((await coordinator.status()).phase, SyncPhase.ready);
      expect(gateway.maintenanceCompletionCalls, 1);
      expect(reminderReconciliations, 1);
      expect(await store.pendingCount(), 0);
      expect(
        await (db.select(
          db.maintenanceRecords,
        )..where((row) => row.id.equals(mutation.recordKey))).getSingleOrNull(),
        isNull,
      );
      expect(
        await (db.select(
          db.maintenanceRecords,
        )..where((row) => row.id.equals('peer-completion'))).getSingleOrNull(),
        isNotNull,
      );
    },
  );

  test('structured terminal completion is retained without failing the sync run', () async {
    final db = AppDatabase(executor: NativeDatabase.memory());
    addTearDown(db.close);

    final store = LocalSyncStore(db);
    await store.account();
    await store.setEnabled(enabled: true, boundUserId: 'user-1');
    await store.recordSyncSuccess(DateTime.utc(2026, 6, 30));
    await db.delete(db.syncOutbox).go();

    const completionKey = 'terminal-conflict-completion';
    const conflictMessage =
        'This completion identifier is already associated with different data.';

    await db
        .into(db.syncOutbox)
        .insert(
          SyncOutboxCompanion.insert(
            entity: 'maintenance_completion',
            recordKey: completionKey,
            operation: 'execute',
            payloadJson: const Value(
              '{"contract_version":1,'
              '"operation_id":"terminal-conflict-completion",'
              '"plan_id":"missing-plan","occurrence_id":"occurrence-1",'
              '"expected_plan_revision":1,'
              '"completed_at":"2026-07-28T00:00:00.000Z",'
              '"time_zone_id":"UTC","notes":null}',
            ),
            changedAt: Value(DateTime.utc(2026, 7, 28, 4)),
            attempts: const Value(0),
          ),
        );
    final auth = _FakeAuthRepository(const AuthSession(userId: 'user-1'));
    addTearDown(auth.controller.close);

    final connectivity = _FakeConnectivity(true);
    addTearDown(connectivity.controller.close);

    final gateway = _StatefulGateway()
      ..forcedMaintenanceCompletionResult = const MaintenanceCompletionResult(
        status: MaintenanceCompletionStatus.conflict,
        retryable: false,
        conflictReason: 'operation_id_reused',
      );
    var reminderReconciliations = 0;

    final coordinator = SyncCoordinator(
      auth,
      store,
      gateway,
      connectivity: connectivity,
      reconcileMaintenanceCompletionReminders: () async {
        reminderReconciliations += 1;
      },
      listenToAuthChanges: false,
    );
    addTearDown(coordinator.dispose);

    final observedMessages = <String?>[];
    final observedPhases = <SyncPhase>[];

    final statusSubscription = coordinator.watchStatus().listen((status) {
      observedMessages.add(status.message);
      observedPhases.add(status.phase);
    });
    addTearDown(statusSubscription.cancel);

    await _eventually(() async {
      final retained =
          await (db.select(db.syncOutbox)..where(
                (row) =>
                    row.entity.equals('maintenance_completion') &
                    row.recordKey.equals(completionKey),
              ))
              .getSingleOrNull();

      final status = await coordinator.status();

      return gateway.maintenanceCompletionCalls == 1 &&
          retained?.attempts == -1 &&
          retained?.nextAttemptAt == null &&
          status.phase == SyncPhase.ready;
    });

    /*
       * Wait beyond the normal 350 ms automatic-sync delay. A retryable
       * mutation would attempt the RPC again during this interval.
       */
    await Future<void>.delayed(const Duration(milliseconds: 700));

    expect(
      gateway.maintenanceCompletionCalls,
      1,
      reason: 'a terminal maintenance conflict must never retry the RPC',
    );
    expect(reminderReconciliations, 0);

    final retained =
        await (db.select(db.syncOutbox)..where(
              (row) =>
                  row.entity.equals('maintenance_completion') &
                  row.recordKey.equals(completionKey),
            ))
            .getSingle();

    expect(retained.attempts, -1);
    expect(retained.nextAttemptAt, isNull);
    expect(retained.lastError, conflictMessage);

    expect(await store.pendingCount(), 0);
    expect(await store.hasReadyMutations(), isFalse);
    expect(await store.pendingMutations(), isEmpty);
    expect(await store.nextRetryAt(), isNull);

    expect(observedPhases, isNot(contains(SyncPhase.error)));
    expect(
      observedMessages.whereType<String>(),
      isNot(contains(conflictMessage)),
    );
  });

  test('invalid completion payload does not abort initial hydration', () async {
    final db = AppDatabase(executor: NativeDatabase.memory());
    addTearDown(db.close);

    final store = LocalSyncStore(db);
    await store.account();
    await store.setEnabled(enabled: true, boundUserId: 'user-1');
    await db.delete(db.syncOutbox).go();

    const completionKey = 'invalid-hydration-completion';
    await db
        .into(db.syncOutbox)
        .insert(
          SyncOutboxCompanion.insert(
            entity: 'maintenance_completion',
            recordKey: completionKey,
            operation: 'execute',
            payloadJson: const Value(
              '{"contract_version":1,'
              '"operation_id":"invalid-hydration-completion",'
              '"plan_id":"missing-plan","occurrence_id":"occurrence-1",'
              '"expected_plan_revision":1,'
              '"completed_at":"2026-08-28T00:00:00.000Z",'
              '"time_zone_id":"UTC","notes":null}',
            ),
            changedAt: Value(DateTime.utc(2026, 8, 28, 4, 48)),
            attempts: const Value(0),
          ),
        );
    await db
        .into(db.tags)
        .insert(
          TagsCompanion.insert(
            id: 'after-invalid-completion',
            name: 'Independent mutation',
            createdAt: Value(DateTime.utc(2026, 8, 28, 4, 49)),
          ),
        );

    final auth = _FakeAuthRepository(const AuthSession(userId: 'user-1'));
    addTearDown(auth.controller.close);
    final gateway = _StatefulGateway()
      ..forcedMaintenanceCompletionResult = const MaintenanceCompletionResult(
        status: MaintenanceCompletionStatus.invalid,
        retryable: false,
        conflictReason: 'plan_unavailable',
      );
    final coordinator = SyncCoordinator(
      auth,
      store,
      gateway,
      listenToAuthChanges: false,
    );
    addTearDown(coordinator.dispose);

    await coordinator.syncNow();

    final status = await coordinator.status();
    expect(status.phase, SyncPhase.ready);
    expect(status.initialHydrationProgress, isNull);
    expect(gateway.maintenanceCompletionCalls, 1);
    expect(
      gateway._records,
      contains(
        isA<_StoredRecord>().having(
          (record) => record.record.recordKey,
          'later independent record',
          'after-invalid-completion',
        ),
      ),
    );
    final retained =
        await (db.select(db.syncOutbox)..where(
              (row) =>
                  row.entity.equals('maintenance_completion') &
                  row.recordKey.equals(completionKey),
            ))
            .getSingle();
    expect(retained.attempts, -1);
    expect(retained.lastErrorCode, 'plan_unavailable');
    expect(await store.pendingCount(), 0);
  });

  test(
    'sync rethrows a canonical failure with the originating stack',
    () async {
      final db = AppDatabase(executor: NativeDatabase.memory());
      addTearDown(db.close);
      final store = LocalSyncStore(db);
      await store.account();
      await store.setEnabled(enabled: true, boundUserId: 'user-1');
      await db.delete(db.syncOutbox).go();
      final auth = _FakeAuthRepository(const AuthSession(userId: 'user-1'));
      addTearDown(auth.controller.close);
      final coordinator = SyncCoordinator(
        auth,
        store,
        _StackFailureGateway(),
        listenToAuthChanges: false,
      );
      addTearDown(coordinator.dispose);

      Object? capturedError;
      StackTrace? capturedStack;
      try {
        await coordinator.syncNow();
      } on Object catch (error, stackTrace) {
        capturedError = error;
        capturedStack = stackTrace;
      }

      expect(capturedError, isA<SupabaseFailure>());
      expect(
        capturedStack.toString(),
        contains('_StackFailureGateway.pullAuthoritativeSnapshotPage'),
      );
    },
  );

  test(
    'maintenance history restore conflict keeps its durable server reason',
    () async {
      final db = AppDatabase(executor: NativeDatabase.memory());
      addTearDown(db.close);

      final store = LocalSyncStore(db);
      await store.account();
      await store.setEnabled(enabled: true, boundUserId: 'user-1');
      await store.recordSyncSuccess(DateTime.utc(2026, 8, 27));
      await db.delete(db.syncOutbox).go();

      const operationId = 'restore-conflict-operation';
      await db
          .into(db.syncOutbox)
          .insert(
            SyncOutboxCompanion.insert(
              entity: 'maintenance_history_restore',
              recordKey: operationId,
              operation: 'execute',
              payloadJson: const Value('{"version":1}'),
              changedAt: Value(DateTime.utc(2026, 8, 27, 1)),
              attempts: const Value(0),
              userId: const Value('user-1'),
            ),
          );

      final auth = _FakeAuthRepository(const AuthSession(userId: 'user-1'));
      addTearDown(auth.controller.close);
      final connectivity = _FakeConnectivity(true);
      addTearDown(connectivity.controller.close);
      final gateway = _StatefulGateway()
        ..maintenanceHistoryRestoreResult =
            const MaintenanceHistoryRestoreResult(
              status: 'conflict',
              insertedCount: 0,
              existingCount: 0,
              alreadyProcessed: false,
              conflictReason: 'history_record_conflict',
            );
      final coordinator = SyncCoordinator(
        auth,
        store,
        gateway,
        connectivity: connectivity,
        listenToAuthChanges: false,
      );
      addTearDown(coordinator.dispose);

      await _eventually(() async {
        final retained =
            await (db.select(db.syncOutbox)..where(
                  (row) =>
                      row.entity.equals('maintenance_history_restore') &
                      row.recordKey.equals(operationId),
                ))
                .getSingleOrNull();
        return gateway.maintenanceHistoryRestoreCalls == 1 &&
            retained?.state == SyncMutationState.failedVisible.name;
      });
      await Future<void>.delayed(const Duration(milliseconds: 700));

      final retained =
          await (db.select(db.syncOutbox)..where(
                (row) =>
                    row.entity.equals('maintenance_history_restore') &
                    row.recordKey.equals(operationId),
              ))
              .getSingle();
      expect(gateway.maintenanceHistoryRestoreCalls, 1);
      expect(retained.attempts, -1);
      expect(retained.nextAttemptAt, isNull);
      expect(retained.lastErrorCode, 'history_record_conflict');
      expect(
        retained.lastError,
        'Maintenance history restore conflict: history_record_conflict.',
      );
      expect(await store.pendingMutations(), isEmpty);
    },
  );

  test(
    'authoritative maintenance conflict reconciles reminders once',
    () async {
      final db = AppDatabase(executor: NativeDatabase.memory());
      addTearDown(db.close);

      final store = LocalSyncStore(db);
      await store.account();
      await store.setEnabled(enabled: true, boundUserId: 'user-1');
      await store.recordSyncSuccess(DateTime.utc(2026, 6, 30));

      await store.withOutboxSuppressed(() async {
        await DriftAssetRepository(db).saveArea(
          id: 'area_first_floor',
          name: 'First Floor',
          kind: AreaKind.indoor,
          sortOrder: 0,
        );
        await db
            .into(db.rooms)
            .insert(
              RoomsCompanion.insert(
                id: 'canonical-conflict-maintenance-room',
                areaId: 'area_first_floor',
                name: 'Canonical conflict maintenance room',
              ),
            );
        await db
            .into(db.assets)
            .insert(
              AssetsCompanion.insert(
                id: 'canonical-conflict-maintenance-asset',
                name: 'Canonical conflict maintenance asset',
                roomId: 'canonical-conflict-maintenance-room',
              ),
            );
        await db
            .into(db.maintenancePlans)
            .insert(
              MaintenancePlansCompanion.insert(
                id: 'canonical-conflict-maintenance-plan',
                assetId: 'canonical-conflict-maintenance-asset',
                title: 'Canonical conflict completion task',
                recurrenceInterval: 1,
                recurrenceUnit: 'months',
                priority: 'medium',
                nextDueDate: DateTime.utc(2026, 7),
              ),
            );
      });
      await db.delete(db.syncOutbox).go();

      final remotePlan =
          await (db.select(db.maintenancePlans)..where(
                (row) => row.id.equals('canonical-conflict-maintenance-plan'),
              ))
              .getSingle();
      final completed = await DriftMaintenanceRepository(db)
          .completeCurrentOccurrence(
            'canonical-conflict-maintenance-plan',
            completedAt: DateTime.utc(2026, 7),
          );
      expect(
        completed.status,
        LocalMaintenanceCompletionStatus.appliedPendingSync,
      );

      final auth = _FakeAuthRepository(const AuthSession(userId: 'user-1'));
      addTearDown(auth.controller.close);
      final gateway = _StatefulGateway()
        ..seedMaintenancePlan(
          userId: 'user-1',
          planId: remotePlan.id,
          assetId: remotePlan.assetId,
          currentOccurrenceId: remotePlan.currentOccurrenceId,
          nextDueDate: remotePlan.nextDueDate,
          recurrenceInterval: remotePlan.recurrenceInterval,
          recurrenceUnit: remotePlan.recurrenceUnit,
        )
        ..maintenanceConflictWithCanonicalPlan = true;
      var reminderReconciliations = 0;
      final coordinator = SyncCoordinator(
        auth,
        store,
        gateway,
        reconcileMaintenanceCompletionReminders: () async {
          reminderReconciliations += 1;
        },
        listenToAuthChanges: false,
      );
      addTearDown(coordinator.dispose);

      await coordinator.syncNow();

      expect(gateway.maintenanceCompletionCalls, 1);
      expect(reminderReconciliations, 1);

      final failedRows = await (db.select(
        db.syncOutbox,
      )..where((row) => row.entity.equals('maintenance_completion'))).get();
      expect(failedRows, isEmpty);

      final plan =
          await (db.select(db.maintenancePlans)..where(
                (row) => row.id.equals('canonical-conflict-maintenance-plan'),
              ))
              .getSingle();
      expect(plan.nextDueDate.toUtc(), isNotNull);
    },
  );

  test(
    'accepted maintenance completion clears pending work without a second push',
    () async {
      final db = AppDatabase(executor: NativeDatabase.memory());
      addTearDown(db.close);

      final store = LocalSyncStore(db);
      await store.account();
      await store.setEnabled(enabled: true, boundUserId: 'user-1');
      await store.recordSyncSuccess(DateTime.utc(2026, 6, 30));

      await store.withOutboxSuppressed(() async {
        await DriftAssetRepository(db).saveArea(
          id: 'area_first_floor',
          name: 'First Floor',
          kind: AreaKind.indoor,
          sortOrder: 0,
        );
        await db
            .into(db.rooms)
            .insert(
              RoomsCompanion.insert(
                id: 'accepted-maintenance-room',
                areaId: 'area_first_floor',
                name: 'Accepted maintenance room',
              ),
            );
        await db
            .into(db.assets)
            .insert(
              AssetsCompanion.insert(
                id: 'accepted-maintenance-asset',
                name: 'Accepted maintenance asset',
                roomId: 'accepted-maintenance-room',
              ),
            );
        await db
            .into(db.maintenancePlans)
            .insert(
              MaintenancePlansCompanion.insert(
                id: 'accepted-maintenance-plan',
                assetId: 'accepted-maintenance-asset',
                title: 'Accepted completion task',
                recurrenceInterval: 1,
                recurrenceUnit: 'months',
                priority: 'medium',
                nextDueDate: DateTime.utc(2026, 7),
              ),
            );
      });
      await db.delete(db.syncOutbox).go();

      final remotePlan =
          await (db.select(db.maintenancePlans)
                ..where((row) => row.id.equals('accepted-maintenance-plan')))
              .getSingle();
      final completed = await DriftMaintenanceRepository(db)
          .completeCurrentOccurrence(
            'accepted-maintenance-plan',
            completedAt: DateTime.utc(2026, 7),
          );
      expect(
        completed.status,
        LocalMaintenanceCompletionStatus.appliedPendingSync,
      );

      final queuedBeforeSync = await db.select(db.syncOutbox).get();
      expect(
        queuedBeforeSync
            .where((row) => row.entity == 'maintenance_completion')
            .toList(),
        hasLength(1),
      );
      expect(
        queuedBeforeSync.where(
          (row) =>
              row.entity == 'maintenance_plan' ||
              row.entity == 'maintenance_record',
        ),
        isEmpty,
      );

      final auth = _FakeAuthRepository(const AuthSession(userId: 'user-1'));
      addTearDown(auth.controller.close);
      final gateway = _StatefulGateway()
        ..seedMaintenancePlan(
          userId: 'user-1',
          planId: remotePlan.id,
          assetId: remotePlan.assetId,
          currentOccurrenceId: remotePlan.currentOccurrenceId,
          nextDueDate: remotePlan.nextDueDate,
          recurrenceInterval: remotePlan.recurrenceInterval,
          recurrenceUnit: remotePlan.recurrenceUnit,
        );
      var reminderReconciliations = 0;
      final coordinator = SyncCoordinator(
        auth,
        store,
        gateway,
        reconcileMaintenanceCompletionReminders: () async {
          reminderReconciliations += 1;
        },
        listenToAuthChanges: false,
      );
      addTearDown(coordinator.dispose);

      await coordinator.syncNow();

      expect(gateway.maintenanceCompletionCalls, 1);
      expect(reminderReconciliations, 1);
      expect(await store.pendingCount(), 0);
      expect(await db.select(db.syncOutbox).get(), isEmpty);

      await coordinator.syncNow();

      expect(
        gateway.maintenanceCompletionCalls,
        1,
        reason: 'accepted completion must not require another push',
      );
      expect(reminderReconciliations, 1);
      expect(gateway.writeCalls['maintenance_plan'] ?? 0, 0);
      expect(gateway.writeCalls['maintenance_record'] ?? 0, 0);
      expect(await store.pendingCount(), 0);
      expect(await db.select(db.syncOutbox).get(), isEmpty);
    },
  );

  test(
    'already-applied maintenance completion clears pending work after restart',
    () async {
      final db = AppDatabase(executor: NativeDatabase.memory());
      addTearDown(db.close);

      final store = LocalSyncStore(db);
      await store.account();
      await store.setEnabled(enabled: true, boundUserId: 'user-1');
      await store.recordSyncSuccess(DateTime.utc(2026, 6, 30));

      await store.withOutboxSuppressed(() async {
        await DriftAssetRepository(db).saveArea(
          id: 'area_first_floor',
          name: 'First Floor',
          kind: AreaKind.indoor,
          sortOrder: 0,
        );
        await db
            .into(db.rooms)
            .insert(
              RoomsCompanion.insert(
                id: 'already-applied-maintenance-room',
                areaId: 'area_first_floor',
                name: 'Already applied maintenance room',
              ),
            );
        await db
            .into(db.assets)
            .insert(
              AssetsCompanion.insert(
                id: 'already-applied-maintenance-asset',
                name: 'Already applied maintenance asset',
                roomId: 'already-applied-maintenance-room',
              ),
            );
        await db
            .into(db.maintenancePlans)
            .insert(
              MaintenancePlansCompanion.insert(
                id: 'already-applied-maintenance-plan',
                assetId: 'already-applied-maintenance-asset',
                title: 'Already applied completion task',
                recurrenceInterval: 1,
                recurrenceUnit: 'months',
                priority: 'medium',
                nextDueDate: DateTime.utc(2026, 7),
              ),
            );
      });
      await db.delete(db.syncOutbox).go();

      final remotePlan =
          await (db.select(db.maintenancePlans)..where(
                (row) => row.id.equals('already-applied-maintenance-plan'),
              ))
              .getSingle();
      final completed = await DriftMaintenanceRepository(db)
          .completeCurrentOccurrence(
            'already-applied-maintenance-plan',
            completedAt: DateTime.utc(2026, 7),
          );
      expect(
        completed.status,
        LocalMaintenanceCompletionStatus.appliedPendingSync,
      );

      final mutation = (await store.pendingMutations()).singleWhere(
        (item) => item.entity == 'maintenance_completion',
      );
      final account = await store.account();
      final gateway = _StatefulGateway()
        ..seedMaintenancePlan(
          userId: 'user-1',
          planId: remotePlan.id,
          assetId: remotePlan.assetId,
          currentOccurrenceId: remotePlan.currentOccurrenceId,
          nextDueDate: remotePlan.nextDueDate,
          recurrenceInterval: remotePlan.recurrenceInterval,
          recurrenceUnit: remotePlan.recurrenceUnit,
        );

      await gateway.completeMaintenance(
        payloadJson: mutation.payloadJson!,
        userId: 'user-1',
        deviceId: account.deviceId,
      );

      final restartedStore = LocalSyncStore(db);
      var reminderReconciliations = 0;
      final auth = _FakeAuthRepository(const AuthSession(userId: 'user-1'));
      addTearDown(auth.controller.close);
      final coordinator = SyncCoordinator(
        auth,
        restartedStore,
        gateway,
        reconcileMaintenanceCompletionReminders: () async {
          reminderReconciliations += 1;
        },
        listenToAuthChanges: false,
      );
      addTearDown(coordinator.dispose);

      await coordinator.syncNow();

      expect(gateway.maintenanceCompletionCalls, 2);
      expect(reminderReconciliations, 1);
      expect(await restartedStore.pendingCount(), 0);
      expect(await db.select(db.syncOutbox).get(), isEmpty);

      await coordinator.syncNow();

      expect(gateway.maintenanceCompletionCalls, 2);
      expect(reminderReconciliations, 1);
      expect(gateway.writeCalls['maintenance_plan'] ?? 0, 0);
      expect(gateway.writeCalls['maintenance_record'] ?? 0, 0);
      expect(await restartedStore.pendingCount(), 0);
    },
  );

  test(
    'earlier completion acknowledgement preserves newer offline plan state',
    () async {
      final db = AppDatabase(executor: NativeDatabase.memory());
      addTearDown(db.close);

      final store = LocalSyncStore(db);
      await store.account();
      await store.setEnabled(enabled: true, boundUserId: 'user-1');
      await store.recordSyncSuccess(DateTime.utc(2026, 6, 30));

      await store.withOutboxSuppressed(() async {
        await DriftAssetRepository(db).saveArea(
          id: 'area_first_floor',
          name: 'First Floor',
          kind: AreaKind.indoor,
          sortOrder: 0,
        );

        await db
            .into(db.rooms)
            .insert(
              RoomsCompanion.insert(
                id: 'multiple-maintenance-room',
                areaId: 'area_first_floor',
                name: 'Multiple maintenance room',
              ),
            );

        await db
            .into(db.assets)
            .insert(
              AssetsCompanion.insert(
                id: 'multiple-maintenance-asset',
                name: 'Multiple maintenance asset',
                roomId: 'multiple-maintenance-room',
              ),
            );

        await db
            .into(db.maintenancePlans)
            .insert(
              MaintenancePlansCompanion.insert(
                id: 'multiple-maintenance-plan',
                assetId: 'multiple-maintenance-asset',
                title: 'Replace multiple filters',
                recurrenceInterval: 1,
                recurrenceUnit: 'months',
                priority: 'medium',
                nextDueDate: DateTime.utc(2026, 7, 1),
              ),
            );
      });

      await db.delete(db.syncOutbox).go();
      final serverPlan =
          await (db.select(db.maintenancePlans)
                ..where((row) => row.id.equals('multiple-maintenance-plan')))
              .getSingle();

      var repositoryNow = DateTime.utc(2026, 7, 1, 10);

      final maintenance = DriftMaintenanceRepository(
        db,
        now: () {
          final value = repositoryNow;
          repositoryNow = repositoryNow.add(const Duration(hours: 1));
          return value;
        },
      );

      final firstResult = await maintenance.completeCurrentOccurrence(
        'multiple-maintenance-plan',
        completedAt: DateTime.utc(2026, 7, 1),
      );

      expect(
        firstResult.status,
        LocalMaintenanceCompletionStatus.appliedPendingSync,
      );

      final afterFirst =
          await (db.select(db.maintenancePlans)
                ..where((row) => row.id.equals('multiple-maintenance-plan')))
              .getSingle();

      final secondResult = await maintenance.completeCurrentOccurrence(
        'multiple-maintenance-plan',
        completedAt: afterFirst.nextDueDate,
      );

      expect(
        secondResult.status,
        LocalMaintenanceCompletionStatus.appliedPendingSync,
      );

      final expectedNewestPlan =
          await (db.select(db.maintenancePlans)
                ..where((row) => row.id.equals('multiple-maintenance-plan')))
              .getSingle();

      final outboxRows = (await db.select(db.syncOutbox).get())
          .where((row) => row.entity == 'maintenance_completion')
          .toList(growable: false);

      expect(outboxRows, hasLength(2));

      final firstMutation = LocalSyncMutation(
        entity: outboxRows.first.entity,
        recordKey: outboxRows.first.recordKey,
        operation: outboxRows.first.operation,
        changedAt: outboxRows.first.changedAt,
        payloadJson: outboxRows.first.payloadJson,
        attempts: 0,
      );
      final secondMutation = LocalSyncMutation(
        entity: outboxRows.last.entity,
        recordKey: outboxRows.last.recordKey,
        operation: outboxRows.last.operation,
        changedAt: outboxRows.last.changedAt,
        payloadJson: outboxRows.last.payloadJson,
        attempts: 0,
      );
      expect(firstMutation.payloadJson, isNotNull);

      final account = await store.account();
      final gateway = _StatefulGateway()
        ..seedMaintenancePlan(
          userId: 'user-1',
          planId: serverPlan.id,
          assetId: serverPlan.assetId,
          currentOccurrenceId: serverPlan.currentOccurrenceId,
          nextDueDate: serverPlan.nextDueDate,
          recurrenceInterval: serverPlan.recurrenceInterval,
          recurrenceUnit: serverPlan.recurrenceUnit,
        );

      final canonicalFirst = await gateway.completeMaintenance(
        payloadJson: firstMutation.payloadJson!,
        userId: 'user-1',
        deviceId: account.deviceId,
      );

      await store.markMaintenanceCompletionSucceeded(
        firstMutation,
        plan: canonicalFirst.plan!,
        record: canonicalFirst.record!,
      );

      final preservedPlan =
          await (db.select(db.maintenancePlans)
                ..where((row) => row.id.equals('multiple-maintenance-plan')))
              .getSingle();

      expect(
        preservedPlan.nextDueDate,
        expectedNewestPlan.nextDueDate,
        reason:
            'acknowledging the first completion must not roll the local '
            'plan back over the second offline completion',
      );

      final remaining = (await store.pendingMutations())
          .where((mutation) => mutation.entity == 'maintenance_completion')
          .toList(growable: false);

      expect(remaining, hasLength(1));
      expect(remaining.single.recordKey, secondMutation.recordKey);
    },
  );
  test('incremental sync fetches one canonical feed page', () async {
    final db = AppDatabase(executor: NativeDatabase.memory());
    addTearDown(db.close);
    final store = LocalSyncStore(db);
    await store.account();
    await store.setEnabled(enabled: true, boundUserId: 'user-1');
    await store.recordSyncSuccess(DateTime.utc(2026, 6, 30));
    await db.delete(db.syncOutbox).go();
    final auth = _FakeAuthRepository(const AuthSession(userId: 'user-1'));
    addTearDown(auth.controller.close);
    final gateway = _StatefulGateway().._syncSeq = 100;
    final coordinator = SyncCoordinator(auth, store, gateway);
    addTearDown(coordinator.dispose);

    await coordinator.syncNow();

    // WP-010: per-entity cursor rows are asserted through Drift after the
    // legacy cursor API was deleted from LocalSyncStore.
    final metadataCursor =
        await (store.db.select(
              store.db.syncCursors,
            )..where((item) => item.entity.equals('maintenance_plan_metadata')))
            .getSingleOrNull();
    expect(metadataCursor?.lastSyncSeq ?? 0, 0);
    expect(gateway.fetchFeedCalls, 1);
    expect(gateway.pullCalls, isEmpty);
  });

  test('overlapping broad startup triggers reuse the active sync', () async {
    final db = AppDatabase(executor: NativeDatabase.memory());
    addTearDown(db.close);

    final store = LocalSyncStore(db);
    await store.account();
    await store.setEnabled(enabled: true, boundUserId: 'user-1');
    await store.recordSyncSuccess(DateTime.utc(2026, 7, 1));
    await db.delete(db.syncOutbox).go();

    final auth = _FakeAuthRepository(const AuthSession(userId: 'user-1'));
    addTearDown(auth.controller.close);

    final connectivity = _FakeConnectivity(true);
    addTearDown(connectivity.controller.close);

    final gateway = _StatefulGateway()..feedGate = Completer<void>();

    final coordinator = SyncCoordinator(
      auth,
      store,
      gateway,
      connectivity: connectivity,
      listenToAuthChanges: false,
    );
    addTearDown(coordinator.dispose);

    final activeSync = coordinator.syncNow();

    await _eventually(() async => gateway.fetchFeedCalls > 0);

    // Exercise both the lifecycle trigger and the coordinator's delayed
    // startup trigger while the broad pull is still active.
    await coordinator.onAppResumed();
    await coordinator.onAppResumed();
    await Future<void>.delayed(const Duration(milliseconds: 650));

    expect(gateway.fetchFeedCalls, 1);

    gateway.feedGate!.complete();
    await activeSync;

    // A duplicate broad pull would be scheduled after the active operation
    // and increment every table's count to two.
    await Future<void>.delayed(const Duration(milliseconds: 700));

    expect(gateway.fetchFeedCalls, 1);
  });

  test('concurrent realtime initialization opens one subscription', () async {
    final db = AppDatabase(executor: NativeDatabase.memory());
    addTearDown(db.close);

    final store = LocalSyncStore(db);
    await store.account();
    await store.setEnabled(enabled: true, boundUserId: 'user-1');
    await store.recordSyncSuccess(DateTime.utc(2026, 7, 1));
    await db.delete(db.syncOutbox).go();

    final auth = _FakeAuthRepository(const AuthSession(userId: 'user-1'));
    addTearDown(auth.controller.close);

    final gateway = _StatefulGateway()..startRealtimeGate = Completer<void>();

    final coordinator = SyncCoordinator(
      auth,
      store,
      gateway,
      realtime: gateway,
      listenToAuthChanges: false,
    );
    addTearDown(coordinator.dispose);

    // The account subscription starts the first Realtime operation.
    await _eventually(() async => gateway.startRealtimeCalls == 1);

    // These calls arrive while the first start operation is blocked.
    final resumeOperations = Future.wait([
      coordinator.onAppResumed(),
      coordinator.onAppResumed(),
      coordinator.onAppResumed(),
    ]);

    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(gateway.startRealtimeCalls, 1);

    gateway.startRealtimeGate!.complete();
    await resumeOperations;

    await Future<void>.delayed(const Duration(milliseconds: 100));

    // Queued callers observe the established identity and return without
    // opening replacement channels.
    expect(gateway.startRealtimeCalls, 1);
  });
  test(
    'offline maintenance completion syncs when connectivity returns',
    () async {
      final db = AppDatabase(executor: NativeDatabase.memory());
      addTearDown(db.close);
      final store = LocalSyncStore(db);
      await store.account();
      await store.setEnabled(enabled: true, boundUserId: 'user-1');
      await store.recordSyncSuccess(DateTime.now().toUtc());
      await _seedMaintenancePlanForSync(db, suffix: 'offline');
      await db.delete(db.syncOutbox).go();
      final serverPlan = await (db.select(
        db.maintenancePlans,
      )..where((row) => row.id.equals('maintenance-plan-offline'))).getSingle();

      final auth = _FakeAuthRepository(const AuthSession(userId: 'user-1'));
      addTearDown(auth.controller.close);
      final connectivity = _FakeConnectivity(false);
      addTearDown(connectivity.controller.close);
      final gateway = _StatefulGateway()
        ..seedMaintenancePlan(
          userId: 'user-1',
          planId: serverPlan.id,
          assetId: serverPlan.assetId,
          currentOccurrenceId: serverPlan.currentOccurrenceId,
          nextDueDate: serverPlan.nextDueDate,
          recurrenceInterval: serverPlan.recurrenceInterval,
          recurrenceUnit: serverPlan.recurrenceUnit,
        );
      final coordinator = SyncCoordinator(
        auth,
        store,
        gateway,
        connectivity: connectivity,
        realtime: gateway,
      );
      addTearDown(coordinator.dispose);

      final completedAt = DateTime.utc(2026, 8, 13, 14, 30);
      final completion = await DriftMaintenanceRepository(db)
          .completePlanResult(
            'maintenance-plan-offline',
            expectedOccurrenceId:
                (await (db.select(db.maintenancePlans)..where(
                          (row) => row.id.equals('maintenance-plan-offline'),
                        ))
                        .getSingle())
                    .currentOccurrenceId,
            completedAt: completedAt,
          );
      expect(completion.isApplied, isTrue);
      expect(await store.pendingCount(), 1);
      expect(gateway.maintenanceCompletionCalls, 0);

      connectivity.setOnline(true);
      await _eventually(() async {
        return gateway.maintenanceCompletionCalls == 1 &&
            await store.pendingCount() == 0;
      });

      final remotePlan = await gateway.fetch(
        spec: syncSpecByEntity['maintenance_plan']!,
        userId: 'user-1',
        deviceId: (await store.account()).deviceId,
        recordKey: 'maintenance-plan-offline',
      );
      expect(remotePlan, isNotNull);
      expect(
        DateTime.parse(remotePlan!.values['next_due_date']! as String).toUtc(),
        DateTime.utc(2026, 9, 13, 14, 30),
      );
      final remoteRecord = gateway._records.singleWhere(
        (item) =>
            item.userId == 'user-1' &&
            item.record.spec.entity == 'maintenance_record',
      );
      expect(
        DateTime.parse(remoteRecord.record.values['completed_at']! as String)
            .toUtc(),
        completedAt,
      );
    },
  );

  test('two devices completing one occurrence converge on the first canonical completion', () async {
    final dbA = AppDatabase(executor: NativeDatabase.memory());
    final dbB = AppDatabase(executor: NativeDatabase.memory());
    addTearDown(dbA.close);
    addTearDown(dbB.close);
    final storeA = LocalSyncStore(dbA);
    final storeB = LocalSyncStore(dbB);
    await storeA.account();
    await storeB.account();
    await storeA.setEnabled(enabled: true, boundUserId: 'user-1');
    await storeB.setEnabled(enabled: true, boundUserId: 'user-1');
    await storeA.recordSyncSuccess(DateTime.now().toUtc());
    await storeB.recordSyncSuccess(DateTime.now().toUtc());
    await _seedMaintenancePlanForSync(dbA, suffix: 'race');
    await _seedMaintenancePlanForSync(dbB, suffix: 'race');
    final serverPlan = await (dbA.select(
      dbA.maintenancePlans,
    )..where((row) => row.id.equals('maintenance-plan-race'))).getSingle();
    await (dbB.update(
      dbB.maintenancePlans,
    )..where((row) => row.id.equals('maintenance-plan-race'))).write(
      MaintenancePlansCompanion(
        currentOccurrenceId: Value(serverPlan.currentOccurrenceId),
      ),
    );
    await dbA.delete(dbA.syncOutbox).go();
    await dbB.delete(dbB.syncOutbox).go();

    final repoA = DriftMaintenanceRepository(dbA);
    final repoB = DriftMaintenanceRepository(dbB);
    final first = await repoA.completePlanResult(
      'maintenance-plan-race',
      expectedOccurrenceId: (await repoA.getTask('maintenance-plan-race'))!
          .plan
          .currentOccurrenceId,
      completedAt: DateTime.utc(2026, 8, 18, 10),
    );
    final second = await repoB.completePlanResult(
      'maintenance-plan-race',
      expectedOccurrenceId: (await repoB.getTask('maintenance-plan-race'))!
          .plan
          .currentOccurrenceId,
      completedAt: DateTime.utc(2026, 8, 18, 10, 5),
    );
    expect(first.isApplied, isTrue);
    expect(second.isApplied, isTrue);

    final authA = _FakeAuthRepository(const AuthSession(userId: 'user-1'));
    final authB = _FakeAuthRepository(const AuthSession(userId: 'user-1'));
    addTearDown(authA.controller.close);
    addTearDown(authB.controller.close);
    final gateway = _StatefulGateway()
      ..seedMaintenancePlan(
        userId: 'user-1',
        planId: serverPlan.id,
        assetId: serverPlan.assetId,
        currentOccurrenceId: serverPlan.currentOccurrenceId,
        nextDueDate: serverPlan.nextDueDate,
        recurrenceInterval: serverPlan.recurrenceInterval,
        recurrenceUnit: serverPlan.recurrenceUnit,
      );
    final coordinatorA = SyncCoordinator(
      authA,
      storeA,
      gateway,
      listenToAuthChanges: false,
    );
    final coordinatorB = SyncCoordinator(
      authB,
      storeB,
      gateway,
      listenToAuthChanges: false,
    );
    addTearDown(coordinatorA.dispose);
    addTearDown(coordinatorB.dispose);

    await coordinatorA.syncNow();
    await coordinatorB.syncNow();

    expect(await storeA.pendingCount(), 0);
    expect(await storeB.pendingCount(), 0);
    final recordsA = await repoA.listRecordsForPlan('maintenance-plan-race');
    final recordsB = await repoB.listRecordsForPlan('maintenance-plan-race');
    expect(recordsA, hasLength(1));
    expect(recordsB, hasLength(1));
    expect(recordsA.single.id, first.operationId);
    expect(recordsB.single.id, first.operationId);
    expect(recordsB.single.id, isNot(second.operationId));
    expect(recordsB.single.completedAt.toUtc(), DateTime.utc(2026, 8, 18, 10));
    expect(
      (await repoB.getTask('maintenance-plan-race'))!.plan.nextDueDate.toUtc(),
      (await repoA.getTask('maintenance-plan-race'))!.plan.nextDueDate.toUtc(),
    );
  });

  test(
    'Undo while completion RPC is in flight compensates the cloud atomically',
    () async {
      final db = AppDatabase(executor: NativeDatabase.memory());
      addTearDown(db.close);
      final store = LocalSyncStore(db);
      await store.account();
      await store.setEnabled(enabled: true, boundUserId: 'user-1');
      await store.recordSyncSuccess(DateTime.now().toUtc());
      await _seedMaintenancePlanForSync(db, suffix: 'undo-race');
      await db.delete(db.syncOutbox).go();
      final serverPlan =
          await (db.select(db.maintenancePlans)
                ..where((row) => row.id.equals('maintenance-plan-undo-race')))
              .getSingle();

      final due = DateTime.utc(2026, 8, 18, 9);
      final repo = DriftMaintenanceRepository(db);
      final completion = await repo.completePlanResult(
        'maintenance-plan-undo-race',
        expectedOccurrenceId: (await repo.getTask(
          'maintenance-plan-undo-race',
        ))!.plan.currentOccurrenceId,
        completedAt: DateTime.utc(2026, 8, 18, 10),
      );
      expect(completion.isApplied, isTrue);

      final auth = _FakeAuthRepository(const AuthSession(userId: 'user-1'));
      addTearDown(auth.controller.close);
      final gateway = _StatefulGateway()
        ..seedMaintenancePlan(
          userId: 'user-1',
          planId: serverPlan.id,
          assetId: serverPlan.assetId,
          currentOccurrenceId: serverPlan.currentOccurrenceId,
          nextDueDate: serverPlan.nextDueDate,
          recurrenceInterval: serverPlan.recurrenceInterval,
          recurrenceUnit: serverPlan.recurrenceUnit,
        )
        ..maintenanceCompletionGate = Completer<void>();
      final coordinator = SyncCoordinator(
        auth,
        store,
        gateway,
        listenToAuthChanges: false,
      );
      addTearDown(coordinator.dispose);

      final syncFuture = coordinator.syncNow();
      await _eventually(() async => gateway.maintenanceCompletionCalls == 1);

      await repo.undoCompletion(
        planId: 'maintenance-plan-undo-race',
        completionId: completion.operationId!,
        completedOccurrenceId: completion.completedOccurrenceId!,
        expectedCurrentOccurrenceId: completion.nextOccurrenceId!,
        previousDueDate: completion.previousDueDate!,
        expectedCurrentNextDueDate: completion.nextDueDate!,
      );
      final queuedAfterUndo = await store.pendingMutations();
      expect(queuedAfterUndo.first.entity, 'maintenance_undo');
      expect(
        queuedAfterUndo.any(
          (mutation) =>
              mutation.entity == 'maintenance_record' &&
              mutation.operation == 'delete',
        ),
        isTrue,
      );
      gateway.maintenanceCompletionGate!.complete();
      await syncFuture;
      await _eventually(() async {
        return gateway.maintenanceUndoCalls == 1 &&
            await store.pendingCount() == 0;
      });

      expect(
        await repo.listRecordsForPlan('maintenance-plan-undo-race'),
        isEmpty,
      );
      expect(
        (await repo.getTask('maintenance-plan-undo-race'))!.plan.nextDueDate
            .toUtc(),
        due,
      );
      expect(
        gateway._records.where(
          (item) =>
              item.userId == 'user-1' &&
              item.record.spec.entity == 'maintenance_record',
        ),
        isEmpty,
      );
      final remotePlan = gateway._records.singleWhere(
        (item) =>
            item.userId == 'user-1' &&
            item.record.spec.entity == 'maintenance_plan' &&
            item.record.recordKey == 'maintenance-plan-undo-race',
      );
      expect(
        DateTime.parse(remotePlan.record.values['next_due_date']! as String)
            .toUtc(),
        due,
      );
    },
  );

  test('old offline timestamps remain normal conflicts while a fast local clock cannot win', () async {
    Future<String> runScenario({required bool fastLocalClock}) async {
      final db = AppDatabase(executor: NativeDatabase.memory());
      addTearDown(db.close);
      final store = LocalSyncStore(db);
      final account = await store.account();
      await store.setEnabled(enabled: true, boundUserId: 'user-1');
      await store.recordSyncSuccess(DateTime.now().toUtc());
      await db.delete(db.syncOutbox).go();
      final gateway = _StatefulGateway();
      final spec = syncSpecByEntity['user_setting']!;
      final now = DateTime.now().toUtc();
      final initialAt = now.subtract(const Duration(hours: 3));
      final remoteEditAt = now.subtract(const Duration(hours: 2));
      final localEditAt = fastLocalClock
          ? now.add(const Duration(hours: 1))
          : now.subtract(const Duration(hours: 1));

      final initialWrite = await gateway.write(
        record: SyncRecord(
          spec: spec,
          recordKey: 'theme',
          values: {
            'key': 'theme',
            'value': 'light',
            'updated_at': initialAt.toIso8601String(),
          },
          clientModifiedAt: initialAt,
          originDeviceId: 'seed-device',
        ),
        userId: 'user-1',
        deviceId: 'seed-device',
        expectedRevision: null,
      );
      await store.applyRemoteRecords([initialWrite.canonical!]);
      await db.delete(db.syncOutbox).go();

      final remoteWrite = await gateway.write(
        record: SyncRecord(
          spec: spec,
          recordKey: 'theme',
          values: {
            'key': 'theme',
            'value': 'dark',
            'updated_at': remoteEditAt.toIso8601String(),
          },
          clientModifiedAt: remoteEditAt,
          originDeviceId: 'remote-device',
        ),
        userId: 'user-1',
        deviceId: 'remote-device',
        expectedRevision: initialWrite.canonical!.revision,
      );
      expect(remoteWrite.conflict, isFalse);

      await (db.update(
        db.settings,
      )..where((row) => row.key.equals('theme'))).write(
        SettingsCompanion(
          value: const Value('system'),
          updatedAt: Value(localEditAt),
        ),
      );
      expect(await store.pendingCount(), 1);

      final auth = _FakeAuthRepository(const AuthSession(userId: 'user-1'));
      addTearDown(auth.controller.close);
      final coordinator = SyncCoordinator(
        auth,
        store,
        gateway,
        listenToAuthChanges: false,
      );
      addTearDown(coordinator.dispose);
      await coordinator.syncNow();

      final remoteFinal = await gateway.fetch(
        spec: spec,
        userId: 'user-1',
        deviceId: account.deviceId,
        recordKey: 'theme',
      );
      return remoteFinal!.values['value']! as String;
    }

    expect(await runScenario(fastLocalClock: false), 'system');
    expect(await runScenario(fastLocalClock: true), 'dark');
  });

  test(
    'network restoration pushes queued edits and realtime pulls remote edits',
    () async {
      final db = AppDatabase(executor: NativeDatabase.memory());
      addTearDown(db.close);
      final store = LocalSyncStore(db);
      final account = await store.account();
      await store.setEnabled(enabled: true, boundUserId: 'user-1');
      await db.customStatement('DELETE FROM offline_mutation_queue');
      final auth = _FakeAuthRepository(const AuthSession(userId: 'user-1'));
      addTearDown(auth.controller.close);
      final connectivity = _FakeConnectivity(false);
      addTearDown(connectivity.controller.close);
      final gateway = _StatefulGateway();
      final coordinator = SyncCoordinator(
        auth,
        store,
        gateway,
        connectivity: connectivity,
        realtime: gateway,
      );
      addTearDown(coordinator.dispose);

      await db.customStatement(
        "UPDATE settings SET value = 'light' WHERE key = 'theme'",
      );
      await Future<void>.delayed(const Duration(milliseconds: 500));
      expect(
        await gateway.fetch(
          spec: syncSpecByEntity['user_setting']!,
          userId: 'user-1',
          deviceId: account.deviceId,
          recordKey: 'theme',
        ),
        isNull,
      );

      connectivity.setOnline(true);
      await _eventually(() async {
        return await gateway.fetch(
              spec: syncSpecByEntity['user_setting']!,
              userId: 'user-1',
              deviceId: account.deviceId,
              recordKey: 'theme',
            ) !=
            null;
      });

      final current = await gateway.fetch(
        spec: syncSpecByEntity['user_setting']!,
        userId: 'user-1',
        deviceId: account.deviceId,
        recordKey: 'theme',
      );
      await gateway.write(
        record: SyncRecord(
          spec: syncSpecByEntity['user_setting']!,
          recordKey: 'theme',
          values: {
            'key': 'theme',
            'value': 'dark',
            'updated_at': DateTime.now()
                .add(const Duration(seconds: 1))
                .toUtc()
                .toIso8601String(),
          },
          clientModifiedAt: DateTime.now()
              .add(const Duration(seconds: 1))
              .toUtc(),
          originDeviceId: 'second-device',
        ),
        userId: 'user-1',
        deviceId: 'second-device',
        expectedRevision: current!.revision,
      );
      final changedTheme = await gateway.fetch(
        spec: syncSpecByEntity['user_setting']!,
        userId: 'user-1',
        deviceId: account.deviceId,
        recordKey: 'theme',
      );
      gateway.onRealtimeChange!(
        RealtimeSyncEvent(
          table: syncSpecByEntity['user_setting']!.remoteTable,
          spec: syncSpecByEntity['user_setting']!,
          type: SyncRealtimeEventType.update,
          recordKey: 'theme',
          revision: changedTheme?.revision,
          updatedAt: changedTheme?.clientModifiedAt,
          originDeviceId: changedTheme?.originDeviceId,
        ),
      );

      await _eventually(() async {
        final row = await db
            .customSelect("SELECT value FROM settings WHERE key = 'theme'")
            .getSingle();
        return row.read<String>('value') == 'dark';
      });

      gateway.onRealtimeDelete!(syncSpecByEntity['user_setting']!, const {
        'user_id': 'other-user',
        'key': 'theme',
      });
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(
        (await db
                .customSelect("SELECT value FROM settings WHERE key = 'theme'")
                .getSingle())
            .read<String>('value'),
        'dark',
      );

      gateway.hardDelete(
        userId: 'user-1',
        spec: syncSpecByEntity['user_setting']!,
        recordKey: 'theme',
      );
      await _eventually(() async {
        return await db
                .customSelect("SELECT 1 FROM settings WHERE key = 'theme'")
                .getSingleOrNull() ==
            null;
      });
      expect(await store.pendingChangedAt('user_setting', 'theme'), isNull);

      await gateway.write(
        record: SyncRecord(
          spec: syncSpecByEntity['user_setting']!,
          recordKey: 'theme',
          values: {
            'key': 'theme',
            'value': 'light',
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          },
          clientModifiedAt: DateTime.now().toUtc(),
          originDeviceId: 'second-device',
        ),
        userId: 'user-1',
        deviceId: 'second-device',
        expectedRevision: null,
      );
      final writtenTheme = await gateway.fetch(
        spec: syncSpecByEntity['user_setting']!,
        userId: 'user-1',
        deviceId: 'second-device',
        recordKey: 'theme',
      );
      gateway.onRealtimeChange!(
        RealtimeSyncEvent(
          table: syncSpecByEntity['user_setting']!.remoteTable,
          spec: syncSpecByEntity['user_setting']!,
          type: SyncRealtimeEventType.insert,
          recordKey: 'theme',
          revision: writtenTheme?.revision,
          updatedAt: writtenTheme?.clientModifiedAt,
          originDeviceId: writtenTheme?.originDeviceId,
        ),
      );
      await _eventually(() async {
        final row = await db
            .customSelect("SELECT value FROM settings WHERE key = 'theme'")
            .getSingleOrNull();
        return row?.read<String>('value') == 'light';
      });
    },
  );

  test(
    'realtime delete preserves and replays newer pending local intent',
    () async {
      final db = AppDatabase(executor: NativeDatabase.memory());
      addTearDown(db.close);
      final store = LocalSyncStore(db);
      final account = await store.account();
      await store.setEnabled(enabled: true, boundUserId: 'user-1');
      await db.delete(db.syncOutbox).go();
      final auth = _FakeAuthRepository(const AuthSession(userId: 'user-1'));
      addTearDown(auth.controller.close);
      final gateway = _StatefulGateway();
      final coordinator = SyncCoordinator(
        auth,
        store,
        gateway,
        realtime: gateway,
      );
      addTearDown(coordinator.dispose);
      await _eventually(() async => gateway.onRealtimeDelete != null);

      final spec = syncSpecByEntity['user_setting']!;
      final seeded = await gateway.write(
        record: SyncRecord(
          spec: spec,
          recordKey: 'theme',
          values: {
            'key': 'theme',
            'value': 'light',
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          },
          clientModifiedAt: DateTime.now().toUtc(),
          originDeviceId: 'peer-device',
        ),
        userId: 'user-1',
        deviceId: 'peer-device',
        expectedRevision: null,
      );
      await store.applyRemoteFeedRecord(seeded.canonical!);
      await db.delete(db.syncOutbox).go();
      await db.customStatement(
        "UPDATE settings SET value = 'dark' WHERE key = 'theme'",
      );
      expect(await store.pendingChangedAt('user_setting', 'theme'), isNotNull);

      gateway.hardDelete(userId: 'user-1', spec: spec, recordKey: 'theme');

      await _eventually(() async {
        final local = await db
            .customSelect("SELECT value FROM settings WHERE key = 'theme'")
            .getSingleOrNull();
        final remote = await gateway.fetch(
          spec: spec,
          userId: 'user-1',
          deviceId: account.deviceId,
          recordKey: 'theme',
        );
        return local?.read<String>('value') == 'dark' &&
            remote?.values['value'] == 'dark';
      });
    },
  );

  test('stale realtime delete cannot apply after the authenticated account changes', () async {
    final db = AppDatabase(executor: NativeDatabase.memory());
    addTearDown(db.close);
    final store = LocalSyncStore(db);
    await store.account();
    await store.setEnabled(enabled: true, boundUserId: 'user-1');
    await store.recordSyncSuccess(DateTime.now().toUtc());
    await db.delete(db.syncOutbox).go();
    final auth = _FakeAuthRepository(const AuthSession(userId: 'user-1'));
    addTearDown(auth.controller.close);
    final gateway = _StatefulGateway();
    final coordinator = SyncCoordinator(
      auth,
      store,
      gateway,
      realtime: gateway,
    );
    addTearDown(coordinator.dispose);
    await _eventually(() async => gateway.onRealtimeDelete != null);

    final spec = syncSpecByEntity['user_setting']!;
    final seeded = await gateway.write(
      record: SyncRecord(
        spec: spec,
        recordKey: 'theme',
        values: {
          'key': 'theme',
          'value': 'dark',
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
        clientModifiedAt: DateTime.now().toUtc(),
        originDeviceId: 'peer-device',
      ),
      userId: 'user-1',
      deviceId: 'peer-device',
      expectedRevision: null,
    );
    await store.applyRemoteFeedRecord(seeded.canonical!);
    await db.delete(db.syncOutbox).go();

    final priorFeedCalls = gateway.fetchFeedCalls;
    gateway.feedGate = Completer<void>();
    gateway.hardDelete(userId: 'user-1', spec: spec, recordKey: 'theme');
    await _eventually(() async => gateway.fetchFeedCalls > priorFeedCalls);

    auth.emit(AuthEventType.signedIn, const AuthSession(userId: 'user-2'));
    gateway.feedGate!.complete();
    await Future<void>.delayed(const Duration(milliseconds: 100));

    final local = await db
        .customSelect("SELECT value FROM settings WHERE key = 'theme'")
        .getSingleOrNull();
    expect(local?.read<String>('value'), 'dark');
  });

  test('duplicate realtime deletes reconcile idempotently', () async {
    final db = AppDatabase(executor: NativeDatabase.memory());
    addTearDown(db.close);
    final store = LocalSyncStore(db);
    await store.account();
    await store.setEnabled(enabled: true, boundUserId: 'user-1');
    await store.recordSyncSuccess(DateTime.now().toUtc());
    await db.delete(db.syncOutbox).go();
    final auth = _FakeAuthRepository(const AuthSession(userId: 'user-1'));
    addTearDown(auth.controller.close);
    final gateway = _StatefulGateway();
    final coordinator = SyncCoordinator(
      auth,
      store,
      gateway,
      realtime: gateway,
    );
    addTearDown(coordinator.dispose);
    await _eventually(() async => gateway.onRealtimeDelete != null);

    final spec = syncSpecByEntity['user_setting']!;
    final seeded = await gateway.write(
      record: SyncRecord(
        spec: spec,
        recordKey: 'theme',
        values: {
          'key': 'theme',
          'value': 'dark',
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
        clientModifiedAt: DateTime.now().toUtc(),
        originDeviceId: 'peer-device',
      ),
      userId: 'user-1',
      deviceId: 'peer-device',
      expectedRevision: null,
    );
    await store.applyRemoteFeedRecord(seeded.canonical!);
    await db.delete(db.syncOutbox).go();

    gateway.hardDelete(userId: 'user-1', spec: spec, recordKey: 'theme');
    gateway.hardDelete(userId: 'user-1', spec: spec, recordKey: 'theme');

    await _eventually(() async {
      return await db
              .customSelect("SELECT 1 FROM settings WHERE key = 'theme'")
              .getSingleOrNull() ==
          null;
    });
    expect(gateway.fetchFeedCalls, greaterThanOrEqualTo(1));
  });
}

Future<void> _seedMaintenancePlanForSync(
  AppDatabase db, {
  required String suffix,
}) async {
  final store = LocalSyncStore(db);
  await store.withOutboxSuppressed(() async {
    await DriftAssetRepository(db).saveArea(
      id: 'area-$suffix',
      name: 'Area $suffix',
      kind: AreaKind.indoor,
      sortOrder: 0,
    );
    await db
        .into(db.rooms)
        .insert(
          RoomsCompanion.insert(
            id: 'maintenance-room-$suffix',
            areaId: 'area-$suffix',
            name: 'Maintenance room $suffix',
          ),
        );
    await db
        .into(db.assets)
        .insert(
          AssetsCompanion.insert(
            id: 'maintenance-asset-$suffix',
            name: 'Maintenance asset $suffix',
            roomId: 'maintenance-room-$suffix',
          ),
        );
    await db
        .into(db.maintenancePlans)
        .insert(
          MaintenancePlansCompanion.insert(
            id: 'maintenance-plan-$suffix',
            assetId: 'maintenance-asset-$suffix',
            title: 'Maintenance task $suffix',
            recurrenceInterval: 1,
            recurrenceUnit: 'months',
            priority: 'medium',
            nextDueDate: DateTime.utc(2026, 8, 18, 9),
          ),
        );
  });
}

Future<void> _eventually(Future<bool> Function() condition) async =>
    // WP-015 (F-024): shared bounded helper replaces the wall-clock loop.
    waitFor(
      () async => await condition(),
      timeout: const Duration(seconds: 5),
      because: 'Condition was not met before the timeout.',
    );
