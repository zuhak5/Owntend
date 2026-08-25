import 'package:flutter/foundation.dart';

import '../../../core/domain/contracts.dart';
import '../../../core/domain/models.dart';
import 'permission_capability.dart';

enum WeatherAreaMode { none, manual, device }

@immutable
class WeatherAreaCapabilitySnapshot {
  const WeatherAreaCapabilitySnapshot({
    required this.selectedArea,
    required this.mode,
    required this.deviceLocationPermission,
    required this.locationServiceEnabled,
    required this.effectiveState,
    required this.nextAction,
  });

  final HomeLocation? selectedArea;
  final WeatherAreaMode mode;
  final AppPermissionState deviceLocationPermission;
  final bool? locationServiceEnabled;
  final EffectiveCapabilityState effectiveState;
  final PermissionNextAction nextAction;

  bool get isConfigured => selectedArea != null;
}

@immutable
class NotificationCapabilitySnapshot {
  const NotificationCapabilitySnapshot({
    required this.preferences,
    required this.notificationPermission,
    required this.notificationsActuallyEnabled,
    required this.effectiveState,
    required this.deviceReminderState,
    required this.inboxState,
    required this.weatherAlertState,
    required this.notificationNextAction,
  });

  final NotificationPreferences preferences;
  final AppPermissionState notificationPermission;
  final bool notificationsActuallyEnabled;
  final EffectiveCapabilityState effectiveState;
  final EffectiveCapabilityState deviceReminderState;
  final EffectiveCapabilityState inboxState;
  final EffectiveCapabilityState weatherAlertState;
  final PermissionNextAction notificationNextAction;
}

@immutable
class CapabilitySetupSnapshot {
  CapabilitySetupSnapshot({
    required this.weather,
    required this.notifications,
    Map<PermissionCapability, PermissionEducationOutcome> educationOutcomes =
        const {},
  }) : capabilityStatuses = Map.unmodifiable(
         _deriveStatuses(weather, notifications, educationOutcomes),
       );

  final WeatherAreaCapabilitySnapshot weather;
  final NotificationCapabilitySnapshot notifications;
  final Map<PermissionCapability, CapabilityStatus> capabilityStatuses;

  CapabilityStatus statusFor(PermissionCapability capability) =>
      capabilityStatuses[capability]!;

  bool isSatisfied(PermissionCapability capability) => switch (capability) {
    PermissionCapability.deviceLocation => weather.isConfigured,
    PermissionCapability.notifications =>
      notifications.deviceReminderState == EffectiveCapabilityState.active ||
          notifications.deviceReminderState ==
              EffectiveCapabilityState.disabledByUser,
  };

  CapabilitySetupSnapshot withEducationOutcomes(
    Map<PermissionCapability, PermissionEducationOutcome> outcomes,
  ) {
    return CapabilitySetupSnapshot(
      weather: weather,
      notifications: notifications,
      educationOutcomes: outcomes,
    );
  }
}

WeatherAreaCapabilitySnapshot deriveWeatherAreaCapability({
  required HomeLocation? selectedArea,
  required AppPermissionState deviceLocationPermission,
  required bool? locationServiceEnabled,
}) {
  final mode = switch (selectedArea?.source.trim().toLowerCase()) {
    'device' => WeatherAreaMode.device,
    null => WeatherAreaMode.none,
    _ => WeatherAreaMode.manual,
  };

  final effectiveState = switch (mode) {
    WeatherAreaMode.none => EffectiveCapabilityState.notConfigured,
    WeatherAreaMode.manual => EffectiveCapabilityState.active,
    WeatherAreaMode.device =>
      deviceLocationPermission == AppPermissionState.granted &&
              locationServiceEnabled != false
          ? EffectiveCapabilityState.active
          : EffectiveCapabilityState.degraded,
  };

  return WeatherAreaCapabilitySnapshot(
    selectedArea: selectedArea,
    mode: mode,
    deviceLocationPermission: deviceLocationPermission,
    locationServiceEnabled: locationServiceEnabled,
    effectiveState: effectiveState,
    nextAction: _locationNextAction(
      deviceLocationPermission,
      locationServiceEnabled: locationServiceEnabled,
      isConfigured: selectedArea != null,
      mode: mode,
    ),
  );
}

NotificationCapabilitySnapshot deriveNotificationCapability({
  required NotificationPreferences preferences,
  required AppPermissionState notificationPermission,
  required NotificationPermissionState schedulerState,
}) {
  final deviceReminderState = _deriveDeviceReminderState(
    preferences,
    notificationPermission,
    schedulerState.notificationsEnabled,
  );
  final inboxState = preferences.allowsInbox
      ? EffectiveCapabilityState.active
      : EffectiveCapabilityState.disabledByUser;
  final weatherAlertState = preferences.allowsWeatherAlerts
      ? EffectiveCapabilityState.active
      : EffectiveCapabilityState.disabledByUser;

  final hasWorkingChannel =
      deviceReminderState == EffectiveCapabilityState.active ||
      inboxState == EffectiveCapabilityState.active;
  final requestedChannelIsImpaired =
      preferences.allowsLocalReminders &&
      deviceReminderState != EffectiveCapabilityState.active;

  final EffectiveCapabilityState effectiveState;
  if (!preferences.enabled) {
    effectiveState = EffectiveCapabilityState.disabledByUser;
  } else if (hasWorkingChannel && requestedChannelIsImpaired) {
    effectiveState = EffectiveCapabilityState.degraded;
  } else if (hasWorkingChannel) {
    effectiveState = EffectiveCapabilityState.active;
  } else if (deviceReminderState == EffectiveCapabilityState.unavailable) {
    effectiveState = EffectiveCapabilityState.unavailable;
  } else if (deviceReminderState == EffectiveCapabilityState.blocked) {
    effectiveState = EffectiveCapabilityState.blocked;
  } else {
    effectiveState = EffectiveCapabilityState.disabledByUser;
  }

  return NotificationCapabilitySnapshot(
    preferences: preferences,
    notificationPermission: notificationPermission,
    notificationsActuallyEnabled: schedulerState.notificationsEnabled,
    effectiveState: effectiveState,
    deviceReminderState: deviceReminderState,
    inboxState: inboxState,
    weatherAlertState: weatherAlertState,
    notificationNextAction: _notificationNextAction(
      notificationPermission,
      deviceReminderState,
    ),
  );
}

CapabilitySetupSnapshot deriveCapabilitySetupSnapshot({
  required HomeLocation? homeLocation,
  required NotificationPreferences notificationPreferences,
  required AppPermissionState deviceLocationPermission,
  required bool? locationServiceEnabled,
  required AppPermissionState notificationPermission,
  required NotificationPermissionState schedulerState,
  Map<PermissionCapability, PermissionEducationOutcome> educationOutcomes =
      const {},
}) {
  return CapabilitySetupSnapshot(
    weather: deriveWeatherAreaCapability(
      selectedArea: homeLocation,
      deviceLocationPermission: deviceLocationPermission,
      locationServiceEnabled: locationServiceEnabled,
    ),
    notifications: deriveNotificationCapability(
      preferences: notificationPreferences,
      notificationPermission: notificationPermission,
      schedulerState: schedulerState,
    ),
    educationOutcomes: educationOutcomes,
  );
}

EffectiveCapabilityState _deriveDeviceReminderState(
  NotificationPreferences preferences,
  AppPermissionState permission,
  bool notificationsActuallyEnabled,
) {
  if (!preferences.allowsLocalReminders) {
    return EffectiveCapabilityState.disabledByUser;
  }
  if (permission == AppPermissionState.restricted ||
      permission == AppPermissionState.unavailable) {
    return EffectiveCapabilityState.unavailable;
  }
  if (permission == AppPermissionState.granted &&
      notificationsActuallyEnabled) {
    return EffectiveCapabilityState.active;
  }
  return EffectiveCapabilityState.blocked;
}

PermissionNextAction _locationNextAction(
  AppPermissionState permission, {
  required bool? locationServiceEnabled,
  required bool isConfigured,
  required WeatherAreaMode mode,
}) {
  if (mode == WeatherAreaMode.manual) {
    return PermissionNextAction.none;
  }
  if (locationServiceEnabled == false) {
    return PermissionNextAction.openLocationSettings;
  }
  return switch (permission) {
    AppPermissionState.granted =>
      isConfigured ? PermissionNextAction.none : PermissionNextAction.request,
    AppPermissionState.denied => PermissionNextAction.request,
    AppPermissionState.permanentlyDenied =>
      PermissionNextAction.openAppSettings,
    AppPermissionState.serviceDisabled =>
      PermissionNextAction.openLocationSettings,
    AppPermissionState.restricted || AppPermissionState.unavailable =>
      isConfigured
          ? PermissionNextAction.none
          : PermissionNextAction.chooseManualLocation,
  };
}

PermissionNextAction _notificationNextAction(
  AppPermissionState permission,
  EffectiveCapabilityState state,
) {
  if (state == EffectiveCapabilityState.active ||
      state == EffectiveCapabilityState.disabledByUser) {
    return PermissionNextAction.none;
  }
  return switch (permission) {
    AppPermissionState.denied => PermissionNextAction.request,
    AppPermissionState.permanentlyDenied =>
      PermissionNextAction.openAppSettings,
    _ => PermissionNextAction.none,
  };
}

Map<PermissionCapability, CapabilityStatus> _deriveStatuses(
  WeatherAreaCapabilitySnapshot weather,
  NotificationCapabilitySnapshot notifications,
  Map<PermissionCapability, PermissionEducationOutcome> educationOutcomes,
) {
  PermissionEducationOutcome currentOutcome(
    PermissionCapability capability,
    EffectiveCapabilityState effectiveState,
    PermissionEducationOutcome successOutcome,
  ) {
    if (effectiveState == EffectiveCapabilityState.active) {
      return successOutcome;
    }
    if (effectiveState == EffectiveCapabilityState.unavailable) {
      return PermissionEducationOutcome.unavailable;
    }
    return educationOutcomes[capability] ??
        (effectiveState == EffectiveCapabilityState.blocked ||
                effectiveState == EffectiveCapabilityState.degraded
            ? PermissionEducationOutcome.blocked
            : PermissionEducationOutcome.deferred);
  }

  final weatherSuccess = weather.mode == WeatherAreaMode.manual
      ? PermissionEducationOutcome.configuredManually
      : PermissionEducationOutcome.granted;

  return {
    PermissionCapability.deviceLocation: CapabilityStatus(
      capability: PermissionCapability.deviceLocation,
      permissionState: weather.deviceLocationPermission,
      outcome: currentOutcome(
        PermissionCapability.deviceLocation,
        weather.effectiveState,
        weatherSuccess,
      ),
      nextAction: weather.nextAction,
      effectiveState: weather.effectiveState,
    ),
    PermissionCapability.notifications: CapabilityStatus(
      capability: PermissionCapability.notifications,
      permissionState: notifications.notificationPermission,
      outcome: currentOutcome(
        PermissionCapability.notifications,
        notifications.deviceReminderState,
        PermissionEducationOutcome.granted,
      ),
      nextAction: notifications.notificationNextAction,
      userPreferenceEnabled: notifications.preferences.allowsLocalReminders,
      effectiveState: notifications.deviceReminderState,
    ),
  };
}
