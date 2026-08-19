import 'models.dart';

class MaintenancePlanValidationException implements Exception {
  const MaintenancePlanValidationException(this.message, {required this.code});

  final String message;
  final String code;

  @override
  String toString() => message;
}

abstract interface class AssetRepository {
  Stream<List<Area>> watchAreas();
  Future<List<Area>> listAreas();
  Future<String> saveArea({
    String? id,
    required String name,
    required AreaKind kind,
    int? sortOrder,
  });
  Future<void> archiveArea(String id);
  Future<void> deleteArea(String id);
  Stream<List<Area>> watchArchivedAreas();
  Future<List<Area>> listArchivedAreas();
  Future<void> trashArea(String id);
  Future<void> restoreArea(String id);
  Stream<List<Room>> watchRooms({String? areaId});
  Future<List<Room>> listRooms({String? areaId});
  Future<String> saveRoom({
    String? id,
    required String areaId,
    required String name,
    RoomType roomType = RoomType.other,
    String? notes,
    int? sortOrder,
  });
  Future<void> archiveRoom(String id);
  Future<void> deleteRoom(String id);
  Stream<List<Room>> watchArchivedRooms();
  Future<List<Room>> listArchivedRooms();
  Future<void> trashRoom(String id);
  Future<void> restoreRoom(String id);
  Stream<List<Asset>> watchAssets({String? roomId});
  Future<List<Asset>> listAssets({String? roomId});
  Stream<Asset?> watchAsset(String id);
  Future<Asset?> getAsset(String id);
  Future<String> saveAsset({
    String? id,
    required String name,
    AssetType assetType = AssetType.general,
    required String roomId,
    String? placement,
    String? notes,
    DateTime? purchaseDate,
    List<String> tagNames,
    DeviceDetails? deviceDetails,
    PetDetails? petDetails,
    PlantDetails? plantDetails,
    SafetyDetails? safetyDetails,
  });
  Future<void> moveAsset({required String assetId, required String roomId});
  Future<String> copyAsset({
    required String assetId,
    required String roomId,
    bool includeTasks,
    bool includePhotos,
    String? newAssetId,
    Map<String, String> taskIdBySource,
  });
  Future<void> archiveAsset(String id);
  Future<void> deleteAsset(String id);
  Stream<List<Asset>> watchArchivedAssets();
  Future<List<Asset>> listArchivedAssets();
  Future<void> trashAsset(String id);
  Future<void> restoreAsset(String id);
  Future<void> emptyTrash();
  Future<AssetPhoto> addPhoto(
    String assetId,
    String sourcePath, {
    String? caption,
    bool makePrimary = false,
  });
  Future<void> setPrimaryPhoto(String assetId, String photoId);
  Future<void> deletePhoto(String photoId);
  Stream<List<AssetPhoto>> watchPhotosForAsset(String assetId);
  Future<List<AssetPhoto>> listPhotosForAsset(String assetId);
  Stream<List<Tag>> watchTagsForAsset(String assetId);
  Future<List<Tag>> listTagsForAsset(String assetId);
}

enum LocalMaintenanceCompletionStatus {
  applied,
  planUnavailable,
  planInactive,
  occurrenceChanged,
}

class LocalMaintenanceCompletionResult {
  const LocalMaintenanceCompletionResult({
    required this.status,
    this.operationId,
    this.previousDueDate,
    this.nextDueDate,
    this.duplicateIgnored = false,
  });

  final LocalMaintenanceCompletionStatus status;
  final String? operationId;
  final DateTime? previousDueDate;
  final DateTime? nextDueDate;
  final bool duplicateIgnored;

  bool get isApplied => status == LocalMaintenanceCompletionStatus.applied;
}

abstract interface class MaintenanceRepository {
  Stream<List<TaskItem>> watchTasks();
  Future<List<TaskItem>> listTasks();
  Stream<List<TaskItem>> watchSavedTasks();
  Future<List<TaskItem>> listSavedTasks();
  Stream<List<TaskItem>> watchArchivedTasks();
  Future<List<TaskItem>> listArchivedTasks();
  Stream<TaskItem?> watchTask(String planId);
  Future<TaskItem?> getTask(String planId);
  Stream<List<TaskItem>> watchTasksForAsset(String assetId);
  Future<List<TaskItem>> listTasksForAsset(String assetId);
  Stream<List<TaskItem>> watchSavedTasksForAsset(String assetId);
  Future<List<TaskItem>> listSavedTasksForAsset(String assetId);
  Future<String> savePlan({
    String? id,
    required String assetId,
    required String title,
    String? instructions,
    required RecurrenceRule recurrence,
    required PriorityLevel priority,
    required DateTime nextDueDate,
    int reminderDaysBefore,
    TaskMetadata? metadata,
  });
  Future<bool> completePlan(
    String planId, {
    DateTime? completedAt,
    String? notes,
    DateTime? expectedNextDueDate,
  });
  Future<LocalMaintenanceCompletionResult> completePlanResult(
    String planId, {
    DateTime? completedAt,
    String? notes,
    DateTime? expectedNextDueDate,
  });
  Future<void> undoCompletion({
    required String planId,
    required String completionId,
    required DateTime previousDueDate,
    required DateTime expectedCurrentNextDueDate,
  });
  Future<void> archivePlan(String planId);
  Future<void> restorePlan(String planId);
  Future<void> setTaskEnabled(String planId, bool enabled);
  Future<void> skipPlanOccurrence(
    String planId, {
    DateTime? skippedAt,
    String? reason,
  });
  Future<void> postponePlan(
    String planId,
    DateTime nextDueDate, {
    String? reason,
  });
  Future<void> deletePlan(String planId);
  Stream<List<MaintenanceRecord>> watchRecordsForPlan(String planId);
  Future<List<MaintenanceRecord>> listRecordsForPlan(String planId);
  Stream<List<MaintenanceRecord>> watchRecordsForAsset(String assetId);
  Future<List<MaintenanceRecord>> listRecordsForAsset(String assetId);
}

abstract interface class CalendarRepository {
  Future<List<TaskItem>> tasksBetween(
    DateTime startInclusive,
    DateTime endInclusive,
  );
}

abstract interface class StatisticsRepository {
  Future<DashboardSummary> dashboardSummary(DateTime now);
  Stream<DashboardSummary> watchDashboardSummary();
  Stream<StatisticsSummary> watchStatisticsSummary();
  Future<StatisticsSummary> statisticsSummary(DateTime now);
}

abstract interface class SettingsRepository {
  Future<AppLanguage> appLanguage();
  Future<void> setAppLanguage(AppLanguage language);
  Stream<AppLanguage> watchAppLanguage();
  Future<AppLocalePreference> appLocalePreference();
  Future<void> setAppLocalePreference(AppLanguage language);
  Stream<AppLocalePreference> watchAppLocalePreference();
  Future<ThemePreference> themePreference();
  Future<void> setThemePreference(ThemePreference preference);
  Stream<ThemePreference> watchThemePreference();
  Future<bool> timeOfDayThemeEnabled();
  Future<void> setTimeOfDayThemeEnabled(bool enabled);
  Stream<bool> watchTimeOfDayThemeEnabled();
  Future<bool> onboardingCompleted();
  Future<void> setOnboardingCompleted(bool completed);
  Stream<bool> watchOnboardingCompleted();
  Future<bool> permissionEducationSeen();
  Future<void> setPermissionEducationSeen(bool seen);
  Stream<bool> watchPermissionEducationSeen();
  Future<AppProfile> profile();
  Stream<AppProfile> watchProfile();
  Future<void> setProfile({String? nickname});
  Future<HomeLocation?> homeLocation();
  Stream<HomeLocation?> watchHomeLocation();
  Future<void> setHomeLocation(HomeLocation? location);
  Future<NotificationPreferences> notificationPreferences();
  Stream<NotificationPreferences> watchNotificationPreferences();
  Future<void> setNotificationPreferences(NotificationPreferences preferences);
  Future<void> mergeNotificationPreferences({
    required NotificationPreferences baseline,
    required NotificationPreferences desired,
  });
}

abstract interface class NotificationInboxRepository {
  Stream<List<InboxNotification>> watchNotifications();
  Stream<int> watchUnreadCount();
  Future<List<InboxNotification>> listNotifications();
  Future<int> unreadCount();
  Future<void> clear();
  Future<void> createNotification({
    required String title,
    required String body,
    required String kind,
    String? route,
    String? planId,
    NotificationMessageCode? messageCode,
    Map<String, dynamic> messageArgs = const {},
  });
  Future<void> markRead(String id);
  Future<void> markAllRead();
}

abstract interface class WeatherRepository {
  Stream<WeatherSnapshot?> watchWeather();
  Future<WeatherSnapshot?> cachedWeather();
  Future<WeatherSnapshot?> refreshWeather();
  Future<List<HomeLocation>> searchLocations(String query);
  Future<HomeLocation?> useDeviceLocation();
  Future<HomeLocation?> useCurrentLocationHomeArea();
}

abstract interface class BackupRepository {
  Future<String> exportBackup({BackupTrigger trigger = BackupTrigger.manual});
  Future<String?> exportAutomaticBackupIfDue();
  Future<BackupState> backupState();
  Future<void> setAutomaticBackupsEnabled(bool enabled);
  Future<BackupPreview> inspectBackup(String zipPath);
  Future<void> restoreBackup(String zipPath);
}

enum BackupTrigger { manual, automatic, preRestore }

class BackupState {
  const BackupState({this.lastBackup, this.automaticBackupsEnabled = true});

  final BackupStatus? lastBackup;
  final bool automaticBackupsEnabled;
}

class BackupStatus {
  const BackupStatus({
    required this.successful,
    required this.updatedAt,
    required this.trigger,
    this.path,
    this.createdAt,
    this.sizeBytes,
    this.message,
  });

  final bool successful;
  final DateTime updatedAt;
  final BackupTrigger trigger;
  final String? path;
  final DateTime? createdAt;
  final int? sizeBytes;
  final String? message;
}

class BackupPreview {
  const BackupPreview({
    required this.path,
    required this.createdAt,
    required this.formatVersion,
    required this.schemaVersion,
    required this.backupSizeBytes,
    required this.databaseSizeBytes,
    required this.fileCount,
    required this.counts,
    required this.includedData,
    required this.excludedData,
    this.trigger,
    this.warnings = const [],
  });

  final String path;
  final DateTime createdAt;
  final int formatVersion;
  final int schemaVersion;
  final int backupSizeBytes;
  final int databaseSizeBytes;
  final int fileCount;
  final Map<String, int> counts;
  final List<String> includedData;
  final List<String> excludedData;
  final BackupTrigger? trigger;
  final List<String> warnings;

  int get taskCount => counts['maintenance_plans'] ?? 0;
  int get thingCount => counts['assets'] ?? 0;
  int get historyCount => counts['maintenance_records'] ?? 0;
  int get notificationCount =>
      (counts['notifications'] ?? 0) + (counts['notification_inbox'] ?? 0);
}

abstract interface class SearchRepository {
  Future<void> rebuildIndex();
  Future<List<SearchResult>> search(String query);
}

abstract interface class RecurrenceEngine {
  DateTime nextDueDate(DateTime completionDate, RecurrenceRule rule);
}

abstract interface class HealthScoreCalculator {
  HealthScoreBreakdown calculate(List<TaskItem> tasks, DateTime now);
}

abstract interface class StreakService {
  Future<StreakState> refresh(DateTime now);
  Future<StreakState> current();
}

abstract interface class NotificationScheduler {
  Future<void> initialize();
  Future<void> requestPermissions({bool exactAlarms = false});
  Future<NotificationPermissionState> permissionState();
  Future<void> refreshSchedules();
  Future<void> clearAllScheduledReminders();
  Future<void> cancelPlanReminders(String planId);
  Future<void> snoozePlan(String planId, Duration duration);
  Future<void> sendTestReminder();
}

class NotificationPermissionState {
  const NotificationPermissionState({
    required this.notificationsEnabled,
    required this.canScheduleExact,
  });

  final bool notificationsEnabled;
  final bool canScheduleExact;
}

abstract interface class BackupService {
  Future<String> exportZip({BackupTrigger trigger = BackupTrigger.manual});
  Future<void> restoreZip(String zipPath);
}

abstract interface class RestoreService {
  Future<void> restore(String zipPath);
}

abstract interface class CrashReporter {
  Future<void> recordError(Object error, StackTrace stackTrace);
}
