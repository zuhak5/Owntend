part of '../monetization.dart';

class HkNativeAdCard extends ConsumerStatefulWidget {
  const HkNativeAdCard({
    required this.placement,
    this.enabledOverride,
    super.key,
  });

  final String placement;
  final bool? enabledOverride;

  @override
  ConsumerState<HkNativeAdCard> createState() => _HkNativeAdCardState();
}

class _HkNativeAdCardState extends ConsumerState<HkNativeAdCard> {
  StreamSubscription<int>? _adsSubscription;
  OwntendAdsService? _ads;
  AdLease<NativeAd>? _displayLease;
  AdLease<NativeAd>? _pendingLease;
  DateTime? _loadedAt;
  int? _pendingRuntimeGeneration;
  int _requestGeneration = 0;
  bool _enabled = false;
  bool _failed = false;
  bool _syncScheduled = false;
  int _loadFailures = 0;
  String? _themeIdentity;
  Timer? _expiryTimer;
  Timer? _retryTimer;

  @override
  void initState() {
    super.initState();
    ref.listenManual(owntendAdsProvider, (_, next) => _bindAds(next));
    ref.listenManual(nativeAdPresentationDepthProvider, (_, _) {
      _scheduleSynchronize();
    });
    scheduleMicrotask(() => _bindAds(ref.read(owntendAdsProvider)));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scheduleSynchronize();
  }

  @override
  void didUpdateWidget(covariant HkNativeAdCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.placement != widget.placement ||
        oldWidget.enabledOverride != widget.enabledOverride) {
      _deactivate();
    }
    _scheduleSynchronize();
  }

  @override
  void dispose() {
    _requestGeneration++;
    _adsSubscription?.cancel();
    _expiryTimer?.cancel();
    _retryTimer?.cancel();
    _displayLease?.release();
    _pendingLease?.release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return HkNativeAdSlotFrame(
      collapsed: !_enabled || _failed,
      bottomSpacing: HkSpacing.sm,
      child: _displayLease != null
          ? ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: AdWidget(ad: _displayLease!.value),
            )
          : const HkNativeAdLoadingSkeleton(),
    );
  }

  void _bindAds(OwntendAdsService ads) {
    if (identical(_ads, ads)) return;
    _adsSubscription?.cancel();
    _ads = ads;
    _adsSubscription = ads.states.listen((_) => _scheduleSynchronize());
    _deactivate();
    _scheduleSynchronize();
  }

  void _scheduleSynchronize() {
    if (!mounted || _syncScheduled) return;
    _syncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncScheduled = false;
      if (mounted) _synchronize();
    });
  }

  void _synchronize() {
    final ads = _ads;
    if (ads == null) return;
    final routeIsCurrent = ModalRoute.isCurrentOf(context) ?? true;
    final presentationSuppressed =
        ref.read(nativeAdPresentationDepthProvider) > 0;
    final enabled = nativeAdPlacementEnabled(
      routeIsCurrent: routeIsCurrent,
      presentationSuppressed: presentationSuppressed,
      configEnabled: ads.eligibility.adsEnabled,
      consentGranted:
          ads.eligibility.consentUpdated && ads.eligibility.canRequestAds,
      adsInitialized: ads.allows(AdFormat.native),
      platformSupported: ads.eligibility.platformSupported,
      enabledOverride: widget.enabledOverride,
    );
    final palette = _nativePalette(Theme.of(context).colorScheme);
    final themeIdentity = palette.entries
        .map((entry) => '${entry.key}:${entry.value}')
        .join('|');

    if (!enabled) {
      _deactivate();
      return;
    }

    var needsReplacement =
        _themeIdentity != null && _themeIdentity != themeIdentity;
    if (_loadedAt case final loadedAt?) {
      needsReplacement =
          needsReplacement || ads.now().difference(loadedAt) >= kAdCacheMaxAge;
    }
    if (_pendingLease != null &&
        _pendingRuntimeGeneration != ads.runtimeGeneration) {
      needsReplacement = true;
    }
    if (needsReplacement) {
      _requestGeneration++;
      _expiryTimer?.cancel();
      _expiryTimer = null;
      _retryTimer?.cancel();
      _retryTimer = null;
      _displayLease?.release();
      _pendingLease?.release();
      _displayLease = null;
      _pendingLease = null;
      _loadedAt = null;
      _pendingRuntimeGeneration = null;
      _failed = false;
      _loadFailures = 0;
    }
    _themeIdentity = themeIdentity;
    if (!_enabled || needsReplacement) {
      setState(() => _enabled = true);
    }
    if (_displayLease == null &&
        _pendingLease == null &&
        _retryTimer?.isActive != true) {
      unawaited(_load(ads, themeIdentity, palette));
    }
  }

  Future<void> _load(
    OwntendAdsService ads,
    String themeIdentity,
    Map<String, Object> palette,
  ) async {
    if (!mounted || !ads.allows(AdFormat.native)) return;
    final repository = ref.read(monetizationRepositoryProvider);
    final runtimeGeneration = ads.runtimeGeneration;
    final requestGeneration = ++_requestGeneration;
    late final NativeAd request;
    late final AdLease<NativeAd> lease;
    request = NativeAd(
      adUnitId: ads.units.native(widget.placement),
      factoryId: _nativeFactoryId,
      customOptions: {
        'schemaVersion': 1,
        'isDark': Theme.of(context).brightness == Brightness.dark,
        'placement': widget.placement,
        ...palette,
      },
      request: const AdRequest(),
      listener: NativeAdListener(
        onAdLoaded: (loadedAd) {
          final currentRequest = identical(_pendingLease, lease);
          if (currentRequest) {
            _pendingLease = null;
            _pendingRuntimeGeneration = null;
          }
          if (!currentRequest ||
              !_requestIsCurrent(
                ads,
                runtimeGeneration,
                requestGeneration,
                themeIdentity,
              )) {
            lease.release();
            return;
          }
          _retryTimer?.cancel();
          _retryTimer = null;
          _loadFailures = 0;
          final loadedAt = ads.now();
          setState(() {
            _displayLease = lease;
            _loadedAt = loadedAt;
            _failed = false;
          });
          _scheduleExpiry(
            ads: ads,
            lease: lease,
            loadedAt: loadedAt,
            runtimeGeneration: runtimeGeneration,
            requestGeneration: requestGeneration,
            themeIdentity: themeIdentity,
          );
        },
        onAdFailedToLoad: (failedAd, error) {
          final currentRequest = identical(_pendingLease, lease);
          if (currentRequest) {
            _pendingLease = null;
            _pendingRuntimeGeneration = null;
          }
          lease.release();
          if (!currentRequest ||
              !_requestIsCurrent(
                ads,
                runtimeGeneration,
                requestGeneration,
                themeIdentity,
              )) {
            return;
          }
          _handleNativeFailure(
            ads,
            runtimeGeneration,
            requestGeneration,
            themeIdentity,
            classifyAdLoadFailure(code: error.code, domain: error.domain),
          );
        },
        onAdImpression: (_) {
          unawaited(
            repository?.recordEvent('ad_native_impression', {
              'screen_name': widget.placement,
              'ad_unit_id': ads.units.native(widget.placement),
            }),
          );
        },
        onAdClicked: (_) {
          unawaited(
            repository?.recordEvent('ad_native_click', {
              'screen_name': widget.placement,
              'ad_unit_id': ads.units.native(widget.placement),
            }),
          );
        },
      ),
    );
    lease = AdLease<NativeAd>(request, (ad) => ad.dispose());
    _pendingLease = lease;
    _pendingRuntimeGeneration = runtimeGeneration;
    try {
      await request.load();
    } on Object catch (error) {
      final currentRequest = identical(_pendingLease, lease);
      if (currentRequest) {
        _pendingLease = null;
        _pendingRuntimeGeneration = null;
      }
      lease.release();
      if (currentRequest &&
          _requestIsCurrent(
            ads,
            runtimeGeneration,
            requestGeneration,
            themeIdentity,
          )) {
        AppLogger.warning('native_ad_load', error: error);
        _handleNativeFailure(
          ads,
          runtimeGeneration,
          requestGeneration,
          themeIdentity,
          AdLoadFailureKind.unknown,
        );
      }
    }
  }

  bool _requestIsCurrent(
    OwntendAdsService ads,
    int runtimeGeneration,
    int requestGeneration,
    String themeIdentity,
  ) =>
      mounted &&
      identical(_ads, ads) &&
      runtimeGeneration == ads.runtimeGeneration &&
      requestGeneration == _requestGeneration &&
      themeIdentity == _themeIdentity &&
      ads.allows(AdFormat.native) &&
      (ModalRoute.isCurrentOf(context) ?? true) &&
      ref.read(nativeAdPresentationDepthProvider) == 0 &&
      widget.enabledOverride != false;

  void _handleNativeFailure(
    OwntendAdsService ads,
    int runtimeGeneration,
    int requestGeneration,
    String themeIdentity,
    AdLoadFailureKind failure,
  ) {
    _loadFailures++;
    final decision = const AdRetryPolicy().decide(
      failure: failure,
      failedAttempt: _loadFailures,
      jitterUnit: _defaultAdJitter(),
    );
    setState(() => _failed = true);
    if (!decision.shouldRetry) return;
    _retryTimer?.cancel();
    _retryTimer = Timer(decision.delay, () {
      _retryTimer = null;
      if (!_requestIsCurrent(
        ads,
        runtimeGeneration,
        requestGeneration,
        themeIdentity,
      )) {
        return;
      }
      setState(() => _failed = false);
      _scheduleSynchronize();
    });
  }

  void _scheduleExpiry({
    required OwntendAdsService ads,
    required AdLease<NativeAd> lease,
    required DateTime loadedAt,
    required int runtimeGeneration,
    required int requestGeneration,
    required String themeIdentity,
  }) {
    _expiryTimer?.cancel();
    _expiryTimer = Timer(kAdCacheMaxAge, () {
      _expiryTimer = null;
      if (!mounted ||
          !identical(_ads, ads) ||
          !identical(_displayLease, lease) ||
          _loadedAt != loadedAt ||
          runtimeGeneration != ads.runtimeGeneration ||
          requestGeneration != _requestGeneration ||
          themeIdentity != _themeIdentity) {
        return;
      }

      final shouldReload = _requestIsCurrent(
        ads,
        runtimeGeneration,
        requestGeneration,
        themeIdentity,
      );
      _requestGeneration++;
      _displayLease = null;
      _loadedAt = null;
      _loadFailures = 0;
      lease.release();
      setState(() {
        _enabled = shouldReload;
        _failed = false;
      });
      if (shouldReload) _scheduleSynchronize();
    });
  }

  Map<String, Object> _nativePalette(ColorScheme scheme) => {
    'backgroundColor': _nativeHex(scheme.surfaceContainerLowest),
    'borderColor': _nativeHex(scheme.outlineVariant),
    'headlineColor': _nativeHex(scheme.onSurface),
    'bodyColor': _nativeHex(scheme.onSurfaceVariant),
    'advertiserColor': _nativeHex(scheme.onSurfaceVariant),
    'sponsoredColor': _nativeHex(scheme.onSurfaceVariant),
    'adBadgeBackgroundColor': _nativeHex(scheme.primaryContainer),
    'adBadgeTextColor': _nativeHex(scheme.onPrimaryContainer),
    'callToActionBackgroundColor': _nativeHex(scheme.primary),
    'callToActionTextColor': _nativeHex(scheme.onPrimary),
  };

  String _nativeHex(Color color) =>
      '#${color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';

  void _deactivate() {
    final hadVisibleState =
        _enabled || _failed || _displayLease != null || _pendingLease != null;
    _requestGeneration++;
    _expiryTimer?.cancel();
    _expiryTimer = null;
    _retryTimer?.cancel();
    _retryTimer = null;
    _displayLease?.release();
    _pendingLease?.release();
    _displayLease = null;
    _pendingLease = null;
    _loadedAt = null;
    _pendingRuntimeGeneration = null;
    _enabled = false;
    _failed = false;
    _loadFailures = 0;
    if (mounted && hadVisibleState) setState(() {});
  }
}

class HkNativeAdLoadingSkeleton extends StatelessWidget {
  const HkNativeAdLoadingSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final placeholder = scheme.onSurfaceVariant.withValues(alpha: 0.14);
    return ExcludeSemantics(
      child: DecoratedBox(
        key: const ValueKey('native-ad-loading-skeleton'),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              _NativeAdSkeletonBlock(
                width: 64,
                height: 64,
                color: placeholder,
                radius: 12,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _NativeAdSkeletonBlock(
                      width: 132,
                      height: 12,
                      color: placeholder,
                    ),
                    const SizedBox(height: 8),
                    _NativeAdSkeletonBlock(
                      width: double.infinity,
                      height: 8,
                      color: placeholder,
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: _NativeAdSkeletonBlock(
                            width: double.infinity,
                            height: 8,
                            color: placeholder,
                          ),
                        ),
                        const SizedBox(width: 16),
                        _NativeAdSkeletonBlock(
                          width: 82,
                          height: 28,
                          color: placeholder,
                          radius: 8,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NativeAdSkeletonBlock extends StatelessWidget {
  const _NativeAdSkeletonBlock({
    required this.width,
    required this.height,
    required this.color,
    this.radius = 4,
  });

  final double width;
  final double height;
  final Color color;
  final double radius;

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    height: height,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(radius),
    ),
  );
}

class HkNativeAdSlotFrame extends StatelessWidget {
  const HkNativeAdSlotFrame({
    required this.collapsed,
    required this.child,
    this.bottomSpacing = 0,
    super.key,
  });

  final bool collapsed;
  final Widget child;
  final double bottomSpacing;

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 180),
      child: SizedBox(
        height: collapsed ? 0 : 112 + bottomSpacing,
        width: double.infinity,
        child: collapsed
            ? null
            : Padding(
                padding: EdgeInsets.only(bottom: bottomSpacing),
                child: child,
              ),
      ),
    );
  }
}
