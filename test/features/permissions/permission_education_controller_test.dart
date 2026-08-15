import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:owntend/main.dart'
    show
        notificationSchedulerProvider,
        settingsRepositoryProvider,
        weatherRepositoryProvider;
import 'package:owntend/src/core/domain/contracts.dart';
import 'package:owntend/src/core/domain/models.dart';
import 'package:owntend/src/features/permissions/application/permission_education_controller.dart';
import 'package:owntend/src/features/permissions/data/device_permission_gateway.dart';
import 'package:owntend/src/features/permissions/data/permission_education_repository.dart';
import 'package:owntend/src/features/permissions/domain/permission_capability.dart';
import 'package:owntend/src/features/permissions/domain/permission_education_state.dart';

class FakeDevicePermissionGateway implements DevicePermissionGateway {
  FakeDevicePermissionGateway({
    Map<PermissionCapability, AppPermissionState>? states,
    Map<PermissionCapability, AppPermissionState>? requestResults,
  }) : states = states ?? {},
       requestResults = requestResults ?? {};

  final Map<PermissionCapability, AppPermissionState> states;
  final Map<PermissionCapability, AppPermissionState> requestResults;
  final List<PermissionCapability> requests = [];
  final List<PermissionCapability> settingsOpens = [];
  bool? locationServiceEnabled = true;

  @override
  Future<AppPermissionState> check(PermissionCapability capability) async {
    return states[capability] ?? AppPermissionState.denied;
  }

  @override
  Future<DeviceLocationAccessState> checkLocationAccess() async {
    return DeviceLocationAccessState(
      permissionState:
          states[PermissionCapability.deviceLocation] ??
          AppPermissionState.denied,
      serviceEnabled: locationServiceEnabled,
    );
  }

  @override
  Future<AppPermissionState> request(PermissionCapability capability) async {
    requests.add(capability);
    final result = requestResults[capability] ?? AppPermissionState.granted;
    states[capability] = result;
    return result;
  }

  @override
  Future<bool> openSettings(PermissionCapability capability) async {
    settingsOpens.add(capability);
    return true;
  }
}

class FakePermissionEducationRepository
    implements PermissionEducationRepository {
  PermissionEducationDeviceState deviceState =
      const PermissionEducationDeviceState();
  int saveCount = 0;

  @override
  Future<PermissionEducationDeviceState> loadDeviceState() async => deviceState;

  @override
  Future<void> saveDeviceState(PermissionEducationDeviceState state) async {
    deviceState = state;
    saveCount++;
  }
}

class FakeSettingsRepository implements SettingsRepository {
  HomeLocation? location;
  NotificationPreferences preferences = const NotificationPreferences();
  bool permissionEducationSeenValue = false;

  @override
  Future<HomeLocation?> homeLocation() async => location;

  @override
  Future<void> setHomeLocation(HomeLocation? value) async {
    location = value;
  }

  @override
  Future<NotificationPreferences> notificationPreferences() async =>
      preferences;

  @override
  Future<void> setNotificationPreferences(NotificationPreferences value) async {
    preferences = value;
  }

  @override
  Future<void> setPermissionEducationSeen(bool seen) async {
    permissionEducationSeenValue = seen;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeNotificationScheduler implements NotificationScheduler {
  NotificationPermissionState state = const NotificationPermissionState(
    notificationsEnabled: false,
    canScheduleExact: false,
  );
  int refreshCount = 0;

  @override
  Future<void> initialize() async {}

  @override
  Future<NotificationPermissionState> permissionState() async => state;

  @override
  Future<void> refreshSchedules() async {
    refreshCount++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeWeatherRepository implements WeatherRepository {
  FakeWeatherRepository(this.settingsRepository);

  final FakeSettingsRepository settingsRepository;
  int useCurrentLocationCount = 0;
  int refreshWeatherCount = 0;
  HomeLocation? currentLocationResult = const HomeLocation(
    label: 'Baghdad',
    latitude: 33.31,
    longitude: 44.36,
    source: 'device',
  );
  Completer<void>? acquisitionGate;

  @override
  Future<HomeLocation?> useCurrentLocationHomeArea() async {
    useCurrentLocationCount++;
    await acquisitionGate?.future;
    final result = currentLocationResult;
    if (result != null) {
      await settingsRepository.setHomeLocation(result);
    }
    return result;
  }

  @override
  Future<WeatherSnapshot?> refreshWeather() async {
    refreshWeatherCount++;
    return null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

ProviderContainer _makeContainer({
  required FakeDevicePermissionGateway gateway,
  required FakePermissionEducationRepository repository,
  required FakeWeatherRepository weatherRepository,
  required FakeSettingsRepository settingsRepository,
  required FakeNotificationScheduler scheduler,
}) {
  return ProviderContainer(
    overrides: [
      devicePermissionGatewayProvider.overrideWithValue(gateway),
      permissionEducationRepositoryProvider.overrideWithValue(repository),
      weatherRepositoryProvider.overrideWithValue(weatherRepository),
      settingsRepositoryProvider.overrideWithValue(settingsRepository),
      notificationSchedulerProvider.overrideWithValue(scheduler),
    ],
  );
}

void main() {
  late FakeDevicePermissionGateway gateway;
  late FakePermissionEducationRepository repository;
  late FakeSettingsRepository settingsRepository;
  late FakeNotificationScheduler scheduler;
  late FakeWeatherRepository weatherRepository;
  late ProviderContainer container;
  late PermissionEducationController notifier;

  setUp(() {
    gateway = FakeDevicePermissionGateway(
      states: {
        PermissionCapability.deviceLocation: AppPermissionState.denied,
        PermissionCapability.notifications: AppPermissionState.denied,
        PermissionCapability.exactReminderTiming: AppPermissionState.denied,
      },
    );
    repository = FakePermissionEducationRepository();
    settingsRepository = FakeSettingsRepository();
    scheduler = FakeNotificationScheduler();
    weatherRepository = FakeWeatherRepository(settingsRepository);
    container = _makeContainer(
      gateway: gateway,
      repository: repository,
      weatherRepository: weatherRepository,
      settingsRepository: settingsRepository,
      scheduler: scheduler,
    );
    notifier = container.read(permissionEducationControllerProvider.notifier);
  });

  tearDown(() => container.dispose());

  test(
    'first dashboard includes weather and notifications but never exact',
    () async {
      await notifier.initialize();

      final state = container.read(permissionEducationControllerProvider);
      expect(state.relevantCapabilities, [
        PermissionCapability.deviceLocation,
        PermissionCapability.notifications,
      ]);
      expect(state.activeCapability, PermissionCapability.deviceLocation);
      expect(state.isVisible, isTrue);
      expect(state.setupSnapshot, isNotNull);
    },
  );

  test('manual weather area suppresses first-run location education', () async {
    settingsRepository.location = const HomeLocation(
      label: 'Basra',
      latitude: 30.50,
      longitude: 47.81,
      source: 'manual',
    );

    await notifier.initialize();

    final state = container.read(permissionEducationControllerProvider);
    expect(state.relevantCapabilities, [PermissionCapability.notifications]);
    expect(
      state.setupSnapshot?.weather.effectiveState,
      EffectiveCapabilityState.active,
    );
    expect(
      state.setupSnapshot?.weather.deviceLocationPermission,
      AppPermissionState.denied,
    );
  });

  test('manual choice preserves the real denied OS location state', () async {
    await notifier.initialize();
    const location = HomeLocation(
      label: 'Basra',
      latitude: 30.50,
      longitude: 47.81,
      source: 'manual',
    );

    await notifier.chooseLocationManually(location);

    final state = container.read(permissionEducationControllerProvider);
    expect(gateway.requests, isEmpty);
    expect(settingsRepository.location, same(location));
    expect(
      state
          .capabilityStatuses[PermissionCapability.deviceLocation]
          ?.permissionState,
      AppPermissionState.denied,
    );
    expect(
      state.capabilityStatuses[PermissionCapability.deviceLocation]?.outcome,
      PermissionEducationOutcome.configuredManually,
    );
    expect(state.activeCapability, PermissionCapability.notifications);
  });

  test(
    'current-location step waits until the area has been persisted',
    () async {
      await notifier.initialize();
      final gate = Completer<void>();
      weatherRepository.acquisitionGate = gate;

      final action = notifier.useCurrentLocation();
      await Future<void>.delayed(Duration.zero);

      expect(weatherRepository.useCurrentLocationCount, 1);
      expect(
        container.read(permissionEducationControllerProvider).activeCapability,
        PermissionCapability.deviceLocation,
      );

      gate.complete();
      await action;

      expect(settingsRepository.location, isNotNull);
      expect(
        container.read(permissionEducationControllerProvider).activeCapability,
        PermissionCapability.notifications,
      );
    },
  );

  test(
    'granted permission without an acquired area does not advance',
    () async {
      weatherRepository.currentLocationResult = null;
      await notifier.initialize();

      await notifier.useCurrentLocation();

      final state = container.read(permissionEducationControllerProvider);
      expect(
        state
            .capabilityStatuses[PermissionCapability.deviceLocation]
            ?.permissionState,
        AppPermissionState.granted,
      );
      expect(
        state.capabilityStatuses[PermissionCapability.deviceLocation]?.outcome,
        PermissionEducationOutcome.failed,
      );
      expect(state.setupSnapshot?.weather.isConfigured, isFalse);
      expect(state.activeCapability, PermissionCapability.deviceLocation);
    },
  );

  test('weather-card source targets only the weather capability', () async {
    settingsRepository.location = const HomeLocation(
      label: 'Basra',
      latitude: 30.50,
      longitude: 47.81,
      source: 'manual',
    );

    await notifier.initialize(source: PermissionEducationSource.weatherCard);

    expect(
      container
          .read(permissionEducationControllerProvider)
          .relevantCapabilities,
      [PermissionCapability.deviceLocation],
    );
  });

  test('reminder source targets exact timing only when requested', () async {
    await notifier.initialize(
      source: PermissionEducationSource.reminderSettings,
    );
    expect(
      container
          .read(permissionEducationControllerProvider)
          .relevantCapabilities,
      isEmpty,
    );

    settingsRepository.preferences = settingsRepository.preferences.copyWith(
      preferExactReminders: true,
    );
    await notifier.initialize(
      source: PermissionEducationSource.reminderSettings,
    );
    expect(
      container
          .read(permissionEducationControllerProvider)
          .relevantCapabilities,
      [PermissionCapability.exactReminderTiming],
    );
  });

  test(
    'settings source includes configured and missing applicable cards',
    () async {
      settingsRepository.location = const HomeLocation(
        label: 'Basra',
        latitude: 30.50,
        longitude: 47.81,
        source: 'manual',
      );
      gateway.states[PermissionCapability.notifications] =
          AppPermissionState.granted;
      gateway.states[PermissionCapability.exactReminderTiming] =
          AppPermissionState.unavailable;
      scheduler.state = const NotificationPermissionState(
        notificationsEnabled: true,
        canScheduleExact: false,
      );

      await notifier.initialize(
        source: PermissionEducationSource.settings,
        forceShow: true,
      );

      expect(
        container
            .read(permissionEducationControllerProvider)
            .relevantCapabilities,
        [
          PermissionCapability.deviceLocation,
          PermissionCapability.notifications,
        ],
      );
    },
  );

  test(
    'settings opener targets the tapped card instead of the active card',
    () async {
      await notifier.initialize(
        source: PermissionEducationSource.settings,
        forceShow: true,
      );
      expect(
        container.read(permissionEducationControllerProvider).activeCapability,
        PermissionCapability.deviceLocation,
      );

      await notifier.openSettingsFor(PermissionCapability.exactReminderTiming);

      expect(gateway.settingsOpens, [PermissionCapability.exactReminderTiming]);
      expect(
        container
            .read(permissionEducationControllerProvider)
            .awaitingSettingsCapability,
        PermissionCapability.exactReminderTiming,
      );
    },
  );

  test(
    'location-service-disabled recovery targets location settings',
    () async {
      gateway.states[PermissionCapability.deviceLocation] =
          AppPermissionState.serviceDisabled;
      await notifier.initialize(
        source: PermissionEducationSource.settings,
        forceShow: true,
      );

      await notifier.openSettingsFor(PermissionCapability.deviceLocation);

      expect(gateway.settingsOpens, [PermissionCapability.deviceLocation]);
      expect(
        container
            .read(permissionEducationControllerProvider)
            .capabilityStatuses[PermissionCapability.deviceLocation]
            ?.nextAction,
        PermissionNextAction.openLocationSettings,
      );
    },
  );

  test(
    'restricted and unavailable capabilities expose no invalid settings action',
    () async {
      gateway.states[PermissionCapability.notifications] =
          AppPermissionState.restricted;
      await notifier.initialize(
        source: PermissionEducationSource.settings,
        forceShow: true,
      );

      await notifier.openSettingsFor(PermissionCapability.notifications);

      expect(gateway.settingsOpens, isEmpty);
      expect(
        container
            .read(permissionEducationControllerProvider)
            .capabilityStatuses[PermissionCapability.notifications]
            ?.nextAction,
        PermissionNextAction.none,
      );
    },
  );

  test(
    'resume re-reads, derives, advances, and publishes exactly once',
    () async {
      await notifier.initialize();
      await notifier.openSettingsFor(PermissionCapability.deviceLocation);
      gateway.states[PermissionCapability.deviceLocation] =
          AppPermissionState.granted;
      settingsRepository.location = const HomeLocation(
        label: 'Baghdad',
        latitude: 33.31,
        longitude: 44.36,
        source: 'device',
      );

      final published = <PermissionEducationControllerState>[];
      final subscription = container.listen(
        permissionEducationControllerProvider,
        (_, next) => published.add(next),
      );
      await notifier.handleAppResume();
      subscription.close();

      expect(published, hasLength(1));
      final state = published.single;
      expect(state.awaitingSettingsReturn, isFalse);
      expect(state.activeCapability, PermissionCapability.notifications);
      expect(
        state.setupSnapshot?.weather.effectiveState,
        EffectiveCapabilityState.active,
      );
      expect(
        state.capabilityStatuses[PermissionCapability.deviceLocation]?.outcome,
        PermissionEducationOutcome.granted,
      );
    },
  );

  test(
    'resume refreshes capability truth even when no education UI is visible',
    () async {
      repository.deviceState = PermissionEducationDeviceState(
        completedAt: DateTime(2026),
      );
      await notifier.refreshCapabilities();
      expect(
        container
            .read(permissionEducationControllerProvider)
            .setupSnapshot
            ?.weather
            .effectiveState,
        EffectiveCapabilityState.notConfigured,
      );

      settingsRepository.location = const HomeLocation(
        label: 'Basra',
        latitude: 30.50,
        longitude: 47.81,
        source: 'manual',
      );
      final published = <PermissionEducationControllerState>[];
      final subscription = container.listen(
        permissionEducationControllerProvider,
        (_, next) => published.add(next),
      );

      await notifier.handleAppResume();
      subscription.close();

      expect(published, hasLength(1));
      expect(published.single.isVisible, isFalse);
      expect(
        published.single.setupSnapshot?.weather.effectiveState,
        EffectiveCapabilityState.active,
      );
      expect(
        published.single.setupSnapshot?.weather.deviceLocationPermission,
        AppPermissionState.denied,
      );
    },
  );

  test(
    'choosing approximate timing clears exact intent and reconciles',
    () async {
      gateway.states[PermissionCapability.notifications] =
          AppPermissionState.granted;
      scheduler.state = const NotificationPermissionState(
        notificationsEnabled: true,
        canScheduleExact: false,
      );
      settingsRepository.preferences = settingsRepository.preferences.copyWith(
        preferExactReminders: true,
      );
      await notifier.initialize(
        source: PermissionEducationSource.reminderSettings,
      );

      await notifier.deferCurrentStep();

      expect(settingsRepository.preferences.preferExactReminders, isFalse);
      expect(scheduler.refreshCount, 1);
      expect(repository.deviceState.completedAt, isNotNull);
      expect(
        container
            .read(permissionEducationControllerProvider)
            .setupSnapshot
            ?.notifications
            .usesApproximateTiming,
        isTrue,
      );
    },
  );

  test(
    'finish later persists a session cooldown without completing setup',
    () async {
      await notifier.initialize();

      await notifier.finishLater();

      var state = container.read(permissionEducationControllerProvider);
      expect(state.isVisible, isFalse);
      expect(repository.deviceState.completedAt, isNull);
      expect(repository.deviceState.dismissedUntil, isNotNull);

      await notifier.initialize();
      state = container.read(permissionEducationControllerProvider);
      expect(state.isVisible, isFalse);
      expect(state.relevantCapabilities, isEmpty);
    },
  );

  test('a second user action cannot overlap an in-flight action', () async {
    await notifier.initialize();
    final gate = Completer<void>();
    weatherRepository.acquisitionGate = gate;

    final locationAction = notifier.useCurrentLocation();
    final notificationAction = notifier.enableNotifications();
    await Future<void>.delayed(Duration.zero);

    expect(gateway.requests, [PermissionCapability.deviceLocation]);
    gate.complete();
    await Future.wait([locationAction, notificationAction]);
    expect(gateway.requests, [PermissionCapability.deviceLocation]);
  });
}
