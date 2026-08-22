import 'package:flutter/widgets.dart';

import '../../../core/domain/contracts.dart';
import '../../../core/domain/models.dart';
import '../../../core/sync/sync_contracts.dart';
import '../../auth/domain/auth_repository.dart';

class InitialHomeSnapshot {
  const InitialHomeSnapshot({
    required this.session,
    required this.profile,
    required this.tasks,
    required this.assets,
    required this.rooms,
    required this.backupState,
    required this.unreadNotifications,
    required this.syncStatus,
    required this.loadedAt,
    this.homeLocation,
    this.weather,
    this.avatarProvider,
    this.offline = false,
  });

  final AuthSession session;
  final AppProfile profile;
  final List<TaskItem> tasks;
  final List<Asset> assets;
  final List<Room> rooms;
  final BackupState backupState;
  final int unreadNotifications;
  final HomeLocation? homeLocation;
  final WeatherSnapshot? weather;
  final SyncStatus syncStatus;
  final ImageProvider<Object>? avatarProvider;
  final DateTime loadedAt;
  final bool offline;

  InitialHomeSnapshot copyWithOffline(bool value) {
    return InitialHomeSnapshot(
      session: session,
      profile: profile,
      tasks: tasks,
      assets: assets,
      rooms: rooms,
      backupState: backupState,
      unreadNotifications: unreadNotifications,
      homeLocation: homeLocation,
      weather: weather,
      syncStatus: syncStatus,
      avatarProvider: avatarProvider,
      loadedAt: loadedAt,
      offline: value,
    );
  }
}
