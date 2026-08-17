from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    file_path = Path(path)
    text = file_path.read_text(encoding="utf-8")
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{path}: expected exactly one match, found {count}")
    file_path.write_text(text.replace(old, new, 1), encoding="utf-8")


store = "lib/src/core/sync/local_sync_store.dart"
coordinator = "lib/src/core/sync/sync_coordinator.dart"
store_test = "test/sync_store_test.dart"
cursor_test = "test/client_pull_cursors_and_healing_test.dart"
sync_doc = "docs/architecture/sync-protocol.md"
changelog = "CHANGELOG.md"

# BUG-001: generic remote/canonical application is not allowed to own inbound
# cursors. Only explicit pull-commit APIs may advance them.
replace_once(
    store,
    """  Future<void> applyRemoteRecordsAndCheckpoint({
    required List<SyncRecord> records,
    required String entity,
    required int lastSyncSeq,
    required String? lastRecordKey,
  }) async {
    await db.transaction(() async {
      await applyRemoteRecords(records);
      await setCursor(entity, lastSyncSeq, lastRecordKey: lastRecordKey);
    });
  }
""",
    """  Future<void> applyRemoteRecordsAndCheckpoints({
    required List<SyncRecord> records,
    required Map<String, (int, String?)> checkpoints,
  }) async {
    await db.transaction(() async {
      await applyRemoteRecords(records);
      for (final entry in checkpoints.entries) {
        final checkpoint = entry.value;
        await setCursor(
          entry.key,
          checkpoint.$1,
          lastRecordKey: checkpoint.$2,
        );
      }
    });
  }
""",
)

replace_once(
    store,
    """        for (final record in records) {
          final syncSeq = record.syncSeq;
          if (syncSeq != null) {
            await db
                .into(db.syncCursors)
                .insertOnConflictUpdate(
                  SyncCursorsCompanion.insert(
                    entity: record.spec.entity,
                    lastSyncSeq: Value(syncSeq),
                  ),
                );
          }
        }
""",
    """""",
)

replace_once(
    store,
    """      Future<void> checkpointWithoutApplying(SyncRecord canonical) async {
        await _saveShadow(canonical);
        final syncSeq = canonical.syncSeq;
        if (syncSeq != null) {
          await setCursor(
            canonical.spec.entity,
            syncSeq,
            lastRecordKey: canonical.recordKey,
          );
        }
      }
""",
    """      Future<void> recordCanonicalWithoutApplying(
        SyncRecord canonical,
      ) async {
        await _saveShadow(canonical);
      }
""",
)

replace_once(
    store,
    """        await checkpointWithoutApplying(plan);
        await checkpointWithoutApplying(record);
""",
    """        await recordCanonicalWithoutApplying(plan);
        await recordCanonicalWithoutApplying(record);
""",
)

replace_once(
    store,
    """        // A later offline completion or edit already changed this plan.
        // Keep that local value while remembering the canonical cloud row
        // for conflict detection and incremental-pull checkpointing.
        await checkpointWithoutApplying(plan);
""",
    """        // A later offline completion or edit already changed this plan.
        // Keep that local value while remembering the canonical cloud row for
        // conflict detection. Inbound pull processing exclusively owns cursors.
        await recordCanonicalWithoutApplying(plan);
""",
)

replace_once(
    store,
    """      if (canonical != null) {
        await _saveShadow(canonical);
        final syncSeq = canonical.syncSeq;
        if (syncSeq != null) {
          await setCursor(
            canonical.spec.entity,
            syncSeq,
            lastRecordKey: canonical.recordKey,
          );
        }
      }
""",
    """      if (canonical != null) {
        await _saveShadow(canonical);
      }
""",
)

# BUG-006: resolve a complete change-feed page first, then apply its local
# mutations and checkpoint in one Drift transaction.
replace_once(
    store,
    """  Future<void> applyRemoteFeedDelete(SyncRecord record) async {
    final hasPending = await hasPendingLocalMutation(
      record.spec.entity,
      record.recordKey,
    );
    await db.transaction(() async {
      await withOutboxSuppressed(() async {
        await (db.delete(db.syncShadows)..where(
              (row) =>
                  row.entity.equals(record.spec.entity) &
                  row.recordKey.equals(record.recordKey),
            ))
            .go();
        if (!hasPending) {
          await _deleteLocal(record);
        }
      });
    });
  }
""",
    """  Future<void> applyRemoteFeedDelete(SyncRecord record) async {
    final hasPending = await hasPendingLocalMutation(
      record.spec.entity,
      record.recordKey,
    );
    await db.transaction(() async {
      await withOutboxSuppressed(() async {
        await (db.delete(db.syncShadows)..where(
              (row) =>
                  row.entity.equals(record.spec.entity) &
                  row.recordKey.equals(record.recordKey),
            ))
            .go();
        if (!hasPending) {
          await _deleteLocal(record);
        }
      });
    });
  }

  Future<void> applyRemoteFeedPageAndCheckpoint({
    required List<SyncRecord> records,
    required int lastSyncSeq,
  }) async {
    await db.transaction(() async {
      for (final record in records) {
        if (record.isDeleted) {
          await applyRemoteFeedDelete(record);
        } else {
          await applyRemoteFeedRecord(record);
        }
      }
      await setFeedCursor(lastSyncSeq);
    });
  }
""",
)

# Change-feed coordinator: collect resolved records first; one store call owns
# local application + feed checkpoint.
replace_once(
    coordinator,
    """      if (page.changes.isEmpty) {
        await _localStore.setFeedCursor(page.nextSeq);
        break;
      }

      remoteRecordCount += page.changes.length;
      final allSpecs = [...syncEntitySpecs, profileSyncSpec];
""",
    """      if (page.changes.isEmpty) {
        await _localStore.applyRemoteFeedPageAndCheckpoint(
          records: const [],
          lastSyncSeq: page.nextSeq,
        );
        break;
      }

      remoteRecordCount += page.changes.length;
      final allSpecs = [...syncEntitySpecs, profileSyncSpec];
      final pageRecords = <SyncRecord>[];
""",
)

replace_once(
    coordinator,
    """          await _localStore.applyRemoteFeedDelete(dummyRecord);
          meaningfulRemoteRecordCount++;
""",
    """          pageRecords.add(dummyRecord);
          meaningfulRemoteRecordCount++;
""",
)

replace_once(
    coordinator,
    """          if (canonical != null) {
            await _localStore.applyRemoteFeedRecord(canonical);
            meaningfulRemoteRecordCount++;
""",
    """          if (canonical != null) {
            pageRecords.add(canonical);
            meaningfulRemoteRecordCount++;
""",
)

replace_once(
    coordinator,
    """      await _localStore.setFeedCursor(page.nextSeq);
      currentSeq = page.nextSeq;
""",
    """      await _localStore.applyRemoteFeedPageAndCheckpoint(
        records: pageRecords,
        lastSyncSeq: page.nextSeq,
      );
      currentSeq = page.nextSeq;
""",
)

# Legacy coordinator: all winners (including tombstones) and every matching
# per-entity checkpoint commit together, preserving delete-before-parent and
# upsert-before-child ordering inside applyRemoteRecords.
replace_once(
    coordinator,
    """    final deletions = remoteWinners
        .where((record) => record.isDeleted)
        .toList(growable: false);
    await _ensureActiveAccountScope(scope);
    await _localStore.applyRemoteRecords(deletions);
    if (firstSync) await _localStore.addHydrationUnits(deletions.length);
    for (final seed in seeds) {
      final checkpoint = cursorUpdates[seed.spec.entity]!;
      final upserts = remoteWinners
          .where(
            (record) =>
                record.spec.entity == seed.spec.entity && !record.isDeleted,
          )
          .toList(growable: false);
      await _ensureActiveAccountScope(scope);
      await _localStore.applyRemoteRecordsAndCheckpoint(
        records: upserts,
        entity: seed.spec.entity,
        lastSyncSeq: checkpoint.$1,
        lastRecordKey: checkpoint.$2,
      );
      if (firstSync) await _localStore.addHydrationUnits(upserts.length);
    }
""",
    """    await _ensureActiveAccountScope(scope);
    await _localStore.applyRemoteRecordsAndCheckpoints(
      records: remoteWinners,
      checkpoints: cursorUpdates,
    );
    if (firstSync) await _localStore.addHydrationUnits(remoteWinners.length);
""",
)

# Existing store test must reflect the new checkpoint-ownership contract.
replace_once(
    store_test,
    """  test('remote application suppresses outbox feedback', () async {
""",
    """  test(
    'remote application suppresses outbox feedback without owning pull cursor',
    () async {
""",
)
replace_once(
    store_test,
    """    expect(await store.pendingCount(), before);
    expect(await store.cursor('area'), 20);
  });
""",
    """    expect(await store.pendingCount(), before);
    expect(await store.cursor('area'), 0);
  });
""",
)

# Strengthen the focused cursor/atomicity suite. The old feed-only ACK check did
# not detect the legacy entity-cursor corruption.
replace_once(
    cursor_test,
    """    test('push ACK does not move feed cursor', () async {
      await store.setFeedCursor(100);
""",
    """    test('push ACK does not move any inbound pull cursor', () async {
      await store.setFeedCursor(100);
      await store.setCursor('area', 100, lastRecordKey: 'area-existing');
""",
)
replace_once(
    cursor_test,
    """      // Feed cursor remains unchanged at 100
      expect(await store.getFeedCursor(), 100);
    });

    test(
      'applyRemoteFeedRecord preserves local pending mutation intent',
""",
    """      expect(await store.getFeedCursor(), 100);
      expect(await store.cursorCheckpoint('area'), (100, 'area-existing'));
    });

    test(
      'maintenance completion ACK records canonical shadows without cursors',
      () async {
        await store.setCursor(
          'maintenance_plan',
          10,
          lastRecordKey: 'plan-before',
        );
        await store.setCursor(
          'maintenance_record',
          11,
          lastRecordKey: 'record-before',
        );
        final now = DateTime.utc(2026, 8, 17, 8);
        final mutation = LocalSyncMutation(
          entity: 'maintenance_completion',
          recordKey: 'completion-ack-1',
          operation: 'execute',
          payloadJson: '{}',
          generation: 1,
          createdAt: now,
          changedAt: now,
          attempts: 1,
        );
        final plan = SyncRecord(
          spec: syncEntitySpecs.firstWhere(
            (spec) => spec.entity == 'maintenance_plan',
          ),
          recordKey: 'plan-ack-1',
          clientModifiedAt: now,
          originDeviceId: 'remote-device',
          revision: 5,
          syncSeq: 500,
          values: const {'id': 'plan-ack-1'},
        );
        final record = SyncRecord(
          spec: syncEntitySpecs.firstWhere(
            (spec) => spec.entity == 'maintenance_record',
          ),
          recordKey: 'completion-ack-1',
          clientModifiedAt: now,
          originDeviceId: 'remote-device',
          revision: 6,
          syncSeq: 501,
          values: const {'id': 'completion-ack-1'},
        );

        await store.markMaintenanceCompletionSucceeded(
          mutation,
          plan: plan,
          record: record,
        );

        expect(
          await store.cursorCheckpoint('maintenance_plan'),
          (10, 'plan-before'),
        );
        expect(
          await store.cursorCheckpoint('maintenance_record'),
          (11, 'record-before'),
        );
        expect(await store.shadow('maintenance_plan', 'plan-ack-1'), isNotNull);
        expect(
          await store.shadow('maintenance_record', 'completion-ack-1'),
          isNotNull,
        );
      },
    );

    test('legacy pull mutations roll back when checkpoint commit fails', () async {
      final now = DateTime.utc(2026, 8, 17, 9);
      await db
          .into(db.areas)
          .insert(
            AreasCompanion.insert(
              id: 'atomic-existing-area',
              name: 'Existing area',
              kind: 'indoor',
              createdAt: Value(now),
              updatedAt: Value(now),
            ),
          );
      await db.delete(db.syncOutbox).go();
      final spec = syncEntitySpecs.firstWhere((s) => s.entity == 'area');
      final deletion = SyncRecord(
        spec: spec,
        recordKey: 'atomic-existing-area',
        clientModifiedAt: now,
        originDeviceId: 'remote-device',
        revision: 2,
        syncSeq: 40,
        serverUpdatedAt: now,
        deletedAt: now,
        values: const {'id': 'atomic-existing-area'},
      );
      final upsert = SyncRecord(
        spec: spec,
        recordKey: 'atomic-new-area',
        clientModifiedAt: now,
        originDeviceId: 'remote-device',
        revision: 3,
        syncSeq: 41,
        serverUpdatedAt: now,
        values: {
          'id': 'atomic-new-area',
          'name': 'Atomic new area',
          'kind': 'indoor',
          'sort_order': 0,
          'created_at': now.toIso8601String(),
          'updated_at': now.toIso8601String(),
          'archived_at': null,
        },
      );
      await db.customStatement('''
CREATE TRIGGER fail_area_checkpoint
BEFORE INSERT ON sync_cursors
WHEN NEW.entity = 'area'
BEGIN
  SELECT RAISE(ABORT, 'forced checkpoint failure');
END;
''');

      await expectLater(
        store.applyRemoteRecordsAndCheckpoints(
          records: [deletion, upsert],
          checkpoints: const {'area': (41, 'atomic-new-area')},
        ),
        throwsA(anything),
      );

      expect(await store.cursor('area'), 0);
      expect(
        await (db.select(db.areas)
              ..where((row) => row.id.equals('atomic-existing-area')))
            .getSingleOrNull(),
        isNotNull,
      );
      expect(
        await (db.select(db.areas)
              ..where((row) => row.id.equals('atomic-new-area')))
            .getSingleOrNull(),
        isNull,
      );
      expect(await store.shadow('area', 'atomic-existing-area'), isNull);
      expect(await store.shadow('area', 'atomic-new-area'), isNull);
    });

    test('feed page mutations roll back when feed checkpoint fails', () async {
      final now = DateTime.utc(2026, 8, 17, 10);
      final spec = syncEntitySpecs.firstWhere((s) => s.entity == 'area');
      final record = SyncRecord(
        spec: spec,
        recordKey: 'atomic-feed-area',
        clientModifiedAt: now,
        originDeviceId: 'remote-device',
        revision: 4,
        values: {
          'id': 'atomic-feed-area',
          'name': 'Atomic feed area',
          'kind': 'indoor',
          'sort_order': 0,
          'created_at': now.toIso8601String(),
          'updated_at': now.toIso8601String(),
          'archived_at': null,
        },
      );
      await db.customStatement('''
CREATE TRIGGER fail_feed_checkpoint
BEFORE INSERT ON sync_cursors
WHEN NEW.entity = 'server_change_feed'
BEGIN
  SELECT RAISE(ABORT, 'forced feed checkpoint failure');
END;
''');

      await expectLater(
        store.applyRemoteFeedPageAndCheckpoint(
          records: [record],
          lastSyncSeq: 77,
        ),
        throwsA(anything),
      );

      expect(await store.getFeedCursor(), 0);
      expect(
        await (db.select(db.areas)
              ..where((row) => row.id.equals('atomic-feed-area')))
            .getSingleOrNull(),
        isNull,
      );
      expect(await store.shadow('area', 'atomic-feed-area'), isNull);
    });

    test(
      'applyRemoteFeedRecord preserves local pending mutation intent',
""",
)

# Documentation: state the exact invariant this remediation enforces.
replace_once(
    sync_doc,
    """6. Records shadows and advances the cursor only after successful application.
7. Continues until the current window is drained.

Cursor advancement must not precede durable local application.
""",
    """6. Records shadows and advances the cursor only after successful application.
7. Continues until the current window is drained.

The local mutations, shadows, and matching checkpoint for a completed pull page
must commit in the same Drift transaction. Any failure rolls back both data
application and checkpoint advancement so retry replays the page safely.
""",
)
replace_once(
    sync_doc,
    """- **Push & Point-Fetch Isolation**: Push acknowledgements (`markMutationSucceeded`), maintenance RPC completions, conflict point-fetches, and Realtime hints update canonical entity shadows but **never** advance the change feed cursor.
""",
    """- **Push & Point-Fetch Isolation**: Push acknowledgements (`markMutationSucceeded`), maintenance RPC completions, conflict point-fetches, and Realtime hints may update canonical entity shadows but **never** advance either the change-feed cursor or legacy per-entity pull cursors. Only completed pull transactions own inbound checkpoints.
""",
)

replace_once(
    changelog,
    """### Fixed

""",
    """### Fixed

- Made inbound sync checkpoints pull-owned and transactionally atomic with the rows and shadows they acknowledge, preventing push acknowledgements or interrupted pull pages from skipping remote changes.
""",
)

# Static patch sanity checks before any formatter/analyzer/test run.
store_text = Path(store).read_text(encoding="utf-8")
coordinator_text = Path(coordinator).read_text(encoding="utf-8")
if "checkpointWithoutApplying" in store_text:
    raise RuntimeError("obsolete maintenance checkpoint helper remains")
if "applyRemoteRecordsAndCheckpoint(" in coordinator_text:
    raise RuntimeError("obsolete singular pull checkpoint call remains")
if "applyRemoteRecordsAndCheckpoints(" not in coordinator_text:
    raise RuntimeError("legacy pull is not using atomic checkpoint API")
if "applyRemoteFeedPageAndCheckpoint(" not in coordinator_text:
    raise RuntimeError("change-feed pull is not using atomic page API")

print("BUG-001/BUG-006 patch applied successfully")
