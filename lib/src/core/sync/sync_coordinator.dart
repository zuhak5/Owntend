import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import '../supabase/supabase_failure.dart';
import '../utils/redacting_logger.dart';
import '../database/app_database.dart';
import '../../features/auth/domain/auth_repository.dart';
import 'local_sync_store.dart';
import 'supabase_sync_gateway.dart';
import 'sync_contracts.dart';
import 'sync_connectivity.dart';
import 'sync_dtos.dart';

class SyncCoordinator implements CloudSyncRepository {
  SyncCoordinator(
    this._authRepository,
    this._localStore,
    this._remoteGateway, {
    SyncConnectivity? connectivity,
    this._realtime,
    this.configureBackgroundSync,
    Future<void> Function()? reconcileMaintenanceCompletionReminders,
    this.leaseScope = 'foreground',
    bool listenToAuthChanges = true,
    this.autoEnableOnAuthChange = true,
    this.localFinalizationTimeout = const Duration(seconds: 8),
  }) : _connectivity = connectivity ?? const AlwaysOnlineSyncConnectivity(),
       _maintenanceCompletionReminderReconciler =
           reconcileMaintenanceCompletionReminders,
       _automaticSyncEnabled = connectivity != null || _realtime != null {
    _accountSubscription = _localStore.watchAccount().listen(
      (account) => _runListener(
        'sync_account_watch_callback_failed',
        () => _handleAccountChanged(account),
      ),
      onError: (Object error, StackTrace stackTrace) {
        _runListener(
          'sync_account_watch_failed',
          () => _handleAccountWatchError(error),
        );
      },
    );
    _pendingSubscription = _localStore.watchPendingCount().listen(
      (pending) => _runListener(
        'sync_pending_watch_callback_failed',
        () => _handlePendingChanged(pending),
      ),
    );
    if (listenToAuthChanges) {
      _authSubscription = _authRepository.watchAuthState().listen(
        _handleAuthStateChanged,
        onError: (Object _, StackTrace _) {
          _phaseOverride = SyncPhase.offline;
          _messageOverride = 'Authentication refresh is waiting for a network.';
          _emit();
        },
      );
    }
    _connectivitySubscription = _connectivity.watchOnline().listen(
      (online) => _runListener(
        'sync_connectivity_callback_failed',
        () => _handleConnectivityChanged(online),
      ),
    );
    _initializationTimer = Timer(const Duration(milliseconds: 500), () {
      _isInitializing = false;
      _scheduleAutomaticSync();
    });
  }

  final AuthRepository _authRepository;
  final LocalSyncStore _localStore;
  final SupabaseSyncGateway _remoteGateway;
  final SyncConnectivity _connectivity;
  final RealtimeSyncSource? _realtime;
  final Future<void> Function(bool enabled)? configureBackgroundSync;
  final Future<void> Function()? _maintenanceCompletionReminderReconciler;
  final String leaseScope;
  final bool _automaticSyncEnabled;
  final bool autoEnableOnAuthChange;
  final Duration localFinalizationTimeout;
  final StreamController<SyncStatus> _statusController =
      StreamController<SyncStatus>.broadcast();
  static const _localCleanupTimeout = Duration(seconds: 4);

  StreamSubscription<Object?>? _accountSubscription;
  StreamSubscription<Object?>? _pendingSubscription;
  StreamSubscription<AuthStateChange>? _authSubscription;
  StreamSubscription<bool>? _connectivitySubscription;
  Future<void>? _activeSync;
  SyncWork? _activeWork;
  Timer? _automaticSyncTimer;
  Timer? _retryTimer;
  Timer? _realtimeReconnectTimer;
  Timer? _realtimeDeleteFollowUpTimer;
  Timer? _initializationTimer;
  bool _isInitializing = true;
  final Set<String> _pendingTargetTables = {};
  bool _pushOnlyRequested = false;
  var _realtimeReconnectAttempts = 0;
  bool _syncRequestedWhileActive = false;
  bool _fullSyncRequestedWhileActive = false;
  bool _online = true;
  bool _mergeConfirmationRequired = false;
  Future<void> _authInitialization = Future<void>.value();
  Future<void> _accountTransition = Future<void>.value();
  Future<void> _realtimeOperation = Future<void>.value();
  String? _realtimeIdentity;
  SyncRealtimeConnection _realtimeConnection = SyncRealtimeConnection.disabled;
  SyncPhase? _phaseOverride;
  String? _messageOverride;
  int _clockSkewConflicts = 0;
  var _accountEpoch = 0;
  var _syncAttemptSerial = 0;
  Future<void>? _postReadyWork;
  final Map<String, SyncRecord> _deferredRemoteMedia = {};
  bool? _lastCloudAccountWasExisting;
  bool _accountDeletionInProgress = false;
  String? _deletingUserId;
  String? _lastAccountScopeKey;

  bool? get lastCloudAccountWasExisting => _lastCloudAccountWasExisting;

  void _runListener(String eventName, Future<void> Function() operation) {
    unawaited(
      operation().catchError((Object error, StackTrace stackTrace) {
        AppLogger.warning(eventName, error: error);
      }),
    );
  }

  Future<void> _serializeAccountTransition(Future<void> Function() operation) {
    final next = _accountTransition
        .catchError((Object _) {})
        .then((_) => operation());
    _accountTransition = next.catchError((Object _) {});
    return next;
  }

  @override
  Stream<SyncStatus> watchStatus() async* {
    yield await status();
    yield* _statusController.stream;
  }

  @override
  Future<SyncStatus> status() async {
    final account = await _localStore.existingAccount();
    final pending = await _localStore.pendingCount();
    final pendingMedia = await _localStore.pendingMediaCleanupCount();
    final nextRetryAt = await _localStore.nextRetryAt();
    final session = _authRepository.currentSession;
    if (account == null) {
      return SyncStatus(
        phase: _phaseOverride ?? SyncPhase.signedOut,
        pendingChanges: pending,
        pendingMediaCleanup: pendingMedia,
        message: _messageOverride,
        realtime: SyncRealtimeConnection.disabled,
        nextRetryAt: nextRetryAt,
        mergeConfirmationRequired: false,
        clockSkewConflicts: _clockSkewConflicts,
      );
    }
    final hydration = await _localStore.hydrationProgress();
    final phase =
        _phaseOverride ??
        (!account.enabled
            ? SyncPhase.ready
            : session == null
            ? SyncPhase.signedOut
            : SyncPhase.ready);
    return SyncStatus(
      phase: phase,
      enabled: account.enabled,
      pendingChanges: pending,
      pendingMediaCleanup: pendingMedia,
      lastSyncedAt: account.lastSyncedAt,
      lastSyncAttemptAt: account.lastSyncAttemptAt,
      lastSyncFailureAt: account.lastSyncFailureAt,
      message: _messageOverride ?? account.lastError,
      boundUserId: account.boundUserId,
      realtime: account.enabled
          ? _realtimeConnection
          : SyncRealtimeConnection.disabled,
      nextRetryAt: nextRetryAt,
      initialHydrationProgress: hydration?.isActive == true ? hydration : null,
      mergeConfirmationRequired: _mergeConfirmationRequired,
      blockedReason: account.blockedReason,
      migrationState: account.migrationState,
      restorePending: account.restorePending,
      backgroundResult: account.backgroundResult,
      clockSkewConflicts: _clockSkewConflicts,
    );
  }

  @override
  Future<void> enable() => _serializeAccountTransition(() async {
    final session = _authRepository.currentSession;
    if (session == null) {
      throw const SupabaseFailure(
        kind: SupabaseFailureKind.authentication,
        message: 'Sign in before enabling cloud sync.',
      );
    }
    final account = await _localStore.account();
    if (account.boundUserId != null && account.boundUserId != session.userId) {
      throw const SupabaseFailure(
        kind: SupabaseFailureKind.permissionDenied,
        message:
            'This device data is linked to a different cloud account. '
            'Sign back into that account or explicitly reset local data.',
      );
    }
    _accountDeletionInProgress = false;
    _deletingUserId = null;
    _mergeConfirmationRequired = false;
    final pristineCloudBootstrap = await _localStore
        .isPristineForCloudBootstrap();
    await _localStore.bindIdentity(session.userId);
    if (!pristineCloudBootstrap) {
      await _localStore.enqueueInitialSnapshot();
    }
    await _startSync(mode: SyncMode.initialHydration);
  });

  @override
  Future<void> disable() => _serializeAccountTransition(() async {
    await _localStore.setEnabled(enabled: false);
    await _stopRealtime();
    _phaseOverride = null;
    _messageOverride = null;
    await _emit();
  });

  @override
  Future<void> unlink() => _serializeAccountTransition(() async {
    await _localStore.clearBinding();
    await _stopRealtime();
    _phaseOverride = null;
    _messageOverride = null;
    await _emit();
  });

  @override
  Future<void> syncNow() => _startSync(mode: SyncMode.manualRefresh);

  @override
  Future<void> retry() => _startSync(mode: SyncMode.incrementalPull);

  @override
  Future<void> fullReconcile() => _startSync(mode: SyncMode.fullReconcile);

  Future<void> syncIncremental() => _startSync(mode: SyncMode.incrementalPull);

  Future<void> prepareForAccountDeletion(String userId) {
    return _serializeAccountTransition(() async {
      final account = await _localStore.existingAccount();
      if (account != null &&
          account.boundUserId != null &&
          account.boundUserId != userId) {
        throw StateError('Local data belongs to a different cloud identity.');
      }
      _accountDeletionInProgress = true;
      _deletingUserId = userId;
      _advanceAccountEpoch('account_deletion_prepare');
      _cancelScheduledSyncWork();
      _deferredRemoteMedia.clear();
      _mergeConfirmationRequired = false;
      _phaseOverride = SyncPhase.signedOut;
      _messageOverride = 'Account deletion is in progress.';
      try {
        await configureBackgroundSync?.call(false);
      } on Object catch (error) {
        AppLogger.warning(
          'sync_account_deletion_background_cancel_failed',
          error: error,
        );
      }
      await _stopRealtime();
      final active = _activeSync;
      if (active != null) {
        try {
          await active.timeout(_localCleanupTimeout);
        } on TimeoutException catch (error) {
          AppLogger.warning(
            'sync_account_deletion_active_sync_detached',
            error: error,
            fields: {'attempt': _syncAttemptSerial},
          );
        } on Object {
          // The active operation already recorded its actionable failure.
        }
      }
      await _emit();
    });
  }

  Future<void> cancelAccountDeletion(String userId) {
    return _serializeAccountTransition(() async {
      if (_deletingUserId != null && _deletingUserId != userId) return;
      _accountDeletionInProgress = false;
      _deletingUserId = null;
      _advanceAccountEpoch('account_deletion_cancelled');
      final account = await _localStore.existingAccount();
      try {
        await configureBackgroundSync?.call(account?.enabled ?? false);
      } on Object catch (error) {
        AppLogger.warning(
          'sync_account_deletion_background_resume_failed',
          error: error,
        );
      }
      _phaseOverride = null;
      _messageOverride = null;
      await _ensureRealtime();
      _scheduleAutomaticSync(delay: Duration.zero);
      await _emit();
    });
  }

  Future<void> _startSync({required SyncMode mode}) {
    if (_accountDeletionInProgress) {
      AppLogger.info('sync_skipped_account_deletion_in_progress');
      return Future<void>.value();
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
        _syncRequestedWhileActive = true;
        _fullSyncRequestedWhileActive =
            _fullSyncRequestedWhileActive || mode == SyncMode.fullReconcile;
      }

      AppLogger.info(
        activeCoversRequestedPull
            ? 'sync_reused_active_${mode.name}'
            : 'sync_follow_up_requested_${mode.name}',
        fields: {'attempt': _syncAttemptSerial},
      );
      return _activeSync!;
    }
    final targetTables = _pendingTargetTables.toSet();
    _pendingTargetTables.clear();
    final pushOnlyRequested = _pushOnlyRequested;
    _pushOnlyRequested = false;
    final work = _workFor(mode, targetTables, pushOnlyRequested);
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
        _syncRequestedWhileActive = false;
        _fullSyncRequestedWhileActive = false;
        _pendingTargetTables.clear();
        _pushOnlyRequested = false;
        return;
      }
      if (_syncRequestedWhileActive) {
        _syncRequestedWhileActive = false;
        final nextFullSync = _fullSyncRequestedWhileActive;
        _fullSyncRequestedWhileActive = false;
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
        targetTables.isNotEmpty
            ? SyncWork(
                mode: SyncMode.targetedPull,
                pullTables: Set.unmodifiable(targetTables),
              )
            : pushOnlyRequested
            ? const SyncWork(mode: SyncMode.pushOnly, pullTables: {})
            : const SyncWork(mode: SyncMode.incrementalPull, pullTables: null),
    };
  }

  Future<void> _runSync(SyncWork requestedWork, {required int attempt}) async {
    _ActiveAccountScope? activeScope;
    if (_accountDeletionInProgress) return;
    final session = _authRepository.currentSession;
    final account = await _localStore.existingAccount();
    if (account == null) return;
    if (!account.enabled) return;
    if (session == null) {
      _phaseOverride = SyncPhase.signedOut;
      _messageOverride = 'Sign in again to resume cloud sync.';
      await _emit();
      return;
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
      return;
    }
    await _ensureActiveAccountScope(activeScope);
    final leaseOwner =
        '$leaseScope:${account.deviceId}:'
        '${DateTime.now().microsecondsSinceEpoch}';
    if (!await _localStore.acquireLease(leaseOwner)) {
      _phaseOverride = SyncPhase.syncing;
      _messageOverride =
          'Another sync operation is already running. '
          'Owntend will retry shortly.';
      await _emit();
      _scheduleAutomaticSync(delay: const Duration(seconds: 2));
      return;
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
                targetTables: work.pullTables,
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
            final details = await _localStore.listFailedVisibleDetails();
            AppLogger.info(
              'sync_failed_visible_detail',
              fields: {'count': failedVisibleCount, 'details': details},
            );
            final abandonedCount = await _localStore
                .abandonStaleFailedVisibleMutations();
            if (abandonedCount > 0) {
              AppLogger.info(
                'sync_outbox_abandoned',
                fields: {'abandoned_count': abandonedCount},
              );
            }
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
      if (attempt != _syncAttemptSerial) return;
      await _ensureActiveAccountScope(activeScope);
      _phaseOverride = SyncPhase.ready;
      _messageOverride = null;
    } on _AccountScopeInactive {
      AppLogger.info(
        'sync_account_scope_discarded',
        fields: {'attempt': attempt},
      );
      return;
    } on Object catch (error) {
      if (!_isActiveAccountScope(activeScope)) {
        AppLogger.info(
          'sync_account_scope_failure_discarded',
          fields: {'attempt': attempt},
        );
        return;
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
          await _localStore.deferPendingAfterFailure(failure.message);
        }
      }
      if (firstSync) {
        try {
          await _localStore
              .failHydration(failure.message)
              .timeout(_localCleanupTimeout);
        } on Object catch (cleanupError) {
          AppLogger.warning(
            'sync_finalization_failure_record_failed',
            error: cleanupError,
            fields: {'attempt': attempt},
          );
        }
      }
      rethrow;
    } finally {
      try {
        await _localStore
            .releaseLease(leaseOwner)
            .timeout(_localCleanupTimeout);
      } on Object catch (cleanupError) {
        AppLogger.warning(
          'sync_lease_release_failed',
          error: cleanupError,
          fields: {'attempt': attempt},
        );
      }
      try {
        await _emit().timeout(_localCleanupTimeout);
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
    Set<String>? targetTables,
  }) async {
    if (!firstSync && targetTables == null) {
      final capability = await _remoteGateway.getSyncFeedCapability();
      if (capability.enabled) {
        return await _pullServerChangeFeed(userId, deviceId, scope: scope);
      }
    }
    return await _pullAllLegacy(
      userId,
      deviceId,
      scope: scope,
      firstSync: firstSync,
      buildHydrationPlan: buildHydrationPlan,
      targetTables: targetTables,
    );
  }

  Future<_PullOutcome> _pullServerChangeFeed(
    String userId,
    String deviceId, {
    required _ActiveAccountScope scope,
  }) async {
    var remoteRecordCount = 0;
    var meaningfulRemoteRecordCount = 0;
    var maintenanceChanged = false;
    var currentSeq = await _localStore.getFeedCursor();

    while (true) {
      final page = await _remoteGateway.fetchUserChangeFeed(
        sinceSeq: currentSeq,
        limit: 100,
      );

      if (page.resnapshotRequired) {
        AppLogger.warning(
          'sync_feed_resnapshot_required',
          fields: {
            'since_seq': currentSeq,
            'high_water_seq': page.highWaterSeq,
          },
        );
        await _localStore.setFeedCursor(0);
        return await _pullAllLegacy(
          userId,
          deviceId,
          scope: scope,
          firstSync: true,
          buildHydrationPlan: false,
        );
      }

      if (page.changes.isEmpty) {
        await _localStore.setFeedCursor(page.nextSeq);
        break;
      }

      remoteRecordCount += page.changes.length;
      final allSpecs = [...syncEntitySpecs, profileSyncSpec];

      for (final change in page.changes) {
        final entity = change['entity_type'] as String?;
        final recordKey = change['record_id'] as String?;
        final opType = change['op_type'] as String?;
        if (entity == null || recordKey == null || opType == null) continue;

        final spec = allSpecs.firstWhere(
          (s) => s.entity == entity,
          orElse: () => profileSyncSpec,
        );

        if (opType == 'DELETE') {
          final now = DateTime.now();
          final dummyRecord = SyncRecord(
            spec: spec,
            recordKey: recordKey,
            clientModifiedAt: now,
            originDeviceId: deviceId,
            deletedAt: now,
            values: {'id': recordKey},
          );
          await _localStore.applyRemoteFeedDelete(dummyRecord);
          meaningfulRemoteRecordCount++;
        } else {
          final canonical = await _remoteGateway.fetchRecordByKey(
            spec: spec,
            recordKey: recordKey,
            userId: userId,
          );
          if (canonical != null) {
            await _localStore.applyRemoteFeedRecord(canonical);
            meaningfulRemoteRecordCount++;
            if (spec.entity == 'maintenance_plan' ||
                spec.entity == 'maintenance_record') {
              maintenanceChanged = true;
            }
          }
        }
      }

      await _localStore.setFeedCursor(page.nextSeq);
      currentSeq = page.nextSeq;

      if (!page.hasMore) break;
    }

    return _PullOutcome(
      remoteRecordCount: remoteRecordCount,
      meaningfulRemoteRecordCount: meaningfulRemoteRecordCount,
      maintenanceChanged: maintenanceChanged,
    );
  }

  Future<int> runHealingScan(String userId) async {
    final parityResults = await _remoteGateway.validateChangeFeedParity();
    var repairedCount = 0;
    final allSpecs = [...syncEntitySpecs, profileSyncSpec];

    for (final row in parityResults) {
      final isParity = row['is_parity'] as bool? ?? true;
      if (!isParity) {
        final entity = row['entity_type'] as String?;
        if (entity != null) {
          final spec = allSpecs.firstWhere(
            (s) => s.entity == entity,
            orElse: () => profileSyncSpec,
          );
          final records = await _remoteGateway.pullChanges(
            spec: spec,
            userId: userId,
            deviceId: '',
            afterSyncSeq: 0,
            materializeMedia: false,
          );
          for (final record in records) {
            await _localStore.applyRemoteFeedRecord(record);
            repairedCount++;
          }
        }
      }
    }
    return repairedCount;
  }

  Future<_PullOutcome> _pullAllLegacy(
    String userId,
    String deviceId, {
    required _ActiveAccountScope scope,
    required bool firstSync,
    required bool buildHydrationPlan,
    Set<String>? targetTables,
  }) async {
    final remoteWinners = <SyncRecord>[];
    final cursorUpdates = <String, (int, String?)>{};
    var maintenanceChanged = false;
    final allSpecs = [...syncEntitySpecs, profileSyncSpec];
    final specs = targetTables == null
        ? allSpecs
        : allSpecs
              .where((spec) => targetTables.contains(spec.remoteTable))
              .toList();
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
              final checkpoint = await _localStore.cursorCheckpoint(
                spec.entity,
              );
              var exactCount = 0;
              final records = await _remoteGateway.pullChanges(
                spec: spec,
                userId: userId,
                deviceId: deviceId,
                afterSyncSeq: checkpoint.$1,
                afterRecordKey: checkpoint.$2,
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
                cursor: checkpoint.$1,
                recordKey: checkpoint.$2,
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
      var cursor = seed.cursor;
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
                  record.originDeviceId.compareTo(deviceId) > 0)) {
            remoteWinners.add(record);
            maintenanceChanged =
                maintenanceChanged || _isMaintenanceSyncEntity(record);
            await _localStore.discardMutation(
              record.spec.entity,
              record.recordKey,
            );
          }
          if (record.syncSeq! > cursor ||
              (record.syncSeq == cursor &&
                  record.recordKey.compareTo(recordKey ?? '') > 0)) {
            cursor = record.syncSeq!;
            recordKey = record.recordKey;
          }
        }
        if (records.length < SupabaseSyncGateway.pageSize) break;
        final stopwatch = Stopwatch()..start();
        records = await _remoteGateway.pullChanges(
          spec: spec,
          userId: userId,
          deviceId: deviceId,
          afterSyncSeq: cursor,
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
      cursorUpdates[spec.entity] = (cursor, recordKey);
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

    final deletions = remoteWinners
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

  Future<bool> _pushPending(
    String userId,
    String deviceId, {
    required _ActiveAccountScope scope,
    bool trackHydration = false,
  }) async {
    bool pushedSomething = false;
    while (true) {
      await _ensureActiveAccountScope(scope);
      final mutations = await _localStore.pendingMutations();
      if (mutations.isEmpty) return pushedSomething;
      pushedSomething = true;
      var index = 0;
      while (index < mutations.length) {
        final mutation = mutations[index];

        if (mutation.entity == 'maintenance_completion') {
          final payloadJson = mutation.payloadJson;
          if (mutation.operation != 'execute' ||
              payloadJson == null ||
              payloadJson.trim().isEmpty) {
            const failure = SupabaseFailure(
              kind: SupabaseFailureKind.incompatibleSchema,
              message:
                  'A queued maintenance completion has an invalid payload. '
                  'Update Owntend before synchronizing again.',
            );
            await _recordMutationFailure(mutation, failure);
            throw failure;
          }

          try {
            await _pushMaintenanceCompletion(
              mutation,
              payloadJson: payloadJson,
              userId: userId,
              deviceId: deviceId,
              scope: scope,
            );
            if (trackHydration) {
              await _localStore.addHydrationUnits(1);
            }
          } on _AccountScopeInactive {
            rethrow;
          } on Object catch (error) {
            final failure = SupabaseFailure.from(error);
            if (!await _localStore.isMutationFailedVisible(mutation)) {
              await _recordMutationFailure(mutation, failure);
            }
            rethrow;
          }

          index++;
          continue;
        }

        if (mutation.operation == 'upsert') {
          final shadow = await _localStore.shadow(
            mutation.entity,
            mutation.recordKey,
          );
          final spec = syncSpecByEntity[mutation.entity];
          if (shadow == null &&
              spec != null &&
              spec.entity != 'asset_photo' &&
              spec.entity != 'profile') {
            final batchMutations = <LocalSyncMutation>[];
            final batchRecords = <SyncRecord>[];
            while (index < mutations.length &&
                batchMutations.length < 100 &&
                mutations[index].operation == 'upsert' &&
                mutations[index].entity == mutation.entity &&
                await _localStore.shadow(
                      mutations[index].entity,
                      mutations[index].recordKey,
                    ) ==
                    null) {
              final candidate = mutations[index];
              final record = await _localStore.readMutation(
                candidate,
                deviceId,
              );
              if (record == null || record.isDeleted) break;
              batchMutations.add(candidate);
              batchRecords.add(record);
              index++;
            }
            if (batchRecords.isNotEmpty) {
              BatchWriteResult batchResult;
              try {
                batchResult = await _remoteGateway.writeNewBatch(
                  records: batchRecords,
                  userId: userId,
                  deviceId: deviceId,
                );
                await _ensureActiveAccountScope(scope);
              } on _AccountScopeInactive {
                rethrow;
              } on Object catch (error) {
                final failure = SupabaseFailure.from(error);
                for (final item in batchMutations) {
                  await _recordMutationFailure(item, failure);
                }
                rethrow;
              }
              if (batchResult is BatchWriteSuccess) {
                final byKey = {
                  for (final record in batchResult.records)
                    record.recordKey: record,
                };
                for (final item in batchMutations) {
                  await _localStore.markMutationSucceeded(
                    item,
                    byKey[item.recordKey],
                  );
                }
                if (trackHydration) {
                  await _localStore.addHydrationUnits(batchMutations.length);
                }
                continue;
              } else if (batchResult is BatchWriteConflict) {
                AppLogger.warning(
                  'sync_batch_write_conflict',
                  fields: {
                    'entity': mutation.entity,
                    'code': batchResult.code,
                    'is_pkey': batchResult.isPrimaryKeyConflict,
                    'count': batchMutations.length,
                  },
                );
                if (batchResult.isPrimaryKeyConflict) {
                  for (
                    var offset = 0;
                    offset < batchMutations.length;
                    offset++
                  ) {
                    final item = batchMutations[offset];
                    final rec = batchRecords[offset];
                    final canonical = await _remoteGateway.fetch(
                      spec: rec.spec,
                      userId: userId,
                      deviceId: deviceId,
                      recordKey: rec.recordKey,
                    );
                    if (canonical != null) {
                      await _localStore.applyRemoteRecords([canonical]);
                      await _localStore.markMutationSucceeded(item, canonical);
                    } else {
                      await _localStore.markMutationFailed(
                        item,
                        'Primary key conflict occurred but canonical row was absent (23505).',
                      );
                    }
                  }
                  if (trackHydration) {
                    await _localStore.addHydrationUnits(batchMutations.length);
                  }
                  continue;
                } else {
                  for (final item in batchMutations) {
                    await _localStore.markMutationFailed(
                      item,
                      'Batch write conflict ${batchResult.code}: ${batchResult.message}',
                    );
                  }
                  continue;
                }
              }
              for (var offset = 0; offset < batchMutations.length; offset++) {
                try {
                  await _pushOne(
                    userId,
                    deviceId,
                    batchMutations[offset],
                    batchRecords[offset],
                    scope: scope,
                  );
                  if (trackHydration) {
                    await _localStore.addHydrationUnits(1);
                  }
                } on _AccountScopeInactive {
                  rethrow;
                } on Object catch (error) {
                  final failure = SupabaseFailure.from(error);
                  await _recordMutationFailure(batchMutations[offset], failure);
                  rethrow;
                }
              }
              continue;
            }
          }
        }
        final record = await _localStore.readMutation(mutation, deviceId);
        if (record == null) {
          await _localStore.discardMutation(
            mutation.entity,
            mutation.recordKey,
          );
          if (trackHydration) await _localStore.addHydrationUnits(1);
          index++;
          continue;
        }
        try {
          await _pushOne(userId, deviceId, mutation, record, scope: scope);
          await _ensureActiveAccountScope(scope);
          if (trackHydration) await _localStore.addHydrationUnits(1);
        } on _AccountScopeInactive {
          rethrow;
        } on Object catch (error) {
          final failure = SupabaseFailure.from(error);
          await _recordMutationFailure(mutation, failure);
          rethrow;
        }
        index++;
      }
      if (mutations.length < 200) return pushedSomething;
    }
  }

  Future<void> _pushMaintenanceCompletion(
    LocalSyncMutation mutation, {
    required String payloadJson,
    required String userId,
    required String deviceId,
    required _ActiveAccountScope scope,
  }) async {
    await _localStore.markMutationInFlight(mutation, userId: userId);
    AppLogger.info(
      'sync_maintenance_completion_rpc_sent',
      fields: {
        'operation': _diagnosticId(mutation.operationId),
        'retry': mutation.attempts,
      },
    );

    MaintenanceCompletionResult result;
    try {
      result = await _remoteGateway.completeMaintenance(
        payloadJson: payloadJson,
        userId: userId,
        deviceId: deviceId,
      );
      await _ensureActiveAccountScope(scope);
    } on _AccountScopeInactive {
      rethrow;
    } on Object catch (error) {
      final failure = SupabaseFailure.from(error);
      if (failure.kind != SupabaseFailureKind.conflict) rethrow;
      result = await _recoverLegacyMaintenanceConflict(
        mutation,
        payloadJson: payloadJson,
        userId: userId,
        deviceId: deviceId,
      );
      await _ensureActiveAccountScope(scope);
    }

    if (result.status == MaintenanceCompletionStatus.applied ||
        result.status == MaintenanceCompletionStatus.alreadyApplied) {
      if (result.plan != null && result.record != null) {
        if (result.record!.recordKey == mutation.recordKey) {
          await _localStore.markMaintenanceCompletionSucceeded(
            mutation,
            plan: result.plan!,
            record: result.record!,
          );
          await _reconcileMaintenanceCompletionReminders(mutation);
          return;
        } else {
          // Record ID mismatch -> another device won this occurrence
          await _localStore.reconcileMaintenanceOccurrenceCompletedElsewhere(
            mutation,
            plan: result.plan!,
            record: result.record!,
          );
          return;
        }
      }
    }

    if (result.status == MaintenanceCompletionStatus.conflict) {
      final reason = result.conflictReason ?? '';
      if (reason == 'occurrence_completed_elsewhere' &&
          result.plan != null &&
          result.record != null) {
        await _localStore.reconcileMaintenanceOccurrenceCompletedElsewhere(
          mutation,
          plan: result.plan!,
          record: result.record!,
        );
        return;
      }

      if (result.retryable &&
          result.currentPlanRevision != null &&
          result.plan != null) {
        final recoveredPayload = _maintenancePayloadWithRevision(
          payloadJson,
          result.currentPlanRevision!,
        );
        await _localStore.markMaintenanceConflictRecovery(
          mutation,
          payloadJson: recoveredPayload,
          errorCode: result.conflictReason ?? 'stale_plan_revision',
          message:
              'The current maintenance plan was fetched for one safe retry.',
        );
        final retried = await _remoteGateway.completeMaintenance(
          payloadJson: recoveredPayload,
          userId: userId,
          deviceId: deviceId,
        );
        await _ensureActiveAccountScope(scope);
        if (retried.status == MaintenanceCompletionStatus.applied ||
            retried.status == MaintenanceCompletionStatus.alreadyApplied) {
          if (retried.plan != null && retried.record != null) {
            await _localStore.markMaintenanceCompletionSucceeded(
              mutation,
              plan: retried.plan!,
              record: retried.record!,
            );
            await _reconcileMaintenanceCompletionReminders(mutation);
            return;
          }
        }
        result = retried;
      }

      if (result.plan != null) {
        await _localStore.reconcileRejectedMaintenanceCompletion(
          mutation,
          errorCode: result.conflictReason ?? 'conflict',
          message: _maintenanceConflictMessage(result),
          plan: result.plan,
        );
        await _reconcileMaintenanceCompletionReminders(mutation);
        return;
      }
    }

    final message = _maintenanceConflictMessage(result);
    await _localStore.markMaintenanceCompletionFailedVisible(
      mutation,
      errorCode: result.conflictReason ?? result.status.name,
      message: message,
      plan: result.plan,
      record: result.record,
    );
    if (result.plan != null) {
      await _reconcileMaintenanceCompletionReminders(mutation);
    }
    throw SupabaseFailure(
      kind: result.status == MaintenanceCompletionStatus.unauthorized
          ? SupabaseFailureKind.permissionDenied
          : result.status == MaintenanceCompletionStatus.invalid
          ? SupabaseFailureKind.incompatibleSchema
          : SupabaseFailureKind.conflict,
      message: message,
    );
  }

  Future<void> _reconcileMaintenanceCompletionReminders(
    LocalSyncMutation mutation,
  ) async {
    final reconcile = _maintenanceCompletionReminderReconciler;
    if (reconcile == null) return;
    try {
      await reconcile();
      AppLogger.info(
        'sync_maintenance_completion_reminder_reconciled',
        fields: {'operation': _diagnosticId(mutation.operationId)},
      );
    } on Object catch (error) {
      AppLogger.warning(
        'sync_maintenance_completion_reminder_reconciliation_failed',
        error: error,
        fields: {'operation': _diagnosticId(mutation.operationId)},
      );
    }
  }

  Future<MaintenanceCompletionResult> _recoverLegacyMaintenanceConflict(
    LocalSyncMutation mutation, {
    required String payloadJson,
    required String userId,
    required String deviceId,
  }) async {
    final operation = _decodeMaintenancePayload(payloadJson);
    final planPayload = Map<String, dynamic>.from(operation['plan'] as Map);
    final planId = planPayload['id'] as String;
    final expectedDue = DateTime.parse(
      operation['expected_next_due_date'] as String,
    ).toUtc();

    final appliedRecord = await _remoteGateway.fetch(
      spec: syncSpecByEntity['maintenance_record']!,
      userId: userId,
      deviceId: deviceId,
      recordKey: mutation.operationId,
      materializeMedia: false,
    );
    final currentPlan = await _remoteGateway.fetch(
      spec: syncSpecByEntity['maintenance_plan']!,
      userId: userId,
      deviceId: deviceId,
      recordKey: planId,
      materializeMedia: false,
    );
    if (appliedRecord != null && currentPlan != null) {
      return MaintenanceCompletionResult(
        status: MaintenanceCompletionStatus.alreadyApplied,
        retryable: false,
        plan: currentPlan,
        record: appliedRecord,
        currentPlanRevision: currentPlan.revision,
      );
    }

    final currentDue = currentPlan == null
        ? null
        : _asUtcDate(currentPlan.values['next_due_date']);
    final recurrenceUnchanged =
        currentPlan != null &&
        currentPlan.values['recurrence_interval'] ==
            planPayload['recurrence_interval'] &&
        currentPlan.values['recurrence_unit'] == planPayload['recurrence_unit'];
    return MaintenanceCompletionResult(
      status: MaintenanceCompletionStatus.conflict,
      retryable:
          currentPlan != null &&
          currentPlan.revision != null &&
          currentDue != null &&
          currentDue.isAtSameMomentAs(expectedDue) &&
          recurrenceUnchanged,
      plan: currentPlan,
      currentPlanRevision: currentPlan?.revision,
      resultingNextDueDate: currentDue,
      conflictReason:
          currentDue != null &&
              currentDue.isAtSameMomentAs(expectedDue) &&
              !recurrenceUnchanged
          ? 'recurrence_changed'
          : 'occurrence_changed',
    );
  }

  String _maintenancePayloadWithRevision(String payloadJson, int revision) {
    final payload = _decodeMaintenancePayload(payloadJson);
    payload['expected_plan_revision'] = revision;
    return jsonEncode(payload);
  }

  Map<String, dynamic> _decodeMaintenancePayload(String payloadJson) {
    final decoded = jsonDecode(payloadJson);
    if (decoded is! Map) {
      throw const FormatException('Invalid maintenance completion payload.');
    }
    return Map<String, dynamic>.from(decoded);
  }

  String _maintenanceConflictMessage(MaintenanceCompletionResult result) {
    return switch (result.conflictReason) {
      'occurrence_completed_elsewhere' =>
        'This occurrence was completed on another device. '
            'Your local completion was reconciled with the cloud.',
      'recurrence_changed' =>
        'The maintenance recurrence changed on another device. '
            'Review the task and confirm the completion again.',
      'plan_inactive' =>
        'This maintenance task was disabled or archived on another device.',
      'operation_id_reused' =>
        'This completion identifier is already associated with different data.',
      _ =>
        'The maintenance plan changed on another device. '
            'Review the task and confirm the completion again.',
    };
  }

  Future<void> _recordMutationFailure(
    LocalSyncMutation mutation,
    SupabaseFailure failure,
  ) {
    if (failure.retryable) {
      return _localStore.markMutationFailed(mutation, failure.message);
    }
    return _localStore.markMutationTerminal(mutation, failure.message);
  }

  Future<void> _pushOne(
    String userId,
    String deviceId,
    LocalSyncMutation mutation,
    SyncRecord local, {
    required _ActiveAccountScope scope,
  }) async {
    final shadow = await _localStore.shadow(
      mutation.entity,
      mutation.recordKey,
    );
    var result = await _remoteGateway.write(
      record: local,
      userId: userId,
      deviceId: deviceId,
      expectedRevision: shadow?.remoteRevision,
    );
    await _ensureActiveAccountScope(scope);
    if (!result.conflict) {
      await _completeMutation(userId, mutation, result);
      return;
    }
    final remote = result.canonical;
    final hasClockSkew = remote != null && _hasClockSkew(local, remote);
    if (hasClockSkew) {
      _clockSkewConflicts++;
    }
    if (remote != null &&
        ((shadow == null && await _localStore.isUntouchedSeed(local)) ||
            _sameRecordData(local, remote))) {
      await _ensureActiveAccountScope(scope);
      await _localStore.applyRemoteRecords([remote]);
      await _localStore.markMutationSucceeded(mutation, remote);
      return;
    } else if (remote == null) {
      result = await _remoteGateway.write(
        record: local,
        userId: userId,
        deviceId: deviceId,
        expectedRevision: null,
      );
      await _ensureActiveAccountScope(scope);
    } else if (hasClockSkew) {
      await _localStore.applyRemoteRecords([remote]);
      await _localStore.markMutationSucceeded(mutation, remote);
      return;
    } else if (local.clientModifiedAt.isAfter(remote.clientModifiedAt) ||
        (local.clientModifiedAt.isAtSameMomentAs(remote.clientModifiedAt) &&
            local.originDeviceId.compareTo(remote.originDeviceId) > 0)) {
      result = await _remoteGateway.write(
        record: local,
        userId: userId,
        deviceId: deviceId,
        expectedRevision: remote.revision,
      );
      await _ensureActiveAccountScope(scope);
    } else {
      await _ensureActiveAccountScope(scope);
      await _localStore.applyRemoteRecords([remote]);
      await _localStore.markMutationSucceeded(mutation, remote);
      return;
    }
    if (result.conflict) {
      final entity = mutation.entity.replaceAll('_', ' ');
      throw SupabaseFailure(
        kind: SupabaseFailureKind.conflict,
        message:
            'A cloud $entity record kept changing during synchronization. '
            'The local change remains queued.',
        retryable: true,
      );
    }
    await _ensureActiveAccountScope(scope);
    await _completeMutation(userId, mutation, result);
  }

  bool _hasClockSkew(SyncRecord local, SyncRecord remote) {
    const tolerance = Duration(minutes: 5);
    final now = DateTime.now().toUtc();
    final localDelta = local.clientModifiedAt.toUtc().difference(now).abs();
    final remoteServerTime = remote.serverUpdatedAt;
    final remoteDelta = remoteServerTime == null
        ? Duration.zero
        : remote.clientModifiedAt
              .toUtc()
              .difference(remoteServerTime.toUtc())
              .abs();
    return localDelta > tolerance || remoteDelta > tolerance;
  }

  Future<void> _completeMutation(
    String userId,
    LocalSyncMutation mutation,
    RemoteWriteResult result,
  ) async {
    await _localStore.markMutationSucceeded(mutation, result.canonical);
    for (final objectPath in result.cleanupObjectPaths) {
      await _localStore.enqueueMediaCleanup(
        objectPath: objectPath,
        userId: userId,
        entity: mutation.entity,
        recordKey: mutation.recordKey,
      );
    }
  }

  Future<void> _processMediaCleanup(
    String userId, {
    required _ActiveAccountScope scope,
    bool trackHydration = false,
  }) async {
    final cleanups = await _localStore.pendingMediaCleanup();
    for (final cleanup in cleanups) {
      await _ensureActiveAccountScope(scope);
      if (cleanup.userId != userId) continue;
      try {
        await _remoteGateway.removeMediaObject(cleanup.objectPath, userId);
        await _ensureActiveAccountScope(scope);
        await _localStore.markMediaCleanupSucceeded(cleanup.objectPath);
        if (trackHydration) await _localStore.addHydrationUnits(1);
      } on _AccountScopeInactive {
        rethrow;
      } on Object catch (error) {
        final failure = SupabaseFailure.from(error);
        if (failure.kind == SupabaseFailureKind.permissionDenied ||
            failure.kind == SupabaseFailureKind.incompatibleSchema) {
          await _localStore.markMediaCleanupTerminal(cleanup, failure.message);
          await _localStore.recordSyncBlocked(failure.message);
          _phaseOverride = SyncPhase.blocked;
          _messageOverride = failure.message;
          throw failure;
        } else {
          await _localStore.markMediaCleanupFailed(cleanup, failure.message);
        }
      }
    }
  }

  void startPostReadyWork() {
    if (_accountDeletionInProgress) return;
    if (_postReadyWork != null) return;
    final work = _runPostReadyWork();
    _postReadyWork = work;
    unawaited(
      work.whenComplete(() {
        if (identical(_postReadyWork, work)) {
          _postReadyWork = null;
        }
      }),
    );
  }

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
      await _ensureRealtime().timeout(_localCleanupTimeout);
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
      return await _remoteGateway.fetch(
        spec: syncSpecByEntity['asset_photo']!,
        userId: userId,
        deviceId: deviceId,
        recordKey: recordKey,
      );
    } on Object catch (error) {
      AppLogger.warning('sync_post_ready_photo_refetch_failed', error: error);
      return null;
    }
  }

  Future<void> onAppResumed() async {
    if (_accountDeletionInProgress) return;
    final account = await _localStore.existingAccount();
    if (account == null) return;
    if (account.enabled && _authRepository.currentSession != null) {
      await _ensureRealtime();
      final lastSyncedAt = account.lastSyncedAt;
      final elapsed = lastSyncedAt == null
          ? null
          : DateTime.now().difference(lastSyncedAt);
      final recentlyReconciled =
          elapsed != null &&
          !elapsed.isNegative &&
          elapsed <= const Duration(minutes: 15);
      _scheduleAutomaticSync(
        delay: Duration.zero,
        pushOnly: recentlyReconciled,
      );
    }
  }

  Future<void> _handleAccountChanged(SyncAccountData? account) async {
    final previousScopeKey = _lastAccountScopeKey;
    final scopeKey = _accountScopeKey(account);
    if (scopeKey != previousScopeKey) {
      _lastAccountScopeKey = scopeKey;
      if (account == null && previousScopeKey != null) {
        _advanceAccountEpoch('account_absent');
      }
    }
    if (account == null) {
      _cancelScheduledSyncWork();
      _mergeConfirmationRequired = false;
      _phaseOverride = SyncPhase.signedOut;
      _messageOverride = null;
      try {
        await configureBackgroundSync?.call(false);
      } on Object {
        // Foreground sync remains available if the OS scheduler rejects work.
      }
      await _stopRealtime();
      await _emit();
      return;
    }
    if (_accountDeletionInProgress &&
        (_deletingUserId == null || account.boundUserId != _deletingUserId)) {
      _accountDeletionInProgress = false;
      _deletingUserId = null;
    }
    try {
      await configureBackgroundSync?.call(
        account.enabled && !_accountDeletionInProgress,
      );
    } on Object {
      // Foreground sync remains available if the OS scheduler rejects work.
    }
    await _emit();
    if (!_accountDeletionInProgress) {
      await _ensureRealtime();
    }
  }

  Future<void> _handleAccountWatchError(Object error) async {
    _phaseOverride = SyncPhase.error;
    _messageOverride = SupabaseFailure.from(error).message;
    _cancelScheduledSyncWork();
    await _stopRealtime();
    await _emit();
  }

  Future<void> _handlePendingChanged(int pending) async {
    if (_accountDeletionInProgress) return;
    await _emit();
    if (pending > 0 && await _localStore.hasReadyMutations()) {
      _scheduleAutomaticSync(pushOnly: true);
    }
    await _scheduleRetry();
  }

  void _handleAuthStateChanged(AuthStateChange state) {
    _authInitialization = _authInitialization
        .catchError((Object _) {})
        .then((_) => _initializeForAuthState(state))
        .catchError((Object _) {
          // The coordinator persists and exposes initialization failures
          // through SyncStatus; auth stream callbacks must not leak errors.
        });
  }

  Future<void> _initializeForAuthState(AuthStateChange state) async {
    await _emit();
    final session = state.session;
    if (session == null) {
      _mergeConfirmationRequired = false;
      await _stopRealtime();
      await _emit();
      return;
    }

    if (_accountDeletionInProgress && session.userId != _deletingUserId) {
      _accountDeletionInProgress = false;
      _deletingUserId = null;
      _advanceAccountEpoch('new_auth_scope_after_deletion');
    }
    if (_accountDeletionInProgress) {
      await _emit();
      return;
    }

    final account = await _localStore.account();
    if (account.boundUserId != null && account.boundUserId != session.userId) {
      _phaseOverride = SyncPhase.blocked;
      _messageOverride = 'Cloud account does not match this device data.';
      await _emit();
      return;
    }

    if (!account.enabled && account.boundUserId == null) {
      _mergeConfirmationRequired = false;
      _phaseOverride = SyncPhase.initializing;
      _messageOverride = null;
      await _emit();
      if (!autoEnableOnAuthChange) return;
      await enable();
      return;
    }

    _mergeConfirmationRequired = false;
    await _ensureRealtime();
    _scheduleAutomaticSync(delay: Duration.zero);
  }

  Future<void> _handleConnectivityChanged(bool online) async {
    if (_online == online) return;
    AppLogger.info('sync_connectivity_changed', fields: {'online': online});
    final restored = !_online && online;
    _online = online;
    if (!online) {
      _phaseOverride = SyncPhase.offline;
      _messageOverride = 'Cloud sync is waiting for a network.';
      await _emit();
      return;
    }
    if (_phaseOverride == SyncPhase.offline) {
      _phaseOverride = null;
      _messageOverride = null;
    }
    if (_accountDeletionInProgress) {
      await _emit();
      return;
    }
    await _ensureRealtime();
    if (restored) {
      _scheduleAutomaticSync(delay: Duration.zero, forceAfterActive: true);
    }
    await _emit();
  }

  void _scheduleAutomaticSync({
    Duration delay = const Duration(milliseconds: 350),
    Set<String>? targetTables,
    bool pushOnly = false,
    bool forceAfterActive = false,
  }) {
    if (_accountDeletionInProgress) return;
    if (targetTables != null) {
      _pendingTargetTables.addAll(targetTables);
    }
    _pushOnlyRequested = _pushOnlyRequested || pushOnly;
    if (!_automaticSyncEnabled || _isInitializing) return;
    if (_activeSync != null) {
      final activeCoversBroadPull = _activeWork?.pullTables == null;

      // Preserve follow-up work when data changed during the active sync, when
      // connectivity was restored, or when the active operation is targeted
      // or push-only and therefore does not cover a broad automatic pull.
      final hasNewWork =
          forceAfterActive ||
          _pendingTargetTables.isNotEmpty ||
          _pushOnlyRequested ||
          !activeCoversBroadPull;
      if (hasNewWork) {
        _syncRequestedWhileActive = true;
      } else {
        AppLogger.info(
          'sync_automatic_skipped_active',
          fields: {'attempt': _syncAttemptSerial},
        );
      }
      return;
    }
    _automaticSyncTimer?.cancel();
    _automaticSyncTimer = Timer(delay, () {
      unawaited(_runAutomaticSync());
    });
  }

  Future<void> _runAutomaticSync() async {
    if (_accountDeletionInProgress) return;
    final account = await _localStore.existingAccount();
    if (account == null) return;
    if (!account.enabled ||
        account.blockedReason != null ||
        !_online ||
        _authRepository.currentSession == null) {
      return;
    }
    try {
      await _startSync(mode: SyncMode.incrementalPull);
    } on Object {
      // syncNow records the actionable failure and preserves queued changes.
    }
  }

  Future<void> _scheduleRetry() async {
    if (!_automaticSyncEnabled) return;
    _retryTimer?.cancel();
    if (_accountDeletionInProgress) return;
    final account = await _localStore.existingAccount();
    if (account == null) return;
    if (account.blockedReason != null) return;
    final retryAt = await _localStore.nextRetryAt();
    if (retryAt == null) return;
    final delay = retryAt.difference(DateTime.now());
    _retryTimer = Timer(
      delay.isNegative ? Duration.zero : delay,
      () => _scheduleAutomaticSync(delay: Duration.zero),
    );
  }

  String? _accountScopeKey(SyncAccountData? account) {
    if (account == null) return null;
    return [
      account.enabled,
      account.boundUserId ?? '',
      account.deviceId,
    ].join('|');
  }

  void _advanceAccountEpoch(String reason) {
    _accountEpoch++;
    AppLogger.info(
      'sync_account_epoch_advanced',
      fields: {'epoch': _accountEpoch, 'reason': reason},
    );
  }

  void _cancelScheduledSyncWork() {
    _automaticSyncTimer?.cancel();
    _retryTimer?.cancel();
    _realtimeReconnectTimer?.cancel();
    _realtimeDeleteFollowUpTimer?.cancel();
    _pendingTargetTables.clear();
    _pushOnlyRequested = false;
    _syncRequestedWhileActive = false;
    _fullSyncRequestedWhileActive = false;
  }

  bool _isActiveAccountScope(_ActiveAccountScope scope) {
    if (_accountDeletionInProgress) return false;
    if (scope.epoch != _accountEpoch) return false;
    return _authRepository.currentSession?.userId == scope.userId;
  }

  Future<void> _ensureActiveAccountScope(_ActiveAccountScope scope) async {
    if (!_isActiveAccountScope(scope)) {
      throw const _AccountScopeInactive();
    }
    final account = await _localStore.existingAccount();
    if (account == null ||
        !account.enabled ||
        account.boundUserId != scope.userId ||
        account.deviceId != scope.deviceId ||
        !_isActiveAccountScope(scope)) {
      throw const _AccountScopeInactive();
    }
  }

  Future<void> _ensureRealtime() =>
      _serializeRealtimeOperation(_ensureRealtimeSerial);

  Future<void> _ensureRealtimeSerial() async {
    final realtime = _realtime;
    if (realtime == null || !_online || _accountDeletionInProgress) return;
    final account = await _localStore.existingAccount();
    if (account == null) return;
    final session = _authRepository.currentSession;
    if (!account.enabled ||
        session == null ||
        account.boundUserId != session.userId) {
      await _stopRealtimeSerial();
      return;
    }
    final identity = '${session.userId}:${account.deviceId}';
    final scope = _ActiveAccountScope(
      epoch: _accountEpoch,
      userId: session.userId,
      deviceId: account.deviceId,
    );
    if (_realtimeIdentity == identity) return;
    _realtimeConnection = _realtimeReconnectAttempts == 0
        ? SyncRealtimeConnection.connecting
        : SyncRealtimeConnection.reconnecting;
    await _emit();
    try {
      await realtime.startRealtime(
        userId: session.userId,
        deviceId: account.deviceId,
        onChange: (event) {
          unawaited(_handleRealtimeChange(event, scope: scope));
        },
        onDelete: (spec, oldRecord) {
          unawaited(
            _handleRealtimeDelete(
              spec: spec,
              oldRecord: oldRecord,
              userId: session.userId,
              deviceId: account.deviceId,
              scope: scope,
            ),
          );
        },
        onStatus: (status, _) {
          if (!_isActiveAccountScope(scope)) return;
          switch (status) {
            case SyncRealtimeStatus.subscribed:
              _realtimeReconnectAttempts = 0;
              _realtimeConnection = SyncRealtimeConnection.connected;
              unawaited(_emit());
            case SyncRealtimeStatus.disconnected || SyncRealtimeStatus.failed:
              _realtimeConnection = SyncRealtimeConnection.reconnecting;
              _realtimeIdentity = null;
              _scheduleRealtimeReconnect();
              unawaited(_emit());
          }
        },
      );
      _realtimeIdentity = identity;
    } on Object {
      _realtimeConnection = SyncRealtimeConnection.reconnecting;
      _realtimeIdentity = null;
      _scheduleRealtimeReconnect();
      await _emit();
    }
  }

  Future<void> _handleRealtimeChange(
    RealtimeSyncEvent event, {
    required _ActiveAccountScope scope,
  }) async {
    if (!_isActiveAccountScope(scope)) return;
    final account = await _localStore.existingAccount();
    if (account == null) return;
    if (event.originDeviceId != null &&
        event.originDeviceId == account.deviceId) {
      AppLogger.info(
        'sync_realtime_self_echo_suppressed',
        fields: {'revision': event.revision ?? 0},
      );
      return;
    }
    AppLogger.info(
      'sync_realtime_${event.type.name}',
      fields: {'revision': event.revision ?? 0},
    );
    final recordKey = event.recordKey;
    final revision = event.revision;
    if (recordKey != null && revision != null) {
      final shadow = await _localStore.shadow(event.spec.entity, recordKey);
      if (shadow != null && shadow.remoteRevision >= revision) {
        return;
      }
    }
    _scheduleAutomaticSync(delay: Duration.zero, targetTables: {event.table});
  }

  void _scheduleRealtimeReconnect() {
    if (!_online || _realtime == null || _accountDeletionInProgress) return;
    _realtimeReconnectTimer?.cancel();
    _realtimeReconnectAttempts++;
    final seconds = math.min(
      1 << math.min(_realtimeReconnectAttempts - 1, 6),
      60,
    );
    _realtimeReconnectTimer = Timer(Duration(seconds: seconds), () {
      unawaited(_ensureRealtime());
    });
  }

  Future<void> _handleRealtimeDelete({
    required SyncEntitySpec spec,
    required Map<String, dynamic> oldRecord,
    required String userId,
    required String deviceId,
    required _ActiveAccountScope scope,
  }) async {
    if (!_isActiveAccountScope(scope)) return;
    AppLogger.info(
      'sync_realtime_delete_hint',
      fields: {'entity': spec.entity},
    );
    await _localStore.applyRemoteHardDelete(
      spec: spec,
      oldRecord: oldRecord,
      userId: userId,
      deviceId: deviceId,
    );
    _scheduleAutomaticSync(
      delay: Duration.zero,
      targetTables: {spec.remoteTable},
    );
  }

  Future<void> _stopRealtime() =>
      _serializeRealtimeOperation(_stopRealtimeSerial);

  Future<void> _stopRealtimeSerial() async {
    _realtimeReconnectTimer?.cancel();
    _realtimeIdentity = null;
    _realtimeConnection = SyncRealtimeConnection.disabled;
    await _realtime?.stopRealtime();
  }

  Future<void> _serializeRealtimeOperation(Future<void> Function() operation) {
    final next = _realtimeOperation.then((_) => operation());

    // Keep the internal queue usable after an individual operation fails,
    // while still returning that failure to the original caller.
    _realtimeOperation = next.catchError((Object _) {});
    return next;
  }

  Future<void> _emit() async {
    if (_statusController.isClosed) return;
    final next = await status();
    if (!_statusController.isClosed) {
      _statusController.add(next);
    }
  }

  Future<void> dispose() async {
    _initializationTimer?.cancel();
    _automaticSyncTimer?.cancel();
    _retryTimer?.cancel();
    _realtimeReconnectTimer?.cancel();
    _realtimeDeleteFollowUpTimer?.cancel();
    await _accountSubscription?.cancel();
    await _pendingSubscription?.cancel();
    await _authSubscription?.cancel();
    await _connectivitySubscription?.cancel();
    await _stopRealtime();
    await _statusController.close();
  }
}

class _ActiveAccountScope {
  const _ActiveAccountScope({
    required this.epoch,
    required this.userId,
    required this.deviceId,
  });

  final int epoch;
  final String userId;
  final String deviceId;
}

class _AccountScopeInactive implements Exception {
  const _AccountScopeInactive();
}

class _PullSeed {
  const _PullSeed({
    required this.spec,
    required this.cursor,
    required this.recordKey,
    required this.exactCount,
    required this.firstPage,
  });

  final SyncEntitySpec spec;
  final int cursor;
  final String? recordKey;
  final int exactCount;
  final List<SyncRecord> firstPage;
}

class _PullOutcome {
  const _PullOutcome({
    this.maintenanceChanged = false,
    this.remoteRecordCount = 0,
    this.meaningfulRemoteRecordCount = 0,
  });

  final bool maintenanceChanged;
  final int remoteRecordCount;
  final int meaningfulRemoteRecordCount;
}

bool _isBootstrapClassificationRecord(_PullSeed seed) {
  return seed.spec.entity != 'profile';
}

bool _sameRecordData(SyncRecord local, SyncRecord remote) {
  if (local.spec.entity != remote.spec.entity ||
      local.isDeleted != remote.isDeleted) {
    return false;
  }
  for (final column in local.spec.localColumns) {
    if (!local.values.containsKey(column) ||
        !remote.values.containsKey(column) ||
        !_sameValue(
          local.spec,
          column,
          local.values[column],
          remote.values[column],
        )) {
      return false;
    }
  }
  return true;
}

bool _isMaintenanceSyncEntity(SyncRecord record) {
  return const {
    'maintenance_plan',
    'maintenance_plan_metadata',
    'maintenance_record',
  }.contains(record.spec.entity);
}

bool _sameValue(
  SyncEntitySpec spec,
  String column,
  Object? local,
  Object? remote,
) {
  if (local == null || remote == null) return local == remote;
  if (spec.dateColumns.contains(column)) {
    final localDate = _asUtcDate(local);
    final remoteDate = _asUtcDate(remote);
    return localDate != null &&
        remoteDate != null &&
        localDate.isAtSameMomentAs(remoteDate);
  }
  if (local is num && remote is num) {
    return local.toDouble() == remote.toDouble();
  }
  return local == remote;
}

DateTime? _asUtcDate(Object? value) {
  if (value is DateTime) return value.toUtc();
  if (value is String) return DateTime.tryParse(value)?.toUtc();
  return null;
}

int _diagnosticId(String value) {
  var hash = 0;
  for (final codeUnit in value.codeUnits) {
    hash = ((hash * 31) + codeUnit) & 0x7fffffff;
  }
  return hash;
}
