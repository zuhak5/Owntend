import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:owntend/l10n/app_localizations_ext.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:material_symbols_icons/symbols.dart';

import '../core/domain/models.dart';
import '../core/domain/task_selectors.dart';
import '../i18n/dynamic_text.dart';
import '../core/utils/date_utils.dart' as hk_dates;
import 'app_theme.dart';
import 'feedback/feedback_coordinator.dart';
import 'feedback/feedback_model.dart';

const double kSwipeRowMinHeight = 48;
const double kSwipeRowRadius = HkRadii.lg;
const double kOwntendFabWidth = 136;
const double kOwntendFabHeight = 48;
const double kOwntendFabLabelMaxWidth = 76;
const double kOwntendBottomNavVisualHeight = 74;
const double kOwntendBottomActionBarHeight = HkSpacing.bottomAction;
const double kOwntendFloatingActionButtonBottomInset = 16;
const double kOwntendHeaderActionHeight = HkSpacing.space48;
const Duration kToastDuration = Duration(seconds: 2);
const Duration kActionToastDuration = Duration(seconds: 3);
const Duration kErrorToastDuration = Duration(seconds: 4);

class ProfileAvatar extends StatefulWidget {
  const ProfileAvatar({
    required this.fallbackName,
    this.avatarUrl,
    this.imageProvider,
    this.radius = 22,
    super.key,
  });

  final String? avatarUrl;
  final ImageProvider<Object>? imageProvider;
  final String fallbackName;
  final double radius;

  @override
  State<ProfileAvatar> createState() => _ProfileAvatarState();
}

/// A shared, theme-aware surface for compact actions in the Home header.
///
/// The visual surface and the interactive target intentionally share the same
/// 48 logical-pixel height so mouse, keyboard, switch-access, and touch users
/// receive the same affordance.
class HeaderActionSurface extends StatelessWidget {
  const HeaderActionSurface({
    required this.onPressed,
    required this.semanticLabel,
    required this.tooltip,
    required this.child,
    this.width,
    super.key,
  });

  final VoidCallback onPressed;
  final String semanticLabel;
  final String tooltip;
  final Widget child;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(HkRadii.full),
      side: BorderSide(color: scheme.outlineVariant),
    );
    return Semantics(
      button: true,
      container: true,
      excludeSemantics: true,
      label: semanticLabel,
      child: Tooltip(
        message: tooltip,
        excludeFromSemantics: true,
        child: SizedBox(
          width: width,
          height: kOwntendHeaderActionHeight,
          child: Material(
            color: scheme.surfaceContainerLowest,
            shape: shape,
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              customBorder: shape,
              onTap: onPressed,
              child: Center(child: child),
            ),
          ),
        ),
      ),
    );
  }
}

String languageSelectorLabel(BuildContext context, AppLanguage language) {
  final l10n = context.l10n;
  return switch (language) {
    AppLanguage.en => l10n.englishUs,
    AppLanguage.ar => l10n.arabic,
  };
}

/// Compact locale picker showing the active language with a dropdown menu.
class LanguageSelectorDropdown extends StatelessWidget {
  const LanguageSelectorDropdown({
    required this.language,
    required this.onChanged,
    this.selectorKey,
    this.hitTargetKey,
    super.key,
  });

  final AppLanguage language;
  final ValueChanged<AppLanguage>? onChanged;
  final Key? selectorKey;
  final Key? hitTargetKey;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final label = languageSelectorLabel(context, language);

    return Semantics(
      container: true,
      button: true,
      label: context.l10n.language,
      child: SizedBox(
        key: hitTargetKey,
        height: kOwntendHeaderActionHeight,
        child: PopupMenuButton<AppLanguage>(
          key: selectorKey,
          useRootNavigator: true,
          enabled: onChanged != null,
          tooltip: '',
          padding: EdgeInsets.zero,
          offset: const Offset(0, 6),
          onSelected: onChanged,
          itemBuilder: (context) {
            return AppLanguage.values
                .map(
                  (option) => PopupMenuItem<AppLanguage>(
                    key: ValueKey('language-option-${option.name}'),
                    value: option,
                    child: _LanguageMenuRow(
                      label: languageSelectorLabel(context, option),
                      textDirection: option == AppLanguage.ar
                          ? TextDirection.rtl
                          : TextDirection.ltr,
                      selected: option == language,
                    ),
                  ),
                )
                .toList(growable: false);
          },
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: scheme.surface.withValues(alpha: 0.94),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: HkColors.appBorder.withValues(alpha: 0.75),
              ),
              boxShadow: [
                BoxShadow(
                  color: HkColors.appTextPrimary.withValues(alpha: 0.08),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Symbols.language_rounded,
                    size: 18,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.labelSmall?.copyWith(
                        color: scheme.onSurface,
                        fontSize: 13,
                        height: 1,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Symbols.expand_more_rounded,
                    size: 18,
                    color: scheme.onSurfaceVariant,
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

class _LanguageMenuRow extends StatelessWidget {
  const _LanguageMenuRow({
    required this.label,
    required this.textDirection,
    required this.selected,
  });

  final String label;
  final TextDirection textDirection;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        SizedBox(
          width: 20,
          child: selected
              ? Icon(Symbols.check_rounded, size: 18, color: scheme.primary)
              : null,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Directionality(
            textDirection: textDirection,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? scheme.primary : scheme.onSurface,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ProfileAvatarState extends State<ProfileAvatar> {
  String? _sourceKey;
  ImageProvider<Object>? _resolvedProvider;
  ImageProvider<Object>? _previousProvider;
  bool _failed = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolveProvider();
  }

  @override
  void didUpdateWidget(covariant ProfileAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    _resolveProvider();
  }

  void _resolveProvider() {
    final avatarUrl = widget.avatarUrl?.trim();
    final logicalSize = widget.radius * 2;
    final decodedWidth = (logicalSize * MediaQuery.devicePixelRatioOf(context))
        .round();
    final key = widget.imageProvider == null
        ? 'network:${avatarUrl ?? ''}:$decodedWidth'
        : 'provider:${widget.imageProvider}:$decodedWidth';
    if (_sourceKey == key) return;
    _sourceKey = key;
    _failed = false;
    _previousProvider = _resolvedProvider;
    final source =
        widget.imageProvider ??
        (avatarUrl == null || avatarUrl.isEmpty
            ? null
            : NetworkImage(avatarUrl) as ImageProvider<Object>);
    _resolvedProvider = source == null
        ? null
        : ResizeImage.resizeIfNeeded(decodedWidth, decodedWidth, source);
    final provider = _resolvedProvider;
    if (provider != null) {
      precacheImage(
            provider,
            context,
            onError: (Object _, StackTrace? _) {
              if (mounted && _sourceKey == key) {
                setState(() {
                  _failed = true;
                  _previousProvider = null;
                });
              }
            },
          )
          .then((_) {
            if (mounted && _sourceKey == key && !_failed) {
              setState(() => _previousProvider = null);
            }
          })
          .catchError((Object _) {
            if (mounted && _sourceKey == key) {
              setState(() {
                _failed = true;
                _previousProvider = null;
              });
            }
          });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final logicalSize = widget.radius * 2;
    final provider = _failed ? null : _resolvedProvider;
    return Container(
      width: logicalSize,
      height: logicalSize,
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        shape: BoxShape.circle,
        border: Border.all(color: scheme.surfaceContainerLowest, width: 1.5),
      ),
      child: ClipOval(
        child: provider != null
            ? Image(
                image: provider,
                alignment: Alignment.center,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
                  if (wasSynchronouslyLoaded || frame != null) {
                    return child;
                  }
                  final previous = _previousProvider;
                  if (previous == null && widget.imageProvider != null) {
                    return const SizedBox.expand();
                  }
                  return previous == null
                      ? _ProfileAvatarFallback(
                          initials: _avatarInitials(widget.fallbackName),
                        )
                      : Image(
                          image: previous,
                          fit: BoxFit.cover,
                          alignment: Alignment.center,
                          gaplessPlayback: true,
                        );
                },
                errorBuilder: (context, error, stackTrace) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted && !_failed) {
                      setState(() {
                        _failed = true;
                        _previousProvider = null;
                      });
                    }
                  });
                  return _ProfileAvatarFallback(
                    initials: _avatarInitials(widget.fallbackName),
                  );
                },
              )
            : _ProfileAvatarFallback(
                initials: _avatarInitials(widget.fallbackName),
              ),
      ),
    );
  }
}

class _ProfileAvatarFallback extends StatelessWidget {
  const _ProfileAvatarFallback({required this.initials});

  final String initials;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: scheme.secondaryContainer,
      child: Center(
        child: initials.isEmpty
            ? Icon(Symbols.person_rounded, color: scheme.primary)
            : Text(
                initials,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: scheme.primary,
                  fontWeight: FontWeight.w800,
                ),
              ),
      ),
    );
  }
}

String _avatarInitials(String value) {
  final parts = value
      .trim()
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .toList(growable: false);
  if (parts.isEmpty) return 'H';
  return parts
      .take(2)
      .map((part) => part.characters.first)
      .join()
      .toUpperCase();
}

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
          Positioned(
            right: size * 0.17,
            top: size * 0.17,
            child: Container(
              width: size * 0.16,
              height: size * 0.16,
              decoration: BoxDecoration(
                color: HkColors.tertiary,
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

enum SwipeActionTone { destructive }

class SwipeAction {
  const SwipeAction({
    required this.icon,
    required this.onAction,
    this.releaseIcon,
    this.tone = SwipeActionTone.destructive,
  });

  factory SwipeAction.moveToTrash({
    required Future<bool> Function()? onAction,
  }) {
    return SwipeAction(
      icon: Symbols.delete_rounded,
      releaseIcon: Symbols.delete_rounded,
      onAction: onAction,
    );
  }

  final IconData icon;
  final IconData? releaseIcon;
  final Future<bool> Function()? onAction;
  final SwipeActionTone tone;

  String label(BuildContext context) => context.l10n.moveToTrash;

  String instruction(BuildContext context) => context.l10n.swipeToMoveToTrash;

  String releaseInstruction(BuildContext context) =>
      context.l10n.releaseToMoveToTrash;

  Color backgroundColor(ColorScheme scheme, double progress) {
    return switch (tone) {
      SwipeActionTone.destructive => Color.lerp(
        scheme.errorContainer,
        scheme.error,
        progress,
      )!,
    };
  }

  Color foregroundColor(ColorScheme scheme, double progress) {
    return switch (tone) {
      SwipeActionTone.destructive =>
        progress > 0.55 ? scheme.onError : scheme.error,
    };
  }
}

class SwipeDelete extends StatefulWidget {
  const SwipeDelete({
    required this.dismissKey,
    required this.child,
    required this.action,
    this.margin = EdgeInsets.zero,
    this.borderRadius = kSwipeRowRadius,
    this.minHeight = kSwipeRowMinHeight,
    super.key,
  });

  final Key dismissKey;
  final Widget child;
  final SwipeAction action;
  final EdgeInsetsGeometry margin;
  final double borderRadius;
  final double minHeight;

  @override
  State<SwipeDelete> createState() => _SwipeDeleteState();
}

class _SwipeDeleteState extends State<SwipeDelete> {
  static final ValueNotifier<Key?> _activeSwipeRow = ValueNotifier<Key?>(null);
  static const _closeBeforeActionDelay = Duration(milliseconds: 500);

  int _resetNonce = 0;
  double _dragProgress = 0;
  bool _releaseReached = false;
  bool _thresholdFeedbackSent = false;
  bool _actionRunning = false;

  @override
  void initState() {
    super.initState();
    _activeSwipeRow.addListener(_handleActiveSwipeRowChanged);
  }

  @override
  void didUpdateWidget(covariant SwipeDelete oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.dismissKey != widget.dismissKey &&
        _activeSwipeRow.value == oldWidget.dismissKey) {
      _activeSwipeRow.value = null;
    }
  }

  @override
  void dispose() {
    _activeSwipeRow.removeListener(_handleActiveSwipeRowChanged);
    if (_activeSwipeRow.value == widget.dismissKey) {
      _activeSwipeRow.value = null;
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final action = widget.action;
    final callback = action.onAction;
    if (callback == null) {
      return Padding(padding: widget.margin, child: widget.child);
    }
    final scheme = Theme.of(context).colorScheme;
    final progress = _dragProgress.clamp(0.0, 1.0);
    final backgroundColor = action.backgroundColor(scheme, progress);
    final foreground = action.foregroundColor(scheme, progress);
    final rowRadius = BorderRadius.circular(widget.borderRadius);
    final swipeRow = KeyedSubtree(
      key: widget.dismissKey,
      child: Semantics(
        button: true,
        label: action.label(context),
        onTap: () => _startAction(callback),
        child: Padding(
          padding: widget.margin,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final dismissibleNonce = _resetNonce;
              final dismissible = Dismissible(
                key: ValueKey('${widget.dismissKey}#$_resetNonce'),
                direction: DismissDirection.endToStart,
                dismissThresholds: const {DismissDirection.endToStart: 0.34},
                onUpdate: (details) =>
                    _handleDismissUpdate(details, dismissibleNonce),
                confirmDismiss: (_) {
                  _startAction(callback);
                  return Future<bool>.value(false);
                },
                movementDuration: const Duration(milliseconds: 140),
                child: SizedBox(
                  width: double.infinity,
                  child: ClipRRect(
                    borderRadius: rowRadius,
                    clipBehavior: Clip.antiAlias,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minHeight: widget.minHeight),
                      child: widget.child,
                    ),
                  ),
                ),
              );
              return ClipRRect(
                borderRadius: rowRadius,
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: _SwipeDeleteBackground(
                        action: action,
                        color: backgroundColor,
                        foreground: foreground,
                        releaseReached: _releaseReached,
                        progress: progress,
                      ),
                    ),
                    if (constraints.hasTightHeight)
                      Positioned.fill(child: dismissible)
                    else
                      SizedBox(width: double.infinity, child: dismissible),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
    return swipeRow;
  }

  void _handleActiveSwipeRowChanged() {
    if (_activeSwipeRow.value == widget.dismissKey ||
        (_dragProgress <= 0 && !_releaseReached)) {
      return;
    }
    _resetSwipe(clearActive: false);
  }

  void _handleDismissUpdate(
    DismissUpdateDetails details,
    int dismissibleNonce,
  ) {
    if (_actionRunning || dismissibleNonce != _resetNonce) {
      return;
    }
    if (details.progress > 0.001 &&
        _activeSwipeRow.value != widget.dismissKey) {
      _activeSwipeRow.value = widget.dismissKey;
    }
    if (details.reached && !_thresholdFeedbackSent) {
      _thresholdFeedbackSent = true;
      HapticFeedback.selectionClick();
    } else if (!details.reached) {
      _thresholdFeedbackSent = false;
    }
    if (!mounted) return;
    setState(() {
      _dragProgress = details.progress;
      _releaseReached = details.reached;
    });
  }

  void _startAction(Future<bool> Function() callback) {
    if (_actionRunning) return;
    _actionRunning = true;
    _resetSwipe();
    unawaited(_runActionAfterClose(callback));
  }

  Future<void> _runActionAfterClose(Future<bool> Function() callback) async {
    await Future<void>.delayed(_closeBeforeActionDelay);
    if (!mounted) return;
    try {
      await callback();
    } catch (_) {
      // The originating action owns user-facing error handling. A thrown action
      // must not leave the swipe row stuck open.
    } finally {
      if (mounted) {
        _resetSwipe();
        _actionRunning = false;
      }
    }
  }

  void _resetSwipe({bool clearActive = true}) {
    if (clearActive && _activeSwipeRow.value == widget.dismissKey) {
      _activeSwipeRow.value = null;
    }
    if (!mounted) return;
    setState(() {
      _dragProgress = 0;
      _releaseReached = false;
      _thresholdFeedbackSent = false;
      _resetNonce++;
    });
  }
}

class _SwipeDeleteBackground extends StatelessWidget {
  const _SwipeDeleteBackground({
    required this.action,
    required this.color,
    required this.foreground,
    required this.releaseReached,
    required this.progress,
  });

  final SwipeAction action;
  final Color color;
  final Color foreground;
  final bool releaseReached;
  final double progress;

  @override
  Widget build(BuildContext context) {
    if (progress <= 0.001) {
      return const SizedBox.expand();
    }
    final direction = Directionality.of(context);
    final icon = releaseReached
        ? action.releaseIcon ?? action.icon
        : action.icon;
    final instruction = releaseReached
        ? action.releaseInstruction(context)
        : action.instruction(context);
    return SizedBox.expand(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsetsDirectional.symmetric(
          horizontal: HkSpacing.md,
        ),
        color: color,
        alignment: AlignmentDirectional.centerEnd,
        child: Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _SwipeDeleteStreakPainter(
                  color: foreground,
                  progress: progress,
                  textDirection: direction,
                ),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                AnimatedScale(
                  scale: releaseReached ? 1.14 : 1,
                  duration: const Duration(milliseconds: 140),
                  curve: Curves.easeOutBack,
                  child: AnimatedRotation(
                    turns: releaseReached ? -0.04 : 0,
                    duration: const Duration(milliseconds: 140),
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: foreground.withValues(alpha: 0.14),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: foreground.withValues(alpha: 0.20),
                        ),
                      ),
                      child: Icon(icon, color: foreground, size: 20),
                    ),
                  ),
                ),
                const SizedBox(width: HkSpacing.xs),
                Flexible(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        action.label(context),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.end,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: foreground,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 120),
                        child: Text(
                          instruction,
                          key: ValueKey(instruction),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.end,
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: foreground.withValues(alpha: 0.82),
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SwipeDeleteStreakPainter extends CustomPainter {
  const _SwipeDeleteStreakPainter({
    required this.color,
    required this.progress,
    required this.textDirection,
  });

  final Color color;
  final double progress;
  final TextDirection textDirection;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0.02) {
      return;
    }
    final paint = Paint()
      ..color = color.withValues(alpha: (0.12 * progress).clamp(0.0, 0.12))
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 3;
    final isRtl = textDirection == TextDirection.rtl;
    final startX = isRtl
        ? size.width * (0.48 - (0.14 * (1 - progress)))
        : size.width * (0.52 + (0.14 * (1 - progress)));
    for (var index = 0; index < 4; index += 1) {
      final y = size.height * (0.28 + (index * 0.15));
      final lineLength = size.width * (0.16 + (progress * 0.08));
      canvas.drawLine(
        Offset(startX + (isRtl ? -index * 10 : index * 10), y),
        Offset(
          startX +
              (isRtl ? -lineLength - (index * 10) : lineLength + (index * 10)),
          y,
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SwipeDeleteStreakPainter oldDelegate) {
    return color != oldDelegate.color ||
        progress != oldDelegate.progress ||
        textDirection != oldDelegate.textDirection;
  }
}

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
                  const Icon(Symbols.arrow_forward_rounded, size: 16),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class CompactActionGroup extends StatelessWidget {
  const CompactActionGroup({
    required this.children,
    this.minButtonWidth = 136,
    this.maxButtonWidth,
    this.buttonHeight = 46,
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
          ? HkColors.tertiaryFixedDim.withValues(alpha: 0.28)
          : scheme.outlineVariant.withValues(alpha: 0.16),
      backgroundColor: alert
          ? Color.alphaBlend(
              HkColors.errorContainer.withValues(alpha: 0.08),
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
                color: alert ? HkColors.tertiary : scheme.onSurface,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Text(
            label.toUpperCase(),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: alert ? HkColors.tertiary : scheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            caption,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: alert ? HkColors.tertiary : color,
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
      backgroundColor: primary ? HkColors.primaryContainer : null,
      borderColor: primary ? Colors.transparent : null,
      shadows: primary
          ? HkShadows.ambient(tint: HkColors.primaryContainer)
          : null,
      child: SizedBox(
        height: 76,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              right: -18,
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
                      height: 42,
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

class StatusPill extends StatelessWidget {
  const StatusPill({
    required this.label,
    required this.color,
    this.icon,
    this.compact = false,
    this.contentType,
    this.semanticLabel,
    super.key,
  });

  final String label;
  final Color color;
  final IconData? icon;
  final bool compact;
  final String? contentType;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final pill = Container(
      constraints: BoxConstraints(minHeight: compact ? 22 : 26),
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 7 : 9,
        vertical: compact ? 3 : 4,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(HkRadii.full),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: compact ? 12 : 14, color: color),
            const SizedBox(width: HkSpacing.base),
          ],
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: compact ? 110 : 160),
            child: contentType == null
                ? Text(
                    label,
                    style: Theme.of(context).textTheme.labelMedium
                        ?.copyWith(color: color, fontWeight: FontWeight.w700),
                  )
                : DynamicText(
                    label,
                    contentType: contentType!,
                    style: Theme.of(context).textTheme.labelMedium
                        ?.copyWith(color: color, fontWeight: FontWeight.w700),
                  ),
          ),
        ],
      ),
    );
    if (semanticLabel == null) {
      return pill;
    }
    return Semantics(label: semanticLabel, child: pill);
  }
}

class ItemDueIndicator extends StatelessWidget {
  const ItemDueIndicator({required this.summary, super.key});

  final ItemTaskStatusSummary summary;

  @override
  Widget build(BuildContext context) {
    return StatusPill(
      label: itemDueLabel(context, summary),
      color: _itemDueColor(context, summary.status),
      icon: _itemDueIcon(summary.status),
      compact: true,
    );
  }
}

String itemDueLabel(BuildContext context, ItemTaskStatusSummary summary) {
  return switch (summary.status) {
    ItemDueStatus.overdue => context.l10n.itemStatusOverdue(summary.count),
    ItemDueStatus.dueToday => context.l10n.itemStatusDueToday(summary.count),
    ItemDueStatus.dueSoon => context.l10n.itemStatusDueSoon(summary.count),
    ItemDueStatus.onTrack => context.l10n.onTrack,
    ItemDueStatus.noTasks => context.l10n.noTasks,
  };
}

Color itemDueAccentColor(BuildContext context, ItemDueStatus status) {
  return _itemDueColor(context, status);
}

Color _itemDueColor(BuildContext context, ItemDueStatus status) {
  final scheme = Theme.of(context).colorScheme;
  return switch (status) {
    ItemDueStatus.overdue => HkColors.appDanger,
    ItemDueStatus.dueToday => HkColors.appWarning,
    ItemDueStatus.dueSoon => HkColors.appInfo,
    ItemDueStatus.onTrack => scheme.primary,
    ItemDueStatus.noTasks => scheme.onSurfaceVariant,
  };
}

IconData _itemDueIcon(ItemDueStatus status) {
  return switch (status) {
    ItemDueStatus.overdue => Symbols.warning_rounded,
    ItemDueStatus.dueToday => Symbols.today_rounded,
    ItemDueStatus.dueSoon => Symbols.event_upcoming_rounded,
    ItemDueStatus.onTrack => Symbols.check_circle_rounded,
    ItemDueStatus.noTasks => Symbols.remove_circle_outline_rounded,
  };
}

class _InlineSeparator extends StatelessWidget {
  const _InlineSeparator();

  @override
  Widget build(BuildContext context) {
    return Text(
      ' · ',
      style: Theme.of(context).textTheme.bodySmall
          ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
    );
  }
}

class TaskCard extends StatefulWidget {
  const TaskCard({
    required this.task,
    this.onComplete,
    this.onEdit,
    this.onSnooze,
    this.onArchive,
    this.onSetEnabled,
    this.onTap,
    this.dense = false,
    this.showChevron = false,
    this.showLocation = true,
    this.margin,
    super.key,
  });

  final TaskItem task;
  final Future<bool> Function()? onComplete;
  final VoidCallback? onEdit;
  final VoidCallback? onSnooze;
  final VoidCallback? onArchive;
  final Future<void> Function(bool enabled)? onSetEnabled;
  final VoidCallback? onTap;
  final bool dense;
  final bool showChevron;
  final bool showLocation;
  final EdgeInsetsGeometry? margin;

  @override
  State<TaskCard> createState() => _TaskCardState();
}

class _TaskCardState extends State<TaskCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _completionController;
  bool _completing = false;

  @override
  void initState() {
    super.initState();
    _completionController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
      reverseDuration: const Duration(milliseconds: 180),
    );
  }

  @override
  void dispose() {
    _completionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _completionController,
      builder: (context, _) => _buildCard(context, _completionController.value),
    );
  }

  Widget _buildCard(BuildContext context, double completionProgress) {
    final task = widget.task;
    final disabled = !task.plan.isEnabled;
    final onComplete = disabled ? null : widget.onComplete;
    final onEdit = widget.onEdit;
    final onSnooze = disabled ? null : widget.onSnooze;
    final onArchive = widget.onArchive;
    final onSetEnabled = widget.onSetEnabled;
    final onTap = widget.onTap;
    final dense = widget.dense;
    final showChevron = widget.showChevron;
    final showLocation = widget.showLocation;
    final margin = widget.margin;
    final scheme = Theme.of(context).colorScheme;
    final colors = _taskColors(
      task.status,
      task.plan.priority,
      disabled: disabled,
    );
    final completed = task.status == TaskStatus.completed;
    final visuallyCompleted = completed || completionProgress > 0.52;
    final locationText = '${task.asset.name} · ${task.room.name}';
    final primaryMeta =
        '${_localizedCategoryName(context, task.category.name)} · ${_localizedPriorityLabel(context, task.plan.priority)}';
    final statusText = _statusText(context, task);
    final card = PremiumCard(
      margin:
          margin ??
          EdgeInsets.only(bottom: dense ? HkSpacing.xs : HkSpacing.sm),
      padding: EdgeInsets.symmetric(
        horizontal: dense ? HkSpacing.xs : 9,
        vertical: dense ? HkSpacing.space6 : 7,
      ),
      borderRadius: kSwipeRowRadius,
      backgroundColor: Color.alphaBlend(
        scheme.primary.withValues(alpha: 0.10 * completionProgress),
        scheme.surfaceContainerLowest,
      ),
      borderColor: Color.lerp(
        !disabled && task.status == TaskStatus.overdue
            ? HkColors.appDanger.withValues(alpha: 0.22)
            : scheme.outlineVariant,
        scheme.primary.withValues(alpha: 0.55),
        completionProgress,
      ),
      shadows: const [],
      child: Stack(
        children: [
          if (completionProgress > 0)
            Positioned.fill(
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: FractionallySizedBox(
                  key: const ValueKey('task-completion-sweep'),
                  widthFactor: completionProgress.clamp(0.0, 1.0),
                  child: ColoredBox(
                    color: scheme.primary.withValues(alpha: 0.07),
                  ),
                ),
              ),
            ),
          if (!disabled && task.status == TaskStatus.overdue)
            PositionedDirectional(
              start: -10,
              top: -10,
              bottom: -10,
              child: Container(width: 3, color: colors.accent),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: dense ? 28 : 30,
                height: dense ? 28 : 30,
                decoration: BoxDecoration(
                  color: colors.container,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _taskIcon(task),
                  color: colors.accent,
                  size: dense ? 16 : 17,
                ),
              ),
              const SizedBox(width: HkSpacing.xs),
              Expanded(
                child: Opacity(
                  opacity: visuallyCompleted
                      ? 0.62
                      : disabled
                      ? 0.82
                      : 1 - (0.20 * completionProgress),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      DynamicText(
                        task.plan.title,
                        contentType: 'maintenance_plan.title',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          decoration: visuallyCompleted
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        primaryMeta,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: disabled
                              ? scheme.onSurfaceVariant
                              : colors.accent,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        runSpacing: 1,
                        children: [
                          Icon(
                            Symbols.autorenew_rounded,
                            size: 14,
                            color: scheme.primary,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            _recurrenceText(context, task.plan.recurrence),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                          const _InlineSeparator(),
                          if (disabled)
                            StatusPill(
                              label: context.l10n.disabled,
                              color: scheme.onSurfaceVariant,
                              icon: Symbols.pause_circle_rounded,
                              compact: true,
                              semanticLabel: context.l10n.taskDisabled,
                            )
                          else
                            Text(
                              statusText,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: task.status == TaskStatus.overdue
                                        ? colors.accent
                                        : scheme.onSurfaceVariant,
                                    fontWeight:
                                        task.status == TaskStatus.overdue
                                        ? FontWeight.w600
                                        : FontWeight.w400,
                                  ),
                            ),
                          if (showLocation) ...[
                            const _InlineSeparator(),
                            DynamicText(
                              locationText,
                              contentType: 'task.location',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: scheme.onSurfaceVariant),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: HkSpacing.space4),
              if (onComplete != null ||
                  onEdit != null ||
                  onSnooze != null ||
                  onArchive != null ||
                  onSetEnabled != null)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (onComplete != null)
                      IconButton(
                        tooltip: context.l10n.completeTask,
                        onPressed: _completing ? null : _handleComplete,
                        iconSize: 20,
                        style: IconButton.styleFrom(
                          backgroundColor: scheme.primary.withValues(
                            alpha: 0.10 + (0.75 * completionProgress),
                          ),
                          foregroundColor: Color.lerp(
                            scheme.primary,
                            scheme.onPrimary,
                            completionProgress,
                          ),
                          minimumSize: Size.square(dense ? 36 : 38),
                          fixedSize: Size.square(dense ? 36 : 38),
                          padding: EdgeInsets.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        icon: Icon(
                          completionProgress > 0.52
                              ? Symbols.check_rounded
                              : Symbols.check_circle_rounded,
                        ),
                      ),
                    if (onComplete != null &&
                        (onEdit != null ||
                            onSnooze != null ||
                            onArchive != null ||
                            onSetEnabled != null))
                      const SizedBox(width: HkSpacing.space4),
                    if (onEdit != null ||
                        onSnooze != null ||
                        onArchive != null ||
                        onSetEnabled != null)
                      Container(
                        width: dense ? 36 : 38,
                        height: dense ? 36 : 38,
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerLow,
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: PopupMenuButton<String>(
                            useRootNavigator: true,
                            tooltip: context.l10n.taskActions,
                            padding: EdgeInsets.zero,
                            iconSize: 20,
                            icon: Icon(
                              Symbols.more_vert_rounded,
                              color: scheme.onSurfaceVariant,
                            ),
                            onSelected: (value) {
                              if (value == 'edit') {
                                onEdit?.call();
                              } else if (value == 'snooze') {
                                onSnooze?.call();
                              } else if (value == 'archive') {
                                onArchive?.call();
                              } else if (value == 'set_enabled') {
                                final callback = onSetEnabled;
                                if (callback != null) {
                                  unawaited(callback(disabled));
                                }
                              }
                            },
                            itemBuilder: (context) => [
                              if (onEdit != null)
                                PopupMenuItem(
                                  value: 'edit',
                                  child: _TaskMenuActionLabel(
                                    icon: Symbols.edit_rounded,
                                    label: context.l10n.editPlan,
                                  ),
                                ),
                              if (onSnooze != null)
                                PopupMenuItem(
                                  value: 'snooze',
                                  child: _TaskMenuActionLabel(
                                    icon: Symbols.snooze_rounded,
                                    label: context.l10n.snooze,
                                  ),
                                ),
                              if (onSetEnabled != null)
                                PopupMenuItem(
                                  value: 'set_enabled',
                                  child: _TaskMenuActionLabel(
                                    icon: disabled
                                        ? Symbols.play_circle_rounded
                                        : Symbols.pause_circle_rounded,
                                    label: disabled
                                        ? context.l10n.enableTask
                                        : context.l10n.disableTask,
                                  ),
                                ),
                              if (onArchive != null)
                                PopupMenuItem(
                                  value: 'archive',
                                  child: _TaskMenuActionLabel(
                                    icon: Symbols.delete_rounded,
                                    label: context.l10n.moveTaskToTrash,
                                    destructive: true,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                  ],
                )
              else if (showChevron)
                Icon(
                  Symbols.chevron_right_rounded,
                  color: scheme.outlineVariant,
                  size: 20,
                ),
            ],
          ),
        ],
      ),
    );
    if (onTap == null) {
      return _scaleForCompletion(card, completionProgress);
    }
    final interactiveCard = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _completing ? null : onTap,
      child: card,
    );
    return _scaleForCompletion(interactiveCard, completionProgress);
  }

  Widget _scaleForCompletion(Widget child, double progress) {
    final scale = progress <= 0.5
        ? 1 - (0.025 * (progress / 0.5))
        : 0.975 + (0.025 * ((progress - 0.5) / 0.5));
    return Transform.scale(scale: scale, child: child);
  }

  Future<void> _handleComplete() async {
    final callback = widget.onComplete;
    if (callback == null || _completing) {
      return;
    }
    setState(() => _completing = true);
    final reduceMotion = HkMotion.reduceMotionOf(context);
    if (reduceMotion) {
      _completionController.value = 1;
    } else {
      unawaited(_completionController.forward(from: 0));
    }
    var success = false;
    try {
      success = await callback();
    } catch (_) {
      success = false;
    }
    if (!mounted) {
      return;
    }
    if (!success || widget.task.status != TaskStatus.completed) {
      await _completionController.reverse();
    }
    if (mounted) {
      setState(() => _completing = false);
    }
  }
}

class _TaskMenuActionLabel extends StatelessWidget {
  const _TaskMenuActionLabel({
    required this.icon,
    required this.label,
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = destructive ? scheme.error : scheme.onSurface;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: HkSpacing.sm),
        Flexible(
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontWeight: destructive ? FontWeight.w700 : FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class ToolTile extends StatelessWidget {
  const ToolTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    super.key,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PremiumCard(
      margin: const EdgeInsets.only(bottom: HkSpacing.xs),
      padding: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(HkRadii.lg),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: scheme.secondaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: scheme.primary, size: 18),
              ),
              const SizedBox(width: HkSpacing.xs),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: HkSpacing.space4),
              Icon(
                Symbols.chevron_right_rounded,
                color: scheme.outline,
                size: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum SereneBottomNavLabel { home, rooms, tasks, calendar, tools }

class SereneBottomNavDestination {
  const SereneBottomNavDestination({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });

  final IconData icon;
  final IconData selectedIcon;
  final SereneBottomNavLabel label;
}

class SereneBottomNavigationBar extends StatelessWidget {
  const SereneBottomNavigationBar({
    required this.selectedIndex,
    required this.destinations,
    required this.onDestinationSelected,
    super.key,
  });

  final int selectedIndex;
  final List<SereneBottomNavDestination> destinations;
  final ValueChanged<int> onDestinationSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Align(
        alignment: Alignment.bottomCenter,
        heightFactor: 1.0,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(HkRadii.xxl),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerLowest.withValues(
                      alpha: 0.91,
                    ),
                    borderRadius: BorderRadius.circular(HkRadii.xxl),
                    border: Border.all(
                      color: scheme.outlineVariant.withValues(alpha: 0.28),
                    ),
                    boxShadow: HkShadows.ambient(tint: scheme.primary),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 5, 8, 5),
                    child: Row(
                      children: [
                        for (
                          var index = 0;
                          index < destinations.length;
                          index++
                        )
                          Expanded(
                            child: _BottomNavItem(
                              destination: destinations[index],
                              selected: selectedIndex == index,
                              onTap: () => onDestinationSelected(index),
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
      ),
    );
  }
}

class _BottomNavItem extends StatelessWidget {
  const _BottomNavItem({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final SereneBottomNavDestination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = selected ? scheme.primary : scheme.onSurfaceVariant;
    final label = switch (destination.label) {
      SereneBottomNavLabel.home => context.l10n.home,
      SereneBottomNavLabel.rooms => context.l10n.rooms,
      SereneBottomNavLabel.tasks => context.l10n.tasks,
      SereneBottomNavLabel.calendar => context.l10n.calendar,
      SereneBottomNavLabel.tools => context.l10n.tools,
    };
    return Semantics(
      selected: selected,
      button: true,
      label: label,
      child: InkWell(
        borderRadius: BorderRadius.circular(HkRadii.lg),
        onTap: onTap,
        child: SizedBox(
          height: 52,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: selected ? 42 : 32,
                height: 24,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected
                      ? scheme.primary.withValues(alpha: 0.13)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(HkRadii.full),
                ),
                child: Icon(
                  selected ? destination.selectedIcon : destination.icon,
                  color: color,
                  size: 19,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: color,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

IconData iconForHealthGroup(HealthGroup group) {
  return switch (group) {
    HealthGroup.safety => Symbols.health_and_safety_rounded,
    HealthGroup.pets => Symbols.pets_rounded,
    HealthGroup.appliances => Symbols.kitchen_rounded,
    HealthGroup.plants => Symbols.local_florist_rounded,
    HealthGroup.cleaning => Symbols.cleaning_services_rounded,
    HealthGroup.other => Symbols.home_repair_service_rounded,
  };
}

IconData _taskIcon(TaskItem task) {
  if (!task.plan.isEnabled) {
    return Symbols.pause_circle_rounded;
  }
  if (task.status == TaskStatus.completed) {
    return Symbols.check_circle_rounded;
  }
  if (task.status == TaskStatus.overdue) {
    return task.plan.healthGroup == HealthGroup.appliances
        ? Symbols.water_drop_rounded
        : Symbols.warning_rounded;
  }
  return iconForHealthGroup(task.plan.healthGroup);
}

String _statusText(BuildContext context, TaskItem task) {
  final dueDate = task.plan.nextDueDate;
  final now = DateTime.now();
  return switch (task.status) {
    TaskStatus.overdue => context.l10n.statusOverdueBy(
      _overdueDayText(context, dueDate, now),
    ),
    TaskStatus.dueToday => _dueTodayText(context, dueDate, now),
    TaskStatus.upcoming => context.l10n.statusDueDate(
      _formatTaskDueDate(context, dueDate),
    ),
    TaskStatus.completed => context.l10n.completedToday,
  };
}

String _formatTaskDueDate(BuildContext context, DateTime dueDate) {
  final locale = Localizations.maybeLocaleOf(context)?.toString();
  try {
    return DateFormat.MMMd(locale).add_jm().format(dueDate);
  } on Object {
    return DateFormat.MMMd().add_jm().format(dueDate);
  }
}

String _overdueDayText(BuildContext context, DateTime dueDate, DateTime now) {
  final days = hk_dates.daysBetweenDates(dueDate, now).clamp(1, 10000);
  return days == 1
      ? context.l10n.durationDay(days)
      : context.l10n.durationDays(days);
}

String _dueTodayText(BuildContext context, DateTime dueDate, DateTime now) {
  final remaining = dueDate.difference(now);
  if (remaining.inMinutes <= 0) {
    return context.l10n.dueNow;
  }
  return context.l10n.statusDueIn(_durationText(context, remaining));
}

String _durationText(BuildContext context, Duration duration) {
  final minutes = duration.inMinutes.abs();
  if (minutes < 60) {
    return context.l10n.durationMinutesShort(minutes.clamp(1, 59));
  }
  if (minutes < 24 * 60) {
    final hours = minutes ~/ 60;
    final remainder = minutes % 60;
    return context.l10n.durationHoursMinutesShort(hours, remainder);
  }
  final days = minutes ~/ (24 * 60);
  return days == 1
      ? context.l10n.durationDay(days)
      : context.l10n.durationDays(days);
}

String _recurrenceText(BuildContext context, RecurrenceRule rule) {
  final unit = _localizedRecurrenceUnit(context, rule);
  if (rule.interval == 1) {
    return context.l10n.recurrenceEveryOne(unit);
  }
  return context.l10n.recurrenceEveryMany(rule.interval, unit);
}

String _localizedRecurrenceUnit(BuildContext context, RecurrenceRule rule) {
  final plural = rule.interval != 1;
  return switch (rule.unit) {
    RecurrenceUnit.hours => plural ? context.l10n.hours2 : context.l10n.hour,
    RecurrenceUnit.days => plural ? context.l10n.days2 : context.l10n.day,
    RecurrenceUnit.weeks => plural ? context.l10n.weeks2 : context.l10n.week,
    RecurrenceUnit.months => plural ? context.l10n.months2 : context.l10n.month,
    RecurrenceUnit.years => plural ? context.l10n.years2 : context.l10n.year,
  };
}

String _localizedPriorityLabel(BuildContext context, PriorityLevel priority) =>
    switch (priority) {
      PriorityLevel.low => context.l10n.routine,
      PriorityLevel.medium => context.l10n.medium,
      PriorityLevel.high => context.l10n.high,
      PriorityLevel.critical => context.l10n.critical,
    };

String _localizedCategoryName(BuildContext context, String name) =>
    switch (name) {
      'Safety' => context.l10n.safety,
      'Pets' => context.l10n.pets,
      'Appliances' => context.l10n.appliances,
      'Plants' => context.l10n.plants,
      'Cleaning' => context.l10n.cleaning,
      'General' => context.l10n.general,
      _ => name,
    };

_TaskColors _taskColors(
  TaskStatus status,
  PriorityLevel priority, {
  bool disabled = false,
}) {
  if (disabled) {
    return const _TaskColors(HkColors.onSurfaceVariant, HkColors.surfaceDim);
  }
  if (status == TaskStatus.completed) {
    return const _TaskColors(HkColors.primary, HkColors.primaryFixed);
  }
  if (status == TaskStatus.overdue || priority == PriorityLevel.critical) {
    return const _TaskColors(HkColors.appDanger, HkColors.appDangerSurface);
  }
  if (priority == PriorityLevel.high) {
    return const _TaskColors(HkColors.appWarning, HkColors.appWarningSurface);
  }
  return const _TaskColors(HkColors.onSurfaceVariant, HkColors.appSurfaceGreen);
}

class _TaskColors {
  const _TaskColors(this.accent, this.container);

  final Color accent;
  final Color container;
}

class AppPageHeader extends StatelessWidget {
  const AppPageHeader({
    required this.title,
    this.subtitle,
    this.onBack,
    super.key,
  });

  final String title;
  final String? subtitle;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final titleTheme = Theme.of(context).textTheme.headlineMedium;
    final subtitleTheme = Theme.of(context).textTheme.bodyMedium;
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          HkSpacing.gutter,
          8,
          HkSpacing.gutter,
          0,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (onBack != null)
              SizedBox.square(
                dimension: 48,
                child: IconButton(
                  tooltip: context.l10n.back,
                  onPressed: onBack,
                  icon: const Icon(Symbols.arrow_back_rounded),
                ),
              )
            else
              const SizedBox(width: 48),
            const SizedBox(width: 4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(title, textAlign: TextAlign.center, style: titleTheme),
                  if (subtitle != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      subtitle!,
                      textAlign: TextAlign.center,
                      style: subtitleTheme?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 48),
          ],
        ),
      ),
    );
  }
}

class SurfaceCard extends StatelessWidget {
  const SurfaceCard({
    required this.child,
    this.padding = const EdgeInsets.all(HkSpacing.md),
    this.backgroundColor,
    this.borderColor,
    this.radius = HkRadii.xl,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? backgroundColor;
  final Color? borderColor;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return PremiumCard(
      padding: padding,
      borderRadius: radius,
      backgroundColor: backgroundColor,
      borderColor: borderColor,
      child: child,
    );
  }
}

class StatusChip extends StatelessWidget {
  const StatusChip({
    required this.label,
    this.positive = false,
    this.warning = false,
    this.negative = false,
    super.key,
  });

  final String label;
  final bool positive;
  final bool warning;
  final bool negative;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = negative
        ? scheme.error
        : warning
        ? HkColors.appWarning
        : positive
        ? scheme.primary
        : scheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(HkRadii.full),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium
            ?.copyWith(color: color, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class SettingsRow extends StatelessWidget {
  const SettingsRow({
    required this.icon,
    required this.title,
    this.subtitle,
    this.value,
    this.sizeScale = 1,
    this.trailing,
    this.onTap,
    super.key,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final String? value;
  final double sizeScale;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final trailingWidgets = trailing == null
        ? const <Widget>[]
        : <Widget>[trailing!];
    final child = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: HkSpacing.md,
        vertical: 12,
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary
                  .withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(HkRadii.md),
            ),
            child: Icon(
              icon,
              size: 20,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(width: HkSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleSmall),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                if (value != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    value!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      height: 1.25 * sizeScale,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: HkSpacing.sm),
          ...trailingWidgets,
          if (onTap != null) ...[
            const SizedBox(width: 6),
            Icon(
              Symbols.chevron_right_rounded,
              size: 20,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ],
        ],
      ),
    );
    return Material(
      color: Colors.transparent,
      child: InkWell(onTap: onTap, child: child),
    );
  }
}
