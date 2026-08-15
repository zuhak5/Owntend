import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:owntend/l10n/app_localizations_ext.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../../src/core/domain/models.dart';
import '../../../../src/ui/app_theme.dart';
import '../application/permission_education_controller.dart';
import '../domain/capability_snapshots.dart';
import '../domain/permission_capability.dart';

class PermissionSetupScreen extends ConsumerStatefulWidget {
  const PermissionSetupScreen({
    this.source = PermissionEducationSource.settings,
    this.onChooseLocationManually,
    this.sponsoredContent,
    super.key,
  });

  final PermissionEducationSource source;
  final Future<HomeLocation?> Function(BuildContext context)?
  onChooseLocationManually;
  final Widget? sponsoredContent;

  @override
  ConsumerState<PermissionSetupScreen> createState() =>
      _PermissionSetupScreenState();
}

class _PermissionSetupScreenState extends ConsumerState<PermissionSetupScreen>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    scheduleMicrotask(() {
      ref
          .read(permissionEducationControllerProvider.notifier)
          .initialize(source: widget.source, forceShow: true);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(
        ref
            .read(permissionEducationControllerProvider.notifier)
            .handleAppResume(),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final PermissionEducationControllerState state = ref.watch(
      permissionEducationControllerProvider,
    );
    final PermissionEducationController notifier = ref.read(
      permissionEducationControllerProvider.notifier,
    );
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.permissionSetup),
        leading: IconButton(
          icon: const Icon(Symbols.arrow_back_rounded),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/');
            }
          },
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              padding: const EdgeInsets.all(HkSpacing.gutter),
              children: [
                if (widget.sponsoredContent case final content?) ...[content],
                Text(
                  context.l10n.permissionSetupSubtitle,
                  style: Theme.of(context).textTheme.bodyLarge
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: HkSpacing.md),
                for (final cap in PermissionCapability.values) ...[
                  if (cap != PermissionCapability.exactReminderTiming ||
                      state.capabilityStatuses[cap]?.permissionState !=
                          AppPermissionState.unavailable)
                    _CapabilityStatusCard(
                      capability: cap,
                      status: state.capabilityStatuses[cap],
                      weather: state.setupSnapshot?.weather,
                      notifications: state.setupSnapshot?.notifications,
                      operationFailure:
                          state.operationFailure?.capability == cap
                          ? state.operationFailure
                          : null,
                      isBusy: state.isBusy,
                      onAction: () async {
                        switch (cap) {
                          case PermissionCapability.deviceLocation:
                            await notifier.useCurrentLocation();
                          case PermissionCapability.notifications:
                            await notifier.enableNotifications();
                          case PermissionCapability.exactReminderTiming:
                            await notifier.enableExactTiming();
                        }
                      },
                      onChooseManual: () async {
                        if (widget.onChooseLocationManually != null) {
                          final chosen = await widget.onChooseLocationManually!(
                            context,
                          );
                          if (chosen != null) {
                            await notifier.chooseLocationManually(chosen);
                          }
                        }
                      },
                      onOpenSettings: () => notifier.openSettingsFor(cap),
                    ),
                  const SizedBox(height: HkSpacing.sm),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CapabilityStatusCard extends StatelessWidget {
  const _CapabilityStatusCard({
    required this.capability,
    required this.status,
    required this.weather,
    required this.notifications,
    required this.operationFailure,
    required this.isBusy,
    required this.onAction,
    required this.onChooseManual,
    required this.onOpenSettings,
  });

  final PermissionCapability capability;
  final CapabilityStatus? status;
  final WeatherAreaCapabilitySnapshot? weather;
  final NotificationCapabilitySnapshot? notifications;
  final PermissionOperationFailure? operationFailure;
  final bool isBusy;
  final VoidCallback onAction;
  final VoidCallback onChooseManual;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final effectiveState =
        status?.effectiveState ?? EffectiveCapabilityState.notConfigured;
    final isActive = effectiveState == EffectiveCapabilityState.active;
    final isDegraded = effectiveState == EffectiveCapabilityState.degraded;
    final nextAction = status?.nextAction ?? PermissionNextAction.none;
    final opensSettings = switch (nextAction) {
      PermissionNextAction.openAppSettings ||
      PermissionNextAction.openLocationSettings ||
      PermissionNextAction.openExactAlarmSettings => true,
      _ => false,
    };
    final enablesPreference =
        effectiveState == EffectiveCapabilityState.disabledByUser &&
        capability != PermissionCapability.deviceLocation;
    final exactCanBeEnabled =
        notifications?.preferences.allowsLocalReminders ?? false;
    final showsPrimaryAction =
        nextAction == PermissionNextAction.request ||
        (enablesPreference &&
            (capability != PermissionCapability.exactReminderTiming ||
                exactCanBeEnabled)) ||
        (capability == PermissionCapability.deviceLocation &&
            weather?.mode == WeatherAreaMode.manual);
    final showsManualAction = capability == PermissionCapability.deviceLocation;
    final detail = _statusDetail(context);

    final title = switch (capability) {
      PermissionCapability.deviceLocation =>
        context.l10n.permissionSetupWeatherTitle,
      PermissionCapability.notifications => context.l10n.notifications,
      PermissionCapability.exactReminderTiming =>
        context.l10n.permissionSetupExactOptionalTitle,
    };

    final body = switch (capability) {
      PermissionCapability.deviceLocation =>
        context.l10n.permissionSetupWeatherBody,
      PermissionCapability.notifications =>
        context.l10n.notificationEducationBody,
      PermissionCapability.exactReminderTiming =>
        context.l10n.permissionSetupExactOptionalBody,
    };

    return Card(
      elevation: 0,
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(HkRadii.xl),
        side: BorderSide(
          color: isActive
              ? HkColors.appPrimary.withValues(alpha: 0.3)
              : scheme.outlineVariant,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(HkSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  switch (capability) {
                    PermissionCapability.deviceLocation =>
                      Symbols.location_on_rounded,
                    PermissionCapability.notifications =>
                      Symbols.notifications_active_rounded,
                    PermissionCapability.exactReminderTiming =>
                      Symbols.alarm_on_rounded,
                  },
                  color: isActive
                      ? HkColors.appPrimary
                      : scheme.onSurfaceVariant,
                ),
                const SizedBox(width: HkSpacing.xs),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: HkSpacing.xs,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: isActive
                        ? HkColors.appPrimary.withValues(alpha: 0.15)
                        : scheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(HkRadii.sm),
                  ),
                  child: Text(
                    _statusLabel(
                      context,
                      effectiveState,
                      configuredManually:
                          status?.outcome ==
                          PermissionEducationOutcome.configuredManually,
                      approximateTiming:
                          capability ==
                              PermissionCapability.exactReminderTiming &&
                          isDegraded,
                    ),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: isActive
                          ? HkColors.appPrimary
                          : scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: HkSpacing.xs),
            Text(
              body,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
            if (detail != null) ...[
              const SizedBox(height: HkSpacing.xs),
              Text(
                detail,
                key: ValueKey('permission-status-${capability.name}'),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: isActive ? scheme.primary : scheme.error,
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
                key: ValueKey('permission-error-${capability.name}'),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.error,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
            if (capability == PermissionCapability.exactReminderTiming &&
                !exactCanBeEnabled) ...[
              const SizedBox(height: HkSpacing.xs),
              Text(
                context.l10n.permissionExactRequiresDeviceReminders,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            const SizedBox(height: HkSpacing.sm),
            if (opensSettings || showsPrimaryAction || showsManualAction)
              Wrap(
                spacing: HkSpacing.xs,
                runSpacing: HkSpacing.xs,
                children: [
                  if (opensSettings)
                    OutlinedButton.icon(
                      onPressed: isBusy ? null : onOpenSettings,
                      icon: const Icon(Symbols.settings_rounded, size: 18),
                      label: Text(
                        nextAction == PermissionNextAction.openLocationSettings
                            ? context.l10n.turnOnLocationServices
                            : context.l10n.permissionSetupManageInSettings,
                      ),
                    ),
                  if (showsPrimaryAction)
                    FilledButton.icon(
                      onPressed: isBusy ? null : onAction,
                      icon: Icon(switch (capability) {
                        PermissionCapability.deviceLocation =>
                          Symbols.my_location_rounded,
                        PermissionCapability.notifications =>
                          Symbols.notifications_active_rounded,
                        PermissionCapability.exactReminderTiming =>
                          Symbols.alarm_on_rounded,
                      }, size: 18),
                      label: Text(switch (capability) {
                        PermissionCapability.deviceLocation =>
                          context.l10n.permissionSetupUseCurrentLocation,
                        PermissionCapability.notifications =>
                          context.l10n.enableNotificationsOnboarding,
                        PermissionCapability.exactReminderTiming =>
                          context.l10n.permissionSetupAllowPreciseTiming,
                      }),
                    ),
                  if (showsManualAction)
                    OutlinedButton.icon(
                      onPressed: isBusy ? null : onChooseManual,
                      icon: const Icon(Symbols.search_rounded, size: 18),
                      label: Text(
                        weather?.isConfigured == true
                            ? context.l10n.permissionSetupChangeLocation
                            : context.l10n.permissionSetupChooseLocation,
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  String _statusLabel(
    BuildContext context,
    EffectiveCapabilityState state, {
    required bool configuredManually,
    required bool approximateTiming,
  }) {
    if (configuredManually) {
      return context.l10n.configuredManually;
    }
    if (approximateTiming) {
      return context.l10n.approximateTiming;
    }
    return switch (state) {
      EffectiveCapabilityState.active => context.l10n.allowed,
      EffectiveCapabilityState.degraded => context.l10n.limited,
      EffectiveCapabilityState.blocked => context.l10n.blocked,
      EffectiveCapabilityState.disabledByUser => context.l10n.disabled,
      EffectiveCapabilityState.notConfigured => context.l10n.notSet,
      EffectiveCapabilityState.unavailable => context.l10n.unavailable,
    };
  }

  String? _statusDetail(BuildContext context) {
    switch (capability) {
      case PermissionCapability.deviceLocation:
        final value = weather;
        if (value == null) return null;
        if (value.mode == WeatherAreaMode.manual &&
            value.selectedArea != null) {
          return context.l10n.permissionSelectedArea(value.selectedArea!.label);
        }
        if (value.mode == WeatherAreaMode.device &&
            value.effectiveState == EffectiveCapabilityState.active) {
          return context.l10n.permissionUsingCurrentLocation;
        }
        if (value.locationServiceEnabled == false) {
          return context.l10n.locationServicesAreOff;
        }
        return switch (value.deviceLocationPermission) {
          AppPermissionState.denied =>
            context.l10n.permissionLocationAccessRequired,
          AppPermissionState.permanentlyDenied => context.l10n.blocked,
          AppPermissionState.restricted || AppPermissionState.unavailable =>
            context.l10n.deviceLocationIsUnavailable,
          _ => value.isConfigured ? null : context.l10n.weatherNotSet,
        };
      case PermissionCapability.notifications:
        final value = notifications;
        if (value == null) return null;
        if (!value.preferences.allowsLocalReminders) {
          return context.l10n.permissionDeviceRemindersOff;
        }
        if (value.deviceReminderState == EffectiveCapabilityState.active) {
          return context.l10n.allowed;
        }
        return value.notificationPermission ==
                AppPermissionState.permanentlyDenied
            ? context.l10n.blocked
            : context.l10n.permissionNotificationAccessRequired;
      case PermissionCapability.exactReminderTiming:
        final value = notifications;
        if (value == null) return null;
        if (!value.preferences.allowsLocalReminders) return null;
        if (value.usesApproximateTiming) {
          return context.l10n.approximateTiming;
        }
        return value.exactTimingState == EffectiveCapabilityState.active
            ? context.l10n.allowed
            : null;
    }
  }
}
