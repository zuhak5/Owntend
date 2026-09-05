part of '../components.dart';

class HkMotion extends InheritedWidget {
  const HkMotion({required super.child, required this.reduceMotion, super.key});

  final bool reduceMotion;

  static bool reduceMotionOf(BuildContext context) {
    return context
            .dependOnInheritedWidgetOfExactType<HkMotion>()
            ?.reduceMotion ??
        _reduceMotion(context);
  }

  @override
  bool updateShouldNotify(HkMotion oldWidget) {
    return reduceMotion != oldWidget.reduceMotion;
  }
}

class PremiumEntrance extends StatefulWidget {
  const PremiumEntrance({
    required this.child,
    this.delay = Duration.zero,
    this.duration = const Duration(milliseconds: 360),
    this.offset = const Offset(0, 0.035),
    super.key,
  });

  final Widget child;
  final Duration delay;
  final Duration duration;
  final Offset offset;

  @override
  State<PremiumEntrance> createState() => _PremiumEntranceState();
}

class _PremiumEntranceState extends State<PremiumEntrance> {
  bool _visible = false;
  Timer? _timer;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_visible || _timer != null) return;
    if (HkMotion.reduceMotionOf(context)) {
      _visible = true;
      return;
    }
    _timer = Timer(widget.delay, () {
      if (mounted) setState(() => _visible = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = HkMotion.reduceMotionOf(context);
    return AnimatedSlide(
      offset: _visible || reduceMotion ? Offset.zero : widget.offset,
      duration: reduceMotion ? Duration.zero : widget.duration,
      curve: Curves.easeOutCubic,
      child: AnimatedOpacity(
        opacity: _visible || reduceMotion ? 1 : 0,
        duration: reduceMotion ? Duration.zero : widget.duration,
        curve: Curves.easeOutCubic,
        child: widget.child,
      ),
    );
  }
}

class PremiumPressable extends StatefulWidget {
  const PremiumPressable({required this.child, this.enabled = true, super.key});

  final Widget child;
  final bool enabled;

  @override
  State<PremiumPressable> createState() => _PremiumPressableState();
}

class _PremiumPressableState extends State<PremiumPressable> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = HkMotion.reduceMotionOf(context);
    return Listener(
      onPointerDown: widget.enabled
          ? (_) => setState(() => _pressed = true)
          : null,
      onPointerUp: widget.enabled
          ? (_) => setState(() => _pressed = false)
          : null,
      onPointerCancel: widget.enabled
          ? (_) => setState(() => _pressed = false)
          : null,
      child: AnimatedScale(
        scale: _pressed && !reduceMotion ? 0.97 : 1,
        duration: reduceMotion
            ? Duration.zero
            : const Duration(milliseconds: 110),
        curve: Curves.easeOutCubic,
        child: widget.child,
      ),
    );
  }
}

class PremiumProgressBar extends StatelessWidget {
  const PremiumProgressBar({
    required this.value,
    this.height = 14,
    this.color,
    super.key,
  });

  final double value;
  final double height;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final reduceMotion = HkMotion.reduceMotionOf(context);
    final progress = value.clamp(0.0, 1.0);
    return Semantics(
      value: '${(progress * 100).round()}%',
      child: Container(
        height: height,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(HkRadii.full),
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: 0.35),
          ),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Align(
              alignment: AlignmentDirectional.centerStart,
              child: AnimatedContainer(
                duration: reduceMotion
                    ? Duration.zero
                    : const Duration(milliseconds: 420),
                curve: Curves.easeOutCubic,
                width: constraints.maxWidth * progress,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      color ?? scheme.primary,
                      Color.lerp(
                            color ?? scheme.primary,
                            const Color(0xFF76D843),
                            0.55,
                          ) ??
                          scheme.primary,
                    ],
                  ),
                  borderRadius: BorderRadius.circular(HkRadii.full),
                  boxShadow: [
                    BoxShadow(
                      color: (color ?? scheme.primary).withValues(alpha: 0.36),
                      blurRadius: 10,
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class BreathingStatusIcon extends StatefulWidget {
  const BreathingStatusIcon({
    required this.icon,
    this.color,
    this.size = 48,
    super.key,
  });

  final IconData icon;
  final Color? color;
  final double size;

  @override
  State<BreathingStatusIcon> createState() => _BreathingStatusIconState();
}

class _BreathingStatusIconState extends State<BreathingStatusIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (HkMotion.reduceMotionOf(context)) {
      _controller
        ..stop()
        ..value = 0;
    } else if (!_controller.isAnimating) {
      _controller.repeat(reverse: true, count: 2);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? Theme.of(context).colorScheme.primary;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final value = Curves.easeInOut.transform(_controller.value);
        return Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1 + (value * 0.06)),
            borderRadius: BorderRadius.circular(widget.size * 0.34),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.08 + (value * 0.12)),
                blurRadius: 12 + (value * 10),
                spreadRadius: value * 2,
              ),
            ],
          ),
          child: Icon(widget.icon, color: color, size: widget.size * 0.5),
        );
      },
    );
  }
}

class ProductivityBackdrop extends StatelessWidget {
  const ProductivityBackdrop({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface,
        gradient: RadialGradient(
          center: const Alignment(0.7, -0.9),
          radius: 1.15,
          colors: [
            scheme.primary.withValues(alpha: 0.075),
            scheme.surface.withValues(alpha: 0),
          ],
        ),
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              scheme.surface,
              scheme.surface.withValues(alpha: 0.76),
              scheme.surface.withValues(alpha: 0),
            ],
            stops: const [0, 0.08, 0.22],
          ),
        ),
        child: child,
      ),
    );
  }
}

class BrandMark extends StatelessWidget {
  const BrandMark({this.size = 40, this.compact = false, super.key});

  final double size;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        shape: compact ? BoxShape.rectangle : BoxShape.circle,
        borderRadius: compact ? BorderRadius.circular(HkRadii.lg) : null,
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.24),
        ),
        boxShadow: HkShadows.ambient(tint: scheme.primary),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Icon(
            Symbols.home_health_rounded,
            size: size * 0.56,
            color: scheme.primary,
          ),
          PositionedDirectional(
            end: size * 0.17,
            top: size * 0.17,
            child: Container(
              width: size * 0.16,
              height: size * 0.16,
              decoration: BoxDecoration(
                color: scheme.tertiary,
                shape: BoxShape.circle,
                border: Border.all(
                  color: scheme.surfaceContainerLowest,
                  width: 1.5,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class PremiumCard extends StatelessWidget {
  const PremiumCard({
    required this.child,
    this.padding = const EdgeInsets.all(10),
    this.margin,
    this.backgroundColor,
    this.borderColor,
    this.borderRadius = HkRadii.xl,
    this.shadows,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final Color? backgroundColor;
  final Color? borderColor;
  final double borderRadius;
  final List<BoxShadow>? shadows;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: backgroundColor ?? scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(
          color:
              borderColor ??
              scheme.outlineVariant.withValues(alpha: _borderOpacity),
        ),
        boxShadow: shadows ?? HkShadows.ambient(tint: scheme.primary),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        type: MaterialType.transparency,
        borderRadius: BorderRadius.circular(borderRadius),
        clipBehavior: Clip.antiAlias,
        child: Padding(padding: padding, child: child),
      ),
    );
  }

  static const _borderOpacity = 1.0;
}
