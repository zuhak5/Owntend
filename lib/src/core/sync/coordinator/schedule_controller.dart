part of '../sync_coordinator.dart';

/// Contract between the schedule controller and the coordinating facade.
///
/// WP-007 (F-011): scheduling decisions own their state here instead of
/// sharing the coordinator's mutable field surface. The facade answers the
/// environment queries; the controller decides when work runs.
abstract interface class _SyncScheduleEnv {
  bool get scheduleAccountDeletionInProgress;
  bool get scheduleAutomaticEnabled;
  bool get scheduleIsInitializing;
  bool get scheduleHasActiveSync;
  bool get scheduleActiveCoversBroadPull;
  int get scheduleAttemptSerial;
  void scheduleRunAutomaticSync();
}

/// Owns the queued-work requests and the automatic-sync timer.
///
/// Request flags (`broadPull`, `pushOnly`, targeted tables, while-active
/// follow-ups) were previously scattered across the coordinator's shared
/// mutable surface; every read and write now flows through this class so the
/// ownership contract test can enforce the boundary mechanically.
class _SyncScheduleController {
  _SyncScheduleController(this.env);

  final _SyncScheduleEnv env;

  Timer? _automaticSyncTimer;
  final Set<String> _pendingTargetTables = {};
  bool _pushOnlyRequested = false;
  bool _broadPullRequested = false;
  bool _syncRequestedWhileActive = false;
  bool _fullSyncRequestedWhileActive = false;

  /// Ports [runtime_coordinator._scheduleAutomaticSync] verbatim.
  void scheduleAutomatic({
    Duration delay = const Duration(milliseconds: 350),
    Set<String>? targetTables,
    bool pushOnly = false,
    bool requireBroadPull = false,
  }) {
    if (env.scheduleAccountDeletionInProgress) return;
    if (requireBroadPull) {
      _broadPullRequested = true;
      _pendingTargetTables.clear();
      _pushOnlyRequested = false;
    } else if (!_broadPullRequested) {
      if (targetTables != null) {
        _pendingTargetTables.addAll(targetTables);
      }
      _pushOnlyRequested = _pushOnlyRequested || pushOnly;
    }
    if (!env.scheduleAutomaticEnabled || env.scheduleIsInitializing) return;
    if (env.scheduleHasActiveSync) {
      final activeCoversBroadPull = env.scheduleActiveCoversBroadPull;

      if (_broadPullRequested && activeCoversBroadPull) {
        _broadPullRequested = false;
        _pendingTargetTables.clear();
        _pushOnlyRequested = false;
        AppLogger.info(
          'sync_automatic_reused_active_broad_pull',
          fields: {'attempt': env.scheduleAttemptSerial},
        );
        return;
      }

      // Preserve follow-up work when data changed during the active sync or
      // when a requested broad convergence is not covered by targeted or
      // push-only active work.
      final hasNewWork =
          _broadPullRequested ||
          _pendingTargetTables.isNotEmpty ||
          _pushOnlyRequested ||
          !activeCoversBroadPull;
      if (hasNewWork) {
        _syncRequestedWhileActive = true;
      } else {
        AppLogger.info(
          'sync_automatic_skipped_active',
          fields: {'attempt': env.scheduleAttemptSerial},
        );
      }
      return;
    }
    _automaticSyncTimer?.cancel();
    _automaticSyncTimer = Timer(delay, () {
      env.scheduleRunAutomaticSync();
    });
  }

  /// Cancels queued work requests and the automatic-sync timer. Realtime
  /// reconnect/delete-follow-up timers remain owned by the realtime cluster.
  void cancelQueuedWork() {
    _automaticSyncTimer?.cancel();
    _pendingTargetTables.clear();
    _pushOnlyRequested = false;
    _broadPullRequested = false;
    _syncRequestedWhileActive = false;
    _fullSyncRequestedWhileActive = false;
  }

  /// Drains the queued work request for a starting sync run.
  ({Set<String> targetTables, bool pushOnly, bool broadPull})
  consumeQueuedWork() {
    final result = (
      targetTables: _pendingTargetTables.toSet(),
      pushOnly: _pushOnlyRequested,
      broadPull: _broadPullRequested,
    );
    _pendingTargetTables.clear();
    _pushOnlyRequested = false;
    _broadPullRequested = false;
    return result;
  }

  void clearQueuedWork() {
    _pendingTargetTables.clear();
    _pushOnlyRequested = false;
    _broadPullRequested = false;
  }

  /// Records that additional work was requested while a sync was active.
  void markFollowUpRequired({required bool full}) {
    _syncRequestedWhileActive = true;
    _fullSyncRequestedWhileActive = _fullSyncRequestedWhileActive || full;
  }

  /// Takes the while-active follow-up flag if set.
  bool takeFollowUpRequested() {
    final requested = _syncRequestedWhileActive;
    _syncRequestedWhileActive = false;
    return requested;
  }

  bool takeFollowUpFullSync() {
    final full = _fullSyncRequestedWhileActive;
    _fullSyncRequestedWhileActive = false;
    return full;
  }

  void dispose() {
    _automaticSyncTimer?.cancel();
  }
}
