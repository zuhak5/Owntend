import 'package:flutter_test/flutter_test.dart';
import 'package:owntend/src/core/domain/contracts.dart';
import 'package:owntend/src/core/services/app_permission_coordinator.dart';
import 'package:owntend/src/core/services/notification_service.dart';
import 'package:owntend/src/features/permissions/data/device_permission_gateway.dart';
import 'package:owntend/src/features/permissions/domain/permission_capability.dart';

class _FakeAppPermissionGateway
    implements AppPermissionGateway, TargetedAppPermissionSettings {
  final Map<AppPermissionKind, AppPermissionState> states = {
    AppPermissionKind.location: AppPermissionState.denied,
    AppPermissionKind.notifications: AppPermissionState.denied,
    AppPermissionKind.exactAlarms: AppPermissionState.denied,
  };
  final List<AppPermissionKind> checks = [];
  final List<AppPermissionKind> requests = [];
  final List<AppPermissionKind> settingsTargets = [];

  @override
  Future<AppPermissionState> check(AppPermissionKind kind) async {
    checks.add(kind);
    return states[kind]!;
  }

  @override
  Future<AppPermissionState> request(AppPermissionKind kind) async {
    requests.add(kind);
    return states[kind]!;
  }

  @override
  Future<bool> openSettingsFor(AppPermissionKind kind) async {
    settingsTargets.add(kind);
    return true;
  }

  @override
  Future<void> markPrompted(AppPermissionKind kind) async {}

  @override
  Future<bool> openAppPermissionSettings() async => true;

  @override
  Future<bool> openLocationServiceSettings() async => true;

  @override
  Future<bool> wasPrompted(AppPermissionKind kind) async => false;
}

class _FakeMaintenanceRepository implements MaintenanceRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test(
    'feature gateway maps every capability to the canonical coordinator',
    () async {
      final coordinator = _FakeAppPermissionGateway();
      final gateway = FlutterDevicePermissionGateway(coordinator);

      await gateway.check(PermissionCapability.deviceLocation);
      await gateway.request(PermissionCapability.notifications);
      await gateway.openSettings(PermissionCapability.exactReminderTiming);

      expect(coordinator.checks, [AppPermissionKind.location]);
      expect(coordinator.requests, [AppPermissionKind.notifications]);
      expect(coordinator.settingsTargets, [AppPermissionKind.exactAlarms]);
    },
  );

  test(
    'notification scheduler delegates all OS requests to the coordinator',
    () async {
      final coordinator = _FakeAppPermissionGateway();
      final scheduler = OwntendNotificationScheduler(
        _FakeMaintenanceRepository(),
        permissionGateway: coordinator,
      );

      await scheduler.requestPermissions(exactAlarms: true);

      expect(coordinator.requests, [
        AppPermissionKind.notifications,
        AppPermissionKind.exactAlarms,
      ]);
    },
  );

  test(
    'notification scheduler fails closed without the canonical requester',
    () async {
      final scheduler = OwntendNotificationScheduler(
        _FakeMaintenanceRepository(),
      );

      await expectLater(
        scheduler.requestPermissions(),
        throwsA(isA<StateError>()),
      );
    },
  );
}
