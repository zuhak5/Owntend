import 'package:flutter/foundation.dart';

enum AdFormat { native, interstitial, rewarded, rewardedInterstitial }

@immutable
class AdRuntimeEligibility {
  const AdRuntimeEligibility({
    required this.platformSupported,
    required this.appResumed,
    required this.consentUpdated,
    required this.canRequestAds,
    required this.adsEnabled,
    required this.nativeAdsEnabled,
    required this.interstitialAdsEnabled,
    required this.rewardedAdsEnabled,
    required this.rewardedInterstitialEnabled,
  });

  const AdRuntimeEligibility.blocked()
    : platformSupported = false,
      appResumed = false,
      consentUpdated = false,
      canRequestAds = false,
      adsEnabled = false,
      nativeAdsEnabled = false,
      interstitialAdsEnabled = false,
      rewardedAdsEnabled = false,
      rewardedInterstitialEnabled = false;

  final bool platformSupported;
  final bool appResumed;
  final bool consentUpdated;
  final bool canRequestAds;
  final bool adsEnabled;
  final bool nativeAdsEnabled;
  final bool interstitialAdsEnabled;
  final bool rewardedAdsEnabled;
  final bool rewardedInterstitialEnabled;

  bool get sdkEligible =>
      platformSupported &&
      appResumed &&
      consentUpdated &&
      canRequestAds &&
      adsEnabled;

  bool allows(AdFormat format) {
    if (!sdkEligible) return false;
    return switch (format) {
      AdFormat.native => nativeAdsEnabled,
      AdFormat.interstitial => interstitialAdsEnabled,
      AdFormat.rewarded => rewardedAdsEnabled,
      AdFormat.rewardedInterstitial => rewardedInterstitialEnabled,
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AdRuntimeEligibility &&
          platformSupported == other.platformSupported &&
          appResumed == other.appResumed &&
          consentUpdated == other.consentUpdated &&
          canRequestAds == other.canRequestAds &&
          adsEnabled == other.adsEnabled &&
          nativeAdsEnabled == other.nativeAdsEnabled &&
          interstitialAdsEnabled == other.interstitialAdsEnabled &&
          rewardedAdsEnabled == other.rewardedAdsEnabled &&
          rewardedInterstitialEnabled == other.rewardedInterstitialEnabled;

  @override
  int get hashCode => Object.hash(
    platformSupported,
    appResumed,
    consentUpdated,
    canRequestAds,
    adsEnabled,
    nativeAdsEnabled,
    interstitialAdsEnabled,
    rewardedAdsEnabled,
    rewardedInterstitialEnabled,
  );
}

@immutable
class AdRuntimeTransition {
  const AdRuntimeTransition({
    required this.previous,
    required this.current,
    required this.generation,
    required this.changed,
  });

  final AdRuntimeEligibility previous;
  final AdRuntimeEligibility current;
  final int generation;
  final bool changed;

  bool lost(AdFormat format) =>
      previous.allows(format) && !current.allows(format);

  bool gained(AdFormat format) =>
      !previous.allows(format) && current.allows(format);
}

class AdRuntimeController {
  AdRuntimeEligibility _current = const AdRuntimeEligibility.blocked();
  int _generation = 0;

  AdRuntimeEligibility get current => _current;
  int get generation => _generation;

  AdRuntimeTransition apply(AdRuntimeEligibility next) {
    final previous = _current;
    if (previous == next) {
      return AdRuntimeTransition(
        previous: previous,
        current: next,
        generation: _generation,
        changed: false,
      );
    }
    _current = next;
    _generation++;
    return AdRuntimeTransition(
      previous: previous,
      current: next,
      generation: _generation,
      changed: true,
    );
  }
}
