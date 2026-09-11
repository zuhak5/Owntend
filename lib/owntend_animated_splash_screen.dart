import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:owntend/l10n/app_localizations.dart';

const Color owntendSplashBackground = Color(0xFFF9FCF8);

/// Dark-mode background for all splash and pre-ready surfaces.
///
/// Matches the Android native splash [android:windowSplashScreenBackground]
/// value in values-night-v31/styles.xml. Use this constant everywhere a
/// dark splash background is needed so native and Flutter surfaces stay
/// visually consistent.
const Color owntendSplashBackgroundDark = Color(0xFF0D2118);

const Duration owntendSplashDisplayDuration = Duration(milliseconds: 3200);
const Duration owntendSplashMinDisplayDuration = Duration(milliseconds: 600);
const Duration owntendSplashFadeOutDuration = Duration(milliseconds: 250);

/// Global readiness and failure notifiers allowing domain and startup controllers
/// to signal when bootstrap is ready to dismiss the splash, or when a fatal
/// startup error occurred that warrants immediate splash dismissal.
final ValueNotifier<bool> hkStartupReadyNotifier = ValueNotifier<bool>(false);
final ValueNotifier<bool> hkStartupFailedNotifier = ValueNotifier<bool>(false);

void resetOwntendStartupNotifiers() {
  hkStartupReadyNotifier.value = false;
  hkStartupFailedNotifier.value = false;
}

Locale _supportedSplashLocale(Locale locale) {
  return locale.languageCode == 'ar' ? const Locale('ar') : const Locale('en');
}

TextDirection _splashTextDirection(Locale locale) {
  return locale.languageCode == 'ar' ? TextDirection.rtl : TextDirection.ltr;
}

/// Resolves whether the ambient splash context is dark mode.
/// Prefers the explicit ancestor [Theme] if present; otherwise falls back to
/// [MediaQuery.platformBrightnessOf].
bool _isDarkSplash(BuildContext context) {
  final themeWidget = context.findAncestorWidgetOfExactType<Theme>();
  if (themeWidget != null) {
    return Theme.of(context).brightness == Brightness.dark;
  }
  return MediaQuery.platformBrightnessOf(context) == Brightness.dark;
}

/// Stable, process-lifetime owner for the one Flutter launch splash.
///
/// This host is deliberately independent from application readiness, routing,
/// providers, theme preferences, and authentication. Its state stays mounted
/// while [child] moves through deferred startup and into the real app.
class OwntendProcessSplash extends StatefulWidget {
  const OwntendProcessSplash({
    required this.child,
    this.displayDuration = owntendSplashDisplayDuration,
    this.minDisplayDuration = owntendSplashMinDisplayDuration,
    this.fadeOutDuration = owntendSplashFadeOutDuration,
    this.initialThemeBrightness,
    this.initialLocale,
    this.isReadyNotifier,
    this.isFailedNotifier,
    this.isFailed = false,
    super.key,
  });

  final Widget child;
  final Duration displayDuration;
  final Duration minDisplayDuration;
  final Duration fadeOutDuration;
  final Brightness? initialThemeBrightness;
  final Locale? initialLocale;
  final ValueListenable<bool>? isReadyNotifier;
  final ValueListenable<bool>? isFailedNotifier;
  final bool isFailed;

  @override
  State<OwntendProcessSplash> createState() => _OwntendProcessSplashState();
}

class _OwntendProcessSplashState extends State<OwntendProcessSplash>
    with WidgetsBindingObserver {
  late Locale _deviceLocale;
  late Brightness _brightness;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _deviceLocale =
        widget.initialLocale ??
        WidgetsBinding.instance.platformDispatcher.locale;
    _brightness =
        widget.initialThemeBrightness ??
        WidgetsBinding.instance.platformDispatcher.platformBrightness;
  }

  @override
  void didChangeLocales(List<Locale>? locales) {
    if (widget.initialLocale != null) return;
    final next =
        locales?.firstOrNull ??
        WidgetsBinding.instance.platformDispatcher.locale;
    if (next == _deviceLocale) return;
    setState(() => _deviceLocale = next);
  }

  @override
  void didChangePlatformBrightness() {
    if (widget.initialThemeBrightness != null) return;
    final next = WidgetsBinding.instance.platformDispatcher.platformBrightness;
    if (next == _brightness) return;
    setState(() => _brightness = next);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final locale = _supportedSplashLocale(_deviceLocale);
    final isDark = _brightness == Brightness.dark;
    final background = isDark
        ? owntendSplashBackgroundDark
        : owntendSplashBackground;
    final isFailure = widget.isFailed;

    return MediaQuery.fromView(
      view: View.of(context),
      child: Directionality(
        textDirection: _splashTextDirection(locale),
        child: Theme(
          data: ThemeData(
            useMaterial3: true,
            brightness: _brightness,
            scaffoldBackgroundColor: background,
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF159A3B),
              brightness: _brightness,
              surface: background,
            ),
          ),
          child: OwntendSplashOverlay(
            locale: locale,
            displayDuration: widget.displayDuration,
            minDisplayDuration: widget.minDisplayDuration,
            fadeOutDuration: widget.fadeOutDuration,
            isReadyNotifier: widget.isReadyNotifier ?? hkStartupReadyNotifier,
            isFailedNotifier:
                widget.isFailedNotifier ?? hkStartupFailedNotifier,
            isFailed: isFailure,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

/// Non-blank, non-animated surface shown only when bootstrap outlives the
/// fixed process splash timer.
///
/// Supports dark and light mode. Reads OS brightness directly from
/// [MediaQuery] — this intentionally uses the device preference rather than
/// any stored user preference, which has not yet been loaded at this point.
class OwntendStartupSurface extends StatelessWidget {
  const OwntendStartupSurface({super.key});

  @override
  Widget build(BuildContext context) {
    final locale = _supportedSplashLocale(
      WidgetsBinding.instance.platformDispatcher.locale,
    );
    final l10n = lookupAppLocalizations(locale);
    final isDark = _isDarkSplash(context);
    final bg = isDark ? owntendSplashBackgroundDark : owntendSplashBackground;
    // Text color: dark navy on light, near-white on dark.
    final textColor = isDark
        ? const Color(0xFFD8EDE0)
        : const Color(0xFF0B1726);

    Widget surface = AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
        statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarDividerColor: Colors.transparent,
        systemNavigationBarIconBrightness: isDark
            ? Brightness.light
            : Brightness.dark,
      ),
      child: ColoredBox(
        color: bg,
        child: SafeArea(
          child: Center(
            child: Semantics(
              container: true,
              liveRegion: true,
              label: l10n.startupStartingOwntend,
              textDirection: _splashTextDirection(locale),
              child: ExcludeSemantics(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Image.asset(
                      'assets/splash/owntend_splash_icon_3d.png',
                      width: 112,
                      height: 112,
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.high,
                    ),
                    const SizedBox(height: 12),
                    // Brand name is always left-to-right per design policy.
                    // See docs/development/localization-and-rtl.md.
                    Text(
                      'Owntend',
                      textDirection: TextDirection.ltr,
                      style: TextStyle(
                        color: textColor,
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        fontFamilyFallback: const [
                          'Noto Sans Arabic',
                          'Noto Naskh Arabic',
                          'sans-serif',
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    if (Directionality.maybeOf(context) == null) {
      surface = Directionality(
        textDirection: _splashTextDirection(locale),
        child: surface,
      );
    }
    if (MediaQuery.maybeOf(context) == null) {
      surface = MediaQuery.fromView(view: View.of(context), child: surface);
    }
    return surface;
  }
}

/// Purely visual, isolated startup splash overlay controller for Owntend.
///
/// Places the animated splash visually above the already-running application child
/// until readiness or the specified presentation duration completes, fades out,
/// and removes itself from the widget tree.
class OwntendSplashOverlay extends StatefulWidget {
  const OwntendSplashOverlay({
    required this.child,
    this.locale = const Locale('en'),
    this.displayDuration = owntendSplashDisplayDuration,
    this.minDisplayDuration = owntendSplashMinDisplayDuration,
    this.fadeOutDuration = owntendSplashFadeOutDuration,
    this.isReadyNotifier,
    this.isFailedNotifier,
    this.isFailed = false,
    super.key,
  });

  final Widget child;
  final Locale locale;
  final Duration displayDuration;
  final Duration minDisplayDuration;
  final Duration fadeOutDuration;
  final ValueListenable<bool>? isReadyNotifier;
  final ValueListenable<bool>? isFailedNotifier;
  final bool isFailed;

  @override
  State<OwntendSplashOverlay> createState() => _OwntendSplashOverlayState();
}

class _OwntendSplashOverlayState extends State<OwntendSplashOverlay> {
  Timer? _displayTimer;
  Timer? _removalTimer;
  Timer? _safetyTimer;
  bool _showSplash = true;
  bool _isFadingOut = false;
  late final DateTime _startTime;

  @override
  void initState() {
    super.initState();
    _startTime = DateTime.now();

    if (widget.isFailed) {
      _showSplash = false;
      return;
    }

    widget.isReadyNotifier?.addListener(_checkReadiness);
    widget.isFailedNotifier?.addListener(_checkFailed);

    if (widget.isFailedNotifier?.value == true) {
      _showSplash = false;
      return;
    }

    if (widget.isReadyNotifier?.value == true) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _checkReadiness());
      return;
    }

    if (widget.isReadyNotifier == null) {
      _displayTimer = Timer(widget.displayDuration, _triggerFadeOut);
    } else {
      _safetyTimer = Timer(widget.displayDuration, _triggerFadeOut);
    }
  }

  void _checkFailed() {
    if (!mounted || !_showSplash) return;
    if (widget.isFailedNotifier?.value == true) {
      _displayTimer?.cancel();
      _safetyTimer?.cancel();
      _removalTimer?.cancel();
      void update() {
        if (mounted) {
          setState(() {
            _showSplash = false;
            _isFadingOut = false;
          });
        }
      }

      if (WidgetsBinding.instance.schedulerPhase ==
          SchedulerPhase.persistentCallbacks) {
        WidgetsBinding.instance.addPostFrameCallback((_) => update());
      } else {
        update();
      }
    }
  }

  void _checkReadiness() {
    if (!mounted || !_showSplash || _isFadingOut) return;
    if (widget.isReadyNotifier?.value != true) return;

    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final minDuration = reduceMotion
        ? Duration.zero
        : widget.minDisplayDuration;
    final elapsed = DateTime.now().difference(_startTime);

    void trigger() {
      if (!mounted || !_showSplash || _isFadingOut) return;
      if (elapsed >= minDuration) {
        _triggerFadeOut();
      } else {
        _displayTimer?.cancel();
        _displayTimer = Timer(minDuration - elapsed, _triggerFadeOut);
      }
    }

    if (WidgetsBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) => trigger());
    } else {
      trigger();
    }
  }

  void _triggerFadeOut() {
    if (!mounted || !_showSplash || _isFadingOut) return;
    void startFade() {
      if (!mounted || !_showSplash || _isFadingOut) return;
      setState(() {
        _isFadingOut = true;
      });
      _removalTimer = Timer(widget.fadeOutDuration, () {
        if (!mounted) return;
        setState(() {
          _showSplash = false;
        });
      });
    }

    if (WidgetsBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) => startFade());
    } else {
      startFade();
    }
  }

  @override
  void didUpdateWidget(OwntendSplashOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isFailed && _showSplash) {
      _displayTimer?.cancel();
      _safetyTimer?.cancel();
      _removalTimer?.cancel();
      setState(() {
        _showSplash = false;
        _isFadingOut = false;
      });
      return;
    }
    if (oldWidget.isReadyNotifier != widget.isReadyNotifier) {
      oldWidget.isReadyNotifier?.removeListener(_checkReadiness);
      widget.isReadyNotifier?.addListener(_checkReadiness);
      if (widget.isReadyNotifier?.value == true) {
        _checkReadiness();
      }
    }
    if (oldWidget.isFailedNotifier != widget.isFailedNotifier) {
      oldWidget.isFailedNotifier?.removeListener(_checkFailed);
      widget.isFailedNotifier?.addListener(_checkFailed);
      if (widget.isFailedNotifier?.value == true) {
        _checkFailed();
      }
    }
  }

  @override
  void dispose() {
    widget.isReadyNotifier?.removeListener(_checkReadiness);
    widget.isFailedNotifier?.removeListener(_checkFailed);
    _displayTimer?.cancel();
    _safetyTimer?.cancel();
    _removalTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (_showSplash)
          Positioned.fill(
            child: BlockSemantics(
              child: AnimatedOpacity(
                opacity: _isFadingOut ? 0.0 : 1.0,
                duration: widget.fadeOutDuration,
                child: OwntendAnimatedSplashScreen(
                  key: const ValueKey('owntend-animated-splash'),
                  locale: widget.locale,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Owntend in-app animated splash screen visual component.
///
/// Pure presentation widget for the fixed startup overlay.
class OwntendAnimatedSplashScreen extends StatefulWidget {
  const OwntendAnimatedSplashScreen({
    super.key,
    this.assetPath = 'assets/splash/owntend_splash_icon_3d.png',
    this.duration = owntendSplashDisplayDuration,
    this.locale = const Locale('en'),
  });

  final String assetPath;
  final Duration duration;
  final Locale locale;

  @override
  State<OwntendAnimatedSplashScreen> createState() =>
      _OwntendAnimatedSplashScreenState();
}

class _OwntendAnimatedSplashScreenState
    extends State<OwntendAnimatedSplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _intro;
  late final AnimationController _loop;

  late final Animation<double> _logoOpacity;
  late final Animation<double> _logoScale;
  late final Animation<double> _logoLift;
  late final Animation<double> _titleOpacity;
  late final Animation<Offset> _titleOffset;
  late final Animation<double> _footerOpacity;

  @override
  void initState() {
    super.initState();

    _intro = AnimationController(vsync: this, duration: widget.duration);

    _loop = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 5200),
    );

    _logoOpacity = const AlwaysStoppedAnimation<double>(1.0);
    _logoScale = const AlwaysStoppedAnimation<double>(1.0);
    _logoLift = const AlwaysStoppedAnimation<double>(0.0);

    _titleOpacity = CurvedAnimation(
      parent: _intro,
      curve: const Interval(0.10, 0.45, curve: Curves.easeOut),
    );

    _titleOffset = Tween<Offset>(begin: const Offset(0, 0.12), end: Offset.zero)
        .animate(
          CurvedAnimation(
            parent: _intro,
            curve: const Interval(0.10, 0.45, curve: Curves.easeOutCubic),
          ),
        );

    _footerOpacity = CurvedAnimation(
      parent: _intro,
      curve: const Interval(0.40, 0.75, curve: Curves.easeOut),
    );

    _intro.forward();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      if (_intro.isAnimating) {
        _intro.stop();
      }
      _intro.value = 1.0;
      if (_loop.isAnimating) {
        _loop.stop();
      }
    } else {
      if (!_intro.isAnimating && !_intro.isCompleted) {
        _intro.forward();
      }
      if (!_loop.isAnimating) {
        _loop.repeat();
      }
    }
  }

  @override
  void didUpdateWidget(OwntendAnimatedSplashScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.duration != oldWidget.duration) {
      _intro.duration = widget.duration;
    }
  }

  @override
  void dispose() {
    _intro.dispose();
    _loop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final l10n = lookupAppLocalizations(_supportedSplashLocale(widget.locale));
    final compact = media.size.height < 520 || media.textScaler.scale(1) >= 1.8;
    final minimumLogoSize = compact ? 84.0 : 140.0;
    final logoHeightFraction = compact ? 0.26 : 0.38;
    final shortest = media.size.shortestSide;
    final logoSize = math.min(
      shortest.clamp(minimumLogoSize, 430.0),
      (media.size.height * logoHeightFraction).clamp(minimumLogoSize, 430.0),
    );
    final horizontalPadding = (media.size.width * 0.075).clamp(16.0, 44.0);
    final isDark = _isDarkSplash(context);
    final splashBg = isDark
        ? owntendSplashBackgroundDark
        : owntendSplashBackground;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
        statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarDividerColor: Colors.transparent,
        systemNavigationBarIconBrightness: isDark
            ? Brightness.light
            : Brightness.dark,
      ),
      child: AbsorbPointer(
        absorbing: true,
        child: Semantics(
          container: true,
          liveRegion: true,
          label: l10n.startupStartingOwntend,
          textDirection: _splashTextDirection(widget.locale),
          child: ExcludeSemantics(
            child: Scaffold(
              backgroundColor: splashBg,
              body: SafeArea(
                child: AnimatedBuilder(
                  animation: Listenable.merge([_intro, _loop]),
                  builder: (context, _) {
                    return Stack(
                      fit: StackFit.expand,
                      children: [
                        RepaintBoundary(
                          child: CustomPaint(
                            painter: _OwntendSplashBackgroundPainter(
                              loopValue: _loop.value,
                              introValue: _intro.value,
                              isDark: isDark,
                            ),
                          ),
                        ),

                        LayoutBuilder(
                          builder: (context, constraints) {
                            return SingleChildScrollView(
                              physics: const NeverScrollableScrollPhysics(),
                              child: ConstrainedBox(
                                constraints: BoxConstraints(
                                  minHeight: constraints.maxHeight,
                                ),
                                child: IntrinsicHeight(
                                  child: Padding(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: horizontalPadding,
                                    ),
                                    child: Column(
                                      children: [
                                        const Spacer(flex: 9),

                                        Transform.translate(
                                          offset: Offset(0, _logoLift.value),
                                          child: FadeTransition(
                                            opacity: _logoOpacity,
                                            child: ScaleTransition(
                                              scale: _logoScale,
                                              child: RepaintBoundary(
                                                child: _AnimatedSplashIcon(
                                                  assetPath: widget.assetPath,
                                                  size: logoSize,
                                                  loopValue: _loop.value,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),

                                        SizedBox(height: compact ? 8 : 18),

                                        FadeTransition(
                                          opacity: _titleOpacity,
                                          child: SlideTransition(
                                            position: _titleOffset,
                                            child: _SplashTitle(
                                              tagline:
                                                  l10n.owntendSplashTagline,
                                              compact: compact,
                                            ),
                                          ),
                                        ),

                                        const Spacer(flex: 7),

                                        _LoadingSection(
                                          loopValue: _loop.value,
                                          statusText:
                                              l10n.startupStartingOwntend,
                                          footerText:
                                              l10n.worksOnlineAndOffline,
                                          footerOpacity: _footerOpacity.value,
                                          compact: compact,
                                        ),

                                        const Spacer(flex: 3),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AnimatedSplashIcon extends StatelessWidget {
  const _AnimatedSplashIcon({
    required this.assetPath,
    required this.size,
    required this.loopValue,
  });

  final String assetPath;
  final double size;
  final double loopValue;

  static const Color _green = Color(0xFF159A3B);

  @override
  Widget build(BuildContext context) {
    final floatY = math.sin(loopValue * math.pi * 2) * 5.0;
    final tilt = math.sin(loopValue * math.pi * 2) * 0.018;

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Transform.rotate(
            angle: loopValue * math.pi * 2,
            child: CustomPaint(
              size: Size(size * 0.82, size * 0.82),
              painter: _RotatingSyncRingPainter(),
            ),
          ),
          Container(
            width: size * 0.72,
            height: size * 0.72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: _green.withValues(alpha: 0.20),
                  blurRadius: 28,
                  spreadRadius: 1,
                  offset: const Offset(0, 14),
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 18,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
          ),
          Transform.translate(
            offset: Offset(0, floatY),
            child: Transform.rotate(
              angle: tilt,
              child: Image.asset(
                assetPath,
                width: size * 0.86,
                height: size * 0.86,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.high,
              ),
            ),
          ),
          Positioned(
            right: size * 0.15,
            top: size * 0.20,
            child: _Sparkle(size: size * 0.045),
          ),
          Positioned(
            left: size * 0.17,
            bottom: size * 0.24,
            child: _Sparkle(size: size * 0.035),
          ),
        ],
      ),
    );
  }
}

class _SplashTitle extends StatelessWidget {
  const _SplashTitle({required this.tagline, required this.compact});

  final String tagline;
  final bool compact;

  static const Color _navy = Color(0xFF0B1726);
  static const Color _green = Color(0xFF159A3B);
  static const Color _muted = Color(0xFF5F6B76);
  static const _fontFallback = <String>[
    'Noto Sans Arabic',
    'Noto Naskh Arabic',
    'sans-serif',
  ];

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final titleSize = width < 380 ? 38.0 : 44.0;
    final isDark = _isDarkSplash(context);

    final ownColor = isDark ? const Color(0xFFD8EDE0) : _navy;
    final tendColor = isDark ? const Color(0xFF45DA67) : _green;
    final mutedColor = isDark ? const Color(0xFFA1B0BC) : _muted;

    return Column(
      children: [
        // Brand name "Owntend" is always left-to-right per design policy.
        // See docs/development/localization-and-rtl.md.
        RichText(
          textAlign: TextAlign.center,
          textDirection: TextDirection.ltr,
          text: TextSpan(
            children: [
              TextSpan(
                text: 'Own',
                style: TextStyle(
                  color: ownColor,
                  fontSize: titleSize,
                  fontWeight: FontWeight.w800,
                  height: 1,
                  letterSpacing: 0.2,
                  fontFamilyFallback: _fontFallback,
                ),
              ),
              TextSpan(
                text: 'tend',
                style: TextStyle(
                  color: tendColor,
                  fontSize: titleSize,
                  fontWeight: FontWeight.w800,
                  height: 1,
                  letterSpacing: 0.2,
                  fontFamilyFallback: _fontFallback,
                ),
              ),
            ],
          ),
        ),
        if (!compact) ...[
          const SizedBox(height: 12),
          Text(
            tagline,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: mutedColor,
              fontSize: 16.5,
              height: 1.45,
              fontWeight: FontWeight.w500,
              fontFamilyFallback: _fontFallback,
            ),
          ),
        ],
      ],
    );
  }
}

class _LoadingSection extends StatelessWidget {
  const _LoadingSection({
    required this.statusText,
    required this.footerText,
    required this.footerOpacity,
    required this.compact,
    this.loopValue = 0.0,
  });

  final String statusText;
  final String footerText;
  final double footerOpacity;
  final bool compact;

  /// Current value of the repeating loop animation (0.0–1.0).
  /// Used to drive the pulsing dots so they are explicitly indeterminate.
  final double loopValue;

  static const Color _muted = Color(0xFF5F6B76);
  static const Color _dot = Color(0xFF22B953);
  static const _fontFallback = <String>[
    'Noto Sans Arabic',
    'Noto Naskh Arabic',
    'sans-serif',
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = _isDarkSplash(context);
    final statusColor = isDark ? const Color(0xFFA1B0BC) : _muted;
    final footerColor = isDark
        ? const Color(0xFF7E9287)
        : const Color(0xFF7B858F);

    // Three dots pulse in sequence using the loop animation value.
    final t = loopValue;
    double dotOpacity(int index) {
      // Each dot leads by 1/3 of the cycle.
      final phase = (t + index / 3.0) % 1.0;
      // Sine curve in [0.25, 1.0] range.
      return 0.25 + 0.75 * math.sin(phase * math.pi).clamp(0.0, 1.0);
    }

    return Column(
      children: [
        // Indeterminate three-dot indicator — explicitly decorative and
        // not connected to any startup progress measurement.
        ExcludeSemantics(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(3, (i) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Opacity(
                  opacity: dotOpacity(i),
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: _dot,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
        SizedBox(height: compact ? 8 : 18),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 240),
          child: Text(
            statusText,
            key: ValueKey<String>(statusText),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: statusColor,
              fontSize: 14.5,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.1,
              fontFamilyFallback: _fontFallback,
            ),
          ),
        ),
        if (!compact) ...[
          const SizedBox(height: 8),
          Opacity(
            opacity: footerOpacity.clamp(0.0, 1.0),
            child: Text(
              footerText,
              style: TextStyle(
                color: footerColor,
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
                fontFamilyFallback: _fontFallback,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _OwntendSplashBackgroundPainter extends CustomPainter {
  _OwntendSplashBackgroundPainter({
    required this.loopValue,
    required this.introValue,
    this.isDark = false,
  });

  final double loopValue;
  final double introValue;
  final bool isDark;

  static const Color _green = Color(0xFF159A3B);
  static const Color _yellowGreen = Color(0xFFCFEA79);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;

    final bg = Paint()
      ..shader =
          (isDark
                  ? const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Color(0xFF0D2118),
                        Color(0xFF0F261C),
                        Color(0xFF0A1912),
                      ],
                    )
                  : const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        owntendSplashBackground,
                        Color(0xFFF4FAF5),
                        Color(0xFFFFFFFF),
                      ],
                    ))
              .createShader(rect);
    canvas.drawRect(rect, bg);

    _drawGlow(
      canvas,
      center: Offset(size.width * 0.18, size.height * 0.13),
      radius: size.width * 0.72,
      color: _green.withValues(alpha: 0.12),
    );

    _drawGlow(
      canvas,
      center: Offset(size.width * 0.86, size.height * 0.78),
      radius: size.width * 0.62,
      color: _yellowGreen.withValues(alpha: 0.13),
    );

    final orbitCenter = Offset(size.width * 0.50, size.height * 0.43);
    final orbitPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.15
      ..color = _green.withValues(alpha: 0.14 * introValue);

    for (var i = 0; i < 3; i++) {
      final orbitRect = Rect.fromCenter(
        center: orbitCenter,
        width: size.width * (0.82 + i * 0.16),
        height: size.width * (0.26 + i * 0.055),
      );

      canvas.save();
      canvas.translate(orbitCenter.dx, orbitCenter.dy);
      canvas.rotate(-0.20 + i * 0.13);
      canvas.translate(-orbitCenter.dx, -orbitCenter.dy);
      canvas.drawArc(
        orbitRect,
        math.pi * 0.02,
        math.pi * 1.58,
        false,
        orbitPaint,
      );
      canvas.restore();
    }

    final dotPaint = Paint()
      ..color = _green.withValues(alpha: 0.44 * introValue);
    final sparklePaint = Paint()
      ..color = _yellowGreen.withValues(alpha: 0.55 * introValue);

    for (var i = 0; i < 11; i++) {
      final angle = loopValue * math.pi * 2 + i * math.pi * 2 / 11;
      final rx = size.width * (0.36 + (i % 3) * 0.055);
      final ry = size.width * (0.11 + (i % 2) * 0.025);
      final offset = Offset(
        orbitCenter.dx + math.cos(angle) * rx,
        orbitCenter.dy + math.sin(angle) * ry,
      );
      final radius = 1.8 + (i % 3) * 0.8;
      canvas.drawCircle(offset, radius, i.isEven ? dotPaint : sparklePaint);
    }
  }

  void _drawGlow(
    Canvas canvas, {
    required Offset center,
    required double radius,
    required Color color,
  }) {
    final paint = Paint()
      ..shader = RadialGradient(colors: [color, color.withValues(alpha: 0.0)])
          .createShader(Rect.fromCircle(center: center, radius: radius));

    canvas.drawCircle(center, radius, paint);
  }

  @override
  bool shouldRepaint(covariant _OwntendSplashBackgroundPainter oldDelegate) {
    return oldDelegate.loopValue != loopValue ||
        oldDelegate.introValue != introValue ||
        oldDelegate.isDark != isDark;
  }
}

class _RotatingSyncRingPainter extends CustomPainter {
  static const Color _green = Color(0xFF159A3B);

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide * 0.44;
    final rect = Rect.fromCircle(center: center, radius: radius);

    final ringPaint = Paint()
      ..color = _green.withValues(alpha: 0.13)
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.shortestSide * 0.018
      ..strokeCap = StrokeCap.round;

    final accentPaint = Paint()
      ..color = _green.withValues(alpha: 0.23)
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.shortestSide * 0.026
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(rect, -2.70, 1.22, false, ringPaint);
    canvas.drawArc(rect, 0.35, 1.28, false, ringPaint);
    canvas.drawArc(
      rect.inflate(size.shortestSide * 0.035),
      -0.08,
      0.62,
      false,
      accentPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _Sparkle extends StatelessWidget {
  const _Sparkle({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(size: Size.square(size), painter: _SparklePainter());
  }
}

class _SparklePainter extends CustomPainter {
  static const Color _greenLight = Color(0xFFBDEB4A);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final path = Path()
      ..moveTo(c.dx, 0)
      ..quadraticBezierTo(
        c.dx + size.width * 0.13,
        c.dy - size.height * 0.13,
        size.width,
        c.dy,
      )
      ..quadraticBezierTo(
        c.dx + size.width * 0.13,
        c.dy + size.height * 0.13,
        c.dx,
        size.height,
      )
      ..quadraticBezierTo(
        c.dx - size.width * 0.13,
        c.dy + size.height * 0.13,
        0,
        c.dy,
      )
      ..quadraticBezierTo(
        c.dx - size.width * 0.13,
        c.dy - size.height * 0.13,
        c.dx,
        0,
      )
      ..close();

    canvas.drawPath(path, Paint()..color = _greenLight.withValues(alpha: 0.85));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
