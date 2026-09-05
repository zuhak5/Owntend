import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:owntend/l10n/app_localizations.dart';

const Color owntendSplashBackground = Color(0xFFF9FCF8);
const Duration owntendSplashDisplayDuration = Duration(milliseconds: 3200);
const Duration owntendSplashFadeOutDuration = Duration(milliseconds: 250);

Locale _supportedSplashLocale(Locale locale) {
  return locale.languageCode == 'ar' ? const Locale('ar') : const Locale('en');
}

TextDirection _splashTextDirection(Locale locale) {
  return locale.languageCode == 'ar' ? TextDirection.rtl : TextDirection.ltr;
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
    this.fadeOutDuration = owntendSplashFadeOutDuration,
    super.key,
  });

  final Widget child;
  final Duration displayDuration;
  final Duration fadeOutDuration;

  @override
  State<OwntendProcessSplash> createState() => _OwntendProcessSplashState();
}

class _OwntendProcessSplashState extends State<OwntendProcessSplash>
    with WidgetsBindingObserver {
  Locale _deviceLocale = WidgetsBinding.instance.platformDispatcher.locale;
  Brightness _brightness =
      WidgetsBinding.instance.platformDispatcher.platformBrightness;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeLocales(List<Locale>? locales) {
    final next =
        locales?.firstOrNull ??
        WidgetsBinding.instance.platformDispatcher.locale;
    if (next == _deviceLocale) return;
    setState(() => _deviceLocale = next);
  }

  @override
  void didChangePlatformBrightness() {
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
        ? const Color(0xFF0E1512)
        : owntendSplashBackground;
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
            fadeOutDuration: widget.fadeOutDuration,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

/// Non-blank, non-animated surface shown only when bootstrap outlives the
/// fixed process splash timer.
class OwntendStartupSurface extends StatelessWidget {
  const OwntendStartupSurface({super.key});

  @override
  Widget build(BuildContext context) {
    final locale = _supportedSplashLocale(
      WidgetsBinding.instance.platformDispatcher.locale,
    );
    final l10n = lookupAppLocalizations(locale);
    Widget surface = ColoredBox(
      color: owntendSplashBackground,
      child: SafeArea(
        child: Center(
          child: Semantics(
            container: true,
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
                  const Text(
                    'Owntend',
                    textDirection: TextDirection.ltr,
                    style: TextStyle(
                      color: Color(0xFF0B1726),
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
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
/// for a fixed duration, fades out, and removes itself from the widget tree.
class OwntendSplashOverlay extends StatefulWidget {
  const OwntendSplashOverlay({
    required this.child,
    this.locale = const Locale('en'),
    this.displayDuration = owntendSplashDisplayDuration,
    this.fadeOutDuration = owntendSplashFadeOutDuration,
    super.key,
  });

  final Widget child;
  final Locale locale;
  final Duration displayDuration;
  final Duration fadeOutDuration;

  @override
  State<OwntendSplashOverlay> createState() => _OwntendSplashOverlayState();
}

class _OwntendSplashOverlayState extends State<OwntendSplashOverlay> {
  Timer? _displayTimer;
  Timer? _removalTimer;
  bool _showSplash = true;
  bool _isFadingOut = false;

  @override
  void initState() {
    super.initState();
    _displayTimer = Timer(widget.displayDuration, () {
      if (!mounted) return;
      setState(() {
        _isFadingOut = true;
      });
      _removalTimer = Timer(widget.fadeOutDuration, () {
        if (!mounted) return;
        setState(() {
          _showSplash = false;
        });
      });
    });
  }

  @override
  void dispose() {
    _displayTimer?.cancel();
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
  late final Animation<double> _progressValue;
  late final Animation<double> _footerOpacity;

  @override
  void initState() {
    super.initState();

    _intro = AnimationController(vsync: this, duration: widget.duration);

    _loop = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 5200),
    );

    _logoOpacity = CurvedAnimation(
      parent: _intro,
      curve: const Interval(0.00, 0.22, curve: Curves.easeOut),
    );

    _logoScale = Tween<double>(begin: 0.72, end: 1.0).animate(
      CurvedAnimation(
        parent: _intro,
        curve: const Interval(0.00, 0.42, curve: Curves.easeOutBack),
      ),
    );

    _logoLift = Tween<double>(begin: 24.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _intro,
        curve: const Interval(0.00, 0.46, curve: Curves.easeOutCubic),
      ),
    );

    _titleOpacity = CurvedAnimation(
      parent: _intro,
      curve: const Interval(0.30, 0.58, curve: Curves.easeOut),
    );

    _titleOffset = Tween<Offset>(begin: const Offset(0, 0.18), end: Offset.zero)
        .animate(
          CurvedAnimation(
            parent: _intro,
            curve: const Interval(0.30, 0.60, curve: Curves.easeOutCubic),
          ),
        );

    _progressValue = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _intro,
        curve: const Interval(0.44, 0.92, curve: Curves.easeInOutCubic),
      ),
    );

    _footerOpacity = CurvedAnimation(
      parent: _intro,
      curve: const Interval(0.62, 0.88, curve: Curves.easeOut),
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
    final isDark = MediaQuery.platformBrightnessOf(context) == Brightness.dark;
    final splashBg = isDark ? const Color(0xFF0D2118) : owntendSplashBackground;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
        statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
        systemNavigationBarColor: splashBg,
        systemNavigationBarIconBrightness: isDark
            ? Brightness.light
            : Brightness.dark,
      ),
      child: AbsorbPointer(
        absorbing: true,
        child: Semantics(
          container: true,
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
                        CustomPaint(
                          painter: _OwntendSplashBackgroundPainter(
                            loopValue: _loop.value,
                            introValue: _intro.value,
                            isDark: isDark,
                          ),
                        ),

                        Padding(
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
                                    child: _AnimatedSplashIcon(
                                      assetPath: widget.assetPath,
                                      size: logoSize,
                                      loopValue: _loop.value,
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
                                    tagline: l10n.owntendSplashTagline,
                                    compact: compact,
                                  ),
                                ),
                              ),

                              const Spacer(flex: 7),

                              _LoadingSection(
                                value: _progressValue.value,
                                statusText: l10n.startupStartingOwntend,
                                footerText: l10n.worksOnlineAndOffline,
                                footerOpacity: _footerOpacity.value,
                                compact: compact,
                              ),

                              const Spacer(flex: 3),
                            ],
                          ),
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
                  blurRadius: 54,
                  spreadRadius: 2,
                  offset: const Offset(0, 24),
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 30,
                  offset: const Offset(0, 18),
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
          PositionedDirectional(
            end: size * 0.15,
            top: size * 0.20,
            child: _Sparkle(size: size * 0.045),
          ),
          PositionedDirectional(
            start: size * 0.17,
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

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final titleSize = width < 380 ? 38.0 : 44.0;

    return Column(
      children: [
        RichText(
          textAlign: TextAlign.center,
          textDirection: TextDirection.ltr,
          text: TextSpan(
            children: [
              TextSpan(
                text: 'Own',
                style: TextStyle(
                  color: _navy,
                  fontSize: titleSize,
                  fontWeight: FontWeight.w800,
                  height: 1,
                  letterSpacing: 0.2,
                ),
              ),
              TextSpan(
                text: 'tend',
                style: TextStyle(
                  color: _green,
                  fontSize: titleSize,
                  fontWeight: FontWeight.w800,
                  height: 1,
                  letterSpacing: 0.2,
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
            style: const TextStyle(
              color: _muted,
              fontSize: 16.5,
              height: 1.45,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ],
    );
  }
}

class _LoadingSection extends StatelessWidget {
  const _LoadingSection({
    required this.value,
    required this.statusText,
    required this.footerText,
    required this.footerOpacity,
    required this.compact,
  });

  final double value;
  final String statusText;
  final String footerText;
  final double footerOpacity;
  final bool compact;

  static const Color _green = Color(0xFF159A3B);
  static const Color _muted = Color(0xFF5F6B76);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ExcludeSemantics(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final progressWidth = math.min(310.0, constraints.maxWidth);
              return SizedBox(
                width: progressWidth,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: Stack(
                    children: [
                      Container(
                        height: 12,
                        decoration: BoxDecoration(
                          color: const Color(0xFFE7EFE8),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                      FractionallySizedBox(
                        widthFactor: value.clamp(0.0, 1.0),
                        child: Container(
                          height: 12,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(999),
                            gradient: const LinearGradient(
                              colors: [
                                Color(0xFF64D85F),
                                Color(0xFF159A3B),
                                Color(0xFF0C7A31),
                              ],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: _green.withValues(alpha: 0.32),
                                blurRadius: 16,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        SizedBox(height: compact ? 8 : 18),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 240),
          child: Text(
            statusText,
            key: ValueKey<String>(statusText),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: _muted,
              fontSize: 14.5,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.1,
            ),
          ),
        ),
        if (!compact) ...[
          const SizedBox(height: 8),
          Opacity(
            opacity: footerOpacity.clamp(0.0, 1.0),
            child: Text(
              footerText,
              style: const TextStyle(
                color: Color(0xFF7B858F),
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
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
        oldDelegate.introValue != introValue;
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
