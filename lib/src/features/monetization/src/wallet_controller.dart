part of '../monetization.dart';

class PointWalletController extends Notifier<AsyncValue<PointWallet?>> {
  StreamSubscription<PointWallet?>? _walletSubscription;
  MonetizationRepository? _repository;
  String? _userId;
  int _scopeGeneration = 0;
  int _mutationGeneration = 0;
  int? _pendingAuthoritativeBalance;
  DateTime? _lastCanonicalUpdatedAt;
  bool _disposed = false;

  @override
  AsyncValue<PointWallet?> build() {
    ref.onDispose(() {
      _disposed = true;
      unawaited(_walletSubscription?.cancel());
    });

    ref.listen(authSessionProvider, (_, _) {
      scheduleMicrotask(() {
        if (!_disposed) unawaited(synchronizeAuthScope());
      });
    });
    ref.listen(monetizationRepositoryProvider, (_, _) {
      scheduleMicrotask(() {
        if (!_disposed) unawaited(synchronizeAuthScope());
      });
    });
    ref.listen(syncConnectivityProvider, (previous, next) {
      final wasOnline = previous?.value == true;
      if (!wasOnline && next.value == true) {
        scheduleMicrotask(() {
          if (!_disposed) unawaited(reconnect());
        });
      }
    });

    _repository = ref.read(monetizationRepositoryProvider);
    _userId = _repository?.currentUserId;
    if (_repository == null || _userId == null) {
      return const AsyncValue.data(null);
    }

    final generation = ++_scopeGeneration;
    scheduleMicrotask(() async {
      if (_disposed) return;
      await _establishWatch(generation);
      await refresh();
    });
    return const AsyncValue.loading();
  }

  Future<void> synchronizeAuthScope() async {
    final repository = ref.read(monetizationRepositoryProvider);
    final userId = repository?.currentUserId;
    final identityChanged = userId != _userId;
    final repositoryChanged = !identical(repository, _repository);

    if (!identityChanged && !repositoryChanged) {
      if (userId != null) await refresh();
      return;
    }

    final generation = ++_scopeGeneration;
    _repository = repository;
    _userId = userId;
    final previousSubscription = _walletSubscription;
    _walletSubscription = null;

    if (identityChanged) {
      _mutationGeneration = 0;
      _pendingAuthoritativeBalance = null;
      _lastCanonicalUpdatedAt = null;
      state = userId == null
          ? const AsyncValue.data(null)
          : const AsyncValue.loading();
    }

    await previousSubscription?.cancel();

    if (repository == null || userId == null) {
      state = const AsyncValue.data(null);
      return;
    }

    await _establishWatch(generation);
    await refresh();
  }

  Future<void> reconnect() async {
    final repository = _repository;
    final userId = _userId;
    if (repository == null || userId == null) return;
    final generation = ++_scopeGeneration;
    await _walletSubscription?.cancel();
    _walletSubscription = null;
    await _establishWatch(generation);
    await refresh();
  }

  Future<void> refresh() async {
    final repository = _repository;
    final userId = _userId;
    if (repository == null || userId == null) return;
    final generation = _scopeGeneration;
    final mutationGeneration = _mutationGeneration;
    try {
      final wallet = await repository.getWallet(userId);
      if (!_scopeIsCurrent(repository, userId, generation)) return;
      if (mutationGeneration != _mutationGeneration) return;
      final pendingBalance = _pendingAuthoritativeBalance;
      final lastUpdatedAt = _lastCanonicalUpdatedAt;
      if (pendingBalance != null &&
          wallet != null &&
          wallet.balance != pendingBalance &&
          (lastUpdatedAt == null || !wallet.updatedAt.isAfter(lastUpdatedAt))) {
        return;
      }
      _acceptCanonical(wallet, clearMutationGate: true);
    } on Object catch (error, stackTrace) {
      if (!_scopeIsCurrent(repository, userId, generation)) return;
      _pendingAuthoritativeBalance = null;
      if (state.value == null) {
        state = AsyncValue.error(error, stackTrace);
      }
    }
  }

  void adoptAuthoritativeMutationResult(int balance, {required String userId}) {
    final repository = _repository;
    if (repository == null ||
        _userId != userId ||
        repository.currentUserId != userId) {
      return;
    }

    _mutationGeneration += 1;
    _pendingAuthoritativeBalance = balance;
    final lastGood = state.value;
    state = AsyncValue.data(
      PointWallet(
        balance: balance,
        timeZone: lastGood?.timeZone ?? 'UTC',
        updatedAt:
            lastGood?.updatedAt ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      ),
    );
    unawaited(refresh());
  }

  void pollForServerVerification({
    int maxAttempts = 6,
    Duration interval = const Duration(seconds: 3),
  }) {
    var attempts = 0;
    Timer.periodic(interval, (timer) async {
      attempts++;
      if (_disposed || attempts > maxAttempts) {
        timer.cancel();
        return;
      }
      await refresh();
    });
  }

  Future<void> _establishWatch(int generation) async {
    final repository = _repository;
    final userId = _userId;
    if (repository == null || userId == null) return;
    if (!_scopeIsCurrent(repository, userId, generation)) return;

    await _walletSubscription?.cancel();
    _walletSubscription = null;
    if (!_scopeIsCurrent(repository, userId, generation)) return;

    _walletSubscription = repository
        .watchWallet(userId)
        .listen(
          (wallet) {
            if (!_scopeIsCurrent(repository, userId, generation)) return;
            final pendingBalance = _pendingAuthoritativeBalance;
            if (pendingBalance != null) {
              if (wallet == null || wallet.balance != pendingBalance) return;
              _acceptCanonical(wallet, clearMutationGate: true);
              return;
            }
            _acceptCanonical(wallet);
          },
          onError: (Object error, StackTrace stackTrace) {
            if (!_scopeIsCurrent(repository, userId, generation)) return;
            if (state.value == null) {
              state = AsyncValue.error(error, stackTrace);
            }
          },
        );
  }

  bool _scopeIsCurrent(
    MonetizationRepository repository,
    String userId,
    int generation,
  ) {
    return !_disposed &&
        identical(repository, _repository) &&
        userId == _userId &&
        generation == _scopeGeneration &&
        repository.currentUserId == userId;
  }

  bool _acceptCanonical(PointWallet? wallet, {bool clearMutationGate = false}) {
    if (wallet == null) {
      if (state.value == null && _pendingAuthoritativeBalance == null) {
        state = const AsyncValue.data(null);
      }
      return false;
    }

    final lastUpdatedAt = _lastCanonicalUpdatedAt;
    if (lastUpdatedAt != null && wallet.updatedAt.isBefore(lastUpdatedAt)) {
      return false;
    }
    final current = state.value;
    if (lastUpdatedAt != null &&
        wallet.updatedAt.isAtSameMomentAs(lastUpdatedAt) &&
        current != null &&
        current.balance != wallet.balance) {
      return false;
    }

    _lastCanonicalUpdatedAt = wallet.updatedAt;
    state = AsyncValue.data(wallet);
    if (clearMutationGate) _pendingAuthoritativeBalance = null;
    return true;
  }
}

final monetizationConfigProvider = StreamProvider<MonetizationConfig>((ref) {
  final repository = ref.watch(monetizationRepositoryProvider);
  if (repository == null) {
    return Stream.value(const MonetizationConfig.failClosed());
  }
  return repository.watchConfig();
});

final pendingRewardClaimsProvider = FutureProvider<List<PendingRewardClaim>>((
  ref,
) async {
  ref.watch(authSessionProvider);
  final repository = ref.watch(monetizationRepositoryProvider);
  final userId = repository?.currentUserId;
  if (repository == null || userId == null) return const [];
  return repository.fetchPendingRewardClaims(userId);
});
