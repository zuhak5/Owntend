enum RecurrenceUnit { hours, days, weeks, months, years }

enum PriorityLevel { low, medium, high, critical }

enum HealthGroup { safety, pets, appliances, plants, cleaning, other }

enum AreaKind { indoor, outdoor }

enum RoomType {
  living,
  bedroom,
  kitchen,
  bathroom,
  utility,
  storage,
  office,
  dining,
  hallway,
  entry,
  garage,
  garden,
  outdoor,
  patio,
  balcony,
  pool,
  lawn,
  shed,
  driveway,
  other,
}

enum AssetType { device, pet, plant, safety, general }

enum PowerSource { mains, battery, solar, none, other }

enum Sunlight { low, medium, brightIndirect, fullSun }

enum ThemePreference { system, light, dark }

enum AppLanguage { en, ar }

enum NotificationMessageCode {
  weatherAlert('weather_alert'),
  taskOverdue('task_overdue'),
  taskDueToday('task_due_today'),
  dailyDigest('daily_digest'),
  taskSkipped('task_skipped'),
  taskPostponed('task_postponed');

  const NotificationMessageCode(this.wireValue);

  final String wireValue;

  static NotificationMessageCode? fromWireValue(String? value) {
    for (final code in values) {
      if (code.wireValue == value) return code;
    }
    return null;
  }
}

class AppLocalePreference {
  const AppLocalePreference({
    required this.language,
    required this.isExplicit,
    required this.updatedAt,
  });

  final AppLanguage language;
  final bool isExplicit;
  final DateTime updatedAt;

  @override
  bool operator ==(Object other) =>
      other is AppLocalePreference &&
      language == other.language &&
      isExplicit == other.isExplicit &&
      updatedAt == other.updatedAt;

  @override
  int get hashCode => Object.hash(language, isExplicit, updatedAt);
}

enum TaskStatus { dueToday, upcoming, overdue, completed }

enum EffectiveCapabilityState {
  active,
  degraded,
  blocked,
  disabledByUser,
  notConfigured,
  unavailable,
}

class NotificationPreferences {
  const NotificationPreferences({
    this.enabled = true,
    this.localReminders = true,
    this.inAppInbox = true,
    this.weatherAlerts = true,
    this.quietHoursEnabled = false,
    this.quietHoursStartMinutes = 22 * 60,
    this.quietHoursEndMinutes = 7 * 60,
    this.criticalBypassQuietHours = true,
    this.privacyMode = false,
    this.dailyDigest = true,
    this.digestHour = 18,
    this.reminderHour = 9,
    this.maxRemindersPerDay = 6,
    this.defaultSnoozeMinutes = 60,
    this.preferExactReminders = false,
  });

  final bool enabled;
  final bool localReminders;
  final bool inAppInbox;
  final bool weatherAlerts;
  final bool quietHoursEnabled;
  final int quietHoursStartMinutes;
  final int quietHoursEndMinutes;
  final bool criticalBypassQuietHours;
  final bool privacyMode;
  final bool dailyDigest;
  final int digestHour;
  final int reminderHour;
  final int maxRemindersPerDay;
  final int defaultSnoozeMinutes;
  final bool preferExactReminders;

  bool get allowsLocalReminders => enabled && localReminders;
  bool get allowsInbox => enabled && inAppInbox;
  bool get allowsWeatherAlerts => allowsInbox && weatherAlerts;
  bool get allowsDailyDigest => enabled && dailyDigest;

  NotificationPreferences copyWith({
    bool? enabled,
    bool? localReminders,
    bool? inAppInbox,
    bool? weatherAlerts,
    bool? quietHoursEnabled,
    int? quietHoursStartMinutes,
    int? quietHoursEndMinutes,
    bool? criticalBypassQuietHours,
    bool? privacyMode,
    bool? dailyDigest,
    int? digestHour,
    int? reminderHour,
    int? maxRemindersPerDay,
    int? defaultSnoozeMinutes,
    bool? preferExactReminders,
  }) {
    return NotificationPreferences(
      enabled: enabled ?? this.enabled,
      localReminders: localReminders ?? this.localReminders,
      inAppInbox: inAppInbox ?? this.inAppInbox,
      weatherAlerts: weatherAlerts ?? this.weatherAlerts,
      quietHoursEnabled: quietHoursEnabled ?? this.quietHoursEnabled,
      quietHoursStartMinutes:
          quietHoursStartMinutes ?? this.quietHoursStartMinutes,
      quietHoursEndMinutes: quietHoursEndMinutes ?? this.quietHoursEndMinutes,
      criticalBypassQuietHours:
          criticalBypassQuietHours ?? this.criticalBypassQuietHours,
      privacyMode: privacyMode ?? this.privacyMode,
      dailyDigest: dailyDigest ?? this.dailyDigest,
      digestHour: digestHour ?? this.digestHour,
      reminderHour: reminderHour ?? this.reminderHour,
      maxRemindersPerDay: maxRemindersPerDay ?? this.maxRemindersPerDay,
      defaultSnoozeMinutes: defaultSnoozeMinutes ?? this.defaultSnoozeMinutes,
      preferExactReminders: preferExactReminders ?? this.preferExactReminders,
    );
  }
}

class Area {
  const Area({
    required this.id,
    required this.name,
    required this.kind,
    required this.sortOrder,
    required this.createdAt,
    required this.updatedAt,
    this.archivedAt,
  });

  final String id;
  final String name;
  final AreaKind kind;
  final int sortOrder;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? archivedAt;
}

class Room {
  const Room({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
    this.areaId = 'area_first_floor',
    this.roomType = RoomType.other,
    this.notes,
    this.sortOrder = 0,
    this.archivedAt,
  });

  final String id;
  final String areaId;
  final String name;
  final RoomType roomType;
  final String? notes;
  final int sortOrder;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? archivedAt;
}

class Category {
  const Category({
    required this.id,
    required this.name,
    required this.healthGroup,
    required this.iconName,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final HealthGroup healthGroup;
  final String iconName;
  final DateTime createdAt;
  final DateTime updatedAt;
}

class Tag {
  const Tag({required this.id, required this.name, required this.createdAt});

  final String id;
  final String name;
  final DateTime createdAt;
}

class AssetPhoto {
  const AssetPhoto({
    required this.id,
    required this.assetId,
    required this.relativePath,
    required this.createdAt,
    this.isPrimary = false,
    this.caption,
  });

  final String id;
  final String assetId;
  final String relativePath;
  final bool isPrimary;
  final String? caption;
  final DateTime createdAt;
}

class AppProfile {
  const AppProfile({
    this.nickname,
    this.displayName = 'Owntend',
    this.avatarPath,
  });

  final String? nickname;
  final String displayName;
  final String? avatarPath;
}

class HomeLocation {
  const HomeLocation({
    required this.label,
    required this.latitude,
    required this.longitude,
    this.timezone,
    this.source = 'manual',
  });

  final String label;
  final double latitude;
  final double longitude;
  final String? timezone;
  final String source;
}

class WeatherForecastDay {
  const WeatherForecastDay({
    required this.date,
    required this.weatherCode,
    required this.temperatureMax,
    required this.temperatureMin,
    required this.precipitationProbabilityMax,
    required this.windSpeedMax,
  });

  final DateTime date;
  final int weatherCode;
  final double temperatureMax;
  final double temperatureMin;
  final int precipitationProbabilityMax;
  final double windSpeedMax;
}

class WeatherSnapshot {
  const WeatherSnapshot({
    required this.location,
    required this.updatedAt,
    required this.temperature,
    required this.apparentTemperature,
    required this.weatherCode,
    required this.windSpeed,
    required this.precipitation,
    required this.humidity,
    required this.forecast,
  });

  final HomeLocation location;
  final DateTime updatedAt;
  final double temperature;
  final double apparentTemperature;
  final int weatherCode;
  final double windSpeed;
  final double precipitation;
  final int humidity;
  final List<WeatherForecastDay> forecast;
}

class InboxNotification {
  const InboxNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.kind,
    required this.createdAt,
    this.route,
    this.planId,
    this.messageCode,
    this.messageArgs = const {},
    this.readAt,
  });

  final String id;
  final String title;
  final String body;
  final String kind;
  final String? route;
  final String? planId;
  final String? messageCode;
  final Map<String, dynamic> messageArgs;
  final DateTime createdAt;
  final DateTime? readAt;

  bool get unread => readAt == null;
}

class Asset {
  const Asset({
    required this.id,
    required this.name,
    required this.categoryId,
    required this.roomId,
    required this.createdAt,
    required this.updatedAt,
    this.assetType = AssetType.general,
    this.placement,
    this.notes,
    this.purchaseDate,
    this.archivedAt,
    this.deviceDetails,
    this.petDetails,
    this.plantDetails,
    this.safetyDetails,
  });

  final String id;
  final String name;
  final AssetType assetType;
  final String categoryId;
  final String roomId;
  final String? placement;
  final String? notes;
  final DateTime? purchaseDate;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? archivedAt;
  final DeviceDetails? deviceDetails;
  final PetDetails? petDetails;
  final PlantDetails? plantDetails;
  final SafetyDetails? safetyDetails;
}

class DeviceDetails {
  const DeviceDetails({
    this.brand,
    this.model,
    this.serialNumber,
    this.powerSource,
    this.warrantyUntil,
    this.manualUrl,
    this.consumable,
  });

  final String? brand;
  final String? model;
  final String? serialNumber;
  final PowerSource? powerSource;
  final DateTime? warrantyUntil;
  final String? manualUrl;
  final String? consumable;
}

class PetDetails {
  const PetDetails({
    this.species,
    this.breed,
    this.birthDate,
    this.microchipId,
    this.vetName,
    this.vetPhone,
    this.feedingNotes,
    this.medicalNotes,
  });

  final String? species;
  final String? breed;
  final DateTime? birthDate;
  final String? microchipId;
  final String? vetName;
  final String? vetPhone;
  final String? feedingNotes;
  final String? medicalNotes;
}

class PlantDetails {
  const PlantDetails({
    this.species,
    this.sunlight,
    this.wateringIntervalDays,
    this.potSize,
    this.lastRepottedAt,
    this.toxicityNotes,
  });

  final String? species;
  final Sunlight? sunlight;
  final int? wateringIntervalDays;
  final String? potSize;
  final DateTime? lastRepottedAt;
  final String? toxicityNotes;
}

class SafetyDetails {
  const SafetyDetails({
    this.safetyType,
    this.installedAt,
    this.expiresAt,
    this.batteryType,
    this.testIntervalDays,
  });

  final String? safetyType;
  final DateTime? installedAt;
  final DateTime? expiresAt;
  final String? batteryType;
  final int? testIntervalDays;
}

class RecurrenceRule {
  const RecurrenceRule({required this.interval, required this.unit});

  final int interval;
  final RecurrenceUnit unit;

  String get label {
    final noun = switch (unit) {
      RecurrenceUnit.hours => interval == 1 ? 'hour' : 'hours',
      RecurrenceUnit.days => interval == 1 ? 'day' : 'days',
      RecurrenceUnit.weeks => interval == 1 ? 'week' : 'weeks',
      RecurrenceUnit.months => interval == 1 ? 'month' : 'months',
      RecurrenceUnit.years => interval == 1 ? 'year' : 'years',
    };
    if (interval == 1) {
      return 'Every $noun';
    }
    return 'Every $interval $noun';
  }
}

class TaskMetadata {
  const TaskMetadata({
    this.taskType,
    this.locationLabel,
    this.estimatedDurationMinutes,
    this.requiredMaterials = const [],
    this.reminderRecommendation,
    this.sortOrder,
  });

  final String? taskType;
  final String? locationLabel;
  final int? estimatedDurationMinutes;
  final List<String> requiredMaterials;
  final String? reminderRecommendation;
  final int? sortOrder;
}

class MaintenancePlan {
  const MaintenancePlan({
    required this.id,
    required this.assetId,
    required this.title,
    required this.recurrence,
    required this.priority,
    required this.nextDueDate,
    required this.healthGroup,
    required this.createdAt,
    required this.updatedAt,
    this.instructions,
    this.reminderDaysBefore = 0,
    this.isEnabled = true,
    this.metadata,
    this.archivedAt,
  });

  final String id;
  final String assetId;
  final String title;
  final String? instructions;
  final RecurrenceRule recurrence;
  final PriorityLevel priority;
  final DateTime nextDueDate;
  final int reminderDaysBefore;
  final bool isEnabled;
  final TaskMetadata? metadata;
  final HealthGroup healthGroup;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? archivedAt;
}

class MaintenanceRecord {
  const MaintenanceRecord({
    required this.id,
    required this.planId,
    required this.completedAt,
    required this.dueDate,
    this.notes,
  });

  final String id;
  final String planId;
  final DateTime dueDate;
  final DateTime completedAt;
  final String? notes;
}

class TaskItem {
  const TaskItem({
    required this.plan,
    required this.asset,
    required this.category,
    required this.room,
    required this.status,
  });

  final MaintenancePlan plan;
  final Asset asset;
  final Category category;
  final Room room;
  final TaskStatus status;
}

class HealthScoreBreakdown {
  const HealthScoreBreakdown({
    required this.score,
    required this.groupScores,
    required this.activeWeights,
  });

  final int score;
  final Map<HealthGroup, double> groupScores;
  final Map<HealthGroup, double> activeWeights;
}

class StreakState {
  const StreakState({
    required this.currentStreak,
    required this.bestStreak,
    required this.updatedAt,
    this.lastCompletedDate,
  });

  final int currentStreak;
  final int bestStreak;
  final DateTime? lastCompletedDate;
  final DateTime updatedAt;
}

class DashboardSummary {
  const DashboardSummary({
    required this.todayTasks,
    required this.upcomingTasks,
    required this.overdueTasks,
    required this.health,
    required this.streak,
    required this.completionRate,
    required this.completedThisMonth,
  });

  final int todayTasks;
  final int upcomingTasks;
  final int overdueTasks;
  final HealthScoreBreakdown health;
  final StreakState streak;
  final double completionRate;
  final int completedThisMonth;
}

class SearchResult {
  const SearchResult({
    required this.entityType,
    required this.entityId,
    required this.title,
    required this.snippet,
  });

  final String entityType;
  final String entityId;
  final String title;
  final String snippet;
}

class StatisticsSummary {
  const StatisticsSummary({
    required this.completionRate,
    required this.overdueRate,
    required this.completedByMonth,
    required this.taskDistribution,
  });

  final double completionRate;
  final double overdueRate;
  final Map<String, int> completedByMonth;
  final Map<HealthGroup, int> taskDistribution;
}
