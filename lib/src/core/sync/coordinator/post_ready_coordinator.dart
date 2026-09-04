part of '../sync_coordinator.dart';

extension _SyncPostReadyCoordinator on SyncCoordinator {
  Future<void> _runPostReadyWork() async {
    if (_accountDeletionInProgress) return;
    final session = _authRepository.currentSession;
    if (session == null) return;
    final account = await _localStore.existingAccount();
    if (account == null ||
        !account.enabled ||
        account.boundUserId != session.userId) {
      return;
    }
    final scope = _ActiveAccountScope(
      epoch: _accountEpoch,
      userId: session.userId,
      deviceId: account.deviceId,
    );
    final stopwatch = Stopwatch()..start();
    AppLogger.info('sync_post_ready_start');
    try {
      await _ensureRealtime().timeout(SyncCoordinator._localCleanupTimeout);
    } on Object catch (error) {
      AppLogger.warning(
        'sync_post_ready_realtime_deferred',
        error: error,
        fields: {'elapsed_ms': stopwatch.elapsedMilliseconds},
      );
    }
    try {
      await _materializePostReadyPhotos(session, scope: scope);
    } on Object catch (error) {
      AppLogger.warning(
        'sync_post_ready_media_deferred',
        error: error,
        fields: {'elapsed_ms': stopwatch.elapsedMilliseconds},
      );
    }
    AppLogger.info(
      'sync_post_ready_completed',
      fields: {'elapsed_ms': stopwatch.elapsedMilliseconds},
    );
  }

  Future<void> _materializePostReadyPhotos(
    AuthSession session, {
    required _ActiveAccountScope scope,
  }) async {
    final account = await _localStore.existingAccount();
    if (account == null) return;
    if (account.boundUserId != session.userId) return;
    final queued = _deferredRemoteMedia.values.toList(growable: false);
    if (queued.isNotEmpty) {
      const parallelism = 4;
      for (var index = 0; index < queued.length; index += parallelism) {
        if (_authRepository.currentSession?.userId != session.userId) return;
        final end = math.min(index + parallelism, queued.length);
        final batch = queued.sublist(index, end);
        final results = await Future.wait([
          for (final record in batch)
            _materializePostReadyRecord(record, session.userId),
        ]);
        final completed = results.whereType<SyncRecord>().toList();
        if (completed.isNotEmpty) {
          await _ensureActiveAccountScope(scope);
          await _localStore.applyRemoteRecords(completed);
          for (final record in completed) {
            _deferredRemoteMedia.remove(record.recordKey);
          }
        }
      }
    }

    final pendingKeys = await _localStore.remotePhotoRecordKeys(session.userId);
    const parallelism = 4;
    for (var index = 0; index < pendingKeys.length; index += parallelism) {
      if (_authRepository.currentSession?.userId != session.userId) return;
      final end = math.min(index + parallelism, pendingKeys.length);
      final records = await Future.wait([
        for (final recordKey in pendingKeys.sublist(index, end))
          _fetchPostReadyPhoto(
            recordKey: recordKey,
            userId: session.userId,
            deviceId: account.deviceId,
          ),
      ]);
      final completed = records.whereType<SyncRecord>().toList();
      if (completed.isNotEmpty) {
        await _ensureActiveAccountScope(scope);
        await _localStore.applyRemoteRecords(completed);
      }
    }
  }

  Future<SyncRecord?> _materializePostReadyRecord(
    SyncRecord record,
    String userId,
  ) async {
    final stopwatch = Stopwatch()..start();
    try {
      final materialized = await _remoteGateway.materializeRemoteMedia(
        record,
        userId,
      );
      AppLogger.info(
        'sync_post_ready_photo_completed',
        fields: {'elapsed_ms': stopwatch.elapsedMilliseconds},
      );
      return materialized;
    } on Object catch (error) {
      AppLogger.warning(
        'sync_post_ready_photo_failed',
        error: error,
        fields: {'elapsed_ms': stopwatch.elapsedMilliseconds},
      );
      return null;
    }
  }

  Future<SyncRecord?> _fetchPostReadyPhoto({
    required String recordKey,
    required String userId,
    required String deviceId,
  }) async {
    try {
      final fetched = await _remoteGateway.fetch(
        spec: syncSpecByEntity['asset_photo']!,
        userId: userId,
        deviceId: deviceId,
        recordKey: recordKey,
      );
      if (fetched == null) return null;
      return await _materializePostReadyRecord(fetched, userId);
    } on Object catch (error) {
      AppLogger.warning('sync_post_ready_photo_refetch_failed', error: error);
      return null;
    }
  }
}
