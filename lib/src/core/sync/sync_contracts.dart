enum SyncPhase {
  disabled,
  signedOut,
  ready,
  initializing,
  waitingForSyncLease,
  syncing,
  offline,
  blocked,
  error,
}

enum SyncRunOutcome { completed, waitingForSyncLease, notEligible }

enum SyncRealtimeConnection { disabled, connecting, connected, reconnecting }

enum RestoreRunState { running, failed, completed }

enum InitialHydrationStage {
  connecting,
  restoringCloudData,
  restoringPhotos,
  syncingLocalChanges,
  checkingLatestUpdates,
  finalizing,
}

class InitialHydrationProgress {
  const InitialHydrationProgress({
    required this.runId,
    required this.state,
    required this.stage,
    required this.completedUnits,
    required this.totalUnits,
    required this.startedAt,
    required this.updatedAt,
    this.failure,
  });

  final String runId;
  final RestoreRunState state;
  final InitialHydrationStage stage;
  final int completedUnits;
  final int totalUnits;
  final DateTime startedAt;
  final DateTime updatedAt;
  final String? failure;

  double get fraction {
    if (state == RestoreRunState.completed) return 1;
    if (totalUnits <= 0) return 0;
    return (completedUnits / totalUnits).clamp(0.0, 1.0);
  }

  int get percentage => (fraction * 100).floor();

  bool get isActive => state != RestoreRunState.completed;
}

class SyncStatus {
  const SyncStatus({
    required this.phase,
    this.enabled = false,
    this.pendingChanges = 0,
    this.pendingMediaCleanup = 0,
    this.lastSyncedAt,
    this.lastSyncAttemptAt,
    this.lastSyncFailureAt,
    this.message,
    this.boundUserId,
    this.realtime = SyncRealtimeConnection.disabled,
    this.nextRetryAt,
    this.initialHydrationProgress,
    this.mergeConfirmationRequired = false,
    this.blockedReason,
    this.migrationState = 'localOnly',
    this.restorePending = false,
    this.backgroundResult,
    this.clockSkewConflicts = 0,
    this.payloadParseFailures = 0,
  });

  const SyncStatus.disabled()
    : this(phase: SyncPhase.disabled, message: 'Cloud sync is disabled.');

  final SyncPhase phase;
  final bool enabled;
  final int pendingChanges;
  final int pendingMediaCleanup;
  final DateTime? lastSyncedAt;
  final DateTime? lastSyncAttemptAt;
  final DateTime? lastSyncFailureAt;
  final String? message;
  final String? boundUserId;
  final SyncRealtimeConnection realtime;
  final DateTime? nextRetryAt;
  final InitialHydrationProgress? initialHydrationProgress;
  final bool mergeConfirmationRequired;
  final String? blockedReason;
  final String migrationState;
  final bool restorePending;
  final String? backgroundResult;
  final int clockSkewConflicts;

  /// WP-006 (F-015): outbox/acknowledgement payloads that failed structural
  /// decoding. Non-PII counter only; no payload content is retained.
  final int payloadParseFailures;
}

abstract interface class CloudSyncRepository {
  Stream<SyncStatus> watchStatus();
  Future<SyncStatus> status();
  Future<void> enable();
  Future<void> disable();
  Future<void> unlink();
  Future<void> retry();
  Future<void> fullReconcile();
  Future<void> syncNow();
}

class DisabledCloudSyncRepository implements CloudSyncRepository {
  const DisabledCloudSyncRepository();

  @override
  Future<void> disable() async {}

  @override
  Future<void> enable() async {}

  @override
  Future<void> unlink() async {}

  @override
  Future<void> retry() async {}

  @override
  Future<void> fullReconcile() async {}

  @override
  Future<void> syncNow() async {}

  @override
  Future<SyncStatus> status() async => const SyncStatus.disabled();

  @override
  Stream<SyncStatus> watchStatus() =>
      Stream<SyncStatus>.value(const SyncStatus.disabled());
}
