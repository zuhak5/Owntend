import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import '../supabase/supabase_failure.dart';
import '../utils/redacting_logger.dart';
import '../database/app_database.dart';
import '../../features/auth/domain/auth_repository.dart';
import 'local_sync_store.dart';
import 'local_sync_store_change_feed.dart';
import 'supabase_sync_gateway.dart';
import 'sync_contracts.dart';
import 'sync_connectivity.dart';
import 'sync_dtos.dart';

part 'coordinator/models.dart';
part 'coordinator/post_ready_coordinator.dart';
part 'coordinator/push_coordinator.dart';
part 'coordinator/repair_coordinator.dart';
part 'coordinator/run_coordinator.dart';
part 'coordinator/runtime_coordinator.dart';
part 'coordinator/schedule_controller.dart';

class SyncCoordinator implements CloudSyncRepository, _SyncScheduleEnv {
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
    this.initialHydrationLeaseRetryDelay = const Duration(seconds: 2),
    this.initialHydrationLeaseWaitTimeout = const Duration(seconds: 30),
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
  final Duration initialHydrationLeaseRetryDelay;
  final Duration initialHydrationLeaseWaitTimeout;
  final StreamController<SyncStatus> _statusController =
      StreamController<SyncStatus>.broadcast();
  static const _localCleanupTimeout = Duration(seconds: 4);

  StreamSubscription<Object?>? _accountSubscription;
  StreamSubscription<Object?>? _pendingSubscription;
  StreamSubscription<AuthStateChange>? _authSubscription;
  StreamSubscription<bool>? _connectivitySubscription;
  Future<SyncRunOutcome>? _activeSync;
  SyncWork? _activeWork;
  Timer? _realtimeReconnectTimer;
  Timer? _realtimeDeleteFollowUpTimer;
  Timer? _retryTimer;
  Timer? _initializationTimer;
  bool _isInitializing = true;

  /// WP-007 (F-011): queued-work requests and the automatic-sync timer are
  /// owned by the schedule controller; the facade only answers environment
  /// queries and consumes drained work requests.
  late final _SyncScheduleController _schedule = _SyncScheduleController(this);
  var _realtimeReconnectAttempts = 0;
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

  // WP-007: environment answers for [_SyncScheduleController].
  @override
  bool get scheduleAccountDeletionInProgress => _accountDeletionInProgress;
  @override
  bool get scheduleAutomaticEnabled => _automaticSyncEnabled;
  @override
  bool get scheduleIsInitializing => _isInitializing;
  @override
  bool get scheduleHasActiveSync => _activeSync != null;
  @override
  bool get scheduleActiveCoversBroadPull => _activeWork?.pullTables == null;
  @override
  int get scheduleAttemptSerial => _syncAttemptSerial;
  @override
  void scheduleRunAutomaticSync() {
    unawaited(_runAutomaticSync());
  }

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
        payloadParseFailures: _localStore.payloadParseFailures,
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
      payloadParseFailures: _localStore.payloadParseFailures,
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
    await _awaitInitialHydrationReadiness(session.userId);
  });

  Future<void> _awaitInitialHydrationReadiness(String expectedUserId) async {
    final deadline = DateTime.now().add(initialHydrationLeaseWaitTimeout);
    while (true) {
      if (_accountDeletionInProgress ||
          _authRepository.currentSession?.userId != expectedUserId) {
        throw const SupabaseFailure(
          kind: SupabaseFailureKind.authentication,
          message:
              'The cloud account changed before initial hydration completed.',
        );
      }

      final outcome = await _startSyncWithOutcome(
        mode: SyncMode.initialHydration,
      );

      if (_accountDeletionInProgress ||
          _authRepository.currentSession?.userId != expectedUserId) {
        throw const SupabaseFailure(
          kind: SupabaseFailureKind.authentication,
          message:
              'The cloud account changed before initial hydration completed.',
        );
      }
      if (await _localStore.hasCompleteSnapshotForUser(expectedUserId)) {
        _phaseOverride = SyncPhase.ready;
        _messageOverride = null;
        await _emit();
        return;
      }

      switch (outcome) {
        case SyncRunOutcome.completed:
          throw const SupabaseFailure(
            kind: SupabaseFailureKind.unknown,
            message:
                'Initial cloud hydration completed without a durable Home snapshot. '
                'Retry to finish startup safely.',
            retryable: true,
          );
        case SyncRunOutcome.notEligible:
          throw const SupabaseFailure(
            kind: SupabaseFailureKind.unknown,
            message:
                'Initial cloud hydration is no longer eligible to continue. '
                'Retry after cloud sync becomes available.',
            retryable: true,
          );
        case SyncRunOutcome.waitingForSyncLease:
          final now = DateTime.now();
          if (!now.isBefore(deadline)) {
            throw const SupabaseFailure(
              kind: SupabaseFailureKind.unknown,
              message:
                  'Another sync operation is still running. '
                  'Retry initial cloud hydration shortly.',
              retryable: true,
            );
          }
          final remaining = deadline.difference(now);
          final delay =
              initialHydrationLeaseRetryDelay.compareTo(remaining) <= 0
              ? initialHydrationLeaseRetryDelay
              : remaining;
          if (delay > Duration.zero) {
            await Future<void>.delayed(delay);
          }
      }
    }
  }

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

  Future<void> completeAccountSignOut(String userId) {
    return _serializeAccountTransition(() async {
      if (_deletingUserId != null && _deletingUserId != userId) {
        throw StateError(
          'Sign-out completion does not match the active account transition.',
        );
      }
      _accountDeletionInProgress = false;
      _deletingUserId = null;
      _advanceAccountEpoch('account_sign_out_completed');
      _cancelScheduledSyncWork();
      _deferredRemoteMedia.clear();
      _mergeConfirmationRequired = false;
      _phaseOverride = SyncPhase.signedOut;
      _messageOverride = null;
      await _stopRealtime();
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

  Future<void> onAppResumed() async {
    if (_accountDeletionInProgress) return;
    final account = await _localStore.existingAccount();
    if (account == null) return;
    if (account.enabled && _authRepository.currentSession != null) {
      await _ensureRealtime();
      _scheduleAutomaticSync(delay: Duration.zero, requireBroadPull: true);
    }
  }

  void _scheduleAutomaticSync({
    Duration delay = const Duration(milliseconds: 350),
    Set<String>? targetTables,
    bool pushOnly = false,
    bool requireBroadPull = false,
  }) {
    _schedule.scheduleAutomatic(
      delay: delay,
      targetTables: targetTables,
      pushOnly: pushOnly,
      requireBroadPull: requireBroadPull,
    );
  }

  Future<void> dispose() async {
    _initializationTimer?.cancel();
    _retryTimer?.cancel();
    _realtimeReconnectTimer?.cancel();
    _realtimeDeleteFollowUpTimer?.cancel();
    _schedule.dispose();
    await _accountSubscription?.cancel();
    await _pendingSubscription?.cancel();
    await _authSubscription?.cancel();
    await _connectivitySubscription?.cancel();
    await _stopRealtime();
    await _statusController.close();
  }
}
