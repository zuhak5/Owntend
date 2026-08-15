import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:drift/drift.dart';
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
    await db.delete(db.syncOutbox).go();
  });

  tearDown(() async {
    await db.close();
  });

  group('Task 19 - Immutable Outbox Generations & Conditional CAS Tests', () {
    test(
      'trigger increments outbox generation on coalesced same-key edits',
      () async {
        final now = DateTime.now();
        await db
            .into(db.areas)
            .insert(
              AreasCompanion.insert(
                id: 'area-gen-1',
                name: 'Original Area',
                kind: 'indoor',
                createdAt: Value(now),
                updatedAt: Value(now),
              ),
            );

        final pending1 = await store.pendingMutations();
        expect(pending1.length, 1);
        expect(pending1.first.entity, 'area');
        expect(pending1.first.recordKey, 'area-gen-1');
        expect(pending1.first.generation, 1);

        // Perform same-key edit (coalesced)
        await (db.update(db.areas)..where((r) => r.id.equals('area-gen-1')))
            .write(AreasCompanion(name: const Value('Edited Area 1')));

        final pending2 = await store.pendingMutations();
        expect(pending2.length, 1);
        expect(pending2.first.generation, 2);

        // Perform another same-key edit
        await (db.update(db.areas)..where((r) => r.id.equals('area-gen-1')))
            .write(AreasCompanion(name: const Value('Edited Area 2')));

        final pending3 = await store.pendingMutations();
        expect(pending3.length, 1);
        expect(pending3.first.generation, 3);
      },
    );

    test(
      'in-flight claim is conditional on exact claimed generation',
      () async {
        final now = DateTime.now();
        await db
            .into(db.areas)
            .insert(
              AreasCompanion.insert(
                id: 'area-claim-1',
                name: 'Area Claim',
                kind: 'indoor',
                createdAt: Value(now),
                updatedAt: Value(now),
              ),
            );

        final initialMutation = (await store.pendingMutations()).first;
        expect(initialMutation.generation, 1);

        // Claim succeeds for generation 1
        final claimed1 = await store.markMutationInFlight(
          initialMutation,
          userId: 'user-1',
        );
        expect(claimed1, isTrue);

        // Edit occurs after claim -> generation becomes 2
        await (db.update(db.areas)..where((r) => r.id.equals('area-claim-1')))
            .write(AreasCompanion(name: const Value('Area Claim Edited')));

        // Trying to claim the old mutation (gen 1) fails because gen is now 2
        final claimedStale = await store.markMutationInFlight(
          initialMutation,
          userId: 'user-1',
        );
        expect(claimedStale, isFalse);
      },
    );

    test('completion does not erase a newer intent generation', () async {
      final now = DateTime.now();
      await db
          .into(db.areas)
          .insert(
            AreasCompanion.insert(
              id: 'area-complete-1',
              name: 'Area Complete',
              kind: 'indoor',
              createdAt: Value(now),
              updatedAt: Value(now),
            ),
          );

      final gen1Mutation = (await store.pendingMutations()).first;
      expect(gen1Mutation.generation, 1);

      await store.markMutationInFlight(gen1Mutation, userId: 'user-1');

      // Edit occurs while network call is in-flight -> outbox generation becomes 2
      await (db.update(db.areas)..where((r) => r.id.equals('area-complete-1')))
          .write(AreasCompanion(name: const Value('Area Complete Edited')));

      // Network response for gen 1 completes and attempts to mark gen 1 succeeded
      final ackResult = await store.markMutationSucceeded(gen1Mutation, null);
      expect(ackResult, isFalse);

      // The newer intent (gen 2) remains intact in the outbox
      final remaining = await store.pendingMutations();
      expect(remaining.length, 1);
      expect(remaining.first.generation, 2);
    });

    test(
      'failure and terminal states do not overwrite a newer intent generation',
      () async {
        final now = DateTime.now();
        await db
            .into(db.areas)
            .insert(
              AreasCompanion.insert(
                id: 'area-fail-1',
                name: 'Area Fail',
                kind: 'indoor',
                createdAt: Value(now),
                updatedAt: Value(now),
              ),
            );

        final gen1Mutation = (await store.pendingMutations()).first;
        expect(gen1Mutation.generation, 1);

        // Edit occurs -> outbox generation becomes 2
        await (db.update(db.areas)..where((r) => r.id.equals('area-fail-1')))
            .write(AreasCompanion(name: const Value('Area Fail Edited')));

        // Mark failed for gen 1 returns false
        final failResult = await store.markMutationFailed(
          gen1Mutation,
          'Network timeout',
        );
        expect(failResult, isFalse);

        // Mark terminal for gen 1 returns false
        final termResult = await store.markMutationTerminal(
          gen1Mutation,
          'Terminal error',
        );
        expect(termResult, isFalse);

        // Generation 2 remains pending
        final remaining = await store.pendingMutations();
        expect(remaining.length, 1);
        expect(remaining.first.generation, 2);
        expect(remaining.first.state, SyncMutationState.pending);
      },
    );
  });
}
