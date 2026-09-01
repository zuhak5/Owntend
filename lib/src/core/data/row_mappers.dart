part of 'repositories.dart';

domain.Area _areaFromRow(AreaRow row) => domain.Area(
  id: row.id,
  name: row.name,
  kind: _areaKind(row.kind),
  sortOrder: row.sortOrder,
  createdAt: row.createdAt,
  updatedAt: row.updatedAt,
  archivedAt: row.archivedAt,
);

domain.Room _roomFromRow(RoomRow row) => domain.Room(
  id: row.id,
  areaId: row.areaId,
  name: row.name,
  roomType: _roomType(row.roomType),
  notes: row.notes,
  sortOrder: row.sortOrder,
  createdAt: row.createdAt,
  updatedAt: row.updatedAt,
  archivedAt: row.archivedAt,
);

domain.Asset _assetFromRow(
  AssetRow row, {
  domain.DeviceDetails? deviceDetails,
  domain.PetDetails? petDetails,
  domain.PlantDetails? plantDetails,
  domain.SafetyDetails? safetyDetails,
}) => domain.Asset(
  id: row.id,
  name: row.name,
  assetType: _assetType(row.assetType),
  roomId: row.roomId,
  placement: row.placement,
  notes: row.notes,
  purchaseDate: row.purchaseDate,
  createdAt: row.createdAt,
  updatedAt: row.updatedAt,
  archivedAt: row.archivedAt,
  deviceDetails: deviceDetails,
  petDetails: petDetails,
  plantDetails: plantDetails,
  safetyDetails: safetyDetails,
);

domain.DeviceDetails _deviceDetailsFromRow(DeviceDetailRow row) =>
    domain.DeviceDetails(
      brand: row.brand,
      model: row.model,
      serialNumber: row.serialNumber,
      powerSource: row.powerSource == null
          ? null
          : _powerSource(row.powerSource!),
      warrantyUntil: row.warrantyUntil,
      manualUrl: row.manualUrl,
      consumable: row.consumable,
    );

domain.PetDetails _petDetailsFromRow(PetDetailRow row) => domain.PetDetails(
  species: row.species,
  breed: row.breed,
  birthDate: row.birthDate,
  microchipId: row.microchipId,
  vetName: row.vetName,
  vetPhone: row.vetPhone,
  feedingNotes: row.feedingNotes,
  medicalNotes: row.medicalNotes,
);

domain.PlantDetails _plantDetailsFromRow(PlantDetailRow row) =>
    domain.PlantDetails(
      species: row.species,
      sunlight: row.sunlight == null ? null : _sunlight(row.sunlight!),
      wateringIntervalDays: row.wateringIntervalDays,
      potSize: row.potSize,
      lastRepottedAt: row.lastRepottedAt,
      toxicityNotes: row.toxicityNotes,
    );

domain.SafetyDetails _safetyDetailsFromRow(SafetyDetailRow row) =>
    domain.SafetyDetails(
      safetyType: row.safetyType,
      installedAt: row.installedAt,
      expiresAt: row.expiresAt,
      batteryType: row.batteryType,
      testIntervalDays: row.testIntervalDays,
    );

domain.Tag _tagFromRow(TagRow row) =>
    domain.Tag(id: row.id, name: row.name, createdAt: row.createdAt);

domain.AssetPhoto _photoFromRow(AssetPhotoRow row) => domain.AssetPhoto(
  id: row.id,
  assetId: row.assetId,
  relativePath: row.relativePath,
  isPrimary: row.isPrimary,
  caption: row.caption,
  createdAt: row.createdAt,
);

domain.InboxNotification _inboxFromRow(InboxNotificationRow row) =>
    domain.InboxNotification(
      id: row.id,
      title: row.title,
      body: row.body,
      kind: row.kind,
      route: row.route,
      planId: row.planId,
      messageCode: domain.NotificationMessageCode.fromWireValue(
        row.messageCode,
      )!,
      messageArgs: _notificationMessageArgs(row.messageArgs),
      readAt: row.readAt,
      createdAt: row.createdAt,
    );

Map<String, dynamic> _notificationMessageArgs(String value) {
  try {
    final decoded = jsonDecode(value);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) {
      return decoded.map((key, item) => MapEntry(key.toString(), item));
    }
  } on FormatException {
    // Older or damaged local records degrade to an empty argument object.
  }
  return const {};
}

domain.MaintenancePlan _planFromRow(
  MaintenancePlanRow row, [
  MaintenancePlanMetadataRow? metadata,
]) => domain.MaintenancePlan(
  id: row.id,
  currentOccurrenceId: row.currentOccurrenceId,
  assetId: row.assetId,
  title: row.title,
  instructions: row.instructions,
  recurrence: domain.RecurrenceRule(
    interval: row.recurrenceInterval,
    unit: _recurrenceUnit(row.recurrenceUnit),
  ),
  priority: _priority(row.priority),
  nextDueDate: row.nextDueDate,
  reminderDaysBefore: row.reminderDaysBefore,
  isEnabled: row.isEnabled,
  metadata: metadata == null
      ? null
      : domain.TaskMetadata(
          taskType: metadata.taskType,
          locationLabel: metadata.locationLabel,
          estimatedDurationMinutes: metadata.estimatedDurationMinutes,
          requiredMaterials: _stringListFromJson(
            metadata.requiredMaterialsJson,
          ),
          reminderRecommendation: metadata.reminderRecommendation,
          sortOrder: metadata.sortOrder,
        ),
  createdAt: row.createdAt,
  updatedAt: row.updatedAt,
  archivedAt: row.archivedAt,
);

List<String> _stringListFromJson(String value) {
  try {
    final decoded = jsonDecode(value);
    if (decoded is List) {
      return decoded
          .map((item) => item.toString())
          .where((item) {
            return item.trim().isNotEmpty;
          })
          .toList(growable: false);
    }
  } on Object {
    return const [];
  }
  return const [];
}

domain.MaintenanceRecord _recordFromRow(MaintenanceRecordRow row) =>
    domain.MaintenanceRecord(
      id: row.id,
      planId: row.planId,
      occurrenceId: row.occurrenceId,
      dueDate: row.dueDate,
      completedAt: row.completedAt,
      acceptedAt: row.acceptedAt,
      timeZoneId: row.timeZoneId,
      notes: row.notes,
    );

domain.StreakState _streakFromRow(StreakRow row) => domain.StreakState(
  currentStreak: row.currentStreak,
  bestStreak: row.bestStreak,
  lastCompletedDate: row.lastCompletedDate,
  updatedAt: row.updatedAt,
);

domain.TaskStatus _statusFor(DateTime dueDate, DateTime now) =>
    activeTaskStatusForDueDate(dueDate, now);

domain.AreaKind _areaKind(String value) {
  return domain.AreaKind.values
          .where((kind) => kind.name == value)
          .firstOrNull ??
      domain.AreaKind.indoor;
}

domain.RoomType _roomType(String value) {
  return domain.RoomType.values
          .where((type) => type.name == value)
          .firstOrNull ??
      domain.RoomType.other;
}

domain.AssetType _assetType(String value) {
  return domain.AssetType.values
          .where((type) => type.name == value)
          .firstOrNull ??
      domain.AssetType.general;
}

domain.PowerSource _powerSource(String value) {
  return domain.PowerSource.values
          .where((source) => source.name == value)
          .firstOrNull ??
      domain.PowerSource.other;
}

domain.Sunlight _sunlight(String value) {
  return domain.Sunlight.values
          .where((sunlight) => sunlight.name == value)
          .firstOrNull ??
      domain.Sunlight.medium;
}

domain.RecurrenceUnit _recurrenceUnit(String value) {
  return domain.RecurrenceUnit.values
          .where((unit) => unit.name == value)
          .firstOrNull ??
      domain.RecurrenceUnit.months;
}

domain.PriorityLevel _priority(String value) {
  return domain.PriorityLevel.values
          .where((priority) => priority.name == value)
          .firstOrNull ??
      domain.PriorityLevel.medium;
}

domain.ThemePreference _themePreference(String? value) {
  return domain.ThemePreference.values
          .where((preference) => preference.name == value)
          .firstOrNull ??
      domain.ThemePreference.system;
}

domain.AppLanguage _appLanguage(String? value) {
  return domain.AppLanguage.values
          .where((language) => language.name == value)
          .firstOrNull ??
      domain.AppLanguage.en;
}

domain.AppLocalePreference _appLocalePreference(List<SettingRow> rows) {
  final languageRow = rows
      .where((row) => row.key == 'app_language')
      .firstOrNull;
  final explicitRow = rows
      .where((row) => row.key == 'app_language_explicit')
      .firstOrNull;
  final updatedAt =
      [
        if (languageRow != null) languageRow.updatedAt,
        if (explicitRow != null) explicitRow.updatedAt,
      ].fold<DateTime>(
        DateTime.fromMillisecondsSinceEpoch(0),
        (latest, value) => value.isAfter(latest) ? value : latest,
      );
  return domain.AppLocalePreference(
    language: _appLanguage(languageRow?.value),
    isExplicit: _boolSetting(explicitRow?.value),
    updatedAt: updatedAt,
  );
}

bool _boolSetting(String? value) => value == 'true';

domain.NotificationPreferences _notificationPreferencesFromValue(
  String? value,
) {
  const defaults = domain.NotificationPreferences();
  if (value == null || value.trim().isEmpty) {
    return defaults;
  }
  try {
    final decoded = jsonDecode(value) as Map<String, dynamic>;
    return _normalizeNotificationPreferences(
      defaults.copyWith(
        enabled: _jsonBool(decoded, 'enabled'),
        localReminders: _jsonBool(decoded, 'localReminders'),
        inAppInbox: _jsonBool(decoded, 'inAppInbox'),
        weatherAlerts: _jsonBool(decoded, 'weatherAlerts'),
        quietHoursEnabled: _jsonBool(decoded, 'quietHoursEnabled'),
        quietHoursStartMinutes: _jsonInt(decoded, 'quietHoursStartMinutes'),
        quietHoursEndMinutes: _jsonInt(decoded, 'quietHoursEndMinutes'),
        criticalBypassQuietHours: _jsonBool(
          decoded,
          'criticalBypassQuietHours',
        ),
        privacyMode: _jsonBool(decoded, 'privacyMode'),
        dailyDigest: _jsonBool(decoded, 'dailyDigest'),
        digestHour: _jsonInt(decoded, 'digestHour'),
        reminderHour: _jsonInt(decoded, 'reminderHour'),
        maxRemindersPerDay: _jsonInt(decoded, 'maxRemindersPerDay'),
        defaultSnoozeMinutes: _jsonInt(decoded, 'defaultSnoozeMinutes'),
      ),
    );
  } catch (_) {
    return defaults;
  }
}

domain.NotificationPreferences _normalizeNotificationPreferences(
  domain.NotificationPreferences preferences,
) {
  return preferences.copyWith(
    quietHoursStartMinutes: _clampInt(
      preferences.quietHoursStartMinutes,
      0,
      1439,
    ),
    quietHoursEndMinutes: _clampInt(preferences.quietHoursEndMinutes, 0, 1439),
    digestHour: _clampInt(preferences.digestHour, 0, 23),
    reminderHour: _clampInt(preferences.reminderHour, 0, 23),
    maxRemindersPerDay: _clampInt(preferences.maxRemindersPerDay, 1, 24),
    defaultSnoozeMinutes: _clampInt(
      preferences.defaultSnoozeMinutes,
      5,
      60 * 24 * 7,
    ),
  );
}

Map<String, Object> _notificationPreferencesToJson(
  domain.NotificationPreferences preferences,
) {
  final normalized = _normalizeNotificationPreferences(preferences);
  return {
    'enabled': normalized.enabled,
    'localReminders': normalized.localReminders,
    'inAppInbox': normalized.inAppInbox,
    'weatherAlerts': normalized.weatherAlerts,
    'quietHoursEnabled': normalized.quietHoursEnabled,
    'quietHoursStartMinutes': normalized.quietHoursStartMinutes,
    'quietHoursEndMinutes': normalized.quietHoursEndMinutes,
    'criticalBypassQuietHours': normalized.criticalBypassQuietHours,
    'privacyMode': normalized.privacyMode,
    'dailyDigest': normalized.dailyDigest,
    'digestHour': normalized.digestHour,
    'reminderHour': normalized.reminderHour,
    'maxRemindersPerDay': normalized.maxRemindersPerDay,
    'defaultSnoozeMinutes': normalized.defaultSnoozeMinutes,
  };
}

bool? _jsonBool(Map<String, dynamic> decoded, String key) {
  final value = decoded[key];
  return value is bool ? value : null;
}

int? _jsonInt(Map<String, dynamic> decoded, String key) {
  final value = decoded[key];
  return value is num ? value.round() : null;
}

int _clampInt(int value, int min, int max) => value.clamp(min, max).toInt();

Duration _notificationDedupeWindow(String kind) {
  return switch (kind) {
    'weather' => const Duration(hours: 12),
    'task' => const Duration(hours: 20),
    'digest' => const Duration(hours: 20),
    _ => const Duration(hours: 2),
  };
}

bool _notificationDedupeIncludesBody(String kind) {
  return switch (kind) {
    'weather' || 'task' || 'digest' => false,
    _ => true,
  };
}

String _notificationDedupeKey({
  required String kind,
  required String title,
  required String body,
  required String? route,
  required String? planId,
  required DateTime createdAt,
}) {
  final window = _notificationDedupeWindow(kind);
  final bucket =
      createdAt.toUtc().millisecondsSinceEpoch ~/ window.inMilliseconds;
  final canonical = jsonEncode([
    kind,
    title.trim(),
    _notificationDedupeIncludesBody(kind) ? body.trim() : '',
    route ?? '',
    planId ?? '',
    bucket,
  ]);
  return sha256.convert(utf8.encode(canonical)).toString();
}

String? _blankToNull(String? value) {
  if (value == null) {
    return null;
  }
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

extension<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    if (iterator.moveNext()) {
      return iterator.current;
    }
    return null;
  }
}
