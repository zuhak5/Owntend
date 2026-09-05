import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:owntend/l10n/app_localizations.dart';
import 'package:owntend/src/core/database/app_database.dart';
import 'package:owntend/src/core/sync/local_sync_store.dart';
import 'package:owntend/src/core/sync/sync_contracts.dart';
import 'package:owntend/src/core/sync/sync_providers.dart';
import 'package:owntend/src/features/settings/presentation/sync_health_screen.dart';

import '../test_theme.dart';

void main() {
  late AppDatabase database;
  late LocalSyncStore store;

  setUp(() {
    database = AppDatabase(executor: NativeDatabase.memory());
    store = LocalSyncStore(database);
  });

  tearDown(() => database.close());

  testWidgets('shows an explicit healthy empty state', (tester) async {
    await tester.pumpWidget(_testApp(store));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('sync-health-empty')), findsOneWidget);
    expect(find.text('No sync issues need attention'), findsOneWidget);
  });

  testWidgets('failed mutation can be returned to the pending queue', (
    tester,
  ) async {
    await database
        .into(database.syncOutbox)
        .insert(
          SyncOutboxCompanion.insert(
            entity: 'asset',
            recordKey: 'asset-private-key',
            operation: 'upsert',
            changedAt: Value(DateTime.now().toUtc()),
            state: const Value('failedVisible'),
            attempts: const Value(-1),
            lastErrorCode: const Value('retry_exhausted'),
          ),
        );

    await tester.pumpWidget(_testApp(store));
    await tester.pumpAndSettle();

    expect(find.text('Needs attention'), findsOneWidget);
    expect(find.text('Changes needing attention'), findsOneWidget);
    expect(find.text('Updated item could not sync'), findsOneWidget);
    expect(find.text('asset-private-key'), findsNothing);

    await tester.tap(find.widgetWithText(FilledButton, 'Retry'));
    await tester.pumpAndSettle();

    final row =
        await (database.select(database.syncOutbox)..where(
              (row) =>
                  row.entity.equals('asset') &
                  row.recordKey.equals('asset-private-key'),
            ))
            .getSingle();
    expect(row.state, 'pending');
    expect(row.attempts, 0);
    expect(find.text('All in Sync'), findsOneWidget);
    expect(find.text('No sync issues need attention'), findsOneWidget);
  });

  testWidgets('conflict resolution is explicit and account scoped', (
    tester,
  ) async {
    await store.setEnabled(enabled: true, boundUserId: 'user-1');
    await (database.update(database.syncOutbox)..where(
          (row) =>
              row.entity.equals('user_setting') & row.recordKey.equals('theme'),
        ))
        .write(
          SyncOutboxCompanion(
            operation: const Value('upsert'),
            changedAt: Value(DateTime.now().toUtc()),
            state: const Value('conflict'),
          ),
        );
    await database
        .into(database.syncConflicts)
        .insert(
          SyncConflictsCompanion.insert(
            id: 'conflict-1',
            accountId: 'user-1',
            entity: 'user_setting',
            recordKey: 'theme',
          ),
        );

    await tester.pumpWidget(_testApp(store));
    await tester.pumpAndSettle();

    expect(find.text('Sync conflicts'), findsOneWidget);
    expect(find.text('Conflicting preference'), findsOneWidget);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Keep cloud'));
    await tester.pumpAndSettle();
    expect(find.text('Keep the cloud version?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Keep cloud'));
    await tester.pumpAndSettle();

    final resolvedOutbox =
        await (database.select(database.syncOutbox)..where(
              (row) =>
                  row.entity.equals('user_setting') &
                  row.recordKey.equals('theme'),
            ))
            .getSingleOrNull();
    expect(resolvedOutbox, isNull);
    final conflict = await database.select(database.syncConflicts).getSingle();
    expect(conflict.resolutionStatus, 'resolved_keep_remote');
    expect(find.text('No sync issues need attention'), findsOneWidget);
  });
}

Widget _testApp(LocalSyncStore store) {
  return ProviderScope(
    overrides: [
      localSyncStoreProvider.overrideWithValue(store),
      syncStatusProvider.overrideWith(
        (ref) => Stream.value(
          const SyncStatus(
            phase: SyncPhase.ready,
            enabled: true,
            pendingChanges: 1,
          ),
        ),
      ),
    ],
    child: MaterialApp(
      theme: testLightTheme(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const SyncHealthScreen(),
    ),
  );
}
