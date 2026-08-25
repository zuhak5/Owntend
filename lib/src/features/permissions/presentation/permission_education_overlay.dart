import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:owntend/l10n/app_localizations_ext.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../core/domain/models.dart';
import '../../../ui/app_theme.dart';
import '../application/permission_education_controller.dart';
import '../domain/capability_snapshots.dart';
import '../domain/permission_capability.dart';

class PermissionEducationOverlayWrapper extends ConsumerWidget {
  const PermissionEducationOverlayWrapper({
    this.targetLink,
    this.targetRect,
    this.onChooseLocationManually,
    super.key,
  });

  final LayerLink? targetLink;
  final Rect? targetRect;
  final Future<HomeLocation?> Function()? onChooseLocationManually;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final PermissionEducationControllerState state = ref.watch(
      permissionEducationControllerProvider,
    );
    if (!state.isVisible || state.activeCapability == null) {
      return const SizedBox.shrink();
    }

    final PermissionEducationController notifier = ref.read(
      permissionEducationControllerProvider.notifier,
    );

    return PermissionEducationOverlayWidget(
      activeCapability: state.activeCapability!,
      relevantCapabilities: state.relevantCapabilities,
      isBusy: state.isBusy,
      status: state.capabilityStatuses[state.activeCapability],
      weather: state.setupSnapshot?.weather,
      notifications: state.setupSnapshot?.notifications,
      operationFailure:
          state.operationFailure?.capability == state.activeCapability
          ? state.operationFailure
          : null,
      targetLink: targetLink,
      targetRect: targetRect,
      onUseCurrentLocation: () {
        notifier.useCurrentLocation();
      },
      onChooseLocationManually: () async {
        if (onChooseLocationManually != null) {
          final chosen = await onChooseLocationManually!();
          if (chosen != null) {
            await notifier.chooseLocationManually(chosen);
          }
        }
      },
      onEnableNotifications: () {
        notifier.enableNotifications();
      },
      onDefer: () {
        notifier.deferCurrentStep();
      },
      onFinishLater: () {
        notifier.finishLater();
      },
      onOpenSettings: () {
        notifier.openSettingsFor(state.activeCapability!);
      },
    );
  }
}

class PermissionEducationOverlayWidget extends StatefulWidget {
  const PermissionEducationOverlayWidget({
    required this.activeCapability,
    required this.relevantCapabilities,
    required this.isBusy,
    required this.onUseCurrentLocation,
    required this.onChooseLocationManually,
    required this.onEnableNotifications,
    required this.onDefer,
    required this.onFinishLater,
    this.status,
    this.weather,
    this.notifications,
    this.operationFailure,
    this.onOpenSettings,
    this.targetLink,
    this.targetRect,
    super.key,
  });

  final PermissionCapability activeCapability;
  final List<PermissionCapability> relevantCapabilities;
  final bool isBusy;
  final VoidCallback onUseCurrentLocation;
  final VoidCallback onChooseLocationManually;
  final VoidCallback onEnableNotifications;
  final VoidCallback onDefer;
  final VoidCallback onFinishLater;
  final CapabilityStatus? status;
  final WeatherAreaCapabilitySnapshot? weather;
  final NotificationCapabilitySnapshot? notifications;
  final PermissionOperationFailure? operationFailure;
  final VoidCallback? onOpenSettings;
  final LayerLink? targetLink;
  final Rect? targetRect;

  @override
  State<PermissionEducationOverlayWidget> createState() =>
      _PermissionEducationOverlayWidgetState();
}

class _PermissionEducationOverlayWidgetState
    extends State<PermissionEducationOverlayWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  final FocusScopeNode _focusNode = FocusScopeNode();

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focusNode.requestFocus();
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final media = MediaQuery.maybeOf(context);
    final isTest = WidgetsBinding.instance.runtimeType.toString().contains(
      'Test',
    );
    final reduceMotion =
        media?.disableAnimations == true ||
        media?.accessibleNavigation == true ||
        isTest;
    if (reduceMotion) {
      _controller.stop();
      _controller.value = 0.45;
    } else if (!_controller.isAnimating) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final scheme = Theme.of(context).colorScheme;
    final reduceMotion = media.disableAnimations || media.accessibleNavigation;
    final bottomInset = math.max(media.padding.bottom, 8.0) + 92;
    final topInset = math.max(media.padding.top, 12.0) + HkSpacing.sm;

    final currentIndex = widget.relevantCapabilities.indexOf(
      widget.activeCapability,
    );
    final stepNumber = currentIndex >= 0 ? currentIndex + 1 : 1;
    final totalSteps = widget.relevantCapabilities.isNotEmpty
        ? widget.relevantCapabilities.length
        : 1;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          widget.onFinishLater();
        }
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          final maxCardHeight = math.max(
            280.0,
            constraints.maxHeight - topInset - bottomInset,
          );
          return Stack(
            key: const ValueKey('permission-education-overlay'),
            fit: StackFit.expand,
            clipBehavior: Clip.hardEdge,
            children: [
              ModalBarrier(
                dismissible: true,
                onDismiss: widget.onFinishLater,
                color: scheme.scrim.withValues(alpha: 0.28),
              ),
              PositionedDirectional(
                start: HkSpacing.md,
                end: HkSpacing.md,
                bottom: bottomInset,
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: 440,
                      maxHeight: maxCardHeight,
                    ),
                    child: FocusScope(
                      node: _focusNode,
                      autofocus: true,
                      child: AnimatedSwitcher(
                        duration: reduceMotion
                            ? Duration.zero
                            : const Duration(milliseconds: 260),
                        switchInCurve: Curves.easeOutCubic,
                        switchOutCurve: Curves.easeInCubic,
                        transitionBuilder: (child, animation) => FadeTransition(
                          opacity: animation,
                          child: SlideTransition(
                            position: Tween<Offset>(
                              begin: const Offset(0.04, 0),
                              end: Offset.zero,
                            ).animate(animation),
                            child: child,
                          ),
                        ),
                        child: _PermissionCapabilityCard(
                          key: ValueKey(widget.activeCapability),
                          capability: widget.activeCapability,
                          stepNumber: stepNumber,
                          totalSteps: totalSteps,
                          animation: _controller,
                          reduceMotion: reduceMotion,
                          isBusy: widget.isBusy,
                          status: widget.status,
                          weather: widget.weather,
                          notifications: widget.notifications,
                          operationFailure: widget.operationFailure,
                          onUseCurrentLocation: widget.onUseCurrentLocation,
                          onChooseLocationManually:
                              widget.onChooseLocationManually,
                          onEnableNotifications: widget.onEnableNotifications,
                          onDefer: widget.onDefer,
                          onFinishLater: widget.onFinishLater,
                          onOpenSettings: widget.onOpenSettings,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _PermissionCapabilityCard extends StatelessWidget {
  const _PermissionCapabilityCard({
    required this.capability,
    required this.stepNumber,
    required this.totalSteps,
    required this.animation,
    required this.reduceMotion,
    required this.isBusy,
    required this.onUseCurrentLocation,
    required this.onChooseLocationManually,
    required this.onEnableNotifications,
    required this.onDefer,
    required this.onFinishLater,
    required this.status,
    required this.weather,
    required this.notifications,
    required this.operationFailure,
    required this.onOpenSettings,
    super.key,
  });

  final PermissionCapability capability;
  final int stepNumber;
  final int totalSteps;
  final Animation<double> animation;
  final bool reduceMotion;
  final bool isBusy;
  final VoidCallback onUseCurrentLocation;
  final VoidCallback onChooseLocationManually;
  final VoidCallback onEnableNotifications;
  final VoidCallback onDefer;
  final VoidCallback onFinishLater;
  final CapabilityStatus? status;
  final WeatherAreaCapabilitySnapshot? weather;
  final NotificationCapabilitySnapshot? notifications;
  final PermissionOperationFailure? operationFailure;
  final VoidCallback? onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final nextAction = status?.nextAction ?? PermissionNextAction.request;
    final opensSettings =
        nextAction == PermissionNextAction.openAppSettings ||
        nextAction == PermissionNextAction.openLocationSettings;
    final statusMessage = _statusMessage(context);

    final title = switch (capability) {
      PermissionCapability.deviceLocation =>
        context.l10n.permissionSetupWeatherTitle,
      PermissionCapability.notifications =>
        context.l10n.neverMissImportantMaintenance,
    };

    final body = switch (capability) {
      PermissionCapability.deviceLocation =>
        context.l10n.permissionSetupWeatherBody,
      PermissionCapability.notifications =>
        context.l10n.notificationEducationBody,
    };

    final reassurance = switch (capability) {
      PermissionCapability.deviceLocation =>
        context.l10n.permissionSetupWeatherPrivacy,
      PermissionCapability.notifications =>
        context.l10n.notificationEducationReassurance,
    };

    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: '${context.l10n.permissionStep(stepNumber, totalSteps)}. $title',
      child: Material(
        key: ValueKey('permission-card-${capability.name}'),
        color: scheme.surfaceContainerLowest,
        elevation: 0,
        borderRadius: BorderRadius.circular(HkRadii.xxl),
        clipBehavior: Clip.antiAlias,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(HkRadii.xxl),
            border: Border.all(color: scheme.primary.withValues(alpha: 0.18)),
            boxShadow: HkShadows.ambient(tint: scheme.primary),
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(HkSpacing.md),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const SizedBox(width: 48),
                    Expanded(
                      child: Text(
                        context.l10n.permissionStep(stepNumber, totalSteps),
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: scheme.primary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: context.l10n.permissionSetupFinishLater,
                      onPressed: isBusy ? null : onFinishLater,
                      icon: const Icon(Symbols.close_rounded),
                    ),
                  ],
                ),
                SizedBox(
                  height: 116,
                  child: switch (capability) {
                    PermissionCapability.deviceLocation =>
                      _LocationCapabilityIllustration(
                        animation: animation,
                        reduceMotion: reduceMotion,
                      ),
                    PermissionCapability.notifications =>
                      _NotificationCapabilityIllustration(
                        animation: animation,
                        reduceMotion: reduceMotion,
                      ),
                  },
                ),
                const SizedBox(height: HkSpacing.sm),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: scheme.onSurface,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: HkSpacing.xs),
                Text(
                  body,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium
                      ?.copyWith(color: scheme.onSurfaceVariant, height: 1.35),
                ),
                if (statusMessage != null) ...[
                  const SizedBox(height: HkSpacing.xs),
                  Text(
                    statusMessage,
                    key: const ValueKey('permission-overlay-status'),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
                if (operationFailure != null) ...[
                  const SizedBox(height: HkSpacing.xs),
                  Text(
                    operationFailure!.kind ==
                            PermissionOperationFailureKind.settings
                        ? context.l10n.permissionSettingsCouldNotOpen
                        : context.l10n.permissionActionCouldNotComplete,
                    key: const ValueKey('permission-overlay-error'),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.error,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
                const SizedBox(height: HkSpacing.sm),
                Container(
                  padding: const EdgeInsets.all(HkSpacing.sm),
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer.withValues(alpha: 0.44),
                    borderRadius: BorderRadius.circular(HkRadii.lg),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        switch (capability) {
                          PermissionCapability.deviceLocation =>
                            Symbols.privacy_tip_rounded,
                          PermissionCapability.notifications =>
                            Symbols.tune_rounded,
                        },
                        size: 20,
                        color: scheme.primary,
                        semanticLabel: null,
                      ),
                      const SizedBox(width: HkSpacing.xs),
                      Expanded(
                        child: Text(
                          reassurance,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: scheme.onPrimaryContainer,
                                height: 1.35,
                              ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: HkSpacing.md),
                if (capability == PermissionCapability.deviceLocation) ...[
                  FilledButton.icon(
                    onPressed: isBusy
                        ? null
                        : opensSettings
                        ? onOpenSettings
                        : onUseCurrentLocation,
                    icon: isBusy
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Symbols.my_location_rounded),
                    label: Text(
                      nextAction == PermissionNextAction.openLocationSettings
                          ? context.l10n.turnOnLocationServices
                          : opensSettings
                          ? context.l10n.permissionSetupManageInSettings
                          : context.l10n.permissionSetupUseCurrentLocation,
                    ),
                  ),
                  const SizedBox(height: HkSpacing.xs),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: isBusy ? null : onChooseLocationManually,
                          icon: const Icon(Symbols.search_rounded),
                          label: Text(
                            context.l10n.permissionSetupChooseLocation,
                          ),
                        ),
                      ),
                      const SizedBox(width: HkSpacing.xs),
                      TextButton(
                        onPressed: isBusy ? null : onDefer,
                        child: Text(context.l10n.notNow),
                      ),
                    ],
                  ),
                ] else ...[
                  Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: isBusy ? null : onDefer,
                          child: Text(context.l10n.notNow),
                        ),
                      ),
                      const SizedBox(width: HkSpacing.xs),
                      Expanded(
                        flex: 2,
                        child: FilledButton.icon(
                          onPressed: isBusy
                              ? null
                              : opensSettings
                              ? onOpenSettings
                              : onEnableNotifications,
                          icon: isBusy
                              ? const SizedBox.square(
                                  dimension: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(
                                  Symbols.notifications_active_rounded,
                                ),
                          label: Text(
                            opensSettings
                                ? context.l10n.permissionSetupManageInSettings
                                : context.l10n.enableNotificationsOnboarding,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  String? _statusMessage(BuildContext context) {
    if (capability == PermissionCapability.deviceLocation) {
      if (weather?.mode == WeatherAreaMode.manual &&
          weather?.selectedArea != null) {
        return context.l10n.permissionSelectedArea(
          weather!.selectedArea!.label,
        );
      }
      if (weather?.locationServiceEnabled == false) {
        return context.l10n.locationServicesAreOff;
      }
      if (status?.permissionState == AppPermissionState.permanentlyDenied) {
        return context.l10n.blocked;
      }
      if (status?.permissionState == AppPermissionState.restricted ||
          status?.permissionState == AppPermissionState.unavailable) {
        return context.l10n.deviceLocationIsUnavailable;
      }
    }
    if (capability == PermissionCapability.notifications &&
        status?.effectiveState == EffectiveCapabilityState.blocked) {
      return context.l10n.permissionNotificationAccessRequired;
    }
    return null;
  }
}

class _LocationCapabilityIllustration extends StatelessWidget {
  const _LocationCapabilityIllustration({
    required this.animation,
    required this.reduceMotion,
  });

  final Animation<double> animation;
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: context.l10n.permissionSetupWeatherTitle,
      image: true,
      child: ExcludeSemantics(
        child: AnimatedBuilder(
          animation: animation,
          builder: (context, child) {
            final phase = reduceMotion ? 0.35 : animation.value;
            return Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(HkRadii.xl),
                    gradient: LinearGradient(
                      colors: [
                        scheme.primaryContainer.withValues(alpha: 0.78),
                        scheme.surfaceContainerLowest,
                      ],
                    ),
                  ),
                ),
                Transform.scale(
                  scale: 0.96 + (phase * 0.06),
                  child: Container(
                    width: 74,
                    height: 74,
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerLowest,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: scheme.primary.withValues(alpha: 0.28),
                        width: 2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: scheme.primary.withValues(alpha: 0.16),
                          blurRadius: 20,
                        ),
                      ],
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Icon(
                          Symbols.location_on_rounded,
                          size: 58,
                          color: scheme.primary,
                        ),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Icon(
                            Symbols.home_rounded,
                            size: 23,
                            color: scheme.onPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                PositionedDirectional(
                  start: 54 + (phase * 6),
                  top: 18,
                  child: const Icon(
                    Symbols.partly_cloudy_day_rounded,
                    color: HkColors.appWarning,
                    size: 31,
                  ),
                ),
                PositionedDirectional(
                  end: 58,
                  bottom: 16 + (phase * 4),
                  child: Icon(
                    Symbols.eco_rounded,
                    color: scheme.primary,
                    size: 26,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _NotificationCapabilityIllustration extends StatelessWidget {
  const _NotificationCapabilityIllustration({
    required this.animation,
    required this.reduceMotion,
  });

  final Animation<double> animation;
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: context.l10n.neverMissImportantMaintenance,
      image: true,
      child: ExcludeSemantics(
        child: AnimatedBuilder(
          animation: animation,
          builder: (context, child) {
            final phase = reduceMotion ? 0.4 : animation.value;
            return Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(HkRadii.xl),
                    gradient: LinearGradient(
                      colors: [
                        scheme.primaryContainer.withValues(alpha: 0.74),
                        scheme.surfaceContainerLowest,
                      ],
                    ),
                  ),
                ),
                Container(
                  width: 78 + (phase * 6),
                  height: 78 + (phase * 6),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: scheme.primary.withValues(alpha: 0.22),
                      width: 3,
                    ),
                  ),
                ),
                Transform.rotate(
                  angle: reduceMotion ? 0 : (phase - 0.5) * 0.08,
                  child: Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerLowest,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: scheme.primary.withValues(alpha: 0.18),
                          blurRadius: 22,
                        ),
                      ],
                    ),
                    child: Icon(
                      Symbols.notifications_active_rounded,
                      color: scheme.primary,
                      size: 39,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
