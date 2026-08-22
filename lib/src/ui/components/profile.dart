part of '../components.dart';

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

typedef LanguageSelectorTriggerBuilder = Widget Function(
  BuildContext context,
  String label,
  bool isOpen,
  Widget chevron,
);

/// Shared anchored locale picker used by onboarding and Settings.
class LanguageSelectorDropdown extends StatefulWidget {
  const LanguageSelectorDropdown({
    required this.language,
    required this.onChanged,
    this.selectorKey,
    this.hitTargetKey,
    this.triggerBuilder,
    this.chevronSize = 18,
    super.key,
  });

  final AppLanguage language;
  final ValueChanged<AppLanguage>? onChanged;
  final Key? selectorKey;
  final Key? hitTargetKey;
  final LanguageSelectorTriggerBuilder? triggerBuilder;
  final double chevronSize;

  @override
  State<LanguageSelectorDropdown> createState() =>
      _LanguageSelectorDropdownState();
}

class _LanguageSelectorDropdownState extends State<LanguageSelectorDropdown> {
  static const _menuGap = 6.0;

  final MenuController _menuController = MenuController();
  final GlobalKey _anchorKey = GlobalKey();
  double? _menuWidth;
  bool _isOpen = false;
  bool _openScheduled = false;

  @override
  void didUpdateWidget(covariant LanguageSelectorDropdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.onChanged == null && _menuController.isOpen) {
      _menuController.close();
    }
  }

  void _toggleMenu() {
    if (widget.onChanged == null) return;
    if (_menuController.isOpen) {
      _menuController.close();
      return;
    }
    if (_openScheduled) return;

    final width = _anchorKey.currentContext?.size?.width;
    if (width == null || width <= 0) return;
    if (_menuWidth != width) {
      _openScheduled = true;
      setState(() => _menuWidth = width);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _openScheduled = false;
        if (widget.onChanged != null && !_menuController.isOpen) {
          _menuController.open();
        }
      });
      return;
    }
    _menuController.open();
  }

  void _handleOpen() {
    if (mounted && !_isOpen) {
      setState(() => _isOpen = true);
    }
  }

  void _handleClose() {
    _openScheduled = false;
    if (mounted && _isOpen) {
      setState(() => _isOpen = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final label = languageSelectorLabel(context, widget.language);
    final reduceMotion = HkMotion.reduceMotionOf(context);
    final chevron = AnimatedRotation(
      key: const ValueKey('language-selector-chevron'),
      turns: _isOpen ? 0.5 : 0,
      duration: reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 160),
      curve: Curves.easeOutCubic,
      child: Icon(
        Symbols.expand_more_rounded,
        size: widget.chevronSize,
        color: scheme.onSurfaceVariant,
      ),
    );
    final menuWidth = _menuWidth;

    return PopScope(
      canPop: !_isOpen,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _isOpen) {
          _menuController.close();
        }
      },
      child: MenuAnchor(
        controller: _menuController,
        useRootOverlay: true,
        crossAxisUnconstrained: false,
        consumeOutsideTap: false,
        alignmentOffset: const Offset(0, _menuGap),
        style: MenuStyle(
          alignment: AlignmentDirectional.bottomStart,
          padding: const WidgetStatePropertyAll<EdgeInsetsGeometry>(
            EdgeInsets.zero,
          ),
          fixedSize: menuWidth == null
              ? null
              : WidgetStatePropertyAll<Size>(Size.fromWidth(menuWidth)),
        ),
        onOpen: _handleOpen,
        onClose: _handleClose,
        menuChildren: [
          for (final option in AppLanguage.values)
            MenuItemButton(
              key: ValueKey('language-option-${option.name}'),
              closeOnActivate: true,
              onPressed: widget.onChanged == null
                  ? null
                  : () => widget.onChanged?.call(option),
              child: Semantics(
                selected: option == widget.language,
                child: _LanguageMenuRow(
                  label: languageSelectorLabel(context, option),
                  textDirection: option == AppLanguage.ar
                      ? TextDirection.rtl
                      : TextDirection.ltr,
                  selected: option == widget.language,
                  optionName: option.name,
                ),
              ),
            ),
        ],
        builder: (context, controller, child) {
          final trigger =
              widget.triggerBuilder?.call(context, label, _isOpen, chevron) ??
              DecoratedBox(
                decoration: BoxDecoration(
                  color: _isOpen
                      ? Color.alphaBlend(
                          scheme.primary.withValues(alpha: 0.06),
                          scheme.surface.withValues(alpha: 0.94),
                        )
                      : scheme.surface.withValues(alpha: 0.94),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: _isOpen
                        ? scheme.primary.withValues(alpha: 0.72)
                        : HkColors.appBorder.withValues(alpha: 0.75),
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
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
                      chevron,
                    ],
                  ),
                ),
              );

          return SizedBox(
            key: _anchorKey,
            child: Semantics(
              key: widget.selectorKey,
              container: true,
              button: true,
              enabled: widget.onChanged != null,
              expanded: _isOpen,
              excludeSemantics: true,
              label: context.l10n.language,
              value: label,
              onTap: widget.onChanged == null ? null : _toggleMenu,
              child: ConstrainedBox(
                key: widget.hitTargetKey,
                constraints: const BoxConstraints(
                  minHeight: kOwntendHeaderActionHeight,
                ),
                child: Material(
                  type: MaterialType.transparency,
                  child: InkWell(
                    onTap: widget.onChanged == null ? null : _toggleMenu,
                    borderRadius: BorderRadius.circular(HkRadii.lg),
                    child: trigger,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _LanguageMenuRow extends StatelessWidget {
  const _LanguageMenuRow({
    required this.label,
    required this.textDirection,
    required this.selected,
    required this.optionName,
  });

  final String label;
  final TextDirection textDirection;
  final bool selected;
  final String optionName;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 32),
      child: SizedBox(
        width: double.infinity,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Padding(
              padding: const EdgeInsetsDirectional.symmetric(horizontal: 28),
              child: Directionality(
                textDirection: textDirection,
                child: Text(
                  label,
                  key: ValueKey('language-option-label-$optionName'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected ? scheme.primary : scheme.onSurface,
                  ),
                ),
              ),
            ),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: SizedBox(
                width: 20,
                child: selected
                    ? Icon(
                        Symbols.check_rounded,
                        key: ValueKey('language-option-check-$optionName'),
                        size: 18,
                        color: scheme.primary,
                      )
                    : null,
              ),
            ),
            const Align(
              alignment: AlignmentDirectional.centerEnd,
              child: SizedBox(width: 20),
            ),
          ],
        ),
      ),
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
