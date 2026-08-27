import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
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

  test('generic sync omits protected economic columns and history writes', () {
    final source = File('lib/src/core/sync/supabase_sync_gateway.dart')
        .readAsStringSync();

    expect(source, contains("payload.remove('asset_type')"));
    expect(source, contains("payload.remove('asset_id')"));
    expect(source, contains("record.spec.entity == 'maintenance_record'"));
    expect(source, contains('Maintenance history is server-authoritative'));
  });
}
