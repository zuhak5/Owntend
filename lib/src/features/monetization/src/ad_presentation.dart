part of '../monetization.dart';

const _nativeFactoryId = 'owntendNative';
const _firstSessionStorageKey = 'monetization_has_completed_session_v1';

enum RewardAdType { rewardedAd, rewardedInterstitial }

enum RewardShowResult {
  shownAwaitingServerVerification,
  unavailable,
  rejected,
  dismissed,
}

enum AdInspectorOpenResult { opened, unavailable, failed }

@visibleForTesting
Duration adRetryDelayForFailure(int failureCount) {
  if (failureCount <= 0 || failureCount > 4) return Duration.zero;
  const seconds = [2, 8, 30, 60];
  return Duration(seconds: seconds[failureCount - 1]);
}

@visibleForTesting
AdLoadFailureKind classifyAdLoadFailure({
  required int code,
  required String domain,
}) {
  final normalizedDomain = domain.toLowerCase();
  if (code == 1) return AdLoadFailureKind.invalidRequest;
  if (code == 2) return AdLoadFailureKind.network;
  if (code == 3) return AdLoadFailureKind.noFill;
  if (code == 0 || normalizedDomain.contains('internal')) {
    return AdLoadFailureKind.internal;
  }
  return AdLoadFailureKind.unknown;
}

@visibleForTesting
bool rewardPresentationIsCurrent({
  required bool disposed,
  required int requestGeneration,
  required int currentGeneration,
  required bool formatAllowed,
}) => !disposed && requestGeneration == currentGeneration && formatAllowed;

Timer _defaultAdTimer(Duration delay, void Function() callback) =>
    Timer(delay, callback);

double _defaultAdJitter() => math.Random().nextDouble();

@visibleForTesting
bool nativeAdPlacementEnabled({
  required bool routeIsCurrent,
  required bool configEnabled,
  required bool consentGranted,
  required bool adsInitialized,
  required bool platformSupported,
  bool presentationSuppressed = false,
  bool? enabledOverride,
}) =>
    routeIsCurrent &&
    !presentationSuppressed &&
    enabledOverride != false &&
    configEnabled &&
    consentGranted &&
    adsInitialized &&
    platformSupported;

@visibleForTesting
ConsentDebugSettings? consentDebugSettingsForAppConfig(AppConfig config) {
  final debugGeography = switch (config.adConsentDebugGeography) {
    AdConsentDebugGeography.eea => DebugGeography.debugGeographyEea,
    AdConsentDebugGeography.regulatedUsState =>
      DebugGeography.debugGeographyRegulatedUsState,
    AdConsentDebugGeography.other => DebugGeography.debugGeographyOther,
    null => null,
  };
  final testIdentifiers = config.adMobTestDeviceIds.isEmpty
      ? null
      : List<String>.unmodifiable(config.adMobTestDeviceIds);
  if (debugGeography == null && testIdentifiers == null) {
    return null;
  }
  return ConsentDebugSettings(
    debugGeography: debugGeography,
    testIdentifiers: testIdentifiers,
  );
}

@visibleForTesting
RequestConfiguration adRequestConfiguration({
  required List<String> testDeviceIds,
}) {
  return RequestConfiguration(
    maxAdContentRating: MaxAdContentRating.pg,
    ageRestrictedTreatment: AgeRestrictedTreatment.unspecified,
    testDeviceIds: testDeviceIds,
  );
}

final nativeAdPresentationDepthProvider =
    NotifierProvider<NativeAdPresentationDepth, int>(
      NativeAdPresentationDepth.new,
    );

class NativeAdPresentationDepth extends Notifier<int> {
  @override
  int build() => 0;

  void push() => state++;

  void pop() => state = (state - 1).clamp(0, 1 << 20);

  void popAfterWidgetTeardown() {
    scheduleMicrotask(() {
      if (ref.mounted) pop();
    });
  }
}

Future<T> runWithNativeAdsSuspended<T>(
  BuildContext context,
  Future<T> Function() action,
) async {
  final presentationDepth = ProviderScope.containerOf(context)
      .read(nativeAdPresentationDepthProvider.notifier);
  presentationDepth.push();
  try {
    if (Platform.isAndroid) {
      // Android platform views are torn down at the end of the frame. Waiting
      // before pushing an overlay prevents the disposed native view from
      // receiving the overlay's first gesture. Other platforms do not need
      // this delay, which also keeps host-side widget interactions immediate.
      await WidgetsBinding.instance.endOfFrame;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    return await action();
  } finally {
    presentationDepth.pop();
  }
}

const _systemUiChannel = MethodChannel('owntend/system_ui');

Future<String?> resolveSystemRewardTimeZone(String? fallback) async {
  if (!_supportsMobileAds || !Platform.isAndroid) return fallback;
  try {
    final value = await _systemUiChannel.invokeMethod<String>('getTimeZoneId');
    final timeZone = value?.trim();
    return timeZone == null || timeZone.isEmpty ? fallback : timeZone;
  } on Object catch (error) {
    AppLogger.warning('reward_time_zone_lookup', error: error);
    return fallback;
  }
}
