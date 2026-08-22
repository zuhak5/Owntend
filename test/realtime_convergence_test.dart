import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';

import 'package:owntend/src/core/database/app_database.dart';
import 'package:owntend/src/core/sync/local_sync_store.dart';
import 'package:owntend/src/core/sync/sync_dtos.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  FlutterSecureStorage.setMockInitialValues(<String, String>{});

  late AppDatabase db;
  late LocalSyncStore store;

  setUp(() async {
    db = AppDatabase(executor: NativeDatabase.memory());
    store = LocalSyncStore(db);
    await db.customStatement('PRAGMA foreign_keys = ON;');
    await db.delete(db.syncCursors).go();
    await db.delete(db.syncOutbox).go();
  });

  tearDown(() async {
    await db.close();
  });

  group('Realtime invalidation and convergence', () {
    test('newer pending local edit survives peer delete hint and remote feed delete', () async {
      final now = DateTime.now();
      await db
          .into(db.areas)
          .insert(
            AreasCompanion.insert(
              id: 'area-edit-survives-1',
              name: 'Local Edit Area',
              kind: 'indoor',
              createdAt: Value(now),
              updatedAt: Value(now),
            ),
          );

      final pending = await store.pendingMutations();
      final targetPending = pending.firstWhere(
        (m) => m.recordKey == 'area-edit-survives-1',
      );
      expect(targetPending.generation, 1);

      final spec = syncEntitySpecs.firstWhere((s) => s.entity == 'area');
      final remoteDeleteRecord = SyncRecord(
        spec: spec,
        recordKey: 'area-edit-survives-1',
        clientModifiedAt: now,
        originDeviceId: 'device-peer',
        deletedAt: now,
        values: {'id': 'area-edit-survives-1'},
      );

      // Deliver remote feed delete
      await store.applyRemoteFeedDelete(remoteDeleteRecord);

      // Local SQLite row and outbox intent survive because generation is pending
      final localRow = await (db.select(
        db.areas,
      )..where((r) => r.id.equals('area-edit-survives-1'))).getSingleOrNull();
      expect(localRow, isNotNull);
      expect(localRow!.name, 'Local Edit Area');

      final remainingPending = await store.pendingMutations();
      expect(
        remainingPending.any((m) => m.recordKey == 'area-edit-survives-1'),
        isTrue,
      );
    });

    test(
      'remote feed delete removes local row when no pending edit exists',
      () async {
        final now = DateTime.now();
        await db
            .into(db.areas)
            .insert(
              AreasCompanion.insert(
                id: 'area-synced-1',
                name: 'Synced Area',
                kind: 'indoor',
                createdAt: Value(now),
                updatedAt: Value(now),
              ),
            );

        // Clear outbox so row has no pending local mutation
        await db.delete(db.syncOutbox).go();

        final spec = syncEntitySpecs.firstWhere((s) => s.entity == 'area');
        final remoteDeleteRecord = SyncRecord(
          spec: spec,
          recordKey: 'area-synced-1',
          clientModifiedAt: now,
          originDeviceId: 'device-peer',
          deletedAt: now,
          values: {'id': 'area-synced-1'},
        );

        await store.applyRemoteFeedDelete(remoteDeleteRecord);

        // Local SQLite row is hard deleted
        final localRow = await (db.select(
          db.areas,
        )..where((r) => r.id.equals('area-synced-1'))).getSingleOrNull();
        expect(localRow, isNull);
      },
    );
  });
}
