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

  static const String keyV3 = 'permission_education_device_state_v3';
  static const String keyV2 = 'permission_education_seen_v2';

  @override
  Future<PermissionEducationDeviceState> loadDeviceState() async {
    final v3Row = await (_database.select(
      _database.settings,
    )..where((s) => s.key.equals(keyV3))).getSingleOrNull();

    if (v3Row != null && v3Row.value.isNotEmpty) {
      return PermissionEducationDeviceState.decode(v3Row.value);
    }

    // Bootstrap from legacy v2 setting if present
    final v2Row = await (_database.select(
      _database.settings,
    )..where((s) => s.key.equals(keyV2))).getSingleOrNull();

    final v2Seen = v2Row?.value == 'true';
    final initial = PermissionEducationDeviceState(
      showCount: v2Seen ? 1 : 0,
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
            key: keyV3,
            value: state.encode(),
            updatedAt: Value(DateTime.now()),
          ),
        );
  }
}
