part of '../monetization.dart';

enum NativeAdVariant {
  standard(112),
  compact(64),
  card(200);

  const NativeAdVariant(this.height);
  final double height;
}

class HkNativeAdCard extends ConsumerStatefulWidget {
  const HkNativeAdCard({
    required this.placement,
    this.variant = NativeAdVariant.standard,
    this.enabledOverride,
    super.key,
  });

  final String placement;
  final NativeAdVariant variant;
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
  ProviderSubscription<OwntendAdsService>? _owntendAdsSubscription;
  ProviderSubscription<int>? _presentationDepthSubscription;

  @override
  void initState() {
    super.initState();
    _owntendAdsSubscription = ref.listenManual(
      owntendAdsProvider,
      (_, next) => _bindAds(next),
    );
    _presentationDepthSubscription = ref.listenManual(
      nativeAdPresentationDepthProvider,
      (_, _) {
        _scheduleSynchronize();
      },
    );
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
        oldWidget.variant != widget.variant ||
        oldWidget.enabledOverride != widget.enabledOverride) {
      _deactivate();
    }
    _scheduleSynchronize();
  }

  @override
  void dispose() {
    _requestGeneration++;
    _owntendAdsSubscription?.close();
    _owntendAdsSubscription = null;
    _presentationDepthSubscription?.close();
    _presentationDepthSubscription = null;
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
      height: widget.variant.height,
      bottomSpacing: HkSpacing.sm,
      child: _displayLease != null
          ? ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: AdWidget(ad: _displayLease!.value),
            )
          : HkNativeAdLoadingSkeleton(variant: widget.variant),
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

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final customOptions = <String, Object>{
      'schemaVersion': 2,
      'layoutVariant': widget.variant.name,
      'cornerRadiusDp': 16.0,
      'isDark': isDark,
      'placement': widget.placement,
      ...palette,
    };

    request = NativeAd(
      adUnitId: ads.units.native(widget.placement),
      factoryId: _nativeFactoryId,
      customOptions: customOptions,
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
  const HkNativeAdLoadingSkeleton({
    this.variant = NativeAdVariant.standard,
    super.key,
  });

  final NativeAdVariant variant;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final placeholder = scheme.onSurfaceVariant.withValues(alpha: 0.14);
    final isCompact = variant == NativeAdVariant.compact;
    final isCard = variant == NativeAdVariant.card;

    return ExcludeSemantics(
      child: DecoratedBox(
        key: const ValueKey('native-ad-loading-skeleton'),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Padding(
          padding: EdgeInsets.all(isCompact ? 10 : 16),
          child: isCard
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _NativeAdSkeletonBlock(
                          width: 48,
                          height: 48,
                          color: placeholder,
                          radius: 10,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _NativeAdSkeletonBlock(
                                width: 120,
                                height: 12,
                                color: placeholder,
                              ),
                              const SizedBox(height: 6),
                              _NativeAdSkeletonBlock(
                                width: 80,
                                height: 10,
                                color: placeholder,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: _NativeAdSkeletonBlock(
                        width: double.infinity,
                        height: double.infinity,
                        color: placeholder,
                      ),
                    ),
                    const SizedBox(height: 10),
                    _NativeAdSkeletonBlock(
                      width: double.infinity,
                      height: 38,
                      color: placeholder,
                      radius: 8,
                    ),
                  ],
                )
              : Row(
                  children: [
                    _NativeAdSkeletonBlock(
                      width: isCompact ? 44 : 64,
                      height: isCompact ? 44 : 64,
                      color: placeholder,
                      radius: isCompact ? 8 : 12,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _NativeAdSkeletonBlock(
                            width: isCompact ? 100 : 132,
                            height: 12,
                            color: placeholder,
                          ),
                          if (!isCompact) ...[
                            const SizedBox(height: 8),
                            _NativeAdSkeletonBlock(
                              width: double.infinity,
                              height: 8,
                              color: placeholder,
                            ),
                          ],
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              if (!isCompact)
                                Expanded(
                                  child: _NativeAdSkeletonBlock(
                                    width: double.infinity,
                                    height: 8,
                                    color: placeholder,
                                  ),
                                ),
                              const Spacer(),
                              _NativeAdSkeletonBlock(
                                width: isCompact ? 64 : 82,
                                height: isCompact ? 24 : 28,
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
    this.height = 112,
    this.bottomSpacing = 0,
    super.key,
  });

  final bool collapsed;
  final Widget child;
  final double height;
  final double bottomSpacing;

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 180),
      child: SizedBox(
        height: collapsed ? 0 : height + bottomSpacing,
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
