part of 'repositories.dart';

class DriftSettingsRepository implements SettingsRepository {
  DriftSettingsRepository(this.db);

  final AppDatabase db;

  @override
  Future<domain.AppLanguage> appLanguage() async {
    final row = await _setting('app_language');
    return _appLanguage(row?.value);
  }

  @override
  Future<void> setAppLanguage(domain.AppLanguage language) async {
    await setAppLocalePreference(language);
  }

  @override
  Stream<domain.AppLanguage> watchAppLanguage() {
    final query = db.select(db.settings)
      ..where((setting) => setting.key.equals('app_language'));
    return query
        .watchSingleOrNull()
        .map((row) => _appLanguage(row?.value))
        .distinct();
  }

  @override
  Future<domain.AppLocalePreference> appLocalePreference() async {
    final rows =
        await (db.select(db.settings)..where(
              (setting) =>
                  setting.key.isIn(['app_language', 'app_language_explicit']),
            ))
            .get();
    return _appLocalePreference(rows);
  }

  @override
  Future<void> setAppLocalePreference(domain.AppLanguage language) async {
    final now = DateTime.now();
    await db.transaction(() async {
      await _setSettingAt('app_language', language.name, now);
      await _setSettingAt('app_language_explicit', 'true', now);
    });
  }

  @override
  Stream<domain.AppLocalePreference> watchAppLocalePreference() {
    final query = db.select(db.settings)
      ..where(
        (setting) =>
            setting.key.isIn(['app_language', 'app_language_explicit']),
      );
    return query.watch().map(_appLocalePreference).distinct();
  }

  @override
  Future<domain.ThemePreference> themePreference() async {
    final row = await _setting('theme');
    return _themePreference(row?.value);
  }

  @override
  Future<void> setThemePreference(domain.ThemePreference preference) async {
    await _setSetting('theme', preference.name);
  }

  @override
  Stream<domain.ThemePreference> watchThemePreference() {
    final query = db.select(db.settings)
      ..where((setting) => setting.key.equals('theme'));
    return query
        .watchSingleOrNull()
        .map((row) => _themePreference(row?.value))
        .distinct();
  }

  @override
  Future<bool> timeOfDayThemeEnabled() async {
    final row = await _setting('theme_time_of_day_enabled');
    return _boolSetting(row?.value);
  }

  @override
  Future<void> setTimeOfDayThemeEnabled(bool enabled) {
    return _setSetting('theme_time_of_day_enabled', enabled.toString());
  }

  @override
  Stream<bool> watchTimeOfDayThemeEnabled() {
    final query = db.select(db.settings)
      ..where((setting) => setting.key.equals('theme_time_of_day_enabled'));
    return query
        .watchSingleOrNull()
        .map((row) => _boolSetting(row?.value))
        .distinct();
  }

  @override
  Future<bool> onboardingCompleted() async {
    final row = await _setting('onboarding_completed');
    return _boolSetting(row?.value);
  }

  @override
  Future<void> setOnboardingCompleted(bool completed) {
    return _setSetting('onboarding_completed', completed.toString());
  }

  @override
  Stream<bool> watchOnboardingCompleted() {
    final query = db.select(db.settings)
      ..where((setting) => setting.key.equals('onboarding_completed'));
    return query.watchSingleOrNull().map((row) => _boolSetting(row?.value));
  }

  @override
  Future<bool> permissionEducationSeen() async {
    final row = await _setting('permission_education_seen_v2');
    return _boolSetting(row?.value);
  }

  @override
  Future<void> setPermissionEducationSeen(bool seen) {
    return _setSetting('permission_education_seen_v2', seen.toString());
  }

  @override
  Stream<bool> watchPermissionEducationSeen() {
    final query = db.select(db.settings)
      ..where((setting) => setting.key.equals('permission_education_seen_v2'));
    return query.watchSingleOrNull().map((row) => _boolSetting(row?.value));
  }

  @override
  Future<domain.AppProfile> profile() async {
    return _profileFromValue((await _setting('profile'))?.value);
  }

  @override
  Stream<domain.AppProfile> watchProfile() {
    final query = db.select(db.settings)
      ..where((setting) => setting.key.equals('profile'));
    return query
        .watchSingleOrNull()
        .map((row) => _profileFromValue(row?.value))
        .distinct(
          (previous, next) =>
              previous.nickname == next.nickname &&
              previous.displayName == next.displayName &&
              previous.avatarPath == next.avatarPath,
        );
  }

  @override
  Future<void> setProfile({String? nickname}) async {
    final current = _profileFromValue((await _setting('profile'))?.value);
    final resolvedNickname = _blankToNull(nickname);
    final value = <String, Object?>{'nickname': resolvedNickname};
    if (current.displayName.trim().isNotEmpty &&
        current.displayName != 'Owntend') {
      value['displayName'] = current.displayName;
    }
    if (current.avatarPath != null) {
      value['avatarPath'] = current.avatarPath;
    }
    await _setSetting('profile', jsonEncode(value));
  }

  @override
  Future<domain.HomeLocation?> homeLocation() async {
    return _locationFromValue((await _setting('home_location'))?.value);
  }

  @override
  Stream<domain.HomeLocation?> watchHomeLocation() {
    final query = db.select(db.settings)
      ..where((setting) => setting.key.equals('home_location'));
    return query
        .watchSingleOrNull()
        .map((row) => _locationFromValue(row?.value))
        .distinct(
          (previous, next) =>
              previous?.label == next?.label &&
              previous?.latitude == next?.latitude &&
              previous?.longitude == next?.longitude &&
              previous?.timezone == next?.timezone &&
              previous?.source == next?.source,
        );
  }

  @override
  Future<void> setHomeLocation(domain.HomeLocation? location) async {
    if (location == null) {
      await (db.delete(
        db.settings,
      )..where((setting) => setting.key.equals('home_location'))).go();
      await (db.delete(
        db.settings,
      )..where((setting) => setting.key.equals('weather_cache'))).go();
      return;
    }
    await _setSetting(
      'home_location',
      jsonEncode({
        'label': location.label,
        'latitude': location.latitude,
        'longitude': location.longitude,
        'timezone': location.timezone,
        'source': location.source,
      }),
    );
  }

  @override
  Future<domain.NotificationPreferences> notificationPreferences() async {
    final row = await _setting('notification_preferences');
    final legacyRow = await _setting('notifications_enabled');
    return _notificationPreferencesFromValue(
      row?.value,
      legacyEnabled: legacyRow == null ? null : _boolSetting(legacyRow.value),
    );
  }

  @override
  Stream<domain.NotificationPreferences> watchNotificationPreferences() {
    final query = db.select(db.settings)
      ..where(
        (setting) => setting.key.isIn([
          'notification_preferences',
          'notifications_enabled',
        ]),
      );
    return query.watch().map((rows) {
      final byKey = {for (final row in rows) row.key: row.value};
      final legacyValue = byKey['notifications_enabled'];
      return _notificationPreferencesFromValue(
        byKey['notification_preferences'],
        legacyEnabled: legacyValue == null ? null : _boolSetting(legacyValue),
      );
    });
  }

  @override
  Future<void> setNotificationPreferences(
    domain.NotificationPreferences preferences,
  ) async {
    final normalized = _normalizeNotificationPreferences(preferences);
    await _setSetting(
      'notification_preferences',
      jsonEncode(_notificationPreferencesToJson(normalized)),
    );
    await _setSetting('notifications_enabled', normalized.enabled.toString());
  }

  Future<SettingRow?> _setting(String key) {
    return (db.select(
      db.settings,
    )..where((setting) => setting.key.equals(key))).getSingleOrNull();
  }

  Future<void> _setSetting(String key, String value) async {
    await _setSettingAt(key, value, DateTime.now());
  }

  Future<void> _setSettingAt(
    String key,
    String value,
    DateTime updatedAt,
  ) async {
    await db
        .into(db.settings)
        .insertOnConflictUpdate(
          SettingsCompanion.insert(
            key: key,
            value: value,
            updatedAt: Value(updatedAt),
          ),
        );
  }

  domain.AppProfile _profileFromValue(String? value) {
    if (value == null || value.trim().isEmpty) {
      return const domain.AppProfile();
    }
    try {
      final decoded = jsonDecode(value) as Map<String, dynamic>;
      return domain.AppProfile(
        nickname: _blankToNull(decoded['nickname'] as String?),
        displayName:
            _blankToNull(decoded['displayName'] as String?) ?? 'Owntend',
        avatarPath: _blankToNull(decoded['avatarPath'] as String?),
      );
    } catch (_) {
      return const domain.AppProfile();
    }
  }

  domain.HomeLocation? _locationFromValue(String? value) {
    if (value == null || value.trim().isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(value) as Map<String, dynamic>;
      final latitude = (decoded['latitude'] as num?)?.toDouble();
      final longitude = (decoded['longitude'] as num?)?.toDouble();
      final label = _blankToNull(decoded['label'] as String?);
      if (latitude == null || longitude == null || label == null) {
        return null;
      }
      return domain.HomeLocation(
        label: label,
        latitude: latitude,
        longitude: longitude,
        timezone: _blankToNull(decoded['timezone'] as String?),
        source: _blankToNull(decoded['source'] as String?) ?? 'manual',
      );
    } catch (_) {
      return null;
    }
  }
}
