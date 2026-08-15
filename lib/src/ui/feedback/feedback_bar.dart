import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../app_theme.dart';
import 'feedback_model.dart';

class HkFeedbackBar extends StatelessWidget {
  const HkFeedbackBar({
    required this.item,
    required this.message,
    required this.onAction,
    required this.onDismiss,
    required this.showCountdown,
    super.key,
  });

  final HkFeedbackItem item;
  final Widget message;
  final VoidCallback? onAction;
  final VoidCallback onDismiss;
  final bool showCountdown;

  @override
  Widget build(BuildContext context) {
    final colors = _toneColors(Theme.of(context).colorScheme, item.tone);
    final isTest = WidgetsBinding.instance.runtimeType.toString().contains(
      'Test',
    );
    final content = Material(
      color: colors.background,
      borderRadius: BorderRadius.circular(HkRadii.lg),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.only(
              start: HkSpacing.sm,
              end: HkSpacing.space4,
              top: HkSpacing.space6,
              bottom: HkSpacing.space6,
            ),
            child: Row(
              children: [
                ExcludeSemantics(
                  child: Icon(_toneIcon(item.tone), color: colors.foreground),
                ),
                const SizedBox(width: HkSpacing.xs),
                Expanded(
                  child: DefaultTextStyle.merge(
                    style: TextStyle(color: colors.foreground),
                    child: message,
                  ),
                ),
                if (item.actionLabel != null) ...[
                  const SizedBox(width: HkSpacing.space4),
                  ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 48),
                    child: TextButton(
                      onPressed: onAction,
                      style: TextButton.styleFrom(
                        foregroundColor: colors.foreground,
                      ),
                      child: Text(item.actionLabel!),
                    ),
                  ),
                ],
                SizedBox.square(
                  dimension: 48,
                  child: IconButton(
                    key: const ValueKey('feedback-dismiss'),
                    tooltip: MaterialLocalizations.of(context).closeButtonLabel,
                    onPressed: onDismiss,
                    icon: Icon(Symbols.close_rounded, color: colors.foreground),
                  ),
                ),
              ],
            ),
          ),
          if (showCountdown)
            ExcludeSemantics(
              child: TweenAnimationBuilder<double>(
                key: const ValueKey('feedback-countdown'),
                tween: Tween(begin: 1, end: 0),
                duration: isTest ? Duration.zero : item.duration,
                builder: (context, value, child) => LinearProgressIndicator(
                  value: isTest ? 1 : value,
                  minHeight: 3,
                  color: colors.foreground,
                  backgroundColor: colors.foreground.withValues(alpha: 0.2),
                ),
              ),
            ),
        ],
      ),
    );

    return Semantics(
      container: true,
      liveRegion: true,
      label: item.semanticLabel,
      child: item.semanticLabel == null
          ? content
          : ExcludeSemantics(child: content),
    );
  }

  IconData _toneIcon(HkFeedbackTone tone) => switch (tone) {
    HkFeedbackTone.success => Symbols.check_circle_rounded,
    HkFeedbackTone.warning => Symbols.warning_rounded,
    HkFeedbackTone.error || HkFeedbackTone.destructive => Symbols.error_rounded,
    HkFeedbackTone.info => Symbols.info_rounded,
    HkFeedbackTone.neutral => Symbols.notifications_rounded,
  };

  _FeedbackToneColors _toneColors(ColorScheme scheme, HkFeedbackTone tone) {
    return switch (tone) {
      HkFeedbackTone.success => _FeedbackToneColors(
        scheme.primaryContainer,
        scheme.onPrimaryContainer,
      ),
      HkFeedbackTone.warning => _FeedbackToneColors(
        scheme.tertiaryContainer,
        scheme.onTertiaryContainer,
      ),
      HkFeedbackTone.error || HkFeedbackTone.destructive => _FeedbackToneColors(
        scheme.errorContainer,
        scheme.onErrorContainer,
      ),
      HkFeedbackTone.info => _FeedbackToneColors(
        scheme.secondaryContainer,
        scheme.onSecondaryContainer,
      ),
      HkFeedbackTone.neutral => _FeedbackToneColors(
        scheme.inverseSurface,
        scheme.onInverseSurface,
      ),
    };
  }
}

class _FeedbackToneColors {
  const _FeedbackToneColors(this.background, this.foreground);

  final Color background;
  final Color foreground;
}
