part of '../sync_coordinator.dart';

extension _SyncRunCoordinator on SyncCoordinator {
  Future<void> _startSync({required SyncMode mode}) async {
    await _startSyncWithOutcome(mode: mode);
  }

  Future<SyncRunOutcome> _startSyncWithOutcome({required SyncMode mode}) {
    if (_accountDeletionInProgress) {
      AppLogger.info('sync_skipped_account_deletion_in_progress');
      return Future<SyncRunOutcome>.value(SyncRunOutcome.notEligible);
    }
    if (_activeSync != null) {
      final activeWork = _activeWork;
      final activeCoversRequestedPull =
          activeWork != null &&
          activeWork.pullTables == null &&
          mode != SyncMode.fullReconcile;

      // A broad active pull already covers overlapping startup, resume, retry,
      // and manual-refresh requests. Targeted or push-only work does not cover
      // a requested broad pull and therefore requires one follow-up sync.
      if (!activeCoversRequestedPull) {
        _schedule.markFollowUpRequired(full: mode == SyncMode.fullReconcile);
      }

      AppLogger.info(
        activeCoversRequestedPull
            ? 'sync_reused_active_${mode.name}'
            : 'sync_follow_up_requested_${mode.name}',
        fields: {'attempt': _syncAttemptSerial},
      );
      return _activeSync!;
    }
    final queued = _schedule.consumeQueuedWork();
    final work = _workFor(
      mode,
      queued.targetTables,
      queued.pushOnly,
      queued.broadPull,
    );
    _activeWork = work;
    final attempt = ++_syncAttemptSerial;
    AppLogger.info(
      'sync_start_${work.mode.name}',
      fields: {
        'attempt': attempt,
        'pull_table_count':
            work.pullTables?.length ?? (syncEntitySpecs.length + 1),
      },
    );
    return _activeSync = _runSync(work, attempt: attempt).whenComplete(() {
      _activeSync = null;
      _activeWork = null;
      if (_accountDeletionInProgress) {
        _schedule.cancelQueuedWork();
        return;
      }
      if (_schedule.takeFollowUpRequested()) {
        final nextFullSync = _schedule.takeFollowUpFullSync();
        if (nextFullSync) {
          unawaited(_startSync(mode: SyncMode.fullReconcile));
        } else {
          _scheduleAutomaticSync();
        }
      }
      unawaited(_scheduleRetry());
    });
  }

  SyncWork _workFor(
    SyncMode requestedMode,
    Set<String> targetTables,
    bool pushOnlyRequested,
    bool broadPullRequested,
  ) {
    return switch (requestedMode) {
      SyncMode.fullReconcile => const SyncWork(
        mode: SyncMode.fullReconcile,
        pullTables: null,
        enqueueReconciliation: true,
      ),
      SyncMode.manualRefresh => const SyncWork(
        mode: SyncMode.manualRefresh,
        pullTables: null,
      ),
      SyncMode.initialHydration => const SyncWork(
        mode: SyncMode.initialHydration,
        pullTables: null,
      ),
      SyncMode.targetedPull || SyncMode.conflictRecovery => SyncWork(
        mode: requestedMode,
        pullTables: Set.unmodifiable(targetTables),
      ),
      SyncMode.pushOnly => const SyncWork(
        mode: SyncMode.pushOnly,
        pullTables: {},
      ),
      SyncMode.incrementalPull =>
        broadPullRequested
            ? const SyncWork(mode: SyncMode.incrementalPull, pullTables: null)
            : targetTables.isNotEmpty
            ? SyncWork(
                mode: SyncMode.targetedPull,
                pullTables: Set.unmodifiable(targetTables),
              )
            : pushOnlyRequested
            ? const SyncWork(mode: SyncMode.pushOnly, pullTables: {})
            : const SyncWork(mode: SyncMode.incrementalPull, pullTables: null),
    };
  }

  Future<SyncRunOutcome> _runSync(
    SyncWork requestedWork, {
    required int attempt,
  }) async {
    _ActiveAccountScope? activeScope;
    if (_accountDeletionInProgress) return SyncRunOutcome.notEligible;
    final session = _authRepository.currentSession;
    final account = await _localStore.existingAccount();
    if (account == null) return SyncRunOutcome.notEligible;
    if (!account.enabled) return SyncRunOutcome.notEligible;
    if (session == null) {
      _phaseOverride = SyncPhase.signedOut;
      _messageOverride = 'Sign in again to resume cloud sync.';
      await _emit();
      return SyncRunOutcome.notEligible;
    }
    activeScope = _ActiveAccountScope(
      epoch: _accountEpoch,
      userId: session.userId,
      deviceId: account.deviceId,
    );
    if (account.boundUserId != session.userId) {
      _phaseOverride = SyncPhase.blocked;
      _messageOverride = 'Cloud account does not match this device data.';
      await _localStore.recordSyncBlocked(_messageOverride!);
      await _emit();
      return SyncRunOutcome.notEligible;
    }
    await _ensureActiveAccountScope(activeScope);
    final leaseOwner =
        '$leaseScope:${account.deviceId}:'
        '${DateTime.now().microsecondsSinceEpoch}';
    if (!await _localStore.acquireLease(leaseOwner)) {
      _phaseOverride = SyncPhase.waitingForSyncLease;
      _messageOverride =
          'Another sync operation is already running. '
          'Owntend is waiting for hydration readiness.';
      await _emit();
      _scheduleAutomaticSync(delay: initialHydrationLeaseRetryDelay);
      return SyncRunOutcome.waitingForSyncLease;
    }

    await _ensureActiveAccountScope(activeScope);
    _phaseOverride = SyncPhase.syncing;
    _messageOverride = null;
    final firstSync = account.lastSyncedAt == null;
    final work = firstSync ? requestedWork.asInitialHydration() : requestedWork;
    InitialHydrationProgress? hydration;
    if (firstSync) {
      hydration = await _localStore.beginOrResumeHydration();
      _phaseOverride = SyncPhase.initializing;
    }
    final resumeFinalizationOnly =
        firstSync &&
        hydration?.stage == InitialHydrationStage.finalizing &&
        hydration!.completedUnits > 0;
    await _localStore.recordSyncAttempt(DateTime.now());
    await _emit();
    try {
      if (!resumeFinalizationOnly) {
        await _setInitialHydrationStage(
          firstSync,
          InitialHydrationStage.restoringCloudData,
        );
        final pullOutcome = work.allowsPull
            ? await _pullAll(
                session.userId,
                account.deviceId,
                scope: activeScope,
                firstSync: firstSync,
                buildHydrationPlan: firstSync,
              )
            : const _PullOutcome();
        if (firstSync) {
          _lastCloudAccountWasExisting =
              pullOutcome.meaningfulRemoteRecordCount > 0;
          AppLogger.info(
            'sync_cloud_account_classified',
            fields: {
              'attempt': attempt,
              'existing': _lastCloudAccountWasExisting!,
              'remote_records': pullOutcome.remoteRecordCount,
              'meaningful_remote_records':
                  pullOutcome.meaningfulRemoteRecordCount,
            },
          );
        }
        if (pullOutcome.maintenanceChanged) {
          await _localStore.recalculateStreak();
        }
        final broadPull = work.allowsPull && work.pullTables == null;
        final integrityDue =
            !firstSync &&
            broadPull &&
            (work.mode == SyncMode.fullReconcile ||
                await _localStore.shouldRunIntegrityCheck());
        if (integrityDue) {
          await _reconcileMissedRemoteDeletes(
            session.userId,
            account.deviceId,
            scope: activeScope,
          );
        }
        await _ensureActiveAccountScope(activeScope);
        if (work.enqueueReconciliation) {
          await _localStore.enqueueReconciliationSnapshot();
        }
        await _setInitialHydrationStage(
          firstSync,
          InitialHydrationStage.syncingLocalChanges,
        );
        final mutationCountsBefore = await _localStore.mutationStateCounts();
        final pushedSomething = await _pushPending(
          session.userId,
          account.deviceId,
          scope: activeScope,
          trackHydration: firstSync,
        );
        await _processMediaCleanup(
          session.userId,
          scope: activeScope,
          trackHydration: firstSync,
        );
        await _drainSkippedFeedEntries(scope: activeScope);
        await _setInitialHydrationStage(
          firstSync,
          InitialHydrationStage.checkingLatestUpdates,
        );
        if (pushedSomething) {
          final mutationCountsAfter = await _localStore.mutationStateCounts();
          final beforeTotal = mutationCountsBefore.values.fold<int>(
            0,
            (total, count) => total + count,
          );
          final afterTotal = mutationCountsAfter.values.fold<int>(
            0,
            (total, count) => total + count,
          );
          final failedVisibleCount =
              mutationCountsAfter[SyncMutationState.failedVisible] ?? 0;
          AppLogger.info(
            'sync_push_completed',
            fields: {
              'pending_before':
                  mutationCountsBefore[SyncMutationState.pending] ?? 0,
              'acknowledged': math.max(0, beforeTotal - afterTotal),
              'pending_after':
                  mutationCountsAfter[SyncMutationState.pending] ?? 0,
              'conflict_recovery':
                  mutationCountsAfter[SyncMutationState.conflictRecovery] ?? 0,
              'failed_visible': failedVisibleCount,
            },
          );
          if (failedVisibleCount > 0) {
            final failures = await _localStore.listFailedVisibleMutations();
            AppLogger.info(
              'sync_failed_visible_detail',
              fields: {
                'count': failedVisibleCount,
                'details': [
                  for (final failure in failures) failure.diagnosticDetails,
                ],
              },
            );
          }
        }
      }
      await _ensureActiveAccountScope(activeScope);
      await _setInitialHydrationStage(
        firstSync,
        InitialHydrationStage.finalizing,
      );
      if (firstSync) {
        await _ensureActiveAccountScope(activeScope);
        await _finalizationStep<void>(
          attempt: attempt,
          operation: 'advance_progress',
          run: () => _localStore.addHydrationUnits(1),
        );
        await _finalizationStep<void>(
          attempt: attempt,
          operation: 'validate_local_home',
          run: _localStore.validateCriticalHomeData,
        );
      }
      final completedAt = DateTime.now();
      if (firstSync) {
        await _ensureActiveAccountScope(activeScope);
        await _finalizationStep<void>(
          attempt: attempt,
          operation: 'commit_local_home_snapshot',
          run: () => _localStore.completeInitialHydration(
            completedAt,
            expectedRunId: hydration!.runId,
          ),
        );
      } else {
        await _ensureActiveAccountScope(activeScope);
        await _localStore.recordSyncSuccess(completedAt);
      }
      if (attempt != _syncAttemptSerial) return SyncRunOutcome.notEligible;
      await _ensureActiveAccountScope(activeScope);
      _phaseOverride = SyncPhase.ready;
      _messageOverride = null;
      return SyncRunOutcome.completed;
    } on _AccountScopeInactive {
      AppLogger.info(
        'sync_account_scope_discarded',
        fields: {'attempt': attempt},
      );
      return SyncRunOutcome.notEligible;
    } on Object catch (error, stackTrace) {
      if (!_isActiveAccountScope(activeScope)) {
        AppLogger.info(
          'sync_account_scope_failure_discarded',
          fields: {'attempt': attempt},
        );
        return SyncRunOutcome.notEligible;
      }
      final failure = SupabaseFailure.from(error);
      if (failure.kind == SupabaseFailureKind.authentication) {
        try {
          await _authRepository.signOut();
        } on Object {
          // The invalid cloud session must not prevent local-first recovery.
        }
      }
      _phaseOverride = switch (failure.kind) {
        SupabaseFailureKind.offline => SyncPhase.offline,
        SupabaseFailureKind.authentication => SyncPhase.signedOut,
        SupabaseFailureKind.permissionDenied ||
        SupabaseFailureKind.incompatibleSchema => SyncPhase.blocked,
        _ => SyncPhase.error,
      };
      _messageOverride = failure.message;
      if (_phaseOverride == SyncPhase.blocked) {
        await _localStore.recordSyncBlocked(failure.message);
      } else {
        await _localStore.recordSyncFailure(failure.message);
        if (failure.retryable) {
          await _localStore.deferPendingAfterFailure();
        }
      }
      if (firstSync) {
        try {
          await _localStore
              .failHydration(failure.message)
              .timeout(SyncCoordinator._localCleanupTimeout);
        } on Object catch (cleanupError) {
          AppLogger.warning(
            'sync_finalization_failure_record_failed',
            error: cleanupError,
            fields: {'attempt': attempt},
          );
        }
      }
      Error.throwWithStackTrace(failure, stackTrace);
    } finally {
      try {
        await _localStore
            .releaseLease(leaseOwner)
            .timeout(SyncCoordinator._localCleanupTimeout);
      } on Object catch (cleanupError) {
        AppLogger.warning(
          'sync_lease_release_failed',
          error: cleanupError,
          fields: {'attempt': attempt},
        );
      }
      try {
        await _emit().timeout(SyncCoordinator._localCleanupTimeout);
      } on Object catch (cleanupError) {
        AppLogger.warning(
          'sync_status_publish_failed',
          error: cleanupError,
          fields: {'attempt': attempt},
        );
      }
    }
  }

  Future<_PullOutcome> _pullAll(
    String userId,
    String deviceId, {
    required _ActiveAccountScope scope,
    required bool firstSync,
    required bool buildHydrationPlan,
  }) async {
    if (!firstSync) {
      return _pullChangeFeed(userId, deviceId, scope: scope);
    }
    final watermark = await _remoteGateway.fetchUserChangeFeedHighWater();
    final outcome = await _pullAuthoritativeSnapshot(
      userId,
      deviceId,
      scope: scope,
      firstSync: firstSync,
      buildHydrationPlan: buildHydrationPlan,
    );
    await _ensureActiveAccountScope(scope);
    await _reconcileMissedRemoteDeletes(userId, deviceId, scope: scope);
    await _ensureActiveAccountScope(scope);
    await _localStore.setFeedCursor(
      watermark.highWaterSeq,
      feedGeneration: watermark.feedGeneration,
      highWaterSeq: watermark.highWaterSeq,
    );
    return outcome;
  }

  Future<_PullOutcome> _pullChangeFeed(
    String userId,
    String deviceId, {
    required _ActiveAccountScope scope,
  }) async {
    var remoteRecordCount = 0;
    var meaningfulRemoteRecordCount = 0;
    var maintenanceChanged = false;
    final pendingResnapshotMarker = await _localStore.feedResnapshotMarker();
    if (pendingResnapshotMarker != null) {
      return _resumeFeedResnapshot(
        userId,
        deviceId,
        scope: scope,
        highWaterSeq: pendingResnapshotMarker.highWaterSeq,
        feedGeneration: pendingResnapshotMarker.feedGeneration,
      );
    }
    final cursorRow = await _localStore.getFeedCursorRow();
    var currentSeq = cursorRow?.lastSyncSeq ?? 0;
    var currentGeneration = cursorRow?.feedGeneration ?? 1;

    while (true) {
      final page = await _remoteGateway.fetchUserChangeFeed(
        sinceSeq: currentSeq,
        limit: 100,
        expectedGeneration: currentGeneration,
      );

      if (page.resnapshotRequired) {
        AppLogger.warning(
          'sync_feed_resnapshot_required',
          fields: {
            'since_seq': currentSeq,
            'high_water_seq': page.highWaterSeq,
            'feed_generation': page.feedGeneration,
          },
        );
        await _localStore.resetFeedCursorForResnapshot(
          highWaterSeq: page.highWaterSeq,
          feedGeneration: page.feedGeneration,
        );
        return _resumeFeedResnapshot(
          userId,
          deviceId,
          scope: scope,
          highWaterSeq: page.highWaterSeq,
        );
      }

      if (page.entries.isEmpty) {
        await _localStore.applyRemoteFeedPageAndCheckpoint(
          records: const [],
          lastSyncSeq: page.nextSeq,
          feedGeneration: page.feedGeneration,
          highWaterSeq: page.highWaterSeq,
        );
        break;
      }

      remoteRecordCount += page.entries.length;
      final pageRecords = <SyncRecord>[];
      for (final entry in page.entries) {
        final record = entry.record;
        final materialized =
            record.spec.entity == 'asset_photo' && !record.isDeleted
            ? await _materializeFeedPhotoWithDeferral(record, userId)
            : record;
        pageRecords.add(materialized);
        if (record.spec.entity != 'profile') {
          meaningfulRemoteRecordCount++;
        }
        if (_isMaintenanceSyncEntity(record)) {
          maintenanceChanged = true;
        }
      }

      await _ensureActiveAccountScope(scope);
      await _localStore.applyRemoteFeedPageAndCheckpoint(
        records: pageRecords,
        lastSyncSeq: page.nextSeq,
        feedGeneration: page.feedGeneration,
        highWaterSeq: page.highWaterSeq,
      );
      currentSeq = page.nextSeq;
      currentGeneration = page.feedGeneration;

      if (!page.hasMore) break;
    }

    return _PullOutcome(
      remoteRecordCount: remoteRecordCount,
      meaningfulRemoteRecordCount: meaningfulRemoteRecordCount,
      maintenanceChanged: maintenanceChanged,
    );
  }

  Future<_PullOutcome> _resumeFeedResnapshot(
    String userId,
    String deviceId, {
    required _ActiveAccountScope scope,
    required int highWaterSeq,
    int? feedGeneration,
  }) async {
    final outcome = await _pullAuthoritativeSnapshot(
      userId,
      deviceId,
      scope: scope,
      firstSync: false,
      buildHydrationPlan: false,
    );
    await _ensureActiveAccountScope(scope);
    await _reconcileMissedRemoteDeletes(userId, deviceId, scope: scope);
    await _ensureActiveAccountScope(scope);
    await _localStore.completeFeedResnapshot(
      highWaterSeq,
      feedGeneration: feedGeneration,
    );
    return outcome;
  }

  Future<_PullOutcome> _pullAuthoritativeSnapshot(
    String userId,
    String deviceId, {
    required _ActiveAccountScope scope,
    required bool firstSync,
    required bool buildHydrationPlan,
  }) async {
    final remoteWinners = <SyncRecord>[];
    var maintenanceChanged = false;
    final allSpecs = [...syncEntitySpecs, profileSyncSpec];
    final specs = allSpecs;
    if (specs.isEmpty) return const _PullOutcome();
    final seeds = <_PullSeed>[];
    const queryParallelism = 4;
    for (var index = 0; index < specs.length; index += queryParallelism) {
      final end = math.min(index + queryParallelism, specs.length);
      seeds.addAll(
        await Future.wait([
          for (final spec in specs.sublist(index, end))
            () async {
              final stopwatch = Stopwatch()..start();
              var exactCount = 0;
              final records = await _remoteGateway
                  .pullAuthoritativeSnapshotPage(
                    spec: spec,
                    userId: userId,
                    deviceId: deviceId,
                    onExactCount: (count) => exactCount = count,
                    materializeMedia: false,
                  );
              AppLogger.info(
                'sync_pull_${spec.entity}_page',
                fields: {
                  'rows': records.length,
                  'exact_rows': exactCount,
                  'elapsed_ms': stopwatch.elapsedMilliseconds,
                },
              );
              return _PullSeed(
                spec: spec,
                recordKey: null,
                exactCount: exactCount,
                firstPage: records,
              );
            }(),
        ]),
      );
    }

    await _ensureActiveAccountScope(scope);
    if (firstSync && buildHydrationPlan) {
      final remoteRecords = seeds.fold<int>(
        0,
        (total, seed) => total + seed.exactCount,
      );
      final queryUnits = seeds.fold<int>(
        0,
        (total, seed) =>
            total + 1 + (seed.exactCount ~/ SupabaseSyncGateway.pageSize),
      );
      final photoUnits = seeds
          .where((seed) => seed.spec.entity == 'asset_photo')
          .fold<int>(0, (total, seed) => total + seed.exactCount);
      final pending = await _localStore.pendingCount();
      final cleanup = await _localStore.pendingMediaCleanupCount();
      await _localStore.setHydrationPlan(
        2 +
            queryUnits +
            remoteRecords +
            photoUnits +
            pending +
            cleanup +
            specs.length +
            pending,
      );
      await _localStore.addHydrationUnits(1);
    }

    for (final seed in seeds) {
      final spec = seed.spec;
      var recordKey = seed.recordKey;
      var records = seed.firstPage;
      while (true) {
        await _ensureActiveAccountScope(scope);
        if (firstSync) await _localStore.addHydrationUnits(1);
        if (records.isEmpty) break;
        for (final record in records) {
          final localChangedAt = await _localStore.pendingChangedAt(
            record.spec.entity,
            record.recordKey,
          );
          if (localChangedAt == null) {
            remoteWinners.add(record);
            maintenanceChanged =
                maintenanceChanged || _isMaintenanceSyncEntity(record);
          } else if ((firstSync &&
                  await _localStore.shadow(
                        record.spec.entity,
                        record.recordKey,
                      ) ==
                      null &&
                  await _localStore.isUntouchedSeed(record)) ||
              record.clientModifiedAt.isAfter(localChangedAt.toUtc()) ||
              (record.clientModifiedAt.isAtSameMomentAs(
                    localChangedAt.toUtc(),
                  ) &&
                  _remoteOriginWinsTie(record.originDeviceId, deviceId))) {
            remoteWinners.add(record);
            maintenanceChanged =
                maintenanceChanged || _isMaintenanceSyncEntity(record);
            // A remote winner never deletes the queued local intent. The
            // outbox row enters the durable `conflict` state (generation-
            // checked) and survives restart until acknowledged or explicitly
            // resolved by the user.
            await _localStore.markEntityMutationConflicted(
              entity: record.spec.entity,
              recordKey: record.recordKey,
              accountId: userId,
              deviceId: deviceId,
              reason: 'pulled_remote_winner',
              remotePayloadJson: jsonEncode(record.values),
              remoteRevision: record.revision,
            );
          }
          recordKey = record.recordKey;
        }
        if (records.length < SupabaseSyncGateway.pageSize) break;
        final stopwatch = Stopwatch()..start();
        records = await _remoteGateway.pullAuthoritativeSnapshotPage(
          spec: spec,
          userId: userId,
          deviceId: deviceId,
          afterRecordKey: recordKey,
          materializeMedia: false,
        );
        AppLogger.info(
          'sync_pull_${spec.entity}_page',
          fields: {
            'rows': records.length,
            'elapsed_ms': stopwatch.elapsedMilliseconds,
          },
        );
        await _ensureActiveAccountScope(scope);
      }
    }

    final photoIndexes = <int>[];
    for (var index = 0; index < remoteWinners.length; index++) {
      if (remoteWinners[index].spec.entity == 'asset_photo' &&
          !remoteWinners[index].isDeleted) {
        photoIndexes.add(index);
      }
    }
    await _setInitialHydrationStage(
      firstSync,
      InitialHydrationStage.restoringPhotos,
    );
    if (firstSync) {
      for (final winnerIndex in photoIndexes) {
        final record = remoteWinners[winnerIndex];
        _deferredRemoteMedia[record.recordKey] = record;
      }
      await _localStore.addHydrationUnits(photoIndexes.length);
    } else if (photoIndexes.isNotEmpty) {
      const mediaParallelism = 4;
      for (
        var index = 0;
        index < photoIndexes.length;
        index += mediaParallelism
      ) {
        final end = math.min(index + mediaParallelism, photoIndexes.length);
        final materialized = await Future.wait([
          for (final winnerIndex in photoIndexes.sublist(index, end))
            _remoteGateway.materializeRemoteMedia(
              remoteWinners[winnerIndex],
              userId,
            ),
        ]);
        await _ensureActiveAccountScope(scope);
        for (var offset = 0; offset < materialized.length; offset++) {
          remoteWinners[photoIndexes[index + offset]] = materialized[offset];
        }
        if (firstSync) {
          await _localStore.addHydrationUnits(materialized.length);
        }
      }
    }

    await _ensureActiveAccountScope(scope);
    await _localStore.applyRemoteRecords(remoteWinners);
    if (firstSync) await _localStore.addHydrationUnits(remoteWinners.length);
    return _PullOutcome(
      maintenanceChanged: maintenanceChanged,
      remoteRecordCount: seeds.fold<int>(
        0,
        (total, seed) => total + seed.exactCount,
      ),
      meaningfulRemoteRecordCount: seeds.fold<int>(
        0,
        (total, seed) =>
            total +
            (_isBootstrapClassificationRecord(seed) ? seed.exactCount : 0),
      ),
    );
  }

  Future<T> _finalizationStep<T>({
    required int attempt,
    required String operation,
    required Future<T> Function() run,
  }) async {
    final stopwatch = Stopwatch()..start();
    AppLogger.info(
      'sync_finalization_${operation}_start',
      fields: {
        'attempt': attempt,
        'timeout_ms': localFinalizationTimeout.inMilliseconds,
      },
    );
    try {
      final result = await run().timeout(localFinalizationTimeout);
      AppLogger.info(
        'sync_finalization_${operation}_completed',
        fields: {
          'attempt': attempt,
          'elapsed_ms': stopwatch.elapsedMilliseconds,
        },
      );
      return result;
    } on TimeoutException catch (error) {
      AppLogger.warning(
        'sync_finalization_${operation}_timeout',
        error: error,
        fields: {
          'attempt': attempt,
          'elapsed_ms': stopwatch.elapsedMilliseconds,
          'timeout_ms': localFinalizationTimeout.inMilliseconds,
        },
      );
      throw SupabaseFailure(
        kind: SupabaseFailureKind.unknown,
        message:
            'The local Home snapshot timed out during '
            '${operation.replaceAll('_', ' ')}. Restored cloud data was '
            'preserved; retry will resume finalization.',
        retryable: true,
      );
    } on Object catch (error) {
      AppLogger.warning(
        'sync_finalization_${operation}_failed',
        error: error,
        fields: {
          'attempt': attempt,
          'elapsed_ms': stopwatch.elapsedMilliseconds,
        },
      );
      throw SupabaseFailure(
        kind: SupabaseFailureKind.unknown,
        message:
            'The local Home snapshot failed during '
            '${operation.replaceAll('_', ' ')}. Restored cloud data was '
            'preserved; retry will resume finalization.',
        retryable: true,
      );
    }
  }

  Future<void> _setInitialHydrationStage(
    bool firstSync,
    InitialHydrationStage stage,
  ) async {
    if (!firstSync) return;
    await _localStore.setHydrationStage(stage);
    await _emit();
  }
}
