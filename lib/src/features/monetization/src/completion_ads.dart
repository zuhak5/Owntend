part of '../monetization.dart';

class InterstitialEligibilityPolicy {
  InterstitialEligibilityPolicy({DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final DateTime Function() _now;
  DateTime? _lastCompletion;
  DateTime? _lastShown;
  int _shownThisSession = 0;
  bool firstEverSession = true;

  bool registerCompletionAndCanShow({
    required MonetizationConfig config,
    required bool keyboardVisible,
    required bool modalActive,
  }) {
    final now = _now();
    final rapid =
        _lastCompletion != null &&
        now.difference(_lastCompletion!).inSeconds <
            config.rapidCompletionWindowSeconds;
    _lastCompletion = now;
    if (firstEverSession ||
        rapid ||
        keyboardVisible ||
        modalActive ||
        !config.adsEnabled ||
        !config.interstitialAdsEnabled ||
        _shownThisSession >= config.interstitialSessionCap) {
      return false;
    }
    if (_lastShown != null &&
        now.difference(_lastShown!).inSeconds <
            config.interstitialCooldownSeconds) {
      return false;
    }
    return true;
  }

  void markShown() {
    _lastShown = _now();
    _shownThisSession++;
  }

  int get nextSessionAdCount => _shownThisSession + 1;
}

class CompletionAdCoordinator {
  CompletionAdCoordinator(this.ads, this.policy);

  final OwntendAdsService ads;
  final InterstitialEligibilityPolicy policy;

  Future<void> initializeSession() async {
    if (!_supportsMobileAds) return;
    const storage = FlutterSecureStorage(
      aOptions: owntendAndroidSecureStorageOptions,
    );
    try {
      final prior = await storage.read(key: _firstSessionStorageKey);
      policy.firstEverSession = prior == null;
      if (prior == null) {
        await storage.write(key: _firstSessionStorageKey, value: 'true');
      }
    } on Object catch (error) {
      AppLogger.warning('completion_ads_session_init_failed', error: error);
      policy.firstEverSession = false;
    }
  }

  Future<bool> onTaskCompleted({
    required MonetizationConfig config,
    required bool keyboardVisible,
    required bool modalActive,
  }) async {
    if (!policy.registerCompletionAndCanShow(
      config: config,
      keyboardVisible: keyboardVisible,
      modalActive: modalActive,
    )) {
      return false;
    }
    final shown = await ads.showInterstitial(
      analyticsProperties: {
        'cooldown_remaining_sec': 0,
        'session_ad_count': policy.nextSessionAdCount,
      },
    );
    if (shown) policy.markShown();
    return shown;
  }
}

final completionAdCoordinatorProvider = Provider<CompletionAdCoordinator>((
  ref,
) {
  return CompletionAdCoordinator(
    ref.watch(owntendAdsProvider),
    InterstitialEligibilityPolicy(),
  );
});
