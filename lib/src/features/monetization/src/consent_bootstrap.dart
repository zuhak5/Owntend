part of '../monetization.dart';

class ConsentSnapshot {
  const ConsentSnapshot({
    required this.canRequestAds,
    required this.privacyOptionsRequired,
    required this.updated,
  });

  const ConsentSnapshot.initial()
    : canRequestAds = false,
      privacyOptionsRequired = false,
      updated = false;

  final bool canRequestAds;
  final bool privacyOptionsRequired;
  final bool updated;
}

class OwntendConsentService {
  OwntendConsentService({ConsentRequestParameters? requestParameters})
    : _requestParameters = requestParameters ?? ConsentRequestParameters();

  final ConsentRequestParameters _requestParameters;
  final _states = StreamController<ConsentSnapshot>.broadcast();
  ConsentSnapshot _current = const ConsentSnapshot.initial();
  bool _started = false;

  Stream<ConsentSnapshot> get states async* {
    yield _current;
    yield* _states.stream;
  }

  Future<void> initialize() async {
    if (_started || !_supportsMobileAds) return;
    _started = true;
    final completion = Completer<void>();
    Future<void> finishRefresh() async {
      try {
        await _refresh();
      } on Object catch (error) {
        AppLogger.warning('ad_consent_refresh', error: error);
        _current = const ConsentSnapshot.initial();
        _states.add(_current);
      } finally {
        if (!completion.isCompleted) completion.complete();
      }
    }

    try {
      ConsentInformation.instance.requestConsentInfoUpdate(
        _requestParameters,
        () async {
          try {
            await ConsentForm.loadAndShowConsentFormIfRequired((error) {
              if (error != null) {
                AppLogger.warning('ad_consent_form', error: error);
              }
            });
          } on Object catch (error) {
            AppLogger.warning('ad_consent_form', error: error);
          } finally {
            await finishRefresh();
          }
        },
        (error) async {
          AppLogger.warning('ad_consent_update', error: error);
          await finishRefresh();
        },
      );
    } on Object catch (error) {
      AppLogger.warning('ad_consent_update', error: error);
      await finishRefresh();
    }
    try {
      await completion.future.timeout(
        const Duration(seconds: 15),
        onTimeout: () async {
          AppLogger.warning('ad_consent_timeout');
          await finishRefresh();
        },
      );
    } catch (_) {}
  }

  Future<void> showPrivacyOptions() async {
    if (!_supportsMobileAds) return;
    await ConsentForm.showPrivacyOptionsForm((error) {
      if (error != null) AppLogger.warning('ad_privacy_options', error: error);
    });
    await _refresh();
  }

  Future<void> _refresh() async {
    final canRequestAds = await ConsentInformation.instance.canRequestAds();
    final privacyStatus = await ConsentInformation.instance
        .getPrivacyOptionsRequirementStatus();
    _current = ConsentSnapshot(
      canRequestAds: canRequestAds,
      privacyOptionsRequired:
          privacyStatus == PrivacyOptionsRequirementStatus.required,
      updated: true,
    );
    _states.add(_current);
  }

  void dispose() => _states.close();
}

final owntendAdsProvider = Provider<OwntendAdsService>((ref) {
  final config = ref.watch(appConfigProvider);
  final repository = ref.watch(monetizationRepositoryProvider);
  final service = OwntendAdsService(
    useProductionUnits: config.environment == AppEnvironment.prod,
    testDeviceIds: config.adMobTestDeviceIds,
    adInspectorEnabled: config.environment != AppEnvironment.prod,
    repository: repository,
  );
  ref.onDispose(service.dispose);
  return service;
});

final consentServiceProvider = Provider<OwntendConsentService>((ref) {
  final config = ref.watch(appConfigProvider);
  final service = OwntendConsentService(
    requestParameters: ConsentRequestParameters(
      consentDebugSettings: consentDebugSettingsForAppConfig(config),
    ),
  );
  ref.onDispose(service.dispose);
  return service;
});

final consentSnapshotProvider = StreamProvider<ConsentSnapshot>((ref) {
  return ref.watch(consentServiceProvider).states;
});

class MonetizationBootstrap extends ConsumerStatefulWidget {
  const MonetizationBootstrap({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<MonetizationBootstrap> createState() =>
      _MonetizationBootstrapState();
}

class _MonetizationBootstrapState extends ConsumerState<MonetizationBootstrap>
    with WidgetsBindingObserver {
  AppLifecycleState _lifecycleState = AppLifecycleState.detached;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _lifecycleState =
        WidgetsBinding.instance.lifecycleState ?? AppLifecycleState.detached;
    ref.listenManual(pointWalletProvider, (_, _) {});
    ref.listenManual(monetizationConfigProvider, (_, _) => _applyRuntime());
    ref.listenManual(consentSnapshotProvider, (_, _) => _applyRuntime());
    scheduleMicrotask(() async {
      await ref.read(completionAdCoordinatorProvider).initializeSession();
      await ref.read(consentServiceProvider).initialize();
      _applyRuntime();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycleState = state;
    _applyRuntime();
    if (state == AppLifecycleState.resumed) {
      unawaited(ref.read(pointWalletControllerProvider.notifier).reconnect());
    }
  }

  void _applyRuntime() {
    if (!mounted) return;
    final config =
        ref.read(monetizationConfigProvider).value ??
        const MonetizationConfig.failClosed();
    final consent =
        ref.read(consentSnapshotProvider).value ??
        const ConsentSnapshot.initial();
    unawaited(
      ref
          .read(owntendAdsProvider)
          .applyEligibility(
            AdRuntimeEligibility(
              platformSupported: _supportsMobileAds,
              appResumed: _lifecycleState == AppLifecycleState.resumed,
              consentUpdated: consent.updated,
              canRequestAds: consent.canRequestAds,
              adsEnabled: config.adsEnabled,
              nativeAdsEnabled: config.nativeAdsEnabled,
              interstitialAdsEnabled: config.interstitialAdsEnabled,
              rewardedAdsEnabled: config.rewardedAdsEnabled,
              rewardedInterstitialEnabled: config.rewardedInterstitialEnabled,
            ),
          ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
