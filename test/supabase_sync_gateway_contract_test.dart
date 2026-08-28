import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:owntend/src/core/supabase/supabase_failure.dart';
import 'package:owntend/src/core/sync/supabase_sync_gateway.dart';
import 'package:owntend/src/core/sync/sync_dtos.dart';

void main() {
  test('zero-row optimistic writes use list responses instead of HTTP 406', () {
    final source = File('lib/src/core/sync/supabase_sync_gateway.dart')
        .readAsStringSync();

    expect(source, isNot(contains('.maybeSingle()')));
    expect(source, contains('final responseRows = await _withDataTimeout'));
    expect(source, contains('_zeroOrOneRemoteRow(responseRows)'));
  });

  test('cloud aliases map to the canonical local sync fields', () {
    final plan = syncSpecByEntity['maintenance_plan']!;
    expect(plan.remoteColumnFor('instructions'), 'instructions');
    expect(plan.remoteColumnFor('recurrence_interval'), 'recurrence_interval');
    expect(plan.remoteColumnFor('recurrence_unit'), 'recurrence_unit');
    expect(plan.localColumnFor('recurrence_interval'), 'recurrence_interval');

    final streak = syncSpecByEntity['streak']!;
    expect(streak.remoteColumnFor('best_streak'), 'longest_streak');
    expect(
      streak.remoteColumnFor('last_completed_date'),
      'last_completion_date',
    );
  });

  test(
    'authoritative-key pagination advances from the fetched page boundary',
    () {
      // F-030: the cursor must be the last row of THIS page, not an implicit
      // accumulated-set ordering property.
      final source = File('lib/src/core/sync/supabase_sync_gateway.dart')
          .readAsStringSync();

      expect(source, isNot(contains('afterRecordKey = keys.last')));
      expect(source, contains('pageLastKey = key;'));
      expect(source, contains('afterRecordKey = pageLastKey;'));
      expect(
        source.indexOf('pageLastKey = key;'),
        lessThan(source.indexOf('afterRecordKey = pageLastKey;')),
      );
    },
  );

  test('batch creation uses exact-key idempotent conflict resolution', () {
    final source = File('lib/src/core/sync/supabase_sync_gateway.dart')
        .readAsStringSync();

    expect(source, contains('onConflict: ['));
    expect(source, contains("ignoreDuplicates: true"));
    expect(source, contains('replayedRecordKeys'));
  });

  test('full asset and plan records produce minimal safe PATCH payloads', () {
    final changedAt = DateTime.utc(2026, 8, 28, 4, 40);
    final asset = SyncRecord(
      spec: syncSpecByEntity['asset']!,
      recordKey: 'asset-1',
      values: {
        'id': 'asset-1',
        'name': 'Updated asset',
        'asset_type': 'safety',
        'room_id': 'room-2',
        'placement': 'North wall',
        'notes': null,
        'purchase_date': null,
        'created_at': '2026-08-01T00:00:00.000Z',
        'updated_at': '2026-08-28T04:39:00.000Z',
        'archived_at': null,
      },
      clientModifiedAt: changedAt,
      revision: 1,
    );
    final plan = SyncRecord(
      spec: syncSpecByEntity['maintenance_plan']!,
      recordKey: 'plan-1',
      values: {
        'id': 'plan-1',
        'asset_id': 'asset-1',
        'title': 'Updated plan',
        'instructions': null,
        'recurrence_interval': 2,
        'recurrence_unit': 'months',
        'priority': 'high',
        'next_due_date': '2026-10-01T00:00:00.000Z',
        'reminder_days_before': 3,
        'is_enabled': true,
        'created_at': '2026-08-01T00:00:00.000Z',
        'updated_at': '2026-08-28T04:46:00.000Z',
        'archived_at': null,
      },
      clientModifiedAt: changedAt,
      revision: 1,
    );

    expect(asset.toRemoteUpdatePayload(), {
      'name': 'Updated asset',
      'room_id': 'room-2',
      'placement': 'North wall',
      'notes': null,
      'purchase_date': null,
      'archived_at': null,
    });
    expect(plan.toRemoteUpdatePayload(), {
      'title': 'Updated plan',
      'instructions': null,
      'recurrence_interval': 2,
      'recurrence_unit': 'months',
      'priority': 'high',
      'next_due_date': '2026-10-01T00:00:00.000Z',
      'reminder_days_before': 3,
      'is_enabled': true,
      'archived_at': null,
    });

    final createPayload = asset.toRemoteCreatePayload('owner-1');
    expect(createPayload['user_id'], 'owner-1');
    expect(createPayload['id'], 'asset-1');
    expect(createPayload['asset_type'], 'safety');
    expect(createPayload['created_at'], '2026-08-01T00:00:00.000Z');
    expect(createPayload['updated_at'], '2026-08-28T04:39:00.000Z');
  });

  test('remote aliases are applied only after update allowlisting', () {
    final streak = SyncRecord(
      spec: syncSpecByEntity['streak']!,
      recordKey: 'default',
      values: {
        'id': 'default',
        'current_streak': 4,
        'best_streak': 9,
        'last_completed_date': null,
        'updated_at': '2026-08-28T00:00:00.000Z',
      },
      clientModifiedAt: DateTime.utc(2026, 8, 28),
    );

    expect(streak.toRemoteUpdatePayload(), {
      'current_streak': 4,
      'longest_streak': 9,
      'last_completion_date': null,
    });
    expect(streak.toRemoteUpdatePayload(), isNot(contains('id')));
    expect(streak.toRemoteUpdatePayload(), isNot(contains('updated_at')));
  });

  test('all entity update contracts are structurally safe and fail closed', () {
    for (final spec in [...syncEntitySpecs, profileSyncSpec]) {
      expect(
        spec.updateContractViolations,
        isEmpty,
        reason: '${spec.entity} has an unsafe generic update contract',
      );
    }

    for (final entity in ['asset_tag', 'asset_photo', 'maintenance_record']) {
      final spec = syncSpecByEntity[entity]!;
      expect(spec.supportsGenericUpdate, isFalse);
      final record = SyncRecord(
        spec: spec,
        recordKey: 'read-only-record',
        values: const {},
        clientModifiedAt: DateTime.utc(2026, 8, 28),
      );
      expect(record.toRemoteUpdatePayload, throwsStateError);
    }
  });

  group('maintenance completion response contract', () {
    const userId = 'owner-1';
    final operation = <String, dynamic>{
      'plan': <String, dynamic>{'id': 'plan-1'},
      'record': <String, dynamic>{'id': 'record-1'},
    };

    test('accepts a fixed applied envelope with canonical records', () {
      final result = parseMaintenanceCompletionResult(
        _completionEnvelope(
          status: 'applied',
          currentPlanRevision: 2,
          resultingRecordId: 'record-1',
          resultingNextDueDate: '2026-10-01T00:00:00.000Z',
          plan: _remotePlan(userId),
          record: _remoteRecord(userId),
        ),
        operation: operation,
        userId: userId,
      );

      expect(result.status, MaintenanceCompletionStatus.applied);
      expect(result.plan?.recordKey, 'plan-1');
      expect(result.record?.recordKey, 'record-1');
      expect(result.currentPlanRevision, 2);
    });

    test('accepts terminal invalid and canonical conflict envelopes', () {
      final invalid = parseMaintenanceCompletionResult(
        _completionEnvelope(
          status: 'invalid',
          conflictReason: 'task_creation_not_authorized',
        ),
        operation: operation,
        userId: userId,
      );
      final conflict = parseMaintenanceCompletionResult(
        _completionEnvelope(
          status: 'conflict',
          conflictReason: 'operation_id_reused',
          currentPlanRevision: 2,
          resultingRecordId: 'record-1',
          resultingNextDueDate: '2026-10-01T00:00:00.000Z',
          plan: _remotePlan(userId),
          record: _remoteRecord(userId),
        ),
        operation: operation,
        userId: userId,
      );
      final crossPlanReuse = parseMaintenanceCompletionResult(
        _completionEnvelope(
          status: 'conflict',
          conflictReason: 'operation_id_reused',
        ),
        operation: operation,
        userId: userId,
      );

      expect(invalid.status, MaintenanceCompletionStatus.invalid);
      expect(invalid.retryable, isFalse);
      expect(conflict.status, MaintenanceCompletionStatus.conflict);
      expect(conflict.plan?.recordKey, 'plan-1');
      expect(conflict.record?.recordKey, 'record-1');
      expect(crossPlanReuse.status, MaintenanceCompletionStatus.conflict);
      expect(crossPlanReuse.plan, isNull);
      expect(crossPlanReuse.record, isNull);
    });

    test('rejects unknown versions, keys, types, and impossible success', () {
      final candidates = <Map<String, dynamic>>[
        {
          ..._completionEnvelope(status: 'invalid', conflictReason: 'x'),
          'contract_version': 2,
        },
        {
          ..._completionEnvelope(status: 'invalid', conflictReason: 'x'),
          'extra': true,
        },
        {
          ..._completionEnvelope(status: 'invalid', conflictReason: 'x'),
          'retryable': 'false',
        },
        _completionEnvelope(status: 'applied'),
        _completionEnvelope(
          status: 'conflict',
          conflictReason: 'occurrence_changed',
          retryable: true,
        ),
        _completionEnvelope(status: 'invalid', conflictReason: 'unknown'),
        _completionEnvelope(
          status: 'invalid',
          conflictReason: 'invalid_values',
          resultingNextDueDate: 'not-a-timestamp',
        ),
      ];

      for (final candidate in candidates) {
        expect(
          () => parseMaintenanceCompletionResult(
            candidate,
            operation: operation,
            userId: userId,
          ),
          throwsA(
            isA<SupabaseFailure>()
                .having(
                  (failure) => failure.kind,
                  'kind',
                  SupabaseFailureKind.incompatibleSchema,
                )
                .having(
                  (failure) => failure.diagnosticCode,
                  'diagnosticCode',
                  maintenanceCompletionRpcContractMismatchCode,
                ),
          ),
        );
      }
    });

    test('rejects canonical records from another account or request', () {
      expect(
        () => parseMaintenanceCompletionResult(
          _completionEnvelope(
            status: 'applied',
            currentPlanRevision: 2,
            resultingRecordId: 'record-1',
            resultingNextDueDate: '2026-10-01T00:00:00.000Z',
            plan: _remotePlan('other-owner'),
            record: _remoteRecord('other-owner'),
          ),
          operation: operation,
          userId: userId,
        ),
        throwsA(
          isA<SupabaseFailure>().having(
            (failure) => failure.kind,
            'kind',
            SupabaseFailureKind.permissionDenied,
          ),
        ),
      );
    });
  });
}

Map<String, dynamic> _completionEnvelope({
  required String status,
  bool retryable = false,
  String? conflictReason,
  int? currentPlanRevision,
  String? resultingRecordId,
  String? resultingNextDueDate,
  Map<String, dynamic>? plan,
  Map<String, dynamic>? record,
}) => <String, dynamic>{
  'contract_version': 1,
  'status': status,
  'retryable': retryable,
  'conflict_reason': conflictReason,
  'current_plan_revision': currentPlanRevision,
  'resulting_record_id': resultingRecordId,
  'resulting_next_due_date': resultingNextDueDate,
  'plan': plan,
  'record': record,
};

Map<String, dynamic> _remotePlan(String userId) => <String, dynamic>{
  'user_id': userId,
  'id': 'plan-1',
  'next_due_date': '2026-10-01T00:00:00.000Z',
  'updated_at': '2026-08-28T04:48:00.000Z',
  'revision': 2,
};

Map<String, dynamic> _remoteRecord(String userId) => <String, dynamic>{
  'user_id': userId,
  'id': 'record-1',
  'plan_id': 'plan-1',
  'created_at': '2026-08-28T04:48:00.000Z',
};
