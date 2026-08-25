part of '../local_sync_store.dart';

mixin _LocalSyncRemoteStore on _LocalSyncStoreBase {
  // WP-010 (D4): the legacy per-entity cursor API (cursor/cursorCheckpoint/
  // setCursor/applyRemoteRecordsAndCheckpoints) was production-dead after the
  // contract-1 change-feed became the only pull path; it was deleted rather
  // than carried. Tests arrange or read cursor rows directly through Drift.

  Future<SyncCursor?> getFeedCursorRow() async {
    return (db.select(db.syncCursors)
          ..where((item) => item.entity.equals('server_change_feed')))
        .getSingleOrNull();
  }

  Future<int> getFeedCursor() async {
    final row = await getFeedCursorRow();
    return row?.lastSyncSeq ?? 0;
  }

  Future<int> getFeedGeneration() async {
    final row = await getFeedCursorRow();
    return row?.feedGeneration ?? 1;
  }

  Future<void> setFeedCursor(
    int lastSyncSeq, {
    int? feedGeneration,
    int? highWaterSeq,
  }) async {
    final current = await getFeedCursorRow();
    final currentSeq = current?.lastSyncSeq ?? 0;
    final currentGen = current?.feedGeneration ?? 1;
    final targetGen = feedGeneration ?? currentGen;
    if (targetGen == currentGen && lastSyncSeq < currentSeq) return;
    await db
        .into(db.syncCursors)
        .insertOnConflictUpdate(
          SyncCursorsCompanion.insert(
            entity: 'server_change_feed',
            lastSyncSeq: Value(lastSyncSeq),
            feedGeneration: Value(targetGen),
            highWaterSeq: Value(highWaterSeq ?? current?.highWaterSeq ?? 0),
          ),
        );
  }

  Future<bool> hasPendingLocalMutation(String entity, String recordKey) async {
    final row =
        await (db.select(db.syncOutbox)..where(
              (r) => r.entity.equals(entity) & r.recordKey.equals(recordKey),
            ))
            .getSingleOrNull();
    return row != null;
  }

  /// WP-004 (F-006): classifies the outbox intent that masks a remote feed
  /// record, or returns null when no intent exists. Active intents
  /// (pending/inFlight/conflictRecovery) may still win; conflict/terminal
  /// intents are user-owned but their local rows must eventually converge.
  Future<String?> _maskingOutboxIntentState(String entity, String key) async {
    final row =
        await (db.select(db.syncOutbox)
              ..where((r) => r.entity.equals(entity) & r.recordKey.equals(key)))
            .getSingleOrNull();
    return row?.state;
  }

  bool _isActiveIntentState(String? state) =>
      state == 'pending' || state == 'inFlight' || state == 'conflictRecovery';

  Future<void> _recordSkippedFeedEntry(
    String entity,
    String recordKey, {
    required bool active,
  }) async {
    await db
        .into(db.syncSkippedFeedEntries)
        .insertOnConflictUpdate(
          SyncSkippedFeedEntriesCompanion.insert(
            entity: entity,
            recordKey: recordKey,
            reason: active ? 'active_intent' : 'conflict_or_terminal',
          ),
        );
  }

  @override
  Future<void> clearSkippedFeedEntry(String entity, String recordKey) {
    return (db.delete(db.syncSkippedFeedEntries)..where(
          (row) => row.entity.equals(entity) & row.recordKey.equals(recordKey),
        ))
        .go();
  }

  /// Skipped-feed promises whose masking intent is gone. Each returned entry
  /// needs one targeted remote fetch to converge; entries whose intent still
  /// exists stay bookkept.
  @override
  Future<List<SyncSkippedFeedEntryRow>> skippedFeedEntriesForDrain() async {
    final rows = await db.select(db.syncSkippedFeedEntries).get();
    if (rows.isEmpty) return const [];
    final masked = await db.select(db.syncOutbox).get();
    final maskKeys = {
      for (final row in masked) '${row.entity}\u0000${row.recordKey}',
    };
    return [
      for (final row in rows)
        if (!maskKeys.contains('${row.entity}\u0000${row.recordKey}')) row,
    ];
  }

  Future<void> applyRemoteFeedRecord(SyncRecord record) async {
    final maskingState = await _maskingOutboxIntentState(
      record.spec.entity,
      record.recordKey,
    );
    await db.transaction(() async {
      await withOutboxSuppressed(() async {
        if (maskingState == null) {
          await _saveShadow(record);
          await _upsertLocal(record);
          // Any earlier skip promise for this key is fulfilled by applying.
          await (db.delete(db.syncSkippedFeedEntries)..where(
                (row) =>
                    row.entity.equals(record.spec.entity) &
                    row.recordKey.equals(record.recordKey),
              ))
              .go();
        } else if (_isActiveIntentState(maskingState)) {
          // The pending intent may still win; promise a refetch once it
          // resolves so the cursor can advance without losing this change.
          await _recordSkippedFeedEntry(
            record.spec.entity,
            record.recordKey,
            active: true,
          );
        } else {
          // Conflict/terminal intents never overwrite the local row here, but
          // the shadow stays truth-adjacent for revision checks and the
          // durable promise guarantees post-dismissal convergence (F-006).
          await _saveShadow(record);
          await _recordSkippedFeedEntry(
            record.spec.entity,
            record.recordKey,
            active: false,
          );
        }
      });
    });
  }

  Future<void> applyRemoteFeedDelete(SyncRecord record) async {
    final maskingState = await _maskingOutboxIntentState(
      record.spec.entity,
      record.recordKey,
    );
    await db.transaction(() async {
      await withOutboxSuppressed(() async {
        if (maskingState == null) {
          await (db.delete(db.syncShadows)..where(
                (row) =>
                    row.entity.equals(record.spec.entity) &
                    row.recordKey.equals(record.recordKey),
              ))
              .go();
          await _deleteLocal(record);
          await (db.delete(db.syncSkippedFeedEntries)..where(
                (row) =>
                    row.entity.equals(record.spec.entity) &
                    row.recordKey.equals(record.recordKey),
              ))
              .go();
        } else {
          // Deletions behind any intent are only promised, never guessed:
          // applying a shadow for a delete would erase the evidence needed by
          // conflict resolution. Drain refetches after the intent clears.
          await _recordSkippedFeedEntry(
            record.spec.entity,
            record.recordKey,
            active: _isActiveIntentState(maskingState),
          );
        }
      });
    });
  }

  Future<void> applyRemoteFeedPageAndCheckpoint({
    required List<SyncRecord> records,
    required int lastSyncSeq,
    int? feedGeneration,
    int? highWaterSeq,
  }) async {
    await db.transaction(() async {
      for (final record in records) {
        if (record.isDeleted) {
          await applyRemoteFeedDelete(record);
        } else {
          await applyRemoteFeedRecord(record);
        }
      }
      await setFeedCursor(
        lastSyncSeq,
        feedGeneration: feedGeneration,
        highWaterSeq: highWaterSeq,
      );
    });
  }

  @override
  Future<void> applyRemoteRecords(List<SyncRecord> records) async {
    if (records.isEmpty) return;
    final invalidatesWeather = records.any(
      (record) =>
          record.spec.entity == 'user_setting' &&
          record.recordKey == 'home_location',
    );
    final inboxChanged = records.any(
      (record) => record.spec.entity == 'notification_inbox',
    );
    final specOrder = {
      for (var index = 0; index < syncEntitySpecs.length; index++)
        syncEntitySpecs[index].entity: index,
      'profile': syncEntitySpecs.length,
    };
    final deletes = records.where((record) => record.isDeleted).toList()
      ..sort(
        (a, b) => (specOrder[b.spec.entity] ?? 0).compareTo(
          specOrder[a.spec.entity] ?? 0,
        ),
      );
    final upserts = records.where((record) => !record.isDeleted).toList()
      ..sort(
        (a, b) => (specOrder[a.spec.entity] ?? 0).compareTo(
          specOrder[b.spec.entity] ?? 0,
        ),
      );

    await db.transaction(() async {
      await withOutboxSuppressed(() async {
        for (final record in deletes) {
          await _deleteLocal(record);
          await _saveShadow(record);
        }
        for (final record in upserts) {
          await _upsertLocal(record);
          await _saveShadow(record);
        }
      });
    });
    if (invalidatesWeather) {
      await db.customUpdate(
        "DELETE FROM settings WHERE key = 'weather_cache'",
        updates: {db.settings},
        updateKind: UpdateKind.delete,
      );
    }
    if (inboxChanged) {
      await enforceInboxRetention();
    }
  }

  Future<void> enforceInboxRetention() {
    return db
        .customUpdate(
          '''
DELETE FROM notification_inbox
WHERE id NOT IN (
  SELECT id
  FROM notification_inbox
  ORDER BY created_at DESC
  LIMIT 250
)
''',
          updates: {db.inboxNotifications},
          updateKind: UpdateKind.delete,
        )
        .then((_) {});
  }

  Future<void> recalculateStreak() {
    return DatabaseStreakService(db).refresh(DateTime.now()).then((_) {});
  }

  @override
  Future<void> _deleteLocal(SyncRecord record) async {
    if (record.spec.entity == 'profile') {
      await db.customUpdate(
        "DELETE FROM settings WHERE key = 'profile'",
        updates: {db.settings},
        updateKind: UpdateKind.delete,
      );
      return;
    }
    final where = <String>[];
    final variables = <dynamic>[];
    for (final column in record.spec.keyColumns) {
      where.add('$column = ?');
      variables.add(record.values[column].toString());
    }
    String? localMediaPath;
    if (record.spec.entity == 'asset_photo') {
      final existing = await db
          .customSelect(
            'SELECT relative_path FROM ${record.spec.localTable} '
            'WHERE ${where.join(' AND ')} LIMIT 1',
            variables: [
              for (final variable in variables)
                Variable<Object>(variable as Object),
            ],
          )
          .getSingleOrNull();
      localMediaPath = existing?.read<String>('relative_path');
    }
    await db.customUpdate(
      'DELETE FROM ${record.spec.localTable} WHERE ${where.join(' AND ')}',
      variables: [
        for (final variable in variables) Variable<Object>(variable as Object),
      ],
      updates: {_localTable(record.spec.localTable)},
      updateKind: UpdateKind.delete,
    );
    if (localMediaPath != null && localMediaPath.isNotEmpty) {
      await _enqueueLocalMediaCleanup(localMediaPath);
    }
  }

  @override
  Future<void> _upsertLocal(SyncRecord record) async {
    if (record.spec.entity == 'profile') {
      final current = await db
          .customSelect(
            "SELECT value FROM settings WHERE key = 'profile' LIMIT 1",
          )
          .getSingleOrNull();
      String? localAvatar;
      if (current != null) {
        final json =
            jsonDecode(current.read<String>('value')) as Map<String, dynamic>;
        if (json['avatarPath'] is String) {
          localAvatar = json['avatarPath'] as String;
        }
      }
      final value = jsonEncode({
        'nickname': record.values['nickname'] as String?,
        // ignore: use_null_aware_elements
        if (localAvatar != null) 'avatarPath': localAvatar,
      });
      await db.customInsert(
        '''
INSERT INTO settings(key, value, updated_at)
VALUES ('profile', ?, CAST(strftime('%s', 'now') AS INTEGER))
ON CONFLICT(key) DO UPDATE SET
  value = excluded.value,
  updated_at = excluded.updated_at
''',
        variables: [Variable<String>(value)],
        updates: {db.settings},
      );
      return;
    }
    final columns = record.spec.localColumns
        .where(record.values.containsKey)
        .toList();
    final valuesByColumn = <String, dynamic>{};
    for (final column in columns) {
      valuesByColumn[column] = _toLocalValue(
        record.spec,
        column,
        record.values[column],
      );
    }
    final keyWhere = record.spec.keyColumns
        .map((column) => '$column = ?')
        .join(' AND ');
    final keyValues = [
      for (final column in record.spec.keyColumns) valuesByColumn[column],
    ];
    final existing = await db
        .customSelect(
          'SELECT * FROM ${record.spec.localTable} '
          'WHERE $keyWhere LIMIT 1',
          variables: [for (final value in keyValues) Variable<Object>(value)],
        )
        .getSingleOrNull();
    final updateColumns = columns
        .where((column) => !record.spec.keyColumns.contains(column))
        .toList();
    if (existing != null) {
      if (updateColumns.isEmpty) return;
      await db.customUpdate(
        'UPDATE ${record.spec.localTable} SET '
        '${updateColumns.map((column) => '$column = ?').join(', ')} '
        'WHERE $keyWhere',
        variables: [
          for (final column in updateColumns) valuesByColumn[column],
          ...keyValues,
        ].map((value) => Variable<Object>(value)).toList(),
        updates: {_localTable(record.spec.localTable)},
        updateKind: UpdateKind.update,
      );
      if (record.spec.entity == 'asset_photo') {
        final previousPath = existing.read<String>('relative_path');
        final nextPath = valuesByColumn['relative_path'] as String?;
        if (nextPath != null &&
            previousPath.isNotEmpty &&
            previousPath != nextPath) {
          await _enqueueLocalMediaCleanup(previousPath);
        }
      }
      return;
    }
    await db.customInsert(
      'INSERT INTO ${record.spec.localTable} (${columns.join(', ')}) '
      'VALUES (${List.filled(columns.length, '?').join(', ')})',
      variables: [
        for (final column in columns) Variable<Object>(valuesByColumn[column]),
      ],
      updates: {_localTable(record.spec.localTable)},
    );
  }

  ResultSetImplementation<dynamic, dynamic> _localTable(String tableName) {
    return db.allTables.firstWhere(
      (table) => table.actualTableName == tableName,
    );
  }

  Future<void> markAssetPhotoPrimarySucceeded(
    LocalSyncMutation mutation, {
    required List<SyncRecord> photos,
  }) async {
    if (mutation.entity != 'asset_photo_primary' ||
        photos.any((record) => record.spec.entity != 'asset_photo')) {
      throw StateError('Invalid primary-photo acknowledgement.');
    }
    await db.transaction(() async {
      await withOutboxSuppressed(() async {
        for (final canonical in photos) {
          final local =
              await (db.select(db.assetPhotos)
                    ..where((row) => row.id.equals(canonical.recordKey)))
                  .getSingleOrNull();
          if (local == null) {
            // A photo created by another device will be materialized by the
            // normal pull path. Remembering its remote row here is unnecessary.
            continue;
          }
          final localized = SyncRecord(
            spec: canonical.spec,
            recordKey: canonical.recordKey,
            values: {...canonical.values, 'relative_path': local.relativePath},
            clientModifiedAt: canonical.clientModifiedAt,
            originDeviceId: canonical.originDeviceId,
            revision: canonical.revision,
            serverUpdatedAt: canonical.serverUpdatedAt,
            deletedAt: canonical.deletedAt,
          );
          await _upsertLocal(localized);
          await _saveShadow(localized);
        }
      });
      await (db.delete(db.syncOutbox)..where(
            (row) =>
                row.entity.equals('asset_photo_primary') &
                row.recordKey.equals(mutation.recordKey),
          ))
          .go();
    });
  }

  Future<void> markMaintenanceUndoSucceeded(
    LocalSyncMutation mutation, {
    required SyncRecord plan,
    required String completionId,
  }) async {
    if (mutation.entity != 'maintenance_undo' ||
        plan.spec.entity != 'maintenance_plan' ||
        mutation.recordKey != completionId) {
      throw StateError('Invalid maintenance undo acknowledgement.');
    }
    await db.transaction(() async {
      await (db.delete(db.syncOutbox)..where(
            (row) =>
                (row.entity.equals('maintenance_undo') &
                    row.recordKey.equals(completionId)) |
                (row.entity.equals('maintenance_plan') &
                    row.recordKey.equals(plan.recordKey)) |
                (row.entity.equals('maintenance_record') &
                    row.recordKey.equals(completionId)),
          ))
          .go();
      await withOutboxSuppressed(() async {
        await _upsertLocal(plan);
        await _saveShadow(plan);
        await (db.delete(
          db.maintenanceRecords,
        )..where((row) => row.id.equals(completionId))).go();
        await (db.delete(db.syncShadows)..where(
              (row) =>
                  row.entity.equals('maintenance_record') &
                  row.recordKey.equals(completionId),
            ))
            .go();
      });
    });
  }

  Future<void> markMaintenanceCompletionSucceeded(
    LocalSyncMutation mutation, {
    required SyncRecord plan,
    required SyncRecord record,
  }) async {
    if (mutation.entity != 'maintenance_completion' ||
        plan.spec.entity != 'maintenance_plan' ||
        record.spec.entity != 'maintenance_record' ||
        record.recordKey != mutation.recordKey) {
      throw StateError('Invalid maintenance completion acknowledgement.');
    }

    await db.transaction(() async {
      Future<void> recordCanonicalWithoutApplying(SyncRecord canonical) async {
        await _saveShadow(canonical);
      }

      final pendingOperation =
          await (db.select(db.syncOutbox)..where(
                (row) =>
                    row.entity.equals(mutation.entity) &
                    row.recordKey.equals(mutation.recordKey),
              ))
              .getSingleOrNull();

      if (pendingOperation == null) {
        // Undo can remove the composite mutation while its RPC is in flight.
        // Retain the locally undone state and only record what reached cloud;
        // the compensating generic mutations remain queued.
        await recordCanonicalWithoutApplying(plan);
        await recordCanonicalWithoutApplying(record);
        return;
      }

      final currentPlan = await (db.select(
        db.maintenancePlans,
      )..where((row) => row.id.equals(plan.recordKey))).getSingleOrNull();

      final otherPendingRows =
          await (db.select(db.syncOutbox)..where(
                (row) =>
                    row.recordKey.equals(mutation.recordKey).not() &
                    (row.entity.equals('maintenance_plan') |
                        row.entity.equals('maintenance_completion')),
              ))
              .get();
      var hasLaterPendingPlanMutation = false;
      for (final row in otherPendingRows) {
        if (row.entity == 'maintenance_plan' &&
            row.recordKey == plan.recordKey) {
          hasLaterPendingPlanMutation = true;
          break;
        }
        if (row.entity == 'maintenance_completion' && row.payloadJson != null) {
          try {
            final decoded =
                jsonDecode(row.payloadJson!) as Map<String, dynamic>;
            final compPlanId =
                decoded['plan_id'] as String? ??
                (decoded['plan'] as Map<String, dynamic>?)?['id'] as String?;
            if (compPlanId == plan.recordKey) {
              hasLaterPendingPlanMutation = true;
              break;
            }
          } on Object {
            // WP-006 (F-015): unreadable payloads are counted, never silent.
            payloadParseFailures++;
          }
        }
      }

      final preserveNewerLocalPlan =
          currentPlan != null &&
          (currentPlan.updatedAt.isAfter(mutation.changedAt) ||
              hasLaterPendingPlanMutation);

      await applyRemoteRecords([if (!preserveNewerLocalPlan) plan, record]);

      if (preserveNewerLocalPlan) {
        // A later offline completion or edit already changed this plan.
        // Keep that local value while remembering the canonical cloud row for
        // conflict detection. Inbound pull processing exclusively owns cursors.
        await recordCanonicalWithoutApplying(plan);
      }

      await (db.delete(db.syncOutbox)..where(
            (row) =>
                row.entity.equals(mutation.entity) &
                row.recordKey.equals(mutation.recordKey),
          ))
          .go();
    });
  }
}
