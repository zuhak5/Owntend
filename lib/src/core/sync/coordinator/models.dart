part of '../sync_coordinator.dart';

class _ActiveAccountScope {
  const _ActiveAccountScope({
    required this.epoch,
    required this.userId,
    required this.deviceId,
  });

  final int epoch;
  final String userId;
  final String deviceId;
}

class _AccountScopeInactive implements Exception {
  const _AccountScopeInactive();
}

class _PullSeed {
  const _PullSeed({
    required this.spec,
    required this.recordKey,
    required this.exactCount,
    required this.firstPage,
  });

  final SyncEntitySpec spec;
  final String? recordKey;
  final int exactCount;
  final List<SyncRecord> firstPage;
}

class _PullOutcome {
  const _PullOutcome({
    this.maintenanceChanged = false,
    this.remoteRecordCount = 0,
    this.meaningfulRemoteRecordCount = 0,
  });

  final bool maintenanceChanged;
  final int remoteRecordCount;
  final int meaningfulRemoteRecordCount;
}

bool _isBootstrapClassificationRecord(_PullSeed seed) {
  return seed.spec.entity != 'profile';
}

bool _sameRecordData(SyncRecord local, SyncRecord remote) {
  if (local.spec.entity != remote.spec.entity ||
      local.isDeleted != remote.isDeleted) {
    return false;
  }
  for (final column in local.spec.localColumns) {
    if (!local.values.containsKey(column) ||
        !remote.values.containsKey(column) ||
        !_sameValue(
          local.spec,
          column,
          local.values[column],
          remote.values[column],
        )) {
      return false;
    }
  }
  return true;
}

bool _isMaintenanceSyncEntity(SyncRecord record) {
  return const {
    'maintenance_plan',
    'maintenance_plan_metadata',
    'maintenance_record',
  }.contains(record.spec.entity);
}

bool _remoteOriginWinsTie(String? remoteOrigin, String localDeviceId) {
  return remoteOrigin != null && remoteOrigin.compareTo(localDeviceId) > 0;
}

bool _localOriginWinsTie(String? localOrigin, String? remoteOrigin) {
  return localOrigin != null &&
      (remoteOrigin == null || localOrigin.compareTo(remoteOrigin) > 0);
}

bool _sameValue(
  SyncEntitySpec spec,
  String column,
  Object? local,
  Object? remote,
) {
  if (local == null || remote == null) return local == remote;
  if (spec.dateColumns.contains(column)) {
    final localDate = _asUtcDate(local);
    final remoteDate = _asUtcDate(remote);
    return localDate != null &&
        remoteDate != null &&
        localDate.isAtSameMomentAs(remoteDate);
  }
  if (local is num && remote is num) {
    return local.toDouble() == remote.toDouble();
  }
  return local == remote;
}

DateTime? _asUtcDate(Object? value) {
  if (value is DateTime) return value.toUtc();
  if (value is String) return DateTime.tryParse(value)?.toUtc();
  return null;
}

int _diagnosticId(String value) {
  var hash = 0;
  for (final codeUnit in value.codeUnits) {
    hash = ((hash * 31) + codeUnit) & 0x7fffffff;
  }
  return hash;
}
