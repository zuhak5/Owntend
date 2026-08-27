import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:owntend/src/features/monetization/monetization.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _MockSupabaseClient extends Mock implements SupabaseClient {}

class _FakePostgrestFilterBuilder<T> extends Fake
    implements PostgrestFilterBuilder<T> {
  _FakePostgrestFilterBuilder(this._future);

  final Future<T> _future;

  @override
  Future<R> then<R>(
    FutureOr<R> Function(T value) onValue, {
    Function? onError,
  }) => _future.then(onValue, onError: onError);
}

void main() {
  group('SupabaseMonetizationRepository Request Signing', () {
    late _MockSupabaseClient client;
    late SupabaseMonetizationRepository repository;

    setUp(() {
      client = _MockSupabaseClient();
      repository = SupabaseMonetizationRepository(client);
    });

    test('createAsset automatically computes deterministic 64-char SHA-256 request_hash for unsigned payload', () async {
      final unsignedPayload = {
        'operation_id': 'op-asset-001',
        'asset': {
          'id': 'asset-001',
          'name': 'Air Conditioner',
          'asset_type': 'device',
          'room_id': 'room-001',
        },
        'details': {'brand': 'CoolCorp', 'model': 'CC-200'},
        'initial_plans': const <Map<String, dynamic>>[],
      };

      final expectedHash = sha256
          .convert(utf8.encode(jsonEncode(unsignedPayload)))
          .toString();

      when(
        () => client.rpc<Map<String, dynamic>>(
          'create_asset',
          params: any(named: 'params'),
        ),
      ).thenAnswer(
        (_) => _FakePostgrestFilterBuilder(
          Future.value({
            'asset_id': 'asset-001',
            'balance': 5,
            'charged': 0,
            'already_processed': false,
          }),
        ),
      );

      final result = await repository.createAsset(unsignedPayload);

      expect(result.charged, equals(0));
      expect(result.balance, equals(5));

      final captured = verify(
        () => client.rpc<Map<String, dynamic>>(
          'create_asset',
          params: captureAny(named: 'params'),
        ),
      ).captured;

      expect(captured, hasLength(1));
      final params = captured.first as Map<String, dynamic>;
      final sentPayload = params['p_operation'] as Map<String, dynamic>;

      expect(sentPayload['request_hash'], equals(expectedHash));
      expect(
        sentPayload['request_hash'] as String,
        matches(RegExp(r'^[0-9a-f]{64}$')),
      );
      expect(sentPayload['operation_id'], equals('op-asset-001'));
    });

    test('createAsset strips existing dirty request_hash and recomputes canonical digest', () async {
      final dirtyPayload = {
        'operation_id': 'op-asset-002',
        'request_hash': 'invalid-or-stale-hash',
        'asset': {
          'id': 'asset-002',
          'name': 'Smoke Detector',
          'asset_type': 'safety',
          'room_id': 'room-002',
        },
        'details': {'safety_type': 'smoke_alarm'},
        'initial_plans': const <Map<String, dynamic>>[],
      };

      final canonicalUnsigned = Map<String, dynamic>.from(dirtyPayload)
        ..remove('request_hash');
      final expectedCanonicalHash = sha256
          .convert(utf8.encode(jsonEncode(canonicalUnsigned)))
          .toString();

      when(
        () => client.rpc<Map<String, dynamic>>(
          'create_asset',
          params: any(named: 'params'),
        ),
      ).thenAnswer(
        (_) => _FakePostgrestFilterBuilder(
          Future.value({
            'asset_id': 'asset-002',
            'balance': 5,
            'charged': 0,
            'already_processed': false,
          }),
        ),
      );

      await repository.createAsset(dirtyPayload);

      final captured = verify(
        () => client.rpc<Map<String, dynamic>>(
          'create_asset',
          params: captureAny(named: 'params'),
        ),
      ).captured;

      final params = captured.first as Map<String, dynamic>;
      final sentPayload = params['p_operation'] as Map<String, dynamic>;

      expect(sentPayload['request_hash'], equals(expectedCanonicalHash));
      expect(
        sentPayload['request_hash'],
        isNot(equals('invalid-or-stale-hash')),
      );
    });

    test(
      'createTask forwards signed payload and preserves valid request_hash',
      () async {
        const validHash =
            'a0bdc12ffb7f4d8ccbc5063a44b3745937acce7ce89a27f5ca4b8e5ae9d970aa';
        final taskPayload = {
          'operation_id': 'op-task-001',
          'request_hash': validHash,
          'plan': {
            'id': 'plan-001',
            'asset_id': 'asset-001',
            'title': 'Replace filter',
          },
        };

        when(
          () => client.rpc<Map<String, dynamic>>(
            'create_task_with_point_debit',
            params: any(named: 'params'),
          ),
        ).thenAnswer(
          (_) => _FakePostgrestFilterBuilder(
            Future.value({
              'plan_id': 'plan-001',
              'balance': 4,
              'charged': 1,
              'already_processed': false,
            }),
          ),
        );

        final result = await repository.createTask(taskPayload);

        expect(result.charged, equals(1));
        expect(result.balance, equals(4));

        final captured = verify(
          () => client.rpc<Map<String, dynamic>>(
            'create_task_with_point_debit',
            params: captureAny(named: 'params'),
          ),
        ).captured;

        final params = captured.first as Map<String, dynamic>;
        final sentPayload = params['p_operation'] as Map<String, dynamic>;
        expect(sentPayload['request_hash'], equals(validHash));
      },
    );

    test(
      'copyAsset signs only the authoritative source-copy contract',
      () async {
        final operation = {
          'operation_id': 'copy-op-001',
          'source_asset_id': 'asset-source',
          'target_asset_id': 'asset-target',
          'destination_room_id': 'room-target',
          'include_tasks': true,
          'plan_id_map': {'plan-source': 'plan-target'},
          'request_hash': 'dirty',
        };
        when(
          () => client.rpc<Map<String, dynamic>>(
            'copy_asset',
            params: any(named: 'params'),
          ),
        ).thenAnswer(
          (_) => _FakePostgrestFilterBuilder(
            Future.value({
              'balance': 4,
              'charged': 0,
              'already_processed': false,
              'asset': {'id': 'asset-target'},
              'plans': const <Map<String, dynamic>>[],
            }),
          ),
        );

        await repository.copyAsset(operation);

        final params =
            verify(
                  () => client.rpc<Map<String, dynamic>>(
                    'copy_asset',
                    params: captureAny(named: 'params'),
                  ),
                ).captured.single
                as Map<String, dynamic>;
        final sent = params['p_operation'] as Map<String, dynamic>;
        final unsigned = Map<String, dynamic>.from(sent)
          ..remove('request_hash');
        expect(sent.keys, containsAll(operation.keys));
        expect(
          sent['request_hash'],
          sha256.convert(utf8.encode(jsonEncode(unsigned))).toString(),
        );
        expect(sent, isNot(contains('asset')));
        expect(sent, isNot(contains('initial_plans')));
      },
    );

    test('move quote and commit use their dedicated RPC contracts', () async {
      when(
        () => client.rpc<Map<String, dynamic>>(
          'quote_maintenance_plan_move',
          params: any(named: 'params'),
        ),
      ).thenAnswer(
        (_) => _FakePostgrestFilterBuilder(
          Future.value({'charge': 1, 'balance': 5, 'plan_revision': 7}),
        ),
      );
      when(
        () => client.rpc<Map<String, dynamic>>(
          'move_maintenance_plan_with_point_delta',
          params: any(named: 'params'),
        ),
      ).thenAnswer(
        (_) => _FakePostgrestFilterBuilder(
          Future.value({
            'status': 'applied',
            'charged': 1,
            'balance': 4,
            'already_processed': false,
          }),
        ),
      );

      final quote = await repository.quoteMaintenancePlanMove(
        planId: 'plan-1',
        targetAssetId: 'asset-2',
      );
      final result = await repository.moveMaintenancePlan({
        'operation_id': 'move-op-1',
        'plan_id': 'plan-1',
        'target_asset_id': 'asset-2',
        'expected_plan_revision': quote.revision,
        'max_charge': quote.charge,
      });

      expect((quote.charge, quote.revision), equals((1, 7)));
      expect((
        result.status,
        result.charged,
        result.balance,
      ), equals(('applied', 1, 4)));
      final params =
          verify(
                () => client.rpc<Map<String, dynamic>>(
                  'move_maintenance_plan_with_point_delta',
                  params: captureAny(named: 'params'),
                ),
              ).captured.single
              as Map<String, dynamic>;
      expect(
        (params['p_operation'] as Map<String, dynamic>)['request_hash'],
        matches(RegExp(r'^[0-9a-f]{64}$')),
      );
    });
  });
}
