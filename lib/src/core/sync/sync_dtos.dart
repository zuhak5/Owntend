const syncMetadataColumns = <String>['revision', 'updated_at'];

enum SyncMode {
  initialHydration,
  incrementalPull,
  pushOnly,
  targetedPull,
  fullReconcile,
  manualRefresh,
  conflictRecovery,
}

class SyncWork {
  const SyncWork({
    required this.mode,
    this.pullTables,
    this.enqueueReconciliation = false,
  });

  final SyncMode mode;
  final Set<String>? pullTables;
  final bool enqueueReconciliation;

  bool get allowsPull => mode != SyncMode.pushOnly;

  SyncWork asInitialHydration() => SyncWork(
    mode: SyncMode.initialHydration,
    pullTables: null,
    enqueueReconciliation: enqueueReconciliation,
  );
}

enum SyncRealtimeEventType { insert, update, delete }

enum SyncMutationState {
  pending,
  inFlight,
  conflictRecovery,
  conflict,
  failedVisible;

  static SyncMutationState fromStorage(String value) {
    return SyncMutationState.values.firstWhere(
      (state) => state.name == value,
      orElse: () => SyncMutationState.pending,
    );
  }
}

class RealtimeSyncEvent {
  const RealtimeSyncEvent({
    required this.table,
    required this.spec,
    required this.type,
    this.recordKey,
    this.revision,
    this.updatedAt,
    this.originDeviceId,
  });

  final String table;
  final SyncEntitySpec spec;
  final SyncRealtimeEventType type;
  final String? recordKey;
  final int? revision;
  final DateTime? updatedAt;
  final String? originDeviceId;
}

enum SyncScope { shared, deviceScoped, catalog }

class SyncEntitySpec {
  const SyncEntitySpec({
    required this.entity,
    required this.localTable,
    required this.remoteTable,
    required this.keyColumns,
    required this.localColumns,
    required this.updatableLocalColumns,
    required this.dateColumns,
    required this.modifiedExpression,
    this.boolColumns = const {},
    this.jsonColumns = const {},
    this.remoteRenames = const {},
    this.localOnlyColumns = const {},
    this.scope = SyncScope.shared,
    this.localWhere,
  });

  final String entity;
  final String localTable;
  final String remoteTable;
  final List<String> keyColumns;
  final List<String> localColumns;

  /// Local columns that generic optimistic PATCH operations may send.
  ///
  /// An empty set makes the entity insert/delete/RPC-only. Ownership, record
  /// keys, device scope, and sync metadata are always filters or server-owned
  /// values and therefore cannot appear here.
  final Set<String> updatableLocalColumns;
  final Set<String> dateColumns;
  final Set<String> boolColumns;
  final Set<String> jsonColumns;
  final String modifiedExpression;
  final Map<String, String> remoteRenames;

  /// Local columns that never exist on the remote table. They are excluded
  /// from the remote select clause and from outgoing write payloads, and are
  /// populated locally (for example by media materialization) instead.
  final Set<String> localOnlyColumns;

  final SyncScope scope;
  final String? localWhere;

  List<String> get remoteDataColumns => [
    for (final column in localColumns)
      if (!localOnlyColumns.contains(column)) remoteRenames[column] ?? column,
  ];

  List<String> get remoteSelectColumns => scope == SyncScope.catalog
      ? remoteDataColumns
      : [
          'user_id',
          if (scope == SyncScope.deviceScoped) 'device_id',
          ...remoteDataColumns,
          for (final column in syncMetadataColumns)
            if (!remoteDataColumns.contains(column)) column,
        ];

  String get selectClause => remoteSelectColumns.join(',');

  String remoteColumnFor(String localColumn) =>
      remoteRenames[localColumn] ?? localColumn;

  String localColumnFor(String remoteColumn) {
    for (final entry in remoteRenames.entries) {
      if (entry.value == remoteColumn) return entry.key;
    }
    return remoteColumn;
  }

  bool get supportsGenericUpdate => updatableLocalColumns.isNotEmpty;

  List<String> get updateContractViolations {
    const protectedRemoteColumns = {
      'user_id',
      'device_id',
      'created_at',
      'updated_at',
      'revision',
    };
    final violations = <String>[];
    final remoteColumns = <String>{};
    for (final localColumn in updatableLocalColumns) {
      final remoteColumn = remoteColumnFor(localColumn);
      if (!localColumns.contains(localColumn)) {
        violations.add('$localColumn is not a local data column');
      }
      if (localOnlyColumns.contains(localColumn)) {
        violations.add('$localColumn is local-only');
      }
      if (keyColumns.contains(localColumn)) {
        violations.add('$localColumn is part of the record key');
      }
      if (protectedRemoteColumns.contains(remoteColumn)) {
        violations.add('$localColumn maps to protected $remoteColumn');
      }
      if (!remoteColumns.add(remoteColumn)) {
        violations.add('$localColumn duplicates remote column $remoteColumn');
      }
    }
    violations.sort();
    return violations;
  }

  void validateUpdateContract() {
    final violations = updateContractViolations;
    if (violations.isNotEmpty) {
      throw StateError(
        'Invalid generic update contract for $entity: ${violations.join('; ')}',
      );
    }
  }
}

/// Device-scoped permission state (`permission_education_device_state`) is
/// deliberately unsynced and excluded from allowedRemoteSettingKeys because OS
/// permissions are device-specific.
const allowedRemoteSettingKeys = <String>{
  'theme',
  'app_language',
  'app_language_explicit',
  'theme_time_of_day_enabled',
  'notification_preferences',
  'onboarding_completed',
  'permission_education_seen',
  'home_location',
};

const userSettingSyncSpec = SyncEntitySpec(
  entity: 'user_setting',
  localTable: 'settings',
  remoteTable: 'user_settings',
  keyColumns: ['key'],
  localColumns: ['key', 'value', 'updated_at'],
  updatableLocalColumns: {'value'},
  dateColumns: {'updated_at'},
  modifiedExpression: 'updated_at',
  localWhere:
      "key IN ('theme', 'app_language', 'app_language_explicit', 'theme_time_of_day_enabled', "
      "'notification_preferences', 'onboarding_completed', "
      "'permission_education_seen', "
      "'home_location')",
);

const syncEntitySpecs = <SyncEntitySpec>[
  SyncEntitySpec(
    entity: 'area',
    localTable: 'areas',
    remoteTable: 'areas',
    keyColumns: ['id'],
    localColumns: [
      'id',
      'name',
      'kind',
      'sort_order',
      'created_at',
      'updated_at',
      'archived_at',
    ],
    updatableLocalColumns: {'name', 'kind', 'sort_order', 'archived_at'},
    dateColumns: {'created_at', 'updated_at', 'archived_at'},
    modifiedExpression: 'updated_at',
  ),
  SyncEntitySpec(
    entity: 'room',
    localTable: 'rooms',
    remoteTable: 'rooms',
    keyColumns: ['id'],
    localColumns: [
      'id',
      'area_id',
      'name',
      'room_type',
      'notes',
      'sort_order',
      'created_at',
      'updated_at',
      'archived_at',
    ],
    updatableLocalColumns: {
      'area_id',
      'name',
      'room_type',
      'notes',
      'sort_order',
      'archived_at',
    },
    dateColumns: {'created_at', 'updated_at', 'archived_at'},
    modifiedExpression: 'updated_at',
  ),
  SyncEntitySpec(
    entity: 'asset',
    localTable: 'assets',
    remoteTable: 'assets',
    keyColumns: ['id'],
    localColumns: [
      'id',
      'name',
      'asset_type',
      'room_id',
      'placement',
      'notes',
      'purchase_date',
      'created_at',
      'updated_at',
      'archived_at',
    ],
    updatableLocalColumns: {
      'name',
      'room_id',
      'placement',
      'notes',
      'purchase_date',
      'archived_at',
    },
    dateColumns: {'purchase_date', 'created_at', 'updated_at', 'archived_at'},
    modifiedExpression: 'updated_at',
  ),
  SyncEntitySpec(
    entity: 'device_detail',
    localTable: 'device_details',
    remoteTable: 'device_details',
    keyColumns: ['asset_id'],
    localColumns: [
      'asset_id',
      'brand',
      'model',
      'serial_number',
      'power_source',
      'warranty_until',
      'manual_url',
      'consumable',
    ],
    updatableLocalColumns: {
      'brand',
      'model',
      'serial_number',
      'power_source',
      'warranty_until',
      'manual_url',
      'consumable',
    },
    dateColumns: {'warranty_until'},
    modifiedExpression:
        '(SELECT updated_at FROM assets WHERE assets.id = asset_id)',
  ),
  SyncEntitySpec(
    entity: 'pet_detail',
    localTable: 'pet_details',
    remoteTable: 'pet_details',
    keyColumns: ['asset_id'],
    localColumns: [
      'asset_id',
      'species',
      'breed',
      'birth_date',
      'microchip_id',
      'vet_name',
      'vet_phone',
      'feeding_notes',
      'medical_notes',
    ],
    updatableLocalColumns: {
      'species',
      'breed',
      'birth_date',
      'microchip_id',
      'vet_name',
      'vet_phone',
      'feeding_notes',
      'medical_notes',
    },
    dateColumns: {'birth_date'},
    modifiedExpression:
        '(SELECT updated_at FROM assets WHERE assets.id = asset_id)',
  ),
  SyncEntitySpec(
    entity: 'plant_detail',
    localTable: 'plant_details',
    remoteTable: 'plant_details',
    keyColumns: ['asset_id'],
    localColumns: [
      'asset_id',
      'species',
      'sunlight',
      'watering_interval_days',
      'pot_size',
      'last_repotted_at',
      'toxicity_notes',
    ],
    updatableLocalColumns: {
      'species',
      'sunlight',
      'watering_interval_days',
      'pot_size',
      'last_repotted_at',
      'toxicity_notes',
    },
    dateColumns: {'last_repotted_at'},
    modifiedExpression:
        '(SELECT updated_at FROM assets WHERE assets.id = asset_id)',
  ),
  SyncEntitySpec(
    entity: 'safety_detail',
    localTable: 'safety_details',
    remoteTable: 'safety_details',
    keyColumns: ['asset_id'],
    localColumns: [
      'asset_id',
      'safety_type',
      'installed_at',
      'expires_at',
      'battery_type',
      'test_interval_days',
    ],
    updatableLocalColumns: {
      'safety_type',
      'installed_at',
      'expires_at',
      'battery_type',
      'test_interval_days',
    },
    dateColumns: {'installed_at', 'expires_at'},
    modifiedExpression:
        '(SELECT updated_at FROM assets WHERE assets.id = asset_id)',
  ),
  SyncEntitySpec(
    entity: 'tag',
    localTable: 'tags',
    remoteTable: 'tags',
    keyColumns: ['id'],
    localColumns: ['id', 'name', 'created_at'],
    updatableLocalColumns: {'name'},
    dateColumns: {'created_at'},
    modifiedExpression: 'created_at',
  ),
  SyncEntitySpec(
    entity: 'asset_tag',
    localTable: 'asset_tags',
    remoteTable: 'asset_tags',
    keyColumns: ['asset_id', 'tag_id'],
    localColumns: ['asset_id', 'tag_id'],
    updatableLocalColumns: {},
    dateColumns: {},
    modifiedExpression:
        '(SELECT updated_at FROM assets WHERE assets.id = asset_id)',
  ),
  SyncEntitySpec(
    entity: 'asset_photo',
    localTable: 'asset_photos',
    remoteTable: 'asset_photos',
    keyColumns: ['id'],
    localColumns: [
      'id',
      'asset_id',
      'relative_path',
      'caption',
      'is_primary',
      'cloud_object_path',
      'created_at',
    ],
    updatableLocalColumns: {},
    dateColumns: {'created_at'},
    boolColumns: {'is_primary'},
    modifiedExpression: 'created_at',
    remoteRenames: {'cloud_object_path': 'object_path'},
    localOnlyColumns: {'relative_path'},
  ),
  SyncEntitySpec(
    entity: 'maintenance_plan',
    localTable: 'maintenance_plans',
    remoteTable: 'maintenance_plans',
    keyColumns: ['id'],
    localColumns: [
      'id',
      'asset_id',
      'title',
      'instructions',
      'recurrence_interval',
      'recurrence_unit',
      'priority',
      'next_due_date',
      'reminder_days_before',
      'is_enabled',
      'created_at',
      'updated_at',
      'archived_at',
    ],
    updatableLocalColumns: {
      'title',
      'instructions',
      'recurrence_interval',
      'recurrence_unit',
      'priority',
      'next_due_date',
      'reminder_days_before',
      'is_enabled',
      'archived_at',
    },
    dateColumns: {'next_due_date', 'created_at', 'updated_at', 'archived_at'},
    boolColumns: {'is_enabled'},
    modifiedExpression: 'updated_at',
    remoteRenames: {},
  ),
  SyncEntitySpec(
    entity: 'maintenance_plan_metadata',
    localTable: 'maintenance_plan_metadata',
    remoteTable: 'maintenance_plan_metadata',
    keyColumns: ['plan_id'],
    localColumns: [
      'plan_id',
      'task_type',
      'location_label',
      'estimated_duration_minutes',
      'required_materials_json',
      'reminder_recommendation',
      'sort_order',
      'created_at',
      'updated_at',
    ],
    updatableLocalColumns: {
      'task_type',
      'location_label',
      'estimated_duration_minutes',
      'required_materials_json',
      'reminder_recommendation',
      'sort_order',
    },
    dateColumns: {'created_at', 'updated_at'},
    modifiedExpression: 'updated_at',
  ),
  SyncEntitySpec(
    entity: 'maintenance_record',
    localTable: 'maintenance_records',
    remoteTable: 'maintenance_records',
    keyColumns: ['id'],
    localColumns: ['id', 'plan_id', 'due_date', 'completed_at', 'notes'],
    updatableLocalColumns: {},
    dateColumns: {'due_date', 'completed_at'},
    modifiedExpression: 'completed_at',
  ),
  SyncEntitySpec(
    entity: 'notification_inbox',
    localTable: 'notification_inbox',
    remoteTable: 'notification_inbox',
    keyColumns: ['id'],
    localColumns: [
      'id',
      'title',
      'body',
      'kind',
      'route',
      'plan_id',
      'message_code',
      'message_args',
      'dedupe_key',
      'read_at',
      'created_at',
      'updated_at',
    ],
    updatableLocalColumns: {'read_at'},
    dateColumns: {'read_at', 'created_at', 'updated_at'},
    jsonColumns: {'message_args'},
    modifiedExpression: 'updated_at',
  ),
  userSettingSyncSpec,
  SyncEntitySpec(
    entity: 'streak',
    localTable: 'streaks',
    remoteTable: 'streaks',
    keyColumns: ['id'],
    localColumns: [
      'id',
      'current_streak',
      'best_streak',
      'last_completed_date',
      'updated_at',
    ],
    updatableLocalColumns: {
      'current_streak',
      'best_streak',
      'last_completed_date',
    },
    dateColumns: {'last_completed_date', 'updated_at'},
    modifiedExpression: 'updated_at',
    remoteRenames: {
      'best_streak': 'longest_streak',
      'last_completed_date': 'last_completion_date',
    },
  ),
];

const profileSyncSpec = SyncEntitySpec(
  entity: 'profile',
  localTable: 'settings',
  remoteTable: 'profiles',
  keyColumns: [],
  localColumns: ['nickname'],
  updatableLocalColumns: {'nickname'},
  dateColumns: {},
  modifiedExpression: "(SELECT updated_at FROM settings WHERE key = 'profile')",
);

final syncSpecByEntity = <String, SyncEntitySpec>{
  for (final spec in syncEntitySpecs) spec.entity: spec,
  profileSyncSpec.entity: profileSyncSpec,
};

class LocalSyncMutation {
  const LocalSyncMutation({
    required this.entity,
    required this.recordKey,
    required this.operation,
    required this.changedAt,
    required this.attempts,
    this.generation = 1,
    this.payloadJson,
    this.userId,
    this.createdAt,
    this.state = SyncMutationState.pending,
    this.lastErrorCode,
    this.lastError,
    this.nextRetryAt,
  });

  final String entity;
  final String recordKey;
  final String operation;
  final DateTime changedAt;
  final int attempts;
  final int generation;
  final String? payloadJson;
  final String? userId;
  final DateTime? createdAt;
  final SyncMutationState state;
  final String? lastErrorCode;
  final String? lastError;
  final DateTime? nextRetryAt;

  String get operationId => recordKey;
}

class SyncRecord {
  const SyncRecord({
    required this.spec,
    required this.recordKey,
    required this.values,
    required this.clientModifiedAt,
    this.originDeviceId,
    this.revision,
    this.serverUpdatedAt,
    this.deletedAt,
  });

  final SyncEntitySpec spec;
  final String recordKey;
  final Map<String, dynamic> values;
  final DateTime clientModifiedAt;
  final String? originDeviceId;
  final int? revision;
  final DateTime? serverUpdatedAt;
  final DateTime? deletedAt;

  bool get isDeleted => deletedAt != null;

  Map<String, dynamic> toRemoteCreatePayload(
    String userId, {
    String? deviceId,
  }) {
    final payload = {
      'user_id': userId,
      if (spec.scope == SyncScope.deviceScoped) 'device_id': deviceId,
      for (final localColumn in spec.localColumns)
        if (!spec.localOnlyColumns.contains(localColumn) &&
            values.containsKey(localColumn))
          spec.remoteColumnFor(localColumn): values[localColumn],
    };
    payload.putIfAbsent(
      'updated_at',
      () => clientModifiedAt.toUtc().toIso8601String(),
    );
    return payload;
  }

  Map<String, dynamic> toRemoteUpdatePayload() {
    spec.validateUpdateContract();
    if (!spec.supportsGenericUpdate) {
      throw StateError(
        '${spec.entity} does not support generic optimistic updates.',
      );
    }
    return {
      for (final localColumn in spec.updatableLocalColumns)
        if (values.containsKey(localColumn))
          spec.remoteColumnFor(localColumn): values[localColumn],
    };
  }

  factory SyncRecord.fromRemote(SyncEntitySpec spec, Map<String, dynamic> row) {
    final values = <String, dynamic>{};
    for (final remoteColumn in spec.remoteDataColumns) {
      final localCol = spec.localColumnFor(remoteColumn);
      var val = row[remoteColumn];
      if (val == null) {
        if (localCol == 'sort_order' || localCol == 'reminder_days_before') {
          val = 0;
        } else if (localCol == 'is_enabled') {
          val = true;
        } else if (localCol == 'is_primary') {
          val = false;
        } else if (localCol == 'required_materials_json') {
          val = '[]';
        }
      }
      values[localCol] = val;
    }
    final updatedAtText =
        row['updated_at'] as String? ??
        row['client_modified_at'] as String? ??
        row['created_at'] as String? ??
        DateTime.now().toUtc().toIso8601String();
    final updatedAt = DateTime.parse(updatedAtText).toUtc();
    final revision = row['revision'] is num
        ? (row['revision'] as num).toInt()
        : 1;
    return SyncRecord(
      spec: spec,
      recordKey: _recordKey(
        spec,
        values,
        fallbackUserId: row['user_id'] as String?,
      ),
      values: values,
      clientModifiedAt: updatedAt,
      originDeviceId: row['origin_device_id'] as String?,
      revision: revision,
      serverUpdatedAt: row['server_updated_at'] == null
          ? updatedAt
          : DateTime.parse(row['server_updated_at'] as String).toUtc(),
      deletedAt: row['deleted_at'] == null
          ? null
          : DateTime.parse(row['deleted_at'] as String).toUtc(),
    );
  }
}

String _recordKey(
  SyncEntitySpec spec,
  Map<String, dynamic> values, {
  String? fallbackUserId,
}) {
  if (spec.keyColumns.isEmpty) {
    return spec.entity;
  }
  return spec.keyColumns.map((column) => values[column].toString()).join('|');
}
