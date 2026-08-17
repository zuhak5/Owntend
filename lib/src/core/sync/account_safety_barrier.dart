typedef AccountSafetyBackgroundCancellation = Future<void> Function();
typedef AccountSafetyScopeHook = Future<void> Function(String userId);

class AccountSafetyBarrier {
  factory AccountSafetyBarrier({
    required AccountSafetyScopeHook prepareAccountScope,
    required AccountSafetyBackgroundCancellation cancelBackgroundWork,
    required AccountSafetyScopeHook releaseAccountScope,
  }) => AccountSafetyBarrier._(
    prepareAccountScope,
    cancelBackgroundWork,
    releaseAccountScope,
  );

  AccountSafetyBarrier._(
    this._prepareAccountScope,
    this._cancelBackgroundWork,
    this._releaseAccountScope,
  );

  final AccountSafetyScopeHook _prepareAccountScope;
  final AccountSafetyBackgroundCancellation _cancelBackgroundWork;
  final AccountSafetyScopeHook _releaseAccountScope;

  Future<void> prepareForSignOut(String expectedUserId) async {
    if (expectedUserId.trim().isEmpty) {
      throw ArgumentError.value(
        expectedUserId,
        'expectedUserId',
        'Account safety requires an immutable account identity.',
      );
    }

    // First prevent new foreground/realtime work and detach any old account
    // epoch. Then cancel every account-scoped background workload. The latter
    // is deliberately not best-effort: sign-out must fail closed if the OS
    // scheduler cannot establish the barrier.
    await _prepareAccountScope(expectedUserId);
    await _cancelBackgroundWork();
  }

  Future<void> releaseAfterSignOut(String expectedUserId) async {
    if (expectedUserId.trim().isEmpty) return;
    await _releaseAccountScope(expectedUserId);
  }
}
