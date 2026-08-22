part of '../monetization.dart';

class HkPointsPill extends ConsumerWidget {
  const HkPointsPill({required this.onTap, this.compact = false, super.key});

  static const width = 82.0;

  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final balance = ref.watch(pointWalletProvider).value?.balance;
    final pointsLabel = balance == null
        ? context.l10n.pointsUnavailable
        : context.l10n.pointsCount(balance);

    // Spec Component C: independent squircle tile (border-radius: 16px).
    // The solid filled star is enclosed in a circular tinted container.
    final height = compact ? 40.0 : 44.0;
    final starCircleSize = compact ? 28.0 : 32.0;
    final innerGap = compact ? 6.0 : HkSpacing.space6;
    final hPadStart = compact ? 6.0 : HkSpacing.xs;
    final hPadEnd = compact ? 10.0 : 14.0;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(HkRadii.lg),
      side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.72)),
    );
    return Semantics(
      button: true,
      container: true,
      excludeSemantics: true,
      label: pointsLabel,
      child: Tooltip(
        message: context.l10n.pointsWallet,
        excludeFromSemantics: true,
        child: SizedBox(
          height: height,
          child: Material(
            color: scheme.surfaceContainerLowest,
            shape: shape,
            elevation: 0,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(HkRadii.lg),
                boxShadow: [
                  BoxShadow(
                    color: HkColors.appTextPrimary.withValues(alpha: 0.06),
                    blurRadius: 14,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: InkWell(
                customBorder: shape,
                onTap: onTap,
                child: Padding(
                  padding: EdgeInsetsDirectional.only(
                    start: hPadStart,
                    end: hPadEnd,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: starCircleSize,
                        height: starCircleSize,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              scheme.primaryContainer,
                              Color.alphaBlend(
                                scheme.tertiary.withValues(alpha: 0.13),
                                scheme.primaryContainer,
                              ),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(HkRadii.md),
                          border: Border.all(
                            color: scheme.primary.withValues(alpha: 0.14),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: scheme.primary.withValues(alpha: 0.12),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        alignment: Alignment.center,
                        child: Stack(
                          clipBehavior: Clip.none,
                          alignment: Alignment.center,
                          children: [
                            Icon(
                              Symbols.star_rounded,
                              size: 19,
                              color: scheme.primary,
                              fill: 1,
                            ),
                            PositionedDirectional(
                              end: 3,
                              top: 3,
                              child: Icon(
                                Symbols.auto_awesome_rounded,
                                size: 7,
                                color: scheme.tertiary,
                                fill: 1,
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(width: innerGap),
                      Text(
                        balance?.toString() ?? '-',
                        maxLines: 1,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: scheme.onSurface,
                              fontWeight: FontWeight.w700,
                              height: 1,
                            ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

bool get _supportsMobileAds =>
    !kIsWeb && (Platform.isAndroid || Platform.isIOS);
