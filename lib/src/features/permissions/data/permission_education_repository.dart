import 'package:drift/drift.dart';

import '../../../../src/core/database/app_database.dart';
import '../domain/permission_capability.dart';
import '../domain/permission_education_state.dart';

abstract interface class PermissionEducationRepository {
  Future<PermissionEducationDeviceState> loadDeviceState();
  Future<void> saveDeviceState(PermissionEducationDeviceState state);
}

class DriftPermissionEducationRepository
    implements PermissionEducationRepository {
  DriftPermissionEducationRepository(this._database);

  final AppDatabase _database;

  static const String key = 'permission_education_device_state';

  @override
  Future<PermissionEducationDeviceState> loadDeviceState() async {
    final row = await (_database.select(
      _database.settings,
    )..where((setting) => setting.key.equals(key))).getSingleOrNull();

    if (row != null && row.value.isNotEmpty) {
      return PermissionEducationDeviceState.decode(row.value);
    }

    const initial = PermissionEducationDeviceState(
      source: PermissionEducationSource.firstDashboardVisit,
    );

    await saveDeviceState(initial);
    return initial;
  }

  @override
  Future<void> saveDeviceState(PermissionEducationDeviceState state) async {
    await _database
        .into(_database.settings)
        .insertOnConflictUpdate(
          SettingsCompanion.insert(
            key: key,
            value: state.encode(),
            updatedAt: Value(DateTime.now()),
          ),
        );
  }
}
