import 'package:flutter/foundation.dart';
import 'package:owntend/src/core/domain/models.dart'
    show EffectiveCapabilityState;
import 'package:owntend/src/core/services/app_permission_coordinator.dart'
    show AppPermissionState;

export 'package:owntend/src/core/services/app_permission_coordinator.dart'
    show AppPermissionState;

enum PermissionCapability { deviceLocation, notifications, exactReminderTiming }

enum PermissionEducationSource {
  firstDashboardVisit,
  settings,
  weatherCard,
  reminderSettings,
  taskScheduling,
}

enum PermissionEducationOutcome {
  granted,
  configuredManually,
  deferred,
  blocked,
  unavailable,
  failed,
}

enum PermissionNextAction {
  request,
  openAppSettings,
  openLocationSettings,
  openExactAlarmSettings,
  chooseManualLocation,
  none,
}

enum PermissionOperationFailureKind { action, settings }

@immutable
class PermissionOperationFailure {
  const PermissionOperationFailure({
    required this.capability,
    required this.kind,
  });

  final PermissionCapability capability;
  final PermissionOperationFailureKind kind;
}

@immutable
class CapabilityStatus {
  const CapabilityStatus({
    required this.capability,
    required this.permissionState,
    required this.outcome,
    required this.nextAction,
    this.userPreferenceEnabled = true,
    this.effectiveState = EffectiveCapabilityState.notConfigured,
  });

  final PermissionCapability capability;
  final AppPermissionState permissionState;
  final PermissionEducationOutcome outcome;
  final PermissionNextAction nextAction;
  final bool userPreferenceEnabled;
  final EffectiveCapabilityState effectiveState;

  CapabilityStatus copyWith({
    PermissionCapability? capability,
    AppPermissionState? permissionState,
    PermissionEducationOutcome? outcome,
    PermissionNextAction? nextAction,
    bool? userPreferenceEnabled,
    EffectiveCapabilityState? effectiveState,
  }) {
    return CapabilityStatus(
      capability: capability ?? this.capability,
      permissionState: permissionState ?? this.permissionState,
      outcome: outcome ?? this.outcome,
      nextAction: nextAction ?? this.nextAction,
      userPreferenceEnabled:
          userPreferenceEnabled ?? this.userPreferenceEnabled,
      effectiveState: effectiveState ?? this.effectiveState,
    );
  }
}
