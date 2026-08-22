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
}
