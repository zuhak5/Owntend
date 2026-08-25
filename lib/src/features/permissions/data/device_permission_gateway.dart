import '../../../core/services/app_permission_coordinator.dart';
import '../domain/permission_capability.dart';

class DeviceLocationAccessState {
  const DeviceLocationAccessState({
    required this.permissionState,
    required this.serviceEnabled,
  });

  final AppPermissionState permissionState;
  final bool? serviceEnabled;
}

abstract interface class DevicePermissionGateway {
  Future<AppPermissionState> check(PermissionCapability capability);
  Future<DeviceLocationAccessState> checkLocationAccess();
  Future<AppPermissionState> request(PermissionCapability capability);
  Future<bool> openSettings(PermissionCapability capability);
}

class FlutterDevicePermissionGateway implements DevicePermissionGateway {
  const FlutterDevicePermissionGateway(this._delegate);

  final AppPermissionGateway _delegate;

  @override
  Future<AppPermissionState> check(PermissionCapability capability) =>
      _delegate.check(_kindFor(capability));

  @override
  Future<DeviceLocationAccessState> checkLocationAccess() async {
    final delegate = _delegate;
    if (delegate is AppLocationAccessGateway) {
      final locDelegate = delegate as AppLocationAccessGateway;
      final values = await Future.wait<Object?>([
        locDelegate.checkLocationPermission(),
        locDelegate.isLocationServiceEnabled(),
      ]);
      return DeviceLocationAccessState(
        permissionState: values[0]! as AppPermissionState,
        serviceEnabled: values[1] as bool?,
      );
    }

    final collapsed = await delegate.check(AppPermissionKind.location);
    return DeviceLocationAccessState(
      permissionState: collapsed == AppPermissionState.serviceDisabled
          ? AppPermissionState.denied
          : collapsed,
      serviceEnabled: collapsed == AppPermissionState.unavailable
          ? null
          : collapsed != AppPermissionState.serviceDisabled,
    );
  }

  @override
  Future<AppPermissionState> request(PermissionCapability capability) =>
      _delegate.request(_kindFor(capability));

  @override
  Future<bool> openSettings(PermissionCapability capability) async {
    final kind = _kindFor(capability);
    final delegate = _delegate;
    if (delegate is TargetedAppPermissionSettings) {
      return (delegate as TargetedAppPermissionSettings).openSettingsFor(kind);
    }
    if (capability == PermissionCapability.deviceLocation &&
        await delegate.check(kind) == AppPermissionState.serviceDisabled) {
      return delegate.openLocationServiceSettings();
    }
    return delegate.openAppPermissionSettings();
  }

  AppPermissionKind _kindFor(PermissionCapability capability) =>
      switch (capability) {
        PermissionCapability.deviceLocation => AppPermissionKind.location,
        PermissionCapability.notifications => AppPermissionKind.notifications,
      };
}
