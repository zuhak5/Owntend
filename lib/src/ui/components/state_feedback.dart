part of '../components.dart';

enum HkIllustrationTone { neutral, info, success, warning, danger }

enum HkToastSeverity { normal, error }

ScaffoldFeatureController<SnackBar, SnackBarClosedReason>? showToast(
  BuildContext context, {
  required Widget content,
  SnackBarAction? action,
  HkToastSeverity severity = HkToastSeverity.normal,
  Duration? duration,
}) {
  final tone = severity == HkToastSeverity.error
      ? HkFeedbackTone.error
      : HkFeedbackTone.neutral;
  final item = HkFeedbackItem(
    id: DateTime.now().microsecondsSinceEpoch.toString(),
    message: content,
    tone: tone,
    mode: action != null ? HkFeedbackMode.actionable : HkFeedbackMode.passive,
    actionLabel: action?.label,
    onAction: action != null ? () => action.onPressed() : null,
    duration:
        duration ??
        (action != null
            ? kActionToastDuration
            : (severity == HkToastSeverity.error
                  ? kErrorToastDuration
                  : kToastDuration)),
  );
  return FeedbackCoordinator.instance.show(context, item);
}

ScaffoldFeatureController<SnackBar, SnackBarClosedReason>? showUndoToast(
  BuildContext context, {
  required Widget content,
  required FutureOr<void> Function() onUndo,
  FutureOr<void> Function()? onFinalize,
  String? actionLabel,
  Duration duration = kActionToastDuration,
}) {
  return _showUndoSnackBar(
    context,
    content: content,
    onUndo: onUndo,
    onFinalize: onFinalize,
    actionLabel: actionLabel ?? context.l10n.undo,
    duration: duration,
    batchItemType: 'completion',
  );
}

ScaffoldFeatureController<SnackBar, SnackBarClosedReason>?
showTaskMovedToTrashSnackBar(
  BuildContext context, {
  required FutureOr<void> Function() onUndo,
  FutureOr<void> Function()? onFinalize,
  String? actionLabel,
  Duration duration = const Duration(seconds: 5),
}) {
  return showMovedToTrashSnackBar(
    context,
    content: Text(context.l10n.taskMovedToTrash),
    onUndo: onUndo,
    onFinalize: onFinalize,
    actionLabel: actionLabel,
    duration: duration,
  );
}

ScaffoldFeatureController<SnackBar, SnackBarClosedReason>?
showMovedToTrashSnackBar(
  BuildContext context, {
  required Widget content,
  required FutureOr<void> Function() onUndo,
  FutureOr<void> Function()? onFinalize,
  String? actionLabel,
  Duration duration = const Duration(seconds: 5),
}) {
  return _showUndoSnackBar(
    context,
    content: content,
    onUndo: onUndo,
    onFinalize: onFinalize,
    actionLabel: actionLabel ?? context.l10n.undo,
    duration: duration,
    batchItemType: 'trash',
    batchMessageBuilder: (count) => count == 1
        ? Text(context.l10n.taskMovedToTrash)
        : Text('${context.l10n.trashItemCount(count)} · ${context.l10n.trash}'),
  );
}

ScaffoldFeatureController<SnackBar, SnackBarClosedReason>? _showUndoSnackBar(
  BuildContext context, {
  required Widget content,
  required FutureOr<void> Function() onUndo,
  FutureOr<void> Function()? onFinalize,
  required String actionLabel,
  required Duration duration,
  EdgeInsetsGeometry? margin,
  String? batchItemType,
  Widget Function(int count)? batchMessageBuilder,
}) {
  final item = HkFeedbackItem(
    id: DateTime.now().microsecondsSinceEpoch.toString(),
    message: content,
    mode: HkFeedbackMode.undoable,
    actionLabel: actionLabel,
    onUndo: onUndo,
    onFinalize: onFinalize,
    duration: duration,
    batchItemType: batchItemType,
    batchMessageBuilder: batchMessageBuilder,
    margin: margin,
  );
  return FeedbackCoordinator.instance.show(context, item);
}

bool _reduceMotion(BuildContext context) {
  final media = MediaQuery.maybeOf(context);
  return media?.disableAnimations == true ||
      media?.accessibleNavigation == true;
}

class HkStateIllustration extends StatelessWidget {
  const HkStateIllustration({
    required this.icon,
    this.tone = HkIllustrationTone.info,
    this.size = 104,
    this.compact = false,
    super.key,
  });

  final IconData icon;
  final HkIllustrationTone tone;
  final double size;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = HkMotion.reduceMotionOf(context);
    final artwork = _StateIllustrationArtwork(
      icon: icon,
      tone: tone,
      size: size,
      compact: compact,
    );
    if (reduceMotion) {
      return artwork;
    }
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 520),
      curve: Curves.easeOutBack,
      builder: (context, value, child) => Opacity(
        opacity: value.clamp(0.0, 1.0),
        child: Transform.translate(
          offset: Offset(0, 8 * (1 - value)),
          child: Transform.scale(scale: 0.88 + (0.12 * value), child: child),
        ),
      ),
      child: artwork,
    );
  }
}

class _StateIllustrationArtwork extends StatelessWidget {
  const _StateIllustrationArtwork({
    required this.icon,
    required this.tone,
    required this.size,
    required this.compact,
  });

  final IconData icon;
  final HkIllustrationTone tone;
  final double size;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = switch (tone) {
      HkIllustrationTone.neutral => scheme.onSurfaceVariant,
      HkIllustrationTone.info => scheme.primary,
      HkIllustrationTone.success => HkColors.green,
      HkIllustrationTone.warning => HkColors.appWarning,
      HkIllustrationTone.danger => scheme.error,
    };
    final height = compact ? size : size * 0.78;
    final panelSize = compact ? size * 0.62 : size * 0.56;
    return RepaintBoundary(
      child: SizedBox(
        width: size,
        height: height,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned(
              left: size * 0.08,
              top: height * 0.18,
              child: Container(
                width: size * 0.46,
                height: height * 0.58,
                decoration: BoxDecoration(
                  color: Color.alphaBlend(
                    accent.withValues(alpha: 0.08),
                    scheme.surfaceContainerLow,
                  ),
                  borderRadius: BorderRadius.circular(HkRadii.md),
                  border: Border.all(color: accent.withValues(alpha: 0.14)),
                ),
              ),
            ),
            Positioned(
              right: size * 0.07,
              top: height * 0.08,
              child: Container(
                width: size * 0.36,
                height: height * 0.44,
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(HkRadii.sm),
                  border: Border.all(
                    color: scheme.outlineVariant.withValues(alpha: 0.55),
                  ),
                ),
              ),
            ),
            Container(
              width: panelSize,
              height: panelSize,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Color.alphaBlend(
                  accent.withValues(alpha: 0.13),
                  scheme.surfaceContainerLowest,
                ),
                borderRadius: BorderRadius.circular(HkRadii.lg),
                border: Border.all(color: accent.withValues(alpha: 0.34)),
                boxShadow: HkShadows.ambient(),
              ),
              child: Icon(
                icon,
                key: ValueKey('state-illustration-${icon.codePoint}'),
                color: accent,
                size: compact ? size * 0.30 : size * 0.28,
              ),
            ),
            Positioned(
              right: size * 0.12,
              bottom: height * 0.06,
              child: Container(
                width: compact ? 8 : 12,
                height: compact ? 8 : 12,
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(HkRadii.xs),
                  border: Border.all(
                    color: scheme.surfaceContainerLowest,
                    width: 2,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
