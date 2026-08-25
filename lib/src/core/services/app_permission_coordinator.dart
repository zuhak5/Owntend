import 'package:drift/drift.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import '../database/app_database.dart';

enum AppPermissionKind { notifications, location }

enum AppPermissionState {
  granted,
  denied,
  permanentlyDenied,
  restricted,
  serviceDisabled,
  unavailable,
}

abstract interface class AppPermissionGateway {
  Future<AppPermissionState> check(AppPermissionKind kind);
  Future<AppPermissionState> request(AppPermissionKind kind);
  Future<bool> wasPrompted(AppPermissionKind kind);
  Future<void> markPrompted(AppPermissionKind kind);
  Future<bool> openAppPermissionSettings();
  Future<bool> openLocationServiceSettings();
}

abstract interface class TargetedAppPermissionSettings {
  Future<bool> openSettingsFor(AppPermissionKind kind);
}

/// Supplies the two independent Android location signals without collapsing a
/// disabled device service into an operating-system permission result.
abstract interface class AppLocationAccessGateway {
  Future<AppPermissionState> checkLocationPermission();
  Future<bool?> isLocationServiceEnabled();
}

class AppPermissionCoordinator
    implements
        AppPermissionGateway,
        TargetedAppPermissionSettings,
        AppLocationAccessGateway {
  AppPermissionCoordinator(this._database);

  final AppDatabase _database;

  @override
  Future<AppPermissionState> check(AppPermissionKind kind) async {
    try {
      if (kind == AppPermissionKind.location &&
          !await Geolocator.isLocationServiceEnabled()) {
        return AppPermissionState.serviceDisabled;
      }
      return _mapStatus(await _permission(kind).status);
    } on MissingPluginException {
      return AppPermissionState.unavailable;
    }
  }

  @override
  Future<AppPermissionState> request(AppPermissionKind kind) async {
    final current = await check(kind);
    if (current == AppPermissionState.granted ||
        current == AppPermissionState.permanentlyDenied ||
        current == AppPermissionState.restricted ||
        current == AppPermissionState.serviceDisabled ||
        current == AppPermissionState.unavailable) {
      return current;
    }
    await markPrompted(kind);
    try {
      return _mapStatus(await _permission(kind).request());
    } on MissingPluginException {
      return AppPermissionState.unavailable;
    }
  }

  @override
  Future<bool> wasPrompted(AppPermissionKind kind) async {
    final row =
        await (_database.select(_database.settings)
              ..where((setting) => setting.key.equals(_historyKey(kind))))
            .getSingleOrNull();
    return row?.value == 'true';
  }

  @override
  Future<void> markPrompted(AppPermissionKind kind) async {
    await _database
        .into(_database.settings)
        .insertOnConflictUpdate(
          SettingsCompanion.insert(
            key: _historyKey(kind),
            value: 'true',
            updatedAt: Value(DateTime.now()),
          ),
        );
  }

  @override
  Future<bool> openAppPermissionSettings() => openAppSettings();

  @override
  Future<bool> openLocationServiceSettings() =>
      Geolocator.openLocationSettings();

  @override
  Future<AppPermissionState> checkLocationPermission() async {
    try {
      return _mapStatus(await Permission.locationWhenInUse.status);
    } on MissingPluginException {
      return AppPermissionState.unavailable;
    } on PlatformException {
      return AppPermissionState.unavailable;
    }
  }

  @override
  Future<bool?> isLocationServiceEnabled() async {
    try {
      return await Geolocator.isLocationServiceEnabled();
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  @override
  Future<bool> openSettingsFor(AppPermissionKind kind) async {
    try {
      switch (kind) {
        case AppPermissionKind.notifications:
          return await openAppPermissionSettings();
        case AppPermissionKind.location:
          if (await check(kind) == AppPermissionState.serviceDisabled) {
            return await openLocationServiceSettings();
          }
          return await openAppPermissionSettings();
      }
    } on MissingPluginException {
      return false;
    } on Exception {
      return false;
    }
  }

  Permission _permission(AppPermissionKind kind) => switch (kind) {
    AppPermissionKind.notifications => Permission.notification,
    AppPermissionKind.location => Permission.locationWhenInUse,
  };

  AppPermissionState _mapStatus(PermissionStatus status) => switch (status) {
    PermissionStatus.granted ||
    PermissionStatus.limited => AppPermissionState.granted,
    PermissionStatus.permanentlyDenied => AppPermissionState.permanentlyDenied,
    PermissionStatus.restricted => AppPermissionState.restricted,
    PermissionStatus.denied ||
    PermissionStatus.provisional => AppPermissionState.denied,
  };

  String _historyKey(AppPermissionKind kind) =>
      'permission_prompted_${kind.name}';
}
