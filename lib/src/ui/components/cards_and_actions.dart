part of '../components.dart';

class GlassPanel extends StatelessWidget {
  const GlassPanel({required this.child, this.padding, super.key});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(HkRadii.xxl),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: padding ?? const EdgeInsets.all(HkSpacing.xs),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLowest.withValues(alpha: 0.78),
            borderRadius: BorderRadius.circular(HkRadii.xxl),
            border: Border.all(
              color: scheme.outlineVariant.withValues(alpha: 0.24),
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

class OwntendFloatingActionButton extends StatefulWidget {
  const OwntendFloatingActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.tooltip,
    super.key,
  });

  final IconData icon;
  final String label;
  final String? tooltip;
  final VoidCallback? onPressed;

  @override
  State<OwntendFloatingActionButton> createState() =>
      _OwntendFloatingActionButtonState();
}

class _OwntendFloatingActionButtonState
    extends State<OwntendFloatingActionButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<double> _scale;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 520),
      vsync: this,
    );
    _fade = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0, 0.54, curve: Curves.easeOutCubic),
    );
    _scale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 0.82,
          end: 1.08,
        ).chain(CurveTween(curve: Curves.easeOutBack)),
        weight: 72,
      ),
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 1.08,
          end: 1,
        ).chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 28,
      ),
    ]).animate(_controller);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.28),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final button = _FixedFabButton(
      icon: widget.icon,
      label: widget.label,
      tooltip: widget.tooltip ?? widget.label,
      onPressed: widget.onPressed,
    );
    if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) {
      return button;
    }
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(
        position: _slide,
        child: ScaleTransition(scale: _scale, child: button),
      ),
    );
  }
}

class _FixedFabButton extends StatelessWidget {
  const _FixedFabButton({
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final safeBottom = MediaQuery.maybeOf(context)?.viewPadding.bottom ?? 0;
    return SizedBox(
      width: kOwntendFabWidth,
      height: kOwntendFabHeight,
      child: Tooltip(
        message: tooltip,
        preferBelow: false,
        verticalOffset: HkSpacing.sm,
        margin: EdgeInsets.fromLTRB(
          HkSpacing.gutter,
          HkSpacing.gutter,
          HkSpacing.gutter,
          safeBottom +
              kOwntendBottomNavVisualHeight +
              kOwntendFloatingActionButtonBottomInset,
        ),
        child: FloatingActionButton.extended(
          tooltip: null,
          onPressed: onPressed,
          icon: Icon(icon, size: 20),
          label: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: kOwntendFabLabelMaxWidth,
            ),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader({
    required this.title,
    this.actionLabel,
    this.onAction,
    this.subtitle,
    super.key,
  });

  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: HkSpacing.sm, bottom: HkSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: HkSpacing.base),
                  Text(
                    subtitle!,
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ],
              ],
            ),
          ),
          if (actionLabel != null)
            TextButton(
              onPressed: onAction,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(actionLabel!),
                  const SizedBox(width: 4),
                  const DirectionalIcon(
                    Symbols.arrow_forward_rounded,
                    size: 16,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class PopupActionLabel extends StatelessWidget {
  const PopupActionLabel({
    required this.icon,
    required this.label,
    this.destructive = false,
    super.key,
  });

  final IconData icon;
  final String label;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final color = destructive
        ? Theme.of(context).colorScheme.error
        : Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: HkSpacing.sm),
        Expanded(
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: destructive ? color : null,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class CompactActionGroup extends StatelessWidget {
  const CompactActionGroup({
    required this.children,
    this.minButtonWidth = 136,
    this.maxButtonWidth,
    this.buttonHeight = 48,
    this.spacing = HkSpacing.xs,
    this.runSpacing = HkSpacing.xs,
    this.stackBelowWidth,
    this.wrapWhenNarrow = false,
    super.key,
  });

  final List<Widget> children;
  final double minButtonWidth;
  final double? maxButtonWidth;
  final double buttonHeight;
  final double spacing;
  final double runSpacing;
  final double? stackBelowWidth;
  final bool wrapWhenNarrow;

  @override
  Widget build(BuildContext context) {
    final visibleChildren = children;
    if (visibleChildren.isEmpty) {
      return const SizedBox.shrink();
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final requiredWidth =
            visibleChildren.length * minButtonWidth +
            (visibleChildren.length - 1) * spacing;
        final stack = constraints.maxWidth < (stackBelowWidth ?? requiredWidth);
        Widget framed(Widget child, {required bool stretched}) {
          var effectiveMinWidth = minButtonWidth;
          if (constraints.hasBoundedWidth &&
              effectiveMinWidth > constraints.maxWidth) {
            effectiveMinWidth = constraints.maxWidth;
          }
          var effectiveMaxWidth = maxButtonWidth ?? double.infinity;
          if (constraints.hasBoundedWidth &&
              effectiveMaxWidth > constraints.maxWidth) {
            effectiveMaxWidth = constraints.maxWidth;
          }
          if (effectiveMaxWidth < effectiveMinWidth) {
            effectiveMaxWidth = effectiveMinWidth;
          }
          final sized = SizedBox(
            width: stretched ? double.infinity : null,
            height: buttonHeight,
            child: child,
          );
          if (stretched) {
            return sized;
          }
          return ConstrainedBox(
            constraints: BoxConstraints(
              minWidth: effectiveMinWidth,
              maxWidth: effectiveMaxWidth,
            ),
            child: sized,
          );
        }

        if (stack && !wrapWhenNarrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var index = 0; index < visibleChildren.length; index++) ...[
                framed(visibleChildren[index], stretched: true),
                if (index != visibleChildren.length - 1)
                  SizedBox(height: runSpacing),
              ],
            ],
          );
        }
        return Wrap(
          alignment: WrapAlignment.center,
          runAlignment: WrapAlignment.center,
          spacing: spacing,
          runSpacing: runSpacing,
          children: [
            for (final child in visibleChildren)
              framed(child, stretched: false),
          ],
        );
      },
    );
  }
}

class DashboardMetricTile extends StatelessWidget {
  const DashboardMetricTile({
    required this.label,
    required this.value,
    required this.caption,
    required this.icon,
    required this.color,
    this.alert = false,
    super.key,
  });

  final String label;
  final String value;
  final String caption;
  final IconData icon;
  final Color color;
  final bool alert;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PremiumCard(
      padding: const EdgeInsets.symmetric(
        horizontal: HkSpacing.xs,
        vertical: HkSpacing.sm,
      ),
      borderColor: alert
          ? scheme.tertiary.withValues(alpha: 0.28)
          : scheme.outlineVariant.withValues(alpha: 0.16),
      backgroundColor: alert
          ? Color.alphaBlend(
              scheme.errorContainer.withValues(alpha: 0.08),
              scheme.surfaceContainerLowest,
            )
          : scheme.surfaceContainerLowest,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: HkSpacing.base),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                color: alert ? scheme.tertiary : scheme.onSurface,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Text(
            label.toUpperCase(),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: alert ? scheme.tertiary : scheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            caption,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: alert ? scheme.tertiary : color,
              fontSize: 9,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class MetricTile extends StatelessWidget {
  const MetricTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.caption,
    super.key,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PremiumCard(
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(height: HkSpacing.xs),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              value,
              style: Theme.of(context).textTheme.headlineLarge
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          Text(
            label.toUpperCase(),
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (caption != null) ...[
            const SizedBox(height: 2),
            Text(
              caption!,
              style: Theme.of(context).textTheme.labelSmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }
}

class AchievementCard extends StatelessWidget {
  const AchievementCard({
    required this.value,
    required this.label,
    required this.icon,
    this.badge,
    this.primary = false,
    super.key,
  });

  final String value;
  final String label;
  final IconData icon;
  final String? badge;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final foreground = primary ? scheme.onPrimary : scheme.onSurface;
    final muted = primary
        ? scheme.onPrimary.withValues(alpha: 0.7)
        : scheme.onSurfaceVariant;
    final compactValue = value.length > 5 || value.contains(' ');
    return PremiumCard(
      padding: const EdgeInsets.all(10),
      backgroundColor: primary ? scheme.primaryContainer : null,
      borderColor: primary ? Colors.transparent : null,
      shadows: primary
          ? HkShadows.ambient(tint: scheme.primaryContainer)
          : null,
      child: SizedBox(
        height: 76,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            PositionedDirectional(
              end: -18,
              bottom: -30,
              child: Icon(
                primary
                    ? Symbols.show_chart_rounded
                    : Symbols.donut_large_rounded,
                size: 76,
                color: foreground.withValues(alpha: primary ? 0.08 : 0.06),
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(icon, size: 18, color: foreground),
                    if (badge != null) ...[
                      const SizedBox(width: HkSpacing.xs),
                      Flexible(
                        child: Align(
                          alignment: AlignmentDirectional.centerEnd,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: HkSpacing.xs,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: primary
                                  ? scheme.onPrimary.withValues(alpha: 0.16)
                                  : HkColors.secondaryFixed,
                              borderRadius: BorderRadius.circular(HkRadii.full),
                            ),
                            child: Text(
                              badge!.toUpperCase(),
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    color: primary
                                        ? scheme.onPrimary
                                        : HkColors.onSecondaryFixed,
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(
                        value,
                        style:
                            (compactValue
                                    ? Theme.of(context).textTheme.headlineMedium
                                    : Theme.of(context).textTheme.headlineLarge)
                                ?.copyWith(
                                  color: foreground,
                                  fontWeight: FontWeight.w700,
                                ),
                      ),
                    ),
                    Text(
                      label.toUpperCase(),
                      style: Theme.of(context).textTheme.labelLarge
                          ?.copyWith(color: muted, fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class PremiumEmptyState extends StatelessWidget {
  const PremiumEmptyState({
    required this.icon,
    required this.title,
    required this.body,
    this.action,
    this.illustrationTone = HkIllustrationTone.info,
    super.key,
  });

  final IconData icon;
  final String title;
  final String body;
  final Widget? action;
  final HkIllustrationTone illustrationTone;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PremiumCard(
      padding: const EdgeInsets.symmetric(
        horizontal: HkSpacing.md,
        vertical: HkSpacing.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          HkStateIllustration(icon: icon, tone: illustrationTone),
          const SizedBox(height: HkSpacing.sm),
          Text(
            title,
            style: Theme.of(context).textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: HkSpacing.space6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 280),
            child: Text(
              body,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
          if (action != null) ...[
            const SizedBox(height: HkSpacing.sm),
            action!,
          ],
        ],
      ),
    );
  }
}

class PremiumBottomActionBar extends StatelessWidget {
  const PremiumBottomActionBar({
    required this.label,
    required this.onPressed,
    required this.icon,
    this.secondary,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData icon;
  final Widget? secondary;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.96),
          border: Border(
            top: BorderSide(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
        ),
        child: Align(
          alignment: Alignment.bottomCenter,
          heightFactor: 1.0,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                HkSpacing.gutter,
                HkSpacing.xs,
                HkSpacing.gutter,
                HkSpacing.xs,
              ),
              child: Row(
                children: [
                  if (secondary != null) ...[
                    Expanded(child: secondary!),
                    const SizedBox(width: HkSpacing.sm),
                  ],
                  Expanded(
                    flex: secondary == null ? 1 : 2,
                    child: SizedBox(
                      height: 48,
                      child: FilledButton.icon(
                        onPressed: onPressed,
                        icon: Icon(icon, size: 18),
                        label: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(label),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
