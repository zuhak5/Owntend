import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('user-facing task dependencies are removed across active layers', () {
    final activeSources = <String>[
      'lib/main.dart',
      'lib/src/core/domain/models.dart',
      'lib/src/core/data/repositories.dart',
      'lib/src/core/sync/sync_dtos.dart',
      'lib/src/features/maintenance/application/task_creation_controller.dart',
      'lib/l10n/app_en.arb',
      'lib/l10n/app_ar.arb',
    ];
    for (final path in activeSources) {
      final source = File(path).readAsStringSync();
      expect(source, isNot(contains('dependencyPlanIds')), reason: path);
      expect(source, isNot(contains('dependency_plan_ids')), reason: path);
      expect(source, isNot(contains('dependencyTasks')), reason: path);
      expect(source, isNot(contains('dependsOn')), reason: path);
    }

    final coreSchema = File(
      'supabase/migrations/20260815000001_core_schema.sql',
    ).readAsStringSync();
    expect(coreSchema, isNot(contains('dependency_plan_ids_json')));

    final completionSync = [
      File('lib/src/core/data/repositories.dart').readAsStringSync(),
      for (final entity in Directory('lib/src/core/data').listSync())
        if (entity is File && entity.path.endsWith('.dart'))
          entity.readAsStringSync(),
    ].join('\n');
    expect(
      completionSync,
      contains("'depends_on_operation_id': predecessorId"),
    );
  });
}
