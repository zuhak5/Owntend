part of '../components.dart';

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
