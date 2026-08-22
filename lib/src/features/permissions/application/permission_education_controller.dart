import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/domain/contracts.dart';
import '../../../core/domain/models.dart';
import '../../../core/providers/app_providers.dart';
import '../data/device_permission_gateway.dart';
import '../data/permission_education_repository.dart';
import '../domain/capability_snapshots.dart';
import '../domain/permission_capability.dart';
import '../domain/permission_education_state.dart';

@immutable
class PermissionEducationControllerState {
  const PermissionEducationControllerState({
    this.deviceState = const PermissionEducationDeviceState(),
    this.relevantCapabilities = const [],
    this.activeCapability,
    this.capabilityStatuses = const {},
    this.setupSnapshot,
    this.isBusy = false,
    this.isVisible = false,
    this.source = PermissionEducationSource.firstDashboardVisit,
    this.awaitingSettingsReturn = false,
    this.awaitingSettingsCapability,
    this.operationFailure,
  });

  final PermissionEducationDeviceState deviceState;
  final List<PermissionCapability> relevantCapabilities;
  final PermissionCapability? activeCapability;
  final Map<PermissionCapability, CapabilityStatus> capabilityStatuses;
  final CapabilitySetupSnapshot? setupSnapshot;
  final bool isBusy;
  final bool isVisible;
  final PermissionEducationSource source;
  final bool awaitingSettingsReturn;
  final PermissionCapability? awaitingSettingsCapability;
  final PermissionOperationFailure? operationFailure;

  PermissionEducationControllerState copyWith({
    PermissionEducationDeviceState? deviceState,
    List<PermissionCapability>? relevantCapabilities,
    PermissionCapability? activeCapability,
    bool clearActiveCapability = false,
    Map<PermissionCapability, CapabilityStatus>? capabilityStatuses,
    CapabilitySetupSnapshot? setupSnapshot,
    bool? isBusy,
    bool? isVisible,
    PermissionEducationSource? source,
    bool? awaitingSettingsReturn,
    PermissionCapability? awaitingSettingsCapability,
    bool clearAwaitingSettingsCapability = false,
    PermissionOperationFailure? operationFailure,
    bool clearOperationFailure = false,
  }) {
    return PermissionEducationControllerState(
      deviceState: deviceState ?? this.deviceState,
      relevantCapabilities: relevantCapabilities ?? this.relevantCapabilities,
      activeCapability: clearActiveCapability
          ? null
          : activeCapability ?? this.activeCapability,
      capabilityStatuses: capabilityStatuses ?? this.capabilityStatuses,
      setupSnapshot: setupSnapshot ?? this.setupSnapshot,
      isBusy: isBusy ?? this.isBusy,
      isVisible: isVisible ?? this.isVisible,
      source: source ?? this.source,
      awaitingSettingsReturn:
          awaitingSettingsReturn ?? this.awaitingSettingsReturn,
      awaitingSettingsCapability: clearAwaitingSettingsCapability
          ? null
          : awaitingSettingsCapability ?? this.awaitingSettingsCapability,
      operationFailure: clearOperationFailure
          ? null
          : operationFailure ?? this.operationFailure,
    );
  }
}

final devicePermissionGatewayProvider = Provider<DevicePermissionGateway>((
  ref,
) {
  return FlutterDevicePermissionGateway(
    ref.watch(permissionCoordinatorProvider),
  );
});

final permissionEducationRepositoryProvider =
    Provider<PermissionEducationRepository>((ref) {
      final database = ref.watch(databaseProvider);
      return DriftPermissionEducationRepository(database);
    });

final permissionEducationControllerProvider =
    NotifierProvider<
      PermissionEducationController,
      PermissionEducationControllerState
    >(PermissionEducationController.new);

class PermissionEducationController
    extends Notifier<PermissionEducationControllerState> {
  PermissionEducationController({
    DevicePermissionGateway? gateway,
    PermissionEducationRepository? repository,
    WeatherRepository? weatherRepository,
    SettingsRepository? settingsRepository,
    NotificationScheduler? notificationScheduler,
    DateTime Function()? now,
  }) : _overrideGateway = gateway,
       _overrideRepository = repository,
       _overrideWeatherRepository = weatherRepository,
       _overrideSettingsRepository = settingsRepository,
       _overrideNotificationScheduler = notificationScheduler,
       _now = now ?? DateTime.now;

  static const sessionDismissalCooldown = Duration(hours: 24);

  final DevicePermissionGateway? _overrideGateway;
  final PermissionEducationRepository? _overrideRepository;
  final WeatherRepository? _overrideWeatherRepository;
  final SettingsRepository? _overrideSettingsRepository;
  final NotificationScheduler? _overrideNotificationScheduler;
  final DateTime Function() _now;

  Future<void> _operationTail = Future<void>.value();
  bool _userActionPending = false;

  DevicePermissionGateway get _gateway =>
      _overrideGateway ?? ref.read(devicePermissionGatewayProvider);
  PermissionEducationRepository get _repository =>
      _overrideRepository ?? ref.read(permissionEducationRepositoryProvider);
  WeatherRepository get _weatherRepository =>
      _overrideWeatherRepository ?? ref.read(weatherRepositoryProvider);
  SettingsRepository get _settingsRepository =>
      _overrideSettingsRepository ?? ref.read(settingsRepositoryProvider);
  NotificationScheduler get _notificationScheduler =>
      _overrideNotificationScheduler ?? ref.read(notificationSchedulerProvider);

  @override
  PermissionEducationControllerState build() =>
      const PermissionEducationControllerState();

  PermissionEducationControllerState get currentState => state;

  Future<void> refreshCapabilities() {
    return _serialize(() async {
      final deviceState = await _repository.loadDeviceState();
      final snapshot = await _readCapabilitySetup(deviceState);
      state = state.copyWith(
        deviceState: deviceState,
        capabilityStatuses: snapshot.capabilityStatuses,
        setupSnapshot: snapshot,
      );
    });
  }

  Future<void> initialize({
    PermissionEducationSource source =
        PermissionEducationSource.firstDashboardVisit,
    bool forceShow = false,
  }) {
    return _serialize(() async {
      final deviceState = await _repository.loadDeviceState();
      final snapshot = await _readCapabilitySetup(deviceState);
      final now = _now();
      final sessionIsDismissed =
          deviceState.dismissedUntil?.isAfter(now) ?? false;
      final relevant =
          sessionIsDismissed &&
              source == PermissionEducationSource.firstDashboardVisit &&
              !forceShow
          ? <PermissionCapability>[]
          : _buildRelevantCapabilities(
              source,
              snapshot,
              deviceState,
              now,
              forceShow: forceShow,
            );
      final active = relevant.isEmpty ? null : relevant.first;
      final shouldShow =
          relevant.isNotEmpty &&
          (forceShow ||
              source != PermissionEducationSource.firstDashboardVisit ||
              !sessionIsDismissed);

      var publishedDeviceState = deviceState;
      if (shouldShow) {
        publishedDeviceState = deviceState.copyWith(
          lastShownAt: now,
          showCount: deviceState.showCount + 1,
          source: source,
        );
        await _repository.saveDeviceState(publishedDeviceState);
      } else if (!forceShow &&
          !sessionIsDismissed &&
          relevant.isEmpty &&
          source == PermissionEducationSource.firstDashboardVisit) {
        await _settingsRepository.setPermissionEducationSeen(true);
      }

      final publishedSnapshot = snapshot.withEducationOutcomes(
        _educationOutcomes(publishedDeviceState),
      );
      state = state.copyWith(
        deviceState: publishedDeviceState,
        relevantCapabilities: relevant,
        activeCapability: active,
        clearActiveCapability: active == null,
        capabilityStatuses: publishedSnapshot.capabilityStatuses,
        setupSnapshot: publishedSnapshot,
        isVisible: shouldShow,
        source: source,
        awaitingSettingsReturn: false,
        clearAwaitingSettingsCapability: true,
      );
    });
  }

  Future<void> useCurrentLocation() {
    return _runUserAction(PermissionCapability.deviceLocation, () async {
      final currentStatus =
          state.capabilityStatuses[PermissionCapability.deviceLocation];
      final currentPermission = currentStatus?.permissionState;
      if (currentStatus?.nextAction == PermissionNextAction.openAppSettings ||
          currentStatus?.nextAction ==
              PermissionNextAction.openLocationSettings) {
        await _openSettingsNow(PermissionCapability.deviceLocation);
        return;
      }
      if (currentPermission == AppPermissionState.restricted ||
          currentPermission == AppPermissionState.unavailable) {
        await _recordAndRefresh(
          PermissionCapability.deviceLocation,
          PermissionEducationOutcome.unavailable,
        );
        return;
      }

      final requested = await _gateway.request(
        PermissionCapability.deviceLocation,
      );
      if (requested == AppPermissionState.permanentlyDenied ||
          requested == AppPermissionState.serviceDisabled) {
        await _recordAndRefresh(
          PermissionCapability.deviceLocation,
          PermissionEducationOutcome.blocked,
        );
        await _openSettingsNow(PermissionCapability.deviceLocation);
        return;
      }
      if (requested != AppPermissionState.granted) {
        await _recordAndRefresh(
          PermissionCapability.deviceLocation,
          requested == AppPermissionState.restricted ||
                  requested == AppPermissionState.unavailable
              ? PermissionEducationOutcome.unavailable
              : PermissionEducationOutcome.blocked,
        );
        return;
      }

      final acquired = await _weatherRepository.useCurrentLocationHomeArea();
      final persisted = await _settingsRepository.homeLocation();
      if (acquired == null || persisted == null) {
        await _recordAndRefresh(
          PermissionCapability.deviceLocation,
          PermissionEducationOutcome.failed,
        );
        return;
      }

      await _recordAndRefresh(
        PermissionCapability.deviceLocation,
        PermissionEducationOutcome.granted,
      );
      if (_isResolvedForAdvancement(
        PermissionCapability.deviceLocation,
        state.setupSnapshot,
      )) {
        await _advanceNextStepNow(PermissionCapability.deviceLocation);
      }
    });
  }

  Future<void> chooseLocationManually(HomeLocation chosenLocation) {
    return _runUserAction(PermissionCapability.deviceLocation, () async {
      final manualLocation =
          chosenLocation.source.trim().toLowerCase() == 'manual'
          ? chosenLocation
          : HomeLocation(
              label: chosenLocation.label,
              latitude: chosenLocation.latitude,
              longitude: chosenLocation.longitude,
              timezone: chosenLocation.timezone,
              source: 'manual',
            );
      await _settingsRepository.setHomeLocation(manualLocation);
      await _recordAndRefresh(
        PermissionCapability.deviceLocation,
        PermissionEducationOutcome.configuredManually,
      );
      unawaited(_refreshWeatherBestEffort());
      await _advanceNextStepNow(PermissionCapability.deviceLocation);
    });
  }

  Future<void> enableNotifications() {
    return _runUserAction(PermissionCapability.notifications, () async {
      final currentPermission = state
          .capabilityStatuses[PermissionCapability.notifications]
          ?.permissionState;
      if (currentPermission == AppPermissionState.permanentlyDenied) {
        await _openSettingsNow(PermissionCapability.notifications);
        return;
      }
      if (currentPermission == AppPermissionState.restricted ||
          currentPermission == AppPermissionState.unavailable) {
        await _recordAndRefresh(
          PermissionCapability.notifications,
          PermissionEducationOutcome.unavailable,
        );
        return;
      }

      final requested = await _gateway.request(
        PermissionCapability.notifications,
      );
      if (requested == AppPermissionState.permanentlyDenied) {
        await _recordAndRefresh(
          PermissionCapability.notifications,
          PermissionEducationOutcome.blocked,
        );
        await _openSettingsNow(PermissionCapability.notifications);
        return;
      }
      if (requested != AppPermissionState.granted) {
        await _recordAndRefresh(
          PermissionCapability.notifications,
          requested == AppPermissionState.restricted ||
                  requested == AppPermissionState.unavailable
              ? PermissionEducationOutcome.unavailable
              : PermissionEducationOutcome.blocked,
        );
        return;
      }

      final preferences = await _settingsRepository.notificationPreferences();
      if (!preferences.allowsLocalReminders) {
        await _settingsRepository.setNotificationPreferences(
          preferences.copyWith(enabled: true, localReminders: true),
        );
      }
      await _notificationScheduler.refreshSchedules();
      await _recordAndRefresh(
        PermissionCapability.notifications,
        PermissionEducationOutcome.granted,
      );
      if (_isResolvedForAdvancement(
        PermissionCapability.notifications,
        state.setupSnapshot,
      )) {
        await _advanceNextStepNow(PermissionCapability.notifications);
      }
    });
  }

  Future<void> enableExactTiming() {
    return _runUserAction(PermissionCapability.exactReminderTiming, () async {
      final currentPermission = state
          .capabilityStatuses[PermissionCapability.exactReminderTiming]
          ?.permissionState;
      if (currentPermission == AppPermissionState.permanentlyDenied) {
        await _openSettingsNow(PermissionCapability.exactReminderTiming);
        return;
      }
      if (currentPermission == AppPermissionState.restricted ||
          currentPermission == AppPermissionState.unavailable) {
        await _recordAndRefresh(
          PermissionCapability.exactReminderTiming,
          PermissionEducationOutcome.unavailable,
        );
        return;
      }

      final preferences = await _settingsRepository.notificationPreferences();
      if (!preferences.allowsLocalReminders) {
        await _recordAndRefresh(
          PermissionCapability.exactReminderTiming,
          PermissionEducationOutcome.failed,
        );
        return;
      }

      final requested = await _gateway.request(
        PermissionCapability.exactReminderTiming,
      );
      if (requested == AppPermissionState.permanentlyDenied) {
        await _recordAndRefresh(
          PermissionCapability.exactReminderTiming,
          PermissionEducationOutcome.blocked,
        );
        await _openSettingsNow(PermissionCapability.exactReminderTiming);
        return;
      }
      if (requested != AppPermissionState.granted) {
        await _notificationScheduler.refreshSchedules();
        await _recordAndRefresh(
          PermissionCapability.exactReminderTiming,
          requested == AppPermissionState.restricted ||
                  requested == AppPermissionState.unavailable
              ? PermissionEducationOutcome.unavailable
              : PermissionEducationOutcome.blocked,
        );
        return;
      }

      await _settingsRepository.setNotificationPreferences(
        preferences.copyWith(preferExactReminders: true),
      );
      await _notificationScheduler.refreshSchedules();
      await _recordAndRefresh(
        PermissionCapability.exactReminderTiming,
        PermissionEducationOutcome.granted,
      );
      if (_isResolvedForAdvancement(
        PermissionCapability.exactReminderTiming,
        state.setupSnapshot,
      )) {
        await _advanceNextStepNow(PermissionCapability.exactReminderTiming);
      }
    });
  }

  Future<void> deferCurrentStep() {
    final capability = state.activeCapability;
    if (capability == null) {
      return Future<void>.value();
    }
    return _runUserAction(capability, () async {
      if (capability == PermissionCapability.exactReminderTiming) {
        final preferences = await _settingsRepository.notificationPreferences();
        if (preferences.preferExactReminders) {
          await _settingsRepository.setNotificationPreferences(
            preferences.copyWith(preferExactReminders: false),
          );
        }
        await _notificationScheduler.refreshSchedules();
      }

      final updatedDeviceState = _deviceStateWithOutcome(
        state.deviceState,
        capability,
        PermissionEducationOutcome.deferred,
        deferredAt: _now(),
      );
      await _repository.saveDeviceState(updatedDeviceState);
      final snapshot = await _readCapabilitySetup(updatedDeviceState);
      _publishSnapshot(updatedDeviceState, snapshot);
      await _advanceNextStepNow(capability);
    });
  }

  Future<void> finishLater() {
    return _runUserAction(state.activeCapability, () async {
      final updatedDeviceState = state.deviceState.copyWith(
        dismissedUntil: _now().add(sessionDismissalCooldown),
      );
      await _repository.saveDeviceState(updatedDeviceState);
      state = state.copyWith(
        deviceState: updatedDeviceState,
        isVisible: false,
        awaitingSettingsReturn: false,
        clearAwaitingSettingsCapability: true,
        clearOperationFailure:
            state.awaitingSettingsCapability != null &&
            _isResolvedForAdvancement(
              state.awaitingSettingsCapability!,
              state.setupSnapshot,
            ),
      );
    });
  }

  Future<void> openSettingsFor(PermissionCapability capability) {
    return _runUserAction(capability, () => _openSettingsNow(capability));
  }

  Future<void> handleAppResume() {
    return _serialize(() async {
      if (!state.awaitingSettingsReturn && !state.isVisible) {
        final deviceState = await _repository.loadDeviceState();
        final snapshot = await _readCapabilitySetup(deviceState);
        state = state.copyWith(
          deviceState: deviceState,
          capabilityStatuses: snapshot.capabilityStatuses,
          setupSnapshot: snapshot,
        );
        return;
      }

      final awaitedCapability = state.awaitingSettingsCapability;
      var deviceState = state.deviceState;
      var snapshot = await _readCapabilitySetup(deviceState);
      var outcome = awaitedCapability == null
          ? null
          : snapshot.statusFor(awaitedCapability).outcome;

      if (awaitedCapability == PermissionCapability.notifications &&
          snapshot.notifications.notificationPermission ==
              AppPermissionState.granted &&
          snapshot.notifications.notificationsActuallyEnabled &&
          !snapshot.notifications.preferences.allowsLocalReminders) {
        await _settingsRepository.setNotificationPreferences(
          snapshot.notifications.preferences.copyWith(
            enabled: true,
            localReminders: true,
          ),
        );
        await _notificationScheduler.refreshSchedules();
        snapshot = await _readCapabilitySetup(deviceState);
        outcome = PermissionEducationOutcome.granted;
      }

      if (awaitedCapability == PermissionCapability.exactReminderTiming &&
          snapshot.notifications.exactAlarmPermission ==
              AppPermissionState.granted &&
          snapshot.notifications.canActuallyScheduleExact &&
          snapshot.notifications.preferences.allowsLocalReminders &&
          !snapshot.notifications.preferences.preferExactReminders) {
        await _settingsRepository.setNotificationPreferences(
          snapshot.notifications.preferences.copyWith(
            preferExactReminders: true,
          ),
        );
        await _notificationScheduler.refreshSchedules();
        snapshot = await _readCapabilitySetup(deviceState);
        outcome = PermissionEducationOutcome.granted;
      }

      var activeCapability = state.activeCapability;
      var isVisible = state.isVisible;
      var completed = false;
      if (awaitedCapability != null &&
          awaitedCapability == activeCapability &&
          _isResolvedForAdvancement(awaitedCapability, snapshot)) {
        deviceState = _deviceStateWithOutcome(
          deviceState,
          awaitedCapability,
          outcome ?? PermissionEducationOutcome.granted,
        );
        final next = _nextCapabilityAfter(awaitedCapability);
        if (next == null) {
          deviceState = deviceState.copyWith(completedAt: _now());
          activeCapability = null;
          isVisible = false;
          completed = true;
        } else {
          activeCapability = next;
        }
        await _repository.saveDeviceState(deviceState);
        if (completed) {
          await _settingsRepository.setPermissionEducationSeen(true);
        }
        snapshot = snapshot.withEducationOutcomes(
          _educationOutcomes(deviceState),
        );
      }

      state = state.copyWith(
        deviceState: deviceState,
        activeCapability: activeCapability,
        clearActiveCapability: activeCapability == null,
        capabilityStatuses: snapshot.capabilityStatuses,
        setupSnapshot: snapshot,
        isVisible: isVisible,
        awaitingSettingsReturn: false,
        clearAwaitingSettingsCapability: true,
      );
    });
  }

  List<PermissionCapability> _buildRelevantCapabilities(
    PermissionEducationSource source,
    CapabilitySetupSnapshot snapshot,
    PermissionEducationDeviceState deviceState,
    DateTime now, {
    required bool forceShow,
  }) {
    bool cooldownAllows(PermissionCapability capability) =>
        forceShow || !deviceState.isDeferredFor(capability, now);

    switch (source) {
      case PermissionEducationSource.firstDashboardVisit:
        return [
          if (!snapshot.weather.isConfigured &&
              cooldownAllows(PermissionCapability.deviceLocation))
            PermissionCapability.deviceLocation,
          if (!snapshot.isSatisfied(PermissionCapability.notifications) &&
              snapshot.notifications.deviceReminderState !=
                  EffectiveCapabilityState.unavailable &&
              cooldownAllows(PermissionCapability.notifications))
            PermissionCapability.notifications,
        ];
      case PermissionEducationSource.weatherCard:
        return const [PermissionCapability.deviceLocation];
      case PermissionEducationSource.reminderSettings:
      case PermissionEducationSource.taskScheduling:
        final exact = snapshot.statusFor(
          PermissionCapability.exactReminderTiming,
        );
        if (exact.permissionState == AppPermissionState.unavailable ||
            (!forceShow &&
                !snapshot.notifications.preferences.preferExactReminders) ||
            exact.effectiveState == EffectiveCapabilityState.active) {
          return const [];
        }
        return const [PermissionCapability.exactReminderTiming];
      case PermissionEducationSource.settings:
        return [
          PermissionCapability.deviceLocation,
          PermissionCapability.notifications,
          if (snapshot
                  .statusFor(PermissionCapability.exactReminderTiming)
                  .permissionState !=
              AppPermissionState.unavailable)
            PermissionCapability.exactReminderTiming,
        ];
    }
  }

  Future<CapabilitySetupSnapshot> _readCapabilitySetup(
    PermissionEducationDeviceState deviceState,
  ) async {
    final previous = state.setupSnapshot;
    final locationAccessFuture = _readOr(
      _gateway.checkLocationAccess,
      DeviceLocationAccessState(
        permissionState:
            previous?.weather.deviceLocationPermission ??
            AppPermissionState.unavailable,
        serviceEnabled: previous?.weather.locationServiceEnabled,
      ),
    );
    final notificationPermissionFuture = _readOr(
      () => _gateway.check(PermissionCapability.notifications),
      AppPermissionState.unavailable,
    );
    final exactPermissionFuture = _readOr(
      () => _gateway.check(PermissionCapability.exactReminderTiming),
      AppPermissionState.unavailable,
    );
    final homeLocationFuture = _readOr(
      _settingsRepository.homeLocation,
      previous?.weather.selectedArea,
    );
    final preferencesFuture = _readOr(
      _settingsRepository.notificationPreferences,
      previous?.notifications.preferences ?? const NotificationPreferences(),
    );
    final schedulerStateFuture = _readOr(
      _notificationScheduler.permissionState,
      NotificationPermissionState(
        notificationsEnabled:
            previous?.notifications.notificationsActuallyEnabled ?? false,
        canScheduleExact:
            previous?.notifications.canActuallyScheduleExact ?? false,
      ),
    );

    return deriveCapabilitySetupSnapshot(
      homeLocation: await homeLocationFuture,
      notificationPreferences: await preferencesFuture,
      deviceLocationPermission: (await locationAccessFuture).permissionState,
      locationServiceEnabled: (await locationAccessFuture).serviceEnabled,
      notificationPermission: await notificationPermissionFuture,
      exactAlarmPermission: await exactPermissionFuture,
      schedulerState: await schedulerStateFuture,
      educationOutcomes: _educationOutcomes(deviceState),
    );
  }

  Future<void> _recordAndRefresh(
    PermissionCapability capability,
    PermissionEducationOutcome outcome,
  ) async {
    final deviceState = _deviceStateWithOutcome(
      state.deviceState,
      capability,
      outcome,
    );
    await _repository.saveDeviceState(deviceState);
    final snapshot = await _readCapabilitySetup(deviceState);
    _publishSnapshot(deviceState, snapshot);
  }

  PermissionEducationDeviceState _deviceStateWithOutcome(
    PermissionEducationDeviceState deviceState,
    PermissionCapability capability,
    PermissionEducationOutcome outcome, {
    DateTime? deferredAt,
  }) {
    final steps = Map<PermissionCapability, StepEducationState>.from(
      deviceState.steps,
    );
    final previous = steps[capability] ?? const StepEducationState();
    steps[capability] = StepEducationState(
      educationSeen: true,
      deferredAt: deferredAt,
      deferCount: deferredAt == null
          ? previous.deferCount
          : previous.deferCount + 1,
      lastOutcome: outcome,
    );
    return deviceState.copyWith(steps: steps);
  }

  void _publishSnapshot(
    PermissionEducationDeviceState deviceState,
    CapabilitySetupSnapshot snapshot,
  ) {
    state = state.copyWith(
      deviceState: deviceState,
      capabilityStatuses: snapshot.capabilityStatuses,
      setupSnapshot: snapshot,
    );
  }

  Future<void> _advanceNextStepNow(
    PermissionCapability completedCapability,
  ) async {
    if (state.activeCapability != completedCapability) {
      return;
    }
    final next = _nextCapabilityAfter(completedCapability);
    if (next != null) {
      state = state.copyWith(activeCapability: next);
      return;
    }

    final updatedDeviceState = state.deviceState.copyWith(completedAt: _now());
    await _repository.saveDeviceState(updatedDeviceState);
    await _settingsRepository.setPermissionEducationSeen(true);
    state = state.copyWith(
      deviceState: updatedDeviceState,
      clearActiveCapability: true,
      isVisible: false,
      awaitingSettingsReturn: false,
      clearAwaitingSettingsCapability: true,
    );
  }

  PermissionCapability? _nextCapabilityAfter(PermissionCapability capability) {
    final index = state.relevantCapabilities.indexOf(capability);
    if (index < 0 || index >= state.relevantCapabilities.length - 1) {
      return null;
    }
    return state.relevantCapabilities[index + 1];
  }

  Future<void> _openSettingsNow(PermissionCapability capability) async {
    final permissionState =
        state.capabilityStatuses[capability]?.permissionState;
    if (permissionState == null ||
        permissionState == AppPermissionState.restricted ||
        permissionState == AppPermissionState.unavailable) {
      state = state.copyWith(
        operationFailure: PermissionOperationFailure(
          capability: capability,
          kind: PermissionOperationFailureKind.settings,
        ),
      );
      return;
    }
    state = state.copyWith(
      awaitingSettingsReturn: true,
      awaitingSettingsCapability: capability,
    );
    final opened = await _gateway.openSettings(capability);
    if (!opened) {
      state = state.copyWith(
        awaitingSettingsReturn: false,
        clearAwaitingSettingsCapability: true,
      );
      await _recordAndRefresh(capability, PermissionEducationOutcome.failed);
      state = state.copyWith(
        operationFailure: PermissionOperationFailure(
          capability: capability,
          kind: PermissionOperationFailureKind.settings,
        ),
      );
    }
  }

  bool _isResolvedForAdvancement(
    PermissionCapability capability,
    CapabilitySetupSnapshot? snapshot,
  ) {
    if (snapshot == null) {
      return false;
    }
    return switch (capability) {
      PermissionCapability.deviceLocation => snapshot.weather.isConfigured,
      PermissionCapability.notifications =>
        snapshot.notifications.deviceReminderState ==
            EffectiveCapabilityState.active,
      PermissionCapability.exactReminderTiming =>
        snapshot.notifications.exactTimingState ==
            EffectiveCapabilityState.active,
    };
  }

  Map<PermissionCapability, PermissionEducationOutcome> _educationOutcomes(
    PermissionEducationDeviceState deviceState,
  ) {
    return {
      for (final entry in deviceState.steps.entries)
        entry.key: entry.value.lastOutcome,
    };
  }

  Future<void> _refreshWeatherBestEffort() async {
    try {
      await _weatherRepository.refreshWeather();
    } catch (_) {}
  }

  Future<T> _readOr<T>(Future<T> Function() read, T fallback) async {
    try {
      return await read();
    } catch (_) {
      return fallback;
    }
  }

  Future<void> _runUserAction(
    PermissionCapability? capability,
    Future<void> Function() operation,
  ) {
    if (_userActionPending) {
      return Future<void>.value();
    }
    _userActionPending = true;
    return _serialize(() async {
      state = state.copyWith(isBusy: true, clearOperationFailure: true);
      try {
        await operation();
      } catch (_) {
        if (capability != null) {
          try {
            await _recordAndRefresh(
              capability,
              PermissionEducationOutcome.failed,
            );
          } catch (_) {}
          state = state.copyWith(
            operationFailure: PermissionOperationFailure(
              capability: capability,
              kind: PermissionOperationFailureKind.action,
            ),
          );
        }
      } finally {
        _userActionPending = false;
        state = state.copyWith(isBusy: false);
      }
    });
  }

  Future<void> _serialize(Future<void> Function() operation) {
    _operationTail = _operationTail.then((_) async {
      try {
        await operation();
      } catch (_) {}
    });
    return _operationTail;
  }
}
