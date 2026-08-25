part of '../sync_coordinator.dart';

extension _SyncRepairCoordinator on SyncCoordinator {
  /// WP-004 (F-006): converge remote changes that were masked by outbox
  /// intents and whose intents have since resolved. Each durable promise
  /// costs at most one targeted fetch; failures leave the promise in place
  /// for the next sync cycle, so a drain can never lose a masked change.
  Future<void> _drainSkippedFeedEntries({
    required _ActiveAccountScope scope,
  }) async {
    final pending = await _localStore.skippedFeedEntriesForDrain();
    if (pending.isEmpty) return;
    var drained = 0;
    for (final entry in pending) {
      await _ensureActiveAccountScope(scope);
      SyncEntitySpec? spec;
      for (final candidate in syncEntitySpecs) {
        if (candidate.entity == entry.entity) {
          spec = candidate;
          break;
        }
      }
      if (spec == null) {
        // Unknown entity: the promise can never be fulfilled; drop it rather
        // than carrying dead state forever.
        await _localStore.clearSkippedFeedEntry(entry.entity, entry.recordKey);
        continue;
      }
      final SyncRecord? record;
      try {
        record = await _remoteGateway.fetch(
          spec: spec,
          userId: scope.userId,
          deviceId: scope.deviceId,
          recordKey: entry.recordKey,
        );
      } on Object {
        // Leave the promise; the next cycle retries after connectivity or
        // server health recovers.
        return;
      }
      await _ensureActiveAccountScope(scope);
      if (record == null) {
        await _localStore.applyRemoteFeedDelete(
          SyncRecord(
            spec: spec,
            recordKey: entry.recordKey,
            values: {
              for (var index = 0; index < spec.keyColumns.length; index++)
                spec.keyColumns[index]: entry.recordKey.split('|')[index],
            },
            clientModifiedAt: DateTime.now().toUtc(),
            originDeviceId: 'skipped-feed-drain',
            deletedAt: DateTime.now().toUtc(),
          ),
        );
      } else {
        await _localStore.applyRemoteFeedRecord(record);
      }
      drained++;
    }
    if (drained > 0) {
      AppLogger.info('sync_skipped_feed_drained', fields: {'count': drained});
    }
  }

  /// WP-006 (F-015): a photo download failure must not fail the whole
  /// incremental sync. The metadata row still applies — keeping revision
  /// shadows current — and the bytes converge through the same post-ready
  /// deferral worker that first-sync photos already use.
  Future<SyncRecord> _materializeFeedPhotoWithDeferral(
    SyncRecord record,
    String userId,
  ) async {
    try {
      return await _remoteGateway.materializeRemoteMedia(record, userId);
    } on Object catch (error) {
      AppLogger.warning('sync_feed_media_deferred', error: error);
      _deferredRemoteMedia[record.recordKey] = record;
      return record;
    }
  }

  Future<void> _reconcileMissedRemoteDeletes(
    String userId,
    String deviceId, {
    required _ActiveAccountScope scope,
  }) async {
    final remoteKeys = <String, Set<String>>{};
    const parallelism = 4;
    for (var index = 0; index < syncEntitySpecs.length; index += parallelism) {
      final end = math.min(index + parallelism, syncEntitySpecs.length);
      final batch = syncEntitySpecs.sublist(index, end);
      final results = await Future.wait([
        for (final spec in batch)
          _remoteGateway.fetchAuthoritativeRecordKeys(
            spec: spec,
            userId: userId,
            deviceId: deviceId,
          ),
      ]);
      await _ensureActiveAccountScope(scope);
      for (var offset = 0; offset < batch.length; offset++) {
        remoteKeys[batch[offset].entity] = results[offset];
      }
    }

    var removed = 0;
    for (final spec in syncEntitySpecs.reversed) {
      await _ensureActiveAccountScope(scope);
      final stopwatch = Stopwatch()..start();
      final tableRemoved = await _localStore.reconcileAuthoritativeRecordKeys(
        spec: spec,
        remoteKeys: remoteKeys[spec.entity] ?? const {},
      );
      removed += tableRemoved;
      AppLogger.info(
        'sync_integrity_${spec.entity}_completed',
        fields: {
          'remote_keys': remoteKeys[spec.entity]?.length ?? 0,
          'removed': tableRemoved,
          'elapsed_ms': stopwatch.elapsedMilliseconds,
        },
      );
    }
    await _localStore.recordIntegrityCheck(DateTime.now());
    AppLogger.info(
      'sync_integrity_completed',
      fields: {'removed': removed, 'tables': syncEntitySpecs.length},
    );
  }
}
