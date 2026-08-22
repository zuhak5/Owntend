part of '../monetization.dart';

class OwntendAdUnits {
  const OwntendAdUnits({required this.production});

  final bool production;

  String native(String placement) {
    if (!production) return 'ca-app-pub-3940256099942544/2247696110';
    return switch (placement) {
      'home' => 'ca-app-pub-5274007212820203/8393243294',
      'assets' ||
      'room_detail' ||
      'thing_detail' ||
      'task_detail' ||
      'maintenance' ||
      'calendar' ||
      'more' ||
      'search' ||
      'notifications' ||
      'statistics' ||
      'account' ||
      'backup' ||
      'trash' ||
      'settings' ||
      'permission_setup' => 'ca-app-pub-5274007212820203/7543196051',
      _ => throw ArgumentError.value(placement, 'placement'),
    };
  }

  String get interstitial => production
      ? 'ca-app-pub-5274007212820203/3851363056'
      : 'ca-app-pub-3940256099942544/1033173712';

  String get rewarded => production
      ? 'ca-app-pub-5274007212820203/4541482404'
      : 'ca-app-pub-3940256099942544/5224354917';

  String get rewardedInterstitial => production
      ? 'ca-app-pub-5274007212820203/7295784043'
      : 'ca-app-pub-3940256099942544/5354046379';
}

class OwntendAdsService {
  OwntendAdsService({
    required this.useProductionUnits,
    required this.testDeviceIds,
    required this.adInspectorEnabled,
    required this.repository,
    this.timeZoneResolver = resolveSystemRewardTimeZone,
    DateTime Function()? now,
    this._retryPolicy = const AdRetryPolicy(),
    double Function()? jitterUnit,
    Timer Function(Duration, void Function())? timerFactory,
  }) : units = OwntendAdUnits(production: useProductionUnits),
       now = now ?? DateTime.now,
       _jitterUnit = jitterUnit ?? _defaultAdJitter,
       _timerFactory = timerFactory ?? _defaultAdTimer;

  final bool useProductionUnits;
  final List<String> testDeviceIds;
  final bool adInspectorEnabled;
  final MonetizationRepository? repository;
  final Future<String?> Function(String? fallback) timeZoneResolver;
  final DateTime Function() now;
  final OwntendAdUnits units;
  final AdRetryPolicy _retryPolicy;
  final double Function() _jitterUnit;
  final Timer Function(Duration, void Function()) _timerFactory;
  final AdRuntimeController _runtime = AdRuntimeController();
  final FullScreenAdGate _fullScreenGate = FullScreenAdGate();
  final StreamController<int> _states = StreamController<int>.broadcast();

  bool _initialized = false;
  bool _disposed = false;
  Future<void>? _initialization;
  int? _preloadingGeneration;
  int? _interstitialLoadGeneration;
  int? _rewardedLoadGeneration;
  int? _rewardedInterstitialLoadGeneration;
  int _interstitialFailures = 0;
  int _rewardedFailures = 0;
  int _rewardedInterstitialFailures = 0;
  Timer? _interstitialRetry;
  Timer? _rewardedRetry;
  Timer? _rewardedInterstitialRetry;
  CachedAd<InterstitialAd>? _interstitial;
  CachedAd<RewardedAd>? _rewarded;
  CachedAd<RewardedInterstitialAd>? _rewardedInterstitial;

  bool get initialized => _initialized;
  int get runtimeGeneration => _runtime.generation;
  AdRuntimeEligibility get eligibility => _runtime.current;
  Stream<int> get states => _states.stream;
  bool allows(AdFormat format) =>
      !_disposed && _initialized && _runtime.current.allows(format);
  bool get canOpenAdInspector =>
      !_disposed && _initialized && adInspectorEnabled && _supportsMobileAds;

  Future<void> applyEligibility(AdRuntimeEligibility eligibility) async {
    if (_disposed) return;
    final transition = _runtime.apply(eligibility);
    if (!transition.changed) return;
    _notifyState();

    _cancelRetries();
    _interstitialFailures = 0;
    _rewardedFailures = 0;
    _rewardedInterstitialFailures = 0;
    _preloadingGeneration = null;
    _interstitialLoadGeneration = null;
    _rewardedLoadGeneration = null;
    _rewardedInterstitialLoadGeneration = null;
    _disposeBlockedCaches();

    if (!eligibility.sdkEligible) return;
    try {
      await initialize();
    } on Object catch (error) {
      AppLogger.warning('ad_sdk_initialize', error: error);
      return;
    }
    if (_disposed || transition.generation != _runtime.generation) return;
    _notifyState();
    await preloadFullScreenAds();
  }

  Future<void> initialize() async {
    if (_initialized || _disposed || !_supportsMobileAds) return;
    final existing = _initialization;
    if (existing != null) {
      await existing;
      return;
    }
    late final Future<void> attempt;
    attempt = _initializeSdk();
    _initialization = attempt;
    try {
      await attempt;
    } on Object {
      if (identical(_initialization, attempt)) _initialization = null;
      rethrow;
    }
  }

  Future<void> _initializeSdk() async {
    if (useProductionUnits && testDeviceIds.isNotEmpty) {
      throw StateError(
        'Production ads cannot initialize with test devices configured.',
      );
    }
    await MobileAds.instance.updateRequestConfiguration(
      adRequestConfiguration(testDeviceIds: testDeviceIds),
    );
    await MobileAds.instance.initialize();
    if (!_disposed) _initialized = true;
  }

  Future<AdInspectorOpenResult> openAdInspector() async {
    if (!canOpenAdInspector) return AdInspectorOpenResult.unavailable;
    try {
      MobileAds.instance.openAdInspector((error) {
        if (error != null) {
          AppLogger.warning(
            'ad_inspector_closed',
            fields: {
              'code': error.code,
              'domain': error.domain,
              'message': error.message,
            },
          );
        } else {
          AppLogger.info('ad_inspector_closed');
        }
      });
      return AdInspectorOpenResult.opened;
    } on Object catch (error, stackTrace) {
      AppLogger.warning(
        'ad_inspector_open',
        error: error,
        stackTrace: stackTrace,
      );
      return AdInspectorOpenResult.failed;
    }
  }

  Future<void> preloadFullScreenAds() async {
    if (!_initialized || _disposed) return;
    final generation = _runtime.generation;
    if (_preloadingGeneration == generation) return;
    _preloadingGeneration = generation;
    try {
      await Future.wait([
        if (_runtime.current.allows(AdFormat.interstitial)) _loadInterstitial(),
        if (_runtime.current.allows(AdFormat.rewarded)) _loadRewarded(),
        if (_runtime.current.allows(AdFormat.rewardedInterstitial))
          _loadRewardedInterstitial(),
      ]);
    } finally {
      if (_preloadingGeneration == generation) {
        _preloadingGeneration = null;
      }
    }
  }

  Future<bool> showInterstitial({
    Map<String, dynamic> analyticsProperties = const {},
  }) async {
    if (!allows(AdFormat.interstitial)) return false;
    final fullScreenLease = _fullScreenGate.tryAcquire();
    if (fullScreenLease == null) return false;
    final ad = _takeFreshInterstitial();
    if (ad == null) {
      fullScreenLease.release();
      unawaited(_loadInterstitial());
      return false;
    }
    final completion = Completer<bool>();
    var finished = false;

    void finish(InterstitialAd finishedAd, bool shown) {
      if (finished) return;
      finished = true;
      finishedAd.dispose();
      fullScreenLease.release();
      if (!completion.isCompleted) completion.complete(shown);
      if (allows(AdFormat.interstitial)) unawaited(_loadInterstitial());
    }

    ad.fullScreenContentCallback = FullScreenContentCallback<InterstitialAd>(
      onAdShowedFullScreenContent: (_) {
        AppLogger.info('ad_impression', fields: {'ad_type': 'interstitial'});
        unawaited(
          repository?.recordEvent('ad_interstitial_shown', analyticsProperties),
        );
      },
      onAdDismissedFullScreenContent: (shownAd) => finish(shownAd, true),
      onAdFailedToShowFullScreenContent: (failedAd, error) {
        AppLogger.warning('interstitial_show', error: error);
        finish(failedAd, false);
      },
    );
    try {
      await ad.show();
    } on Object catch (error) {
      AppLogger.warning('interstitial_show', error: error);
      finish(ad, false);
    }
    return completion.future;
  }

  Future<RewardShowResult> showReward(
    RewardAdType type, {
    required String? timeZone,
    required String entryPoint,
  }) async {
    final format = type == RewardAdType.rewardedAd
        ? AdFormat.rewarded
        : AdFormat.rewardedInterstitial;
    if (!allows(format) || repository == null || !_hasFreshReward(type)) {
      _loadRewardType(type);
      return RewardShowResult.unavailable;
    }
    final fullScreenLease = _fullScreenGate.tryAcquire();
    if (fullScreenLease == null) return RewardShowResult.unavailable;
    final generation = _runtime.generation;

    RewardClaimRequest claim;
    try {
      final resolvedTimeZone = await timeZoneResolver(timeZone);
      claim = await repository!.createRewardClaim(
        type,
        timeZone: resolvedTimeZone,
      );
    } on Object {
      fullScreenLease.release();
      return RewardShowResult.rejected;
    }
    if (_disposed ||
        generation != _runtime.generation ||
        !allows(format) ||
        !_hasFreshReward(type)) {
      fullScreenLease.release();
      return RewardShowResult.unavailable;
    }

    final earned = Completer<bool>();
    final dismissed = Completer<void>();
    var failedToShow = false;
    var finished = false;
    var activeAdDisposed = false;
    void Function()? disposeActiveAd;

    void finish({required bool failed}) {
      if (finished) return;
      finished = true;
      if (failed) failedToShow = true;
      fullScreenLease.release();
      if (!earned.isCompleted && failed) earned.complete(false);
      if (!dismissed.isCompleted) dismissed.complete();
      if (allows(format)) _loadRewardType(type);
    }

    try {
      if (type == RewardAdType.rewardedAd) {
        final ad = _takeFreshRewarded();
        if (ad == null) {
          fullScreenLease.release();
          return RewardShowResult.unavailable;
        }
        disposeActiveAd = () {
          if (activeAdDisposed) return;
          activeAdDisposed = true;
          ad.dispose();
        };
        await ad.setServerSideOptions(
          ServerSideVerificationOptions(
            userId: claim.userId,
            customData: claim.claimId,
          ),
        );
        if (!rewardPresentationIsCurrent(
          disposed: _disposed,
          requestGeneration: generation,
          currentGeneration: _runtime.generation,
          formatAllowed: allows(format),
        )) {
          disposeActiveAd();
          finish(failed: true);
          return RewardShowResult.unavailable;
        }
        ad.fullScreenContentCallback = FullScreenContentCallback<RewardedAd>(
          onAdDismissedFullScreenContent: (shownAd) {
            disposeActiveAd?.call();
            finish(failed: false);
          },
          onAdFailedToShowFullScreenContent: (failedAd, error) {
            AppLogger.warning('rewarded_show', error: error);
            disposeActiveAd?.call();
            finish(failed: true);
          },
        );
        await ad.show(
          onUserEarnedReward: (_, reward) {
            AppLogger.info(
              'ad_rewarded',
              fields: {'ad_type': 'rewarded', 'reward_amount': reward.amount},
            );
            if (!earned.isCompleted) earned.complete(true);
          },
        );
      } else {
        final ad = _takeFreshRewardedInterstitial();
        if (ad == null) {
          fullScreenLease.release();
          return RewardShowResult.unavailable;
        }
        disposeActiveAd = () {
          if (activeAdDisposed) return;
          activeAdDisposed = true;
          ad.dispose();
        };
        await ad.setServerSideOptions(
          ServerSideVerificationOptions(
            userId: claim.userId,
            customData: claim.claimId,
          ),
        );
        if (!rewardPresentationIsCurrent(
          disposed: _disposed,
          requestGeneration: generation,
          currentGeneration: _runtime.generation,
          formatAllowed: allows(format),
        )) {
          disposeActiveAd();
          finish(failed: true);
          return RewardShowResult.unavailable;
        }
        ad.fullScreenContentCallback =
            FullScreenContentCallback<RewardedInterstitialAd>(
              onAdDismissedFullScreenContent: (shownAd) {
                disposeActiveAd?.call();
                finish(failed: false);
              },
              onAdFailedToShowFullScreenContent: (failedAd, error) {
                AppLogger.warning('rewarded_interstitial_show', error: error);
                disposeActiveAd?.call();
                finish(failed: true);
              },
            );
        await ad.show(
          onUserEarnedReward: (_, reward) {
            AppLogger.info(
              'ad_rewarded',
              fields: {
                'ad_type': 'rewarded_interstitial',
                'reward_amount': reward.amount,
              },
            );
            if (!earned.isCompleted) earned.complete(true);
          },
        );
      }
    } on Object catch (error) {
      AppLogger.warning('reward_show', error: error);
      disposeActiveAd?.call();
      finish(failed: true);
    }

    await dismissed.future;
    final wasEarned = earned.isCompleted ? await earned.future : false;
    if (!wasEarned) {
      return failedToShow
          ? RewardShowResult.unavailable
          : RewardShowResult.dismissed;
    }
    unawaited(
      repository!.recordEvent('ad_rewarded_watched', {
        'reward_amount': claim.rewardAmount,
        'entry_point': entryPoint,
        'verification': 'server_pending',
      }),
    );
    AppLogger.info(
      'ad_show_completed',
      fields: {
        'ad_type': type.name,
        'entry_point': entryPoint,
        'verification': 'server_pending',
      },
    );
    return RewardShowResult.shownAwaitingServerVerification;
  }

  Future<void> _loadInterstitial({bool retry = false}) async {
    _discardStaleInterstitial();
    if (!allows(AdFormat.interstitial) ||
        _interstitial != null ||
        _interstitialLoadGeneration != null ||
        (!retry && _interstitialRetry?.isActive == true)) {
      return;
    }
    _interstitialRetry?.cancel();
    _interstitialRetry = null;
    final generation = _runtime.generation;
    _interstitialLoadGeneration = generation;
    final completion = Completer<void>();
    AppLogger.info('ad_load_requested', fields: {'ad_type': 'interstitial'});
    try {
      await InterstitialAd.load(
        adUnitId: units.interstitial,
        request: const AdRequest(),
        adLoadCallback: InterstitialAdLoadCallback(
          onAdLoaded: (ad) {
            if (_interstitialLoadGeneration == generation) {
              _interstitialLoadGeneration = null;
            }
            if (_accepts(generation, AdFormat.interstitial)) {
              _interstitialFailures = 0;
              _interstitial = CachedAd(value: ad, loadedAt: now());
              AppLogger.info('ad_loaded', fields: {'ad_type': 'interstitial'});
            } else {
              ad.dispose();
            }
            if (!completion.isCompleted) completion.complete();
          },
          onAdFailedToLoad: (error) {
            if (_interstitialLoadGeneration == generation) {
              _interstitialLoadGeneration = null;
            }
            AppLogger.warning(
              'ad_load_failed',
              error: error,
              fields: {'ad_type': 'interstitial'},
            );
            _scheduleInterstitialRetry(
              generation,
              classifyAdLoadFailure(code: error.code, domain: error.domain),
            );
            if (!completion.isCompleted) completion.complete();
          },
        ),
      );
    } on Object catch (error) {
      if (_interstitialLoadGeneration == generation) {
        _interstitialLoadGeneration = null;
      }
      AppLogger.warning(
        'ad_load_failed',
        error: error,
        fields: {'ad_type': 'interstitial'},
      );
      _scheduleInterstitialRetry(generation, AdLoadFailureKind.unknown);
      if (!completion.isCompleted) completion.complete();
    }
    await completion.future;
  }

  Future<void> _loadRewarded({bool retry = false}) async {
    _discardStaleRewarded();
    if (!allows(AdFormat.rewarded) ||
        _rewarded != null ||
        _rewardedLoadGeneration != null ||
        (!retry && _rewardedRetry?.isActive == true)) {
      return;
    }
    _rewardedRetry?.cancel();
    _rewardedRetry = null;
    final generation = _runtime.generation;
    _rewardedLoadGeneration = generation;
    final completion = Completer<void>();
    AppLogger.info('ad_load_requested', fields: {'ad_type': 'rewarded'});
    try {
      await RewardedAd.load(
        adUnitId: units.rewarded,
        request: const AdRequest(),
        rewardedAdLoadCallback: RewardedAdLoadCallback(
          onAdLoaded: (ad) {
            if (_rewardedLoadGeneration == generation) {
              _rewardedLoadGeneration = null;
            }
            if (_accepts(generation, AdFormat.rewarded)) {
              _rewardedFailures = 0;
              _rewarded = CachedAd(value: ad, loadedAt: now());
              AppLogger.info('ad_loaded', fields: {'ad_type': 'rewarded'});
            } else {
              ad.dispose();
            }
            if (!completion.isCompleted) completion.complete();
          },
          onAdFailedToLoad: (error) {
            if (_rewardedLoadGeneration == generation) {
              _rewardedLoadGeneration = null;
            }
            AppLogger.warning(
              'ad_load_failed',
              error: error,
              fields: {'ad_type': 'rewarded'},
            );
            _scheduleRewardedRetry(
              generation,
              classifyAdLoadFailure(code: error.code, domain: error.domain),
            );
            if (!completion.isCompleted) completion.complete();
          },
        ),
      );
    } on Object catch (error) {
      if (_rewardedLoadGeneration == generation) {
        _rewardedLoadGeneration = null;
      }
      AppLogger.warning(
        'ad_load_failed',
        error: error,
        fields: {'ad_type': 'rewarded'},
      );
      _scheduleRewardedRetry(generation, AdLoadFailureKind.unknown);
      if (!completion.isCompleted) completion.complete();
    }
    await completion.future;
  }

  Future<void> _loadRewardedInterstitial({bool retry = false}) async {
    _discardStaleRewardedInterstitial();
    if (!allows(AdFormat.rewardedInterstitial) ||
        _rewardedInterstitial != null ||
        _rewardedInterstitialLoadGeneration != null ||
        (!retry && _rewardedInterstitialRetry?.isActive == true)) {
      return;
    }
    _rewardedInterstitialRetry?.cancel();
    _rewardedInterstitialRetry = null;
    final generation = _runtime.generation;
    _rewardedInterstitialLoadGeneration = generation;
    final completion = Completer<void>();
    AppLogger.info(
      'ad_load_requested',
      fields: {'ad_type': 'rewarded_interstitial'},
    );
    try {
      await RewardedInterstitialAd.load(
        adUnitId: units.rewardedInterstitial,
        request: const AdRequest(),
        rewardedInterstitialAdLoadCallback: RewardedInterstitialAdLoadCallback(
          onAdLoaded: (ad) {
            if (_rewardedInterstitialLoadGeneration == generation) {
              _rewardedInterstitialLoadGeneration = null;
            }
            if (_accepts(generation, AdFormat.rewardedInterstitial)) {
              _rewardedInterstitialFailures = 0;
              _rewardedInterstitial = CachedAd(value: ad, loadedAt: now());
              AppLogger.info(
                'ad_loaded',
                fields: {'ad_type': 'rewarded_interstitial'},
              );
            } else {
              ad.dispose();
            }
            if (!completion.isCompleted) completion.complete();
          },
          onAdFailedToLoad: (error) {
            if (_rewardedInterstitialLoadGeneration == generation) {
              _rewardedInterstitialLoadGeneration = null;
            }
            AppLogger.warning(
              'ad_load_failed',
              error: error,
              fields: {'ad_type': 'rewarded_interstitial'},
            );
            _scheduleRewardedInterstitialRetry(
              generation,
              classifyAdLoadFailure(code: error.code, domain: error.domain),
            );
            if (!completion.isCompleted) completion.complete();
          },
        ),
      );
    } on Object catch (error) {
      if (_rewardedInterstitialLoadGeneration == generation) {
        _rewardedInterstitialLoadGeneration = null;
      }
      AppLogger.warning(
        'ad_load_failed',
        error: error,
        fields: {'ad_type': 'rewarded_interstitial'},
      );
      _scheduleRewardedInterstitialRetry(generation, AdLoadFailureKind.unknown);
      if (!completion.isCompleted) completion.complete();
    }
    await completion.future;
  }

  bool _accepts(int generation, AdFormat format) =>
      !_disposed && generation == _runtime.generation && allows(format);

  void _scheduleInterstitialRetry(int generation, AdLoadFailureKind failure) {
    if (!_accepts(generation, AdFormat.interstitial) ||
        _interstitialRetry?.isActive == true) {
      return;
    }
    _interstitialFailures++;
    final decision = _retryPolicy.decide(
      failure: failure,
      failedAttempt: _interstitialFailures,
      jitterUnit: _jitterUnit(),
    );
    if (!decision.shouldRetry) return;
    _interstitialRetry = _timerFactory(decision.delay, () {
      _interstitialRetry = null;
      if (_accepts(generation, AdFormat.interstitial)) {
        unawaited(_loadInterstitial(retry: true));
      }
    });
  }

  void _scheduleRewardedRetry(int generation, AdLoadFailureKind failure) {
    if (!_accepts(generation, AdFormat.rewarded) ||
        _rewardedRetry?.isActive == true) {
      return;
    }
    _rewardedFailures++;
    final decision = _retryPolicy.decide(
      failure: failure,
      failedAttempt: _rewardedFailures,
      jitterUnit: _jitterUnit(),
    );
    if (!decision.shouldRetry) return;
    _rewardedRetry = _timerFactory(decision.delay, () {
      _rewardedRetry = null;
      if (_accepts(generation, AdFormat.rewarded)) {
        unawaited(_loadRewarded(retry: true));
      }
    });
  }

  void _scheduleRewardedInterstitialRetry(
    int generation,
    AdLoadFailureKind failure,
  ) {
    if (!_accepts(generation, AdFormat.rewardedInterstitial) ||
        _rewardedInterstitialRetry?.isActive == true) {
      return;
    }
    _rewardedInterstitialFailures++;
    final decision = _retryPolicy.decide(
      failure: failure,
      failedAttempt: _rewardedInterstitialFailures,
      jitterUnit: _jitterUnit(),
    );
    if (!decision.shouldRetry) return;
    _rewardedInterstitialRetry = _timerFactory(decision.delay, () {
      _rewardedInterstitialRetry = null;
      if (_accepts(generation, AdFormat.rewardedInterstitial)) {
        unawaited(_loadRewardedInterstitial(retry: true));
      }
    });
  }

  void _loadRewardType(RewardAdType type) {
    if (type == RewardAdType.rewardedAd) {
      unawaited(_loadRewarded());
    } else {
      unawaited(_loadRewardedInterstitial());
    }
  }

  bool _hasFreshReward(RewardAdType type) {
    if (type == RewardAdType.rewardedAd) {
      _discardStaleRewarded();
      return _rewarded != null;
    }
    _discardStaleRewardedInterstitial();
    return _rewardedInterstitial != null;
  }

  InterstitialAd? _takeFreshInterstitial() {
    _discardStaleInterstitial();
    final cached = _interstitial;
    _interstitial = null;
    return cached?.value;
  }

  RewardedAd? _takeFreshRewarded() {
    _discardStaleRewarded();
    final cached = _rewarded;
    _rewarded = null;
    return cached?.value;
  }

  RewardedInterstitialAd? _takeFreshRewardedInterstitial() {
    _discardStaleRewardedInterstitial();
    final cached = _rewardedInterstitial;
    _rewardedInterstitial = null;
    return cached?.value;
  }

  void _discardStaleInterstitial() {
    final cached = _interstitial;
    if (cached != null && !cached.isFresh(now())) {
      cached.value.dispose();
      _interstitial = null;
    }
  }

  void _discardStaleRewarded() {
    final cached = _rewarded;
    if (cached != null && !cached.isFresh(now())) {
      cached.value.dispose();
      _rewarded = null;
    }
  }

  void _discardStaleRewardedInterstitial() {
    final cached = _rewardedInterstitial;
    if (cached != null && !cached.isFresh(now())) {
      cached.value.dispose();
      _rewardedInterstitial = null;
    }
  }

  void _disposeBlockedCaches() {
    if (!_runtime.current.allows(AdFormat.interstitial)) {
      _interstitial?.value.dispose();
      _interstitial = null;
    }
    if (!_runtime.current.allows(AdFormat.rewarded)) {
      _rewarded?.value.dispose();
      _rewarded = null;
    }
    if (!_runtime.current.allows(AdFormat.rewardedInterstitial)) {
      _rewardedInterstitial?.value.dispose();
      _rewardedInterstitial = null;
    }
  }

  void _cancelRetries() {
    _interstitialRetry?.cancel();
    _rewardedRetry?.cancel();
    _rewardedInterstitialRetry?.cancel();
    _interstitialRetry = null;
    _rewardedRetry = null;
    _rewardedInterstitialRetry = null;
  }

  void _notifyState() {
    if (!_disposed && !_states.isClosed) _states.add(_runtime.generation);
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _runtime.apply(const AdRuntimeEligibility.blocked());
    _cancelRetries();
    _interstitial?.value.dispose();
    _rewarded?.value.dispose();
    _rewardedInterstitial?.value.dispose();
    _interstitial = null;
    _rewarded = null;
    _rewardedInterstitial = null;
    unawaited(_states.close());
  }
}
