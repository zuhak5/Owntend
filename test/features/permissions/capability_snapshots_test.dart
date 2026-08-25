import 'package:flutter_test/flutter_test.dart';
import 'package:owntend/src/core/domain/contracts.dart';
import 'package:owntend/src/core/domain/models.dart';
import 'package:owntend/src/features/permissions/domain/capability_snapshots.dart';
import 'package:owntend/src/features/permissions/domain/permission_capability.dart';

const _manualArea = HomeLocation(
  label: 'Baghdad',
  latitude: 33.31,
  longitude: 44.36,
  source: 'manual',
);

const _deviceArea = HomeLocation(
  label: 'Baghdad',
  latitude: 33.31,
  longitude: 44.36,
  source: 'device',
);

const _schedulerAllowed = NotificationPermissionState(
  notificationsEnabled: true,
);

const _schedulerBlocked = NotificationPermissionState(
  notificationsEnabled: false,
);

void main() {
  group('weather capability derivation', () {
    test('no location stays not configured for denied permission', () {
      final snapshot = deriveWeatherAreaCapability(
        selectedArea: null,
        deviceLocationPermission: AppPermissionState.denied,
        locationServiceEnabled: true,
      );

      expect(snapshot.mode, WeatherAreaMode.none);
      expect(snapshot.effectiveState, EffectiveCapabilityState.notConfigured);
      expect(snapshot.nextAction, PermissionNextAction.request);
    });

    test('manual area is active while OS location remains denied', () {
      final snapshot = deriveWeatherAreaCapability(
        selectedArea: _manualArea,
        deviceLocationPermission: AppPermissionState.denied,
        locationServiceEnabled: true,
      );

      expect(snapshot.mode, WeatherAreaMode.manual);
      expect(snapshot.deviceLocationPermission, AppPermissionState.denied);
      expect(snapshot.effectiveState, EffectiveCapabilityState.active);
      expect(snapshot.nextAction, PermissionNextAction.none);
    });

    test('manual area is active when OS location is granted', () {
      final snapshot = deriveWeatherAreaCapability(
        selectedArea: _manualArea,
        deviceLocationPermission: AppPermissionState.granted,
        locationServiceEnabled: true,
      );

      expect(snapshot.effectiveState, EffectiveCapabilityState.active);
    });

    test(
      'device area is active while permission and service are available',
      () {
        final snapshot = deriveWeatherAreaCapability(
          selectedArea: _deviceArea,
          deviceLocationPermission: AppPermissionState.granted,
          locationServiceEnabled: true,
        );

        expect(snapshot.mode, WeatherAreaMode.device);
        expect(snapshot.effectiveState, EffectiveCapabilityState.active);
        expect(snapshot.locationServiceEnabled, isTrue);
      },
    );

    test('device area degrades after permission is denied', () {
      final snapshot = deriveWeatherAreaCapability(
        selectedArea: _deviceArea,
        deviceLocationPermission: AppPermissionState.denied,
        locationServiceEnabled: true,
      );

      expect(snapshot.effectiveState, EffectiveCapabilityState.degraded);
      expect(snapshot.nextAction, PermissionNextAction.request);
    });

    test(
      'device area degrades and targets service settings when service is off',
      () {
        final snapshot = deriveWeatherAreaCapability(
          selectedArea: _deviceArea,
          deviceLocationPermission: AppPermissionState.granted,
          locationServiceEnabled: false,
        );

        expect(snapshot.effectiveState, EffectiveCapabilityState.degraded);
        expect(snapshot.locationServiceEnabled, isFalse);
        expect(snapshot.nextAction, PermissionNextAction.openLocationSettings);
      },
    );

    test('manual area remains active when the location API is unavailable', () {
      final snapshot = deriveWeatherAreaCapability(
        selectedArea: _manualArea,
        deviceLocationPermission: AppPermissionState.unavailable,
        locationServiceEnabled: null,
      );

      expect(snapshot.effectiveState, EffectiveCapabilityState.active);
      expect(snapshot.locationServiceEnabled, isNull);
    });
  });

  group('notification capability derivation', () {
    test('master off disables every dependent preference capability', () {
      final snapshot = deriveNotificationCapability(
        preferences: const NotificationPreferences(enabled: false),
        notificationPermission: AppPermissionState.granted,
        schedulerState: _schedulerAllowed,
      );

      expect(snapshot.effectiveState, EffectiveCapabilityState.disabledByUser);
      expect(
        snapshot.deviceReminderState,
        EffectiveCapabilityState.disabledByUser,
      );
      expect(snapshot.inboxState, EffectiveCapabilityState.disabledByUser);
      expect(
        snapshot.weatherAlertState,
        EffectiveCapabilityState.disabledByUser,
      );
    });

    test('device reminders are active only when both signals allow them', () {
      final snapshot = deriveNotificationCapability(
        preferences: const NotificationPreferences(),
        notificationPermission: AppPermissionState.granted,
        schedulerState: _schedulerAllowed,
      );

      expect(snapshot.deviceReminderState, EffectiveCapabilityState.active);
    });

    test('device reminders are blocked when Android denies them', () {
      final snapshot = deriveNotificationCapability(
        preferences: const NotificationPreferences(),
        notificationPermission: AppPermissionState.denied,
        schedulerState: _schedulerBlocked,
      );

      expect(snapshot.deviceReminderState, EffectiveCapabilityState.blocked);
      expect(snapshot.notificationNextAction, PermissionNextAction.request);
    });

    test(
      'in-app inbox stays active while Android notifications are blocked',
      () {
        final snapshot = deriveNotificationCapability(
          preferences: const NotificationPreferences(),
          notificationPermission: AppPermissionState.permanentlyDenied,
          schedulerState: _schedulerBlocked,
        );

        expect(snapshot.inboxState, EffectiveCapabilityState.active);
        expect(snapshot.effectiveState, EffectiveCapabilityState.degraded);
      },
    );

    test('weather inbox alerts become inactive when inbox is off', () {
      final snapshot = deriveNotificationCapability(
        preferences: const NotificationPreferences(
          inAppInbox: false,
          weatherAlerts: true,
        ),
        notificationPermission: AppPermissionState.granted,
        schedulerState: _schedulerAllowed,
      );

      expect(
        snapshot.weatherAlertState,
        EffectiveCapabilityState.disabledByUser,
      );
    });
  });

  test(
    'capability setup keeps manual success separate from denied OS state',
    () {
      final snapshot = deriveCapabilitySetupSnapshot(
        homeLocation: _manualArea,
        notificationPreferences: const NotificationPreferences(),
        deviceLocationPermission: AppPermissionState.denied,
        locationServiceEnabled: true,
        notificationPermission: AppPermissionState.denied,
        schedulerState: _schedulerBlocked,
      );

      final location = snapshot.statusFor(PermissionCapability.deviceLocation);
      expect(location.permissionState, AppPermissionState.denied);
      expect(location.outcome, PermissionEducationOutcome.configuredManually);
      expect(location.effectiveState, EffectiveCapabilityState.active);
      expect(snapshot.isSatisfied(PermissionCapability.deviceLocation), isTrue);
    },
  );
}
