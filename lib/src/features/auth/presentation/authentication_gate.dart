import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:owntend/l10n/app_localizations_ext.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/app_failure.dart';
import '../../../core/domain/models.dart';
import '../../../core/database/app_database.dart';
import '../../../core/sync/sync_providers.dart';
import '../../../ui/app_theme.dart';
import '../../../ui/components.dart' as hk_ui;
import '../../../ui/full_bleed_illustration_background.dart';
import '../../../ui/full_canvas_system_ui.dart';
import 'auth_providers.dart';
import 'quarantine_resolution_view.dart';

class AuthenticationGate extends ConsumerStatefulWidget {
  const AuthenticationGate({
    required this.child,
    this.language = AppLanguage.en,
    this.onLanguageChanged,
    super.key,
  });

  final Widget child;
  final AppLanguage language;
  final ValueChanged<AppLanguage>? onLanguageChanged;

  @override
  ConsumerState<AuthenticationGate> createState() => _AuthenticationGateState();
}

class _AuthenticationGateState extends ConsumerState<AuthenticationGate> {
  bool _busy = false;
  String? _error;

  Future<void> _continueWithGoogle() async {
    if (_busy) return;
    final auth = ref.read(authRepositoryProvider);
    if (auth == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await auth.signInWithGoogle();
    } on Object catch (error) {
      if (mounted) {
        setState(
          () => _error = localizedFailureMessage(
            context.l10n,
            appFailureCodeFor(error, fallback: AppFailureCode.signIn),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authRepositoryProvider);
    final session = ref.watch(authSessionProvider).value;

    if (session != null) {
      final syncStatus = ref.watch(syncStatusProvider).value;
      if (syncStatus != null &&
          (syncStatus.migrationState == 'quarantined' ||
              syncStatus.blockedReason == 'quarantined')) {
        final database = ref.watch(databaseProvider);
        return StandardSystemUi(
          child: Scaffold(body: QuarantineResolutionView(database: database)),
        );
      }
      return StandardSystemUi(child: widget.child);
    }

    return _WelcomeScreen(
      busy: _busy,
      error: _error,
      language: widget.language,
      onLanguageChanged: widget.onLanguageChanged,
      onGoogle: auth == null ? null : _continueWithGoogle,
    );
  }
}

class _WelcomeScreen extends StatelessWidget {
  const _WelcomeScreen({
    required this.busy,
    required this.error,
    required this.language,
    required this.onLanguageChanged,
    required this.onGoogle,
  });

  final bool busy;
  final String? error;
  final AppLanguage language;
  final ValueChanged<AppLanguage>? onLanguageChanged;
  final VoidCallback? onGoogle;

  @override
  Widget build(BuildContext context) {
    return FullCanvasSystemUi(
      child: Theme(
        data: OwntendTheme.light().copyWith(
          splashFactory: Theme.of(context).splashFactory,
        ),
        child: Builder(
          builder: (context) => Scaffold(
            backgroundColor: HkColors.appBackground,
            body: Stack(
              children: [
                KeyedSubtree(
                  key: const ValueKey('onboarding-viewport'),
                  child: FullBleedIllustrationBackground(
                    key: const ValueKey('onboarding-hero-illustration'),
                    illustrationAsset: 'assets/illustrations/owntend-onboarding-hero-target.webp',
                    alignment: Alignment.center,
                    fit: BoxFit.contain,
                    backgroundGradient: const RadialGradient(
                      center: Alignment(0.18, -0.08),
                      radius: 1.12,
                      colors: [
                        Color(0xFFEAF3E4),
                        Color(0xFFF8FAF5),
                        HkColors.appBackground,
                      ],
                      stops: [0, 0.60, 1],
                    ),
                    topFade: 0.10,
                    bottomFade: 0.18,
                    leftFade: 0.08,
                    rightFade: 0.08,
                    decorativeOverlay: const CustomPaint(
                      painter: _OnboardingParticlePainter(),
                    ),
                    scrim: const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Color(0xE6F8FAF5),
                        Color(0x00F8FAF5),
                        Color(0x00F8FAF5),
                        Color(0xF2F7F9FC),
                      ],
                      stops: [0, 0.22, 0.58, 1],
                    ),
                    child: SafeArea(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final horizontalPadding = constraints.maxWidth < 400
                              ? 12.0
                              : 24.0;
                          final contentWidth = math.min(
                            640.0,
                            constraints.maxWidth - horizontalPadding * 2,
                          );
                          final textScale =
                              MediaQuery.textScalerOf(context).scale(10) / 10;
                          final compact =
                              constraints.maxHeight < 760 || textScale > 1.12;
                          final verticalPadding = compact ? 4.0 : 8.0;
                          const selectorHeight = 48.0;
                          final maximumLayoutHeight =
                              constraints.maxHeight >= 1000
                              ? 940.0
                              : compact
                              ? 740.0
                              : 800.0;
                          final layoutHeight = math.min(
                            maximumLayoutHeight,
                            math.max(
                              0.0,
                              constraints.maxHeight -
                                  verticalPadding * 2 -
                                  selectorHeight -
                                  8,
                            ),
                          );
                          final featureHeight = compact ? 124.0 : 132.0;
                          final privacyHeight = compact ? 46.0 : 50.0;
                          final errorHeight = error == null
                              ? 0.0
                              : compact
                              ? 48.0
                              : 54.0;
                          final actionsHeight =
                              errorHeight +
                              featureHeight +
                              privacyHeight +
                              56 +
                              (compact ? 22 : 28);
                          final heroHeight = math.max(
                            260.0,
                            layoutHeight - actionsHeight - 4,
                          );
                          final minimumLayoutHeight =
                              heroHeight + actionsHeight + 4;
                          final effectiveLayoutHeight = math.max(
                            layoutHeight,
                            minimumLayoutHeight,
                          );
                          final needsScroll =
                              effectiveLayoutHeight +
                                  selectorHeight +
                                  8 +
                                  verticalPadding * 2 >
                              constraints.maxHeight;
                          final frame = ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 640),
                            child: SizedBox(
                              key: const ValueKey('onboarding-design-frame'),
                              width: contentWidth,
                              height: effectiveLayoutHeight,
                              child: Column(
                                children: [
                                  _OnboardingHero(
                                    height: heroHeight,
                                    compact: compact,
                                  ),
                                  const SizedBox(height: 4),
                                  SizedBox(
                                    height: actionsHeight,
                                    child: _OnboardingActions(
                                      busy: busy,
                                      error: error,
                                      onGoogle: onGoogle,
                                      compact: compact,
                                      featureHeight: featureHeight,
                                      privacyHeight: privacyHeight,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                          final content = Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              SizedBox(
                                height: selectorHeight,
                                child: Align(
                                  alignment: AlignmentDirectional.centerEnd,
                                  child: hk_ui.LanguageSelectorDropdown(
                                    selectorKey: const ValueKey(
                                      'onboarding-language-selector',
                                    ),
                                    hitTargetKey: const ValueKey(
                                      'onboarding-language-selector-hit-target',
                                    ),
                                    language: language,
                                    onChanged: onLanguageChanged,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Center(child: frame),
                            ],
                          );
                          return RepaintBoundary(
                            child: Padding(
                              padding: EdgeInsets.symmetric(
                                horizontal: horizontalPadding,
                                vertical: verticalPadding,
                              ),
                              child: needsScroll
                                  ? SingleChildScrollView(child: content)
                                  : content,
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OnboardingParticlePainter extends CustomPainter {
  const _OnboardingParticlePainter();

  @override
  void paint(Canvas canvas, Size size) {
    const particles = [
      (0.73, 0.15, 1.3, 0.18),
      (0.87, 0.18, 2.0, 0.25),
      (0.62, 0.23, 0.9, 0.14),
      (0.35, 0.30, 1.1, 0.16),
      (0.22, 0.44, 1.2, 0.12),
      (0.74, 0.68, 1.0, 0.11),
      (0.51, 0.82, 1.1, 0.10),
    ];
    for (final particle in particles) {
      final center = Offset(
        size.width * particle.$1,
        size.height * particle.$2,
      );
      final radius = particle.$3;
      final alpha = particle.$4;
      canvas.drawCircle(
        center,
        radius * 3.2,
        Paint()
          ..shader = RadialGradient(
            colors: [
              const Color(0xFF5DDD83).withValues(alpha: alpha * 0.28),
              const Color(0xFF5DDD83).withValues(alpha: 0),
            ],
          ).createShader(Rect.fromCircle(center: center, radius: radius * 3.2)),
      );
      canvas.drawCircle(
        center,
        radius,
        Paint()..color = const Color(0xFF5DDD83).withValues(alpha: alpha),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _OnboardingParticlePainter oldDelegate) => false;
}

class _OnboardingHero extends StatelessWidget {
  const _OnboardingHero({required this.height, required this.compact});

  final double height;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final textScale = MediaQuery.textScalerOf(context).scale(10) / 10;
    final typeCompensation = 1 / math.max(1, textScale * 0.8);
    return SizedBox(
      height: height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 8,
            right: 8,
            top: compact ? 4 : 10,
            child: Column(
              children: [
                Text(
                  context.l10n.yourTasks,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.displayLarge?.copyWith(
                    color: HkColors.appTextPrimary,
                    fontSize: (compact ? 28 : 34) * typeCompensation,
                    height: 1.04,
                    letterSpacing: 0,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: compact ? 2 : 4),
                Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.center,
                  children: [
                    Text(
                      context.l10n.allInSync,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.displayLarge?.copyWith(
                        color: HkColors.appPrimary,
                        fontSize: (compact ? 30 : 36) * typeCompensation,
                        height: 1.04,
                        letterSpacing: 0,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Positioned(
                      right: compact ? 44 : 38,
                      top: compact ? -8 : -10,
                      child: const Icon(
                        Icons.auto_awesome_rounded,
                        color: Color(0xFFFFD36A),
                        size: 20,
                        shadows: [
                          Shadow(color: Color(0x99FFD36A), blurRadius: 7),
                        ],
                      ),
                    ),
                  ],
                ),
                SizedBox(height: compact ? 7 : 10),
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: compact ? 9 : 12,
                    vertical: compact ? 3 : 4,
                  ),
                  decoration: BoxDecoration(
                    color: HkColors.appBackground.withValues(alpha: 0.74),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Text(
                    context.l10n.onboardingHeroSubtitle,
                    maxLines: 2,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: HkColors.appTextSecondary,
                      height: 1.28,
                      fontSize: (compact ? 11.5 : 13.5) * typeCompensation,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OnboardingActions extends StatelessWidget {
  const _OnboardingActions({
    required this.busy,
    required this.error,
    required this.onGoogle,
    required this.compact,
    required this.featureHeight,
    required this.privacyHeight,
  });

  final bool busy;
  final String? error;
  final VoidCallback? onGoogle;
  final bool compact;
  final double featureHeight;
  final double privacyHeight;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.sizeOf(context).width.isFinite) {
      return _ResponsiveOnboardingActions(
        busy: busy,
        error: error,
        onGoogle: onGoogle,
        compact: compact,
        featureHeight: featureHeight,
        privacyHeight: privacyHeight,
      );
    }
    final scheme = Theme.of(context).colorScheme;
    final benefits = [
      _Benefit(
        icon: Icons.devices_rounded,
        title: context.l10n.anyDevice,
        subtitle: context.l10n.accessYourTasksAndRoutinesAcrossAllYourDevices,
      ),
      _Benefit(
        icon: Icons.autorenew_rounded,
        title: context.l10n.smartRoutines,
        subtitle: context.l10n.buildHabitsAndAutomateRoutinesThatKeepYouMoving,
      ),
      _Benefit(
        icon: Icons.insights_rounded,
        title: context.l10n.progressInsights,
        subtitle: context.l10n.trackProgressStreaksAndGoalsToStayMotivated,
      ),
    ];
    return Stack(
      key: const ValueKey('onboarding-actions'),
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: 35,
          top: 0,
          width: 570,
          height: 166,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 15),
            decoration: BoxDecoration(
              color: HkColors.appSurface.withValues(alpha: 0.94),
              borderRadius: BorderRadius.circular(11),
              border: Border.all(
                color: HkColors.appBorder.withValues(alpha: 0.90),
              ),
              boxShadow: [
                BoxShadow(
                  color: HkColors.appTextPrimary.withValues(alpha: 0.10),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: benefits[0]),
                  _BenefitDivider(color: HkColors.appBorder),
                  Expanded(child: benefits[1]),
                  _BenefitDivider(color: HkColors.appBorder),
                  Expanded(child: benefits[2]),
                ],
              ),
            ),
          ),
        ),
        Positioned(
          left: 44,
          top: 187,
          width: 552,
          height: 59,
          child: _GoogleSignInButton(busy: busy, onPressed: onGoogle),
        ),
        Positioned(
          left: 44,
          top: 271,
          width: 552,
          height: 48,
          child: Container(
            key: const ValueKey('onboarding-privacy-footer'),
            padding: const EdgeInsets.symmetric(horizontal: 20),
            decoration: BoxDecoration(
              color: HkColors.appSurface.withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(13),
              border: Border.all(
                color: HkColors.appBorder.withValues(alpha: 0.92),
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.shield_rounded,
                  size: 28,
                  color: HkColors.appPrimary,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    context.l10n.yourDataStaysPrivateAndSecure,
                    maxLines: 1,
                    style: TextStyle(
                      color: HkColors.appTextSecondary,
                      fontSize: 12.3,
                      height: 1.2,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const Icon(
                  Icons.info_outline_rounded,
                  color: HkColors.appPrimary,
                  size: 24,
                ),
              ],
            ),
          ),
        ),
        if (error != null)
          Positioned(
            left: 45,
            top: -50,
            width: 550,
            height: 44,
            child: Semantics(
              liveRegion: true,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: scheme.errorContainer,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  error!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: scheme.onErrorContainer,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _ResponsiveOnboardingActions extends StatelessWidget {
  const _ResponsiveOnboardingActions({
    required this.busy,
    required this.error,
    required this.onGoogle,
    required this.compact,
    required this.featureHeight,
    required this.privacyHeight,
  });

  final bool busy;
  final String? error;
  final VoidCallback? onGoogle;
  final bool compact;
  final double featureHeight;
  final double privacyHeight;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final benefits = [
      _Benefit(
        icon: Icons.devices_rounded,
        title: context.l10n.anyDevice,
        subtitle: context.l10n.accessYourTasksAndRoutinesAcrossAllYourDevices,
      ),
      _Benefit(
        icon: Icons.autorenew_rounded,
        title: context.l10n.smartRoutines,
        subtitle: context.l10n.buildHabitsAndAutomateRoutinesThatKeepYouMoving,
      ),
      _Benefit(
        icon: Icons.insights_rounded,
        title: context.l10n.progressInsights,
        subtitle: context.l10n.trackProgressStreaksAndGoalsToStayMotivated,
      ),
    ];
    final textScale = MediaQuery.textScalerOf(context).scale(10) / 10;
    final typeCompensation = 1 / math.max(1, textScale * 0.8);
    return Column(
      key: const ValueKey('onboarding-actions'),
      children: [
        if (error != null) ...[
          Semantics(
            liveRegion: true,
            child: SizedBox(
              height: compact ? 42 : 48,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: scheme.errorContainer,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  error!,
                  maxLines: 3,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: scheme.onErrorContainer,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
          SizedBox(height: compact ? 6 : 8),
        ],
        LayoutBuilder(
          builder: (context, constraints) {
            return Container(
              width: double.infinity,
              height: featureHeight,
              padding: EdgeInsets.symmetric(
                horizontal: compact ? 4 : 6,
                vertical: compact ? 6 : 8,
              ),
              decoration: BoxDecoration(
                color: HkColors.appSurface.withValues(alpha: 0.91),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: HkColors.appBorder.withValues(alpha: 0.88),
                ),
                boxShadow: [
                  BoxShadow(
                    color: HkColors.appTextPrimary.withValues(alpha: 0.09),
                    blurRadius: 22,
                    offset: const Offset(0, 9),
                  ),
                ],
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: benefits[0]),
                  _BenefitDivider(color: HkColors.appBorder),
                  Expanded(child: benefits[1]),
                  _BenefitDivider(color: HkColors.appBorder),
                  Expanded(child: benefits[2]),
                ],
              ),
            );
          },
        ),
        SizedBox(height: compact ? 8 : 10),
        _GoogleSignInButton(busy: busy, onPressed: onGoogle),
        SizedBox(height: compact ? 8 : 10),
        SizedBox(
          height: privacyHeight,
          child: Container(
            key: const ValueKey('onboarding-privacy-footer'),
            width: double.infinity,
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 10 : 14,
              vertical: compact ? 6 : 8,
            ),
            decoration: BoxDecoration(
              color: HkColors.appSurface.withValues(alpha: 0.90),
              borderRadius: BorderRadius.circular(15),
              border: Border.all(
                color: HkColors.appBorder.withValues(alpha: 0.88),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.shield_rounded,
                  size: compact ? 21 : 24,
                  color: HkColors.appPrimary,
                ),
                SizedBox(width: compact ? 8 : 11),
                Expanded(
                  child: Text(
                    context.l10n.yourDataStaysPrivateAndSecure,
                    maxLines: 1,
                    style: TextStyle(
                      color: HkColors.appTextSecondary,
                      fontSize: (compact ? 9.8 : 11.2) * typeCompensation,
                      height: 1.22,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                SizedBox(width: compact ? 5 : 8),
                Icon(
                  Icons.info_outline_rounded,
                  color: HkColors.appPrimary,
                  size: compact ? 19 : 22,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _GoogleSignInButton extends StatelessWidget {
  const _GoogleSignInButton({required this.busy, required this.onPressed});

  final bool busy;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final textScale = MediaQuery.textScalerOf(context).scale(10) / 10;
    final typeCompensation = 1 / math.max(1, textScale * 0.8);
    return SizedBox(
      key: const ValueKey('continue-google-hit-target'),
      width: double.infinity,
      height: 56,
      child: OutlinedButton(
        key: const ValueKey('continue-google'),
        onPressed: busy ? null : onPressed,
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size.fromHeight(56)),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 14),
          ),
          backgroundColor: const WidgetStatePropertyAll(Color(0xFFFFFFFF)),
          foregroundColor: const WidgetStatePropertyAll(Color(0xFF1F1F1F)),
          side: const WidgetStatePropertyAll(
            BorderSide(color: Color(0xFF747775)),
          ),
          overlayColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.pressed)
                ? const Color(0x1F000000)
                : states.contains(WidgetState.hovered)
                ? const Color(0x0F000000)
                : null,
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: busy
                  ? const SizedBox.square(
                      dimension: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Color(0xFF1F1F1F),
                      ),
                    )
                  : Semantics(
                      label: context.l10n.google,
                      image: true,
                      child: Image.asset(
                        'assets/brand/google-g-logo.png',
                        key: const ValueKey('google-g-logo'),
                        width: 20,
                        height: 20,
                        fit: BoxFit.contain,
                        filterQuality: FilterQuality.high,
                      ),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 42),
              child: Text(
                context.l10n.continueWithGoogle,
                maxLines: 1,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: const Color(0xFF1F1F1F),
                  fontSize: 15.5 * typeCompensation,
                  height: 1,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Benefit extends StatelessWidget {
  const _Benefit({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).height < 760;
    final textScale = MediaQuery.textScalerOf(context).scale(10) / 10;
    final typeCompensation = 1 / math.max(1, textScale * 0.8);
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: compact ? 3 : 5, vertical: 2),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: HkColors.appPrimary, size: compact ? 21 : 24),
          SizedBox(height: compact ? 4 : 6),
          Text(
            title,
            maxLines: 2,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: HkColors.appTextPrimary,
              fontSize: (compact ? 10.7 : 12.2) * typeCompensation,
              height: 1.08,
              fontWeight: FontWeight.w700,
            ),
          ),
          SizedBox(height: compact ? 3 : 4),
          Text(
            subtitle,
            maxLines: 4,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: HkColors.appTextSecondary.withValues(alpha: 0.82),
              fontSize: (compact ? 8.5 : 9.8) * typeCompensation,
              height: 1.16,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _BenefitDivider extends StatelessWidget {
  const _BenefitDivider({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      margin: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
      color: color,
    );
  }
}
