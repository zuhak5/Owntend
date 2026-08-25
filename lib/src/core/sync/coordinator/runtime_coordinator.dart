part of '../sync_coordinator.dart';

extension _SyncRuntimeCoordinator on SyncCoordinator {
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
      _scheduleAutomaticSync(delay: Duration.zero, requireBroadPull: true);
    }
    await _emit();
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
    _retryTimer?.cancel();
    _realtimeReconnectTimer?.cancel();
    _realtimeDeleteFollowUpTimer?.cancel();
    _schedule.cancelQueuedWork();
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
          _runListener(
            'sync_realtime_delete_reconcile_failed',
            () => _handleRealtimeDelete(
              spec: spec,
              oldRecord: oldRecord,
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
    required _ActiveAccountScope scope,
  }) async {
    if (!_isActiveAccountScope(scope)) return;
    if (spec.scope != SyncScope.catalog &&
        oldRecord['user_id'] != scope.userId) {
      return;
    }
    if (spec.scope == SyncScope.deviceScoped &&
        oldRecord['device_id'] != scope.deviceId) {
      return;
    }

    AppLogger.info(
      'sync_realtime_delete_hint',
      fields: {'entity': spec.entity},
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
}
