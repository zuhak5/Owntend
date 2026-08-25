import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart' show XFile;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:owntend/main.dart';
import 'package:owntend/src/core/domain/contracts.dart';
import 'package:owntend/src/core/domain/models.dart';
import 'package:owntend/src/core/services/app_permission_coordinator.dart';
import 'package:owntend/src/core/sync/sync_contracts.dart';
import 'package:owntend/src/features/auth/domain/auth_repository.dart';
import 'package:owntend/src/features/monetization/monetization.dart';
import 'package:owntend/src/features/permissions/data/device_permission_gateway.dart';
import 'package:owntend/src/features/permissions/data/permission_education_repository.dart';
import 'package:owntend/src/features/permissions/domain/permission_capability.dart';
import 'package:owntend/src/features/permissions/domain/permission_education_state.dart';
import 'package:owntend/l10n/app_localizations.dart';
import 'package:owntend/src/ui/components.dart' as hk_ui;
import 'package:go_router/go_router.dart';

import '../test_theme.dart';

const signedInTestSession = AuthSession(
  userId: 'widget-test-user',
  fullName: 'Widget Tester',
  email: 'widget@example.invalid',
  providers: {'google'},
);

InitialHydrationProgress testHydrationProgress(
  InitialHydrationStage stage, {
  RestoreRunState state = RestoreRunState.running,
  int completedUnits = 42,
  int totalUnits = 100,
}) {
  final timestamp = DateTime.utc(2026, 7, 20, 12);
  return InitialHydrationProgress(
    runId: 'widget-restore-run',
    state: state,
    stage: stage,
    completedUnits: completedUnits,
    totalUnits: totalUnits,
    startedAt: timestamp,
    updatedAt: timestamp,
  );
}

FakeCloudSyncRepository blockingCloudSyncRepository(
  SyncStatus status, {
  Completer<void>? enable,
}) {
  final restore = enable ?? Completer<void>();
  addTearDown(() {
    if (!restore.isCompleted) restore.complete();
  });
  return FakeCloudSyncRepository(status, enableFuture: restore.future);
}

Future<void> pumpSwipeRows(
  WidgetTester tester, {
  required List<Widget> rows,
  Locale locale = const Locale('en'),
}) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: testLightTheme(),
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 320,
            child: Column(mainAxisSize: MainAxisSize.min, children: rows),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> pumpPermissionEducation(WidgetTester tester) async {
  await tester.pumpAndSettle();
}

Widget swipeTestRow(String id, {required Future<bool> Function()? onAction}) {
  return hk_ui.SwipeDelete(
    dismissKey: ValueKey('swipe-row-$id'),
    action: hk_ui.SwipeAction.moveToTrash(onAction: onAction),
    margin: const EdgeInsets.only(bottom: 8),
    child: Container(
      key: ValueKey('swipe-card-$id'),
      width: double.infinity,
      height: 64,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.black12),
        borderRadius: BorderRadius.circular(hk_ui.kSwipeRowRadius),
      ),
      child: Text('Row $id'),
    ),
  );
}

Future<GoRouter> pumpDashboardHeader(
  WidgetTester tester, {
  required FakeSettingsRepository settings,
  required ThemeData theme,
  int balance = 7,
  int unreadNotifications = 3,
}) async {
  settings.homeLocationValue ??= const HomeLocation(
    label: 'Baghdad',
    latitude: 33.3152,
    longitude: 44.3661,
    source: 'manual',
  );
  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (context, state) => const DashboardScreen()),
      GoRoute(
        path: '/notifications',
        builder: (context, state) => const Scaffold(
          body: Center(child: Text('Notification route target')),
        ),
      ),
      GoRoute(
        path: '/search',
        builder: (context, state) => const Scaffold(body: Text('Search')),
      ),
      GoRoute(
        path: '/account',
        builder: (context, state) => const Scaffold(body: Text('Account')),
      ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...testOverrides(settings, unreadNotifications: unreadNotifications),
        monetizationRepositoryProvider.overrideWithValue(null),
        pointWalletProvider.overrideWithValue(
          AsyncData(
            PointWallet(
              balance: balance,
              timeZone: 'Asia/Baghdad',
              updatedAt: DateTime.utc(2026, 8, 2),
            ),
          ),
        ),
        monetizationConfigProvider.overrideWithValue(
          const AsyncData(MonetizationConfig.failClosed()),
        ),
        pendingRewardClaimsProvider.overrideWithValue(const AsyncData([])),
      ],
      child: MaterialApp.router(
        routerConfig: router,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        theme: theme,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

Future<void> dragSwipeRowPastThreshold(
  WidgetTester tester,
  Finder row, {
  Offset offset = const Offset(-500, 0),
  String? dialogTitle,
}) async {
  await tester.drag(row, offset);
  await waitForSwipeBackgroundToClose(tester);
  if (dialogTitle != null) {
    expect(find.text(dialogTitle), findsNothing);
  }
  await tester.pump(const Duration(milliseconds: 800));
}

Future<void> waitForSwipeBackgroundToClose(WidgetTester tester) async {
  for (var index = 0; index < 20; index++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (find.text('Move to Trash').evaluate().isEmpty &&
        find.text('Swipe to move to Trash').evaluate().isEmpty &&
        find.text('Release to move to Trash').evaluate().isEmpty) {
      break;
    }
  }
  expect(find.text('Swipe to move to Trash'), findsNothing);
  expect(find.text('Release to move to Trash'), findsNothing);
  expect(find.text('Move to Trash'), findsNothing);
}

void expectContainedHero(WidgetTester tester, ValueKey<String> key) {
  final hero = find.byKey(key);
  expect(hero, findsOneWidget);

  final topLeft = tester.getTopLeft(hero);
  final heroSize = tester.getSize(hero);
  final viewportSize = tester.view.physicalSize / tester.view.devicePixelRatio;

  expect(topLeft.dx, moreOrLessEquals(0));
  expect(topLeft.dy, moreOrLessEquals(0));
  expect(heroSize.width, moreOrLessEquals(viewportSize.width));
  expect(heroSize.height, moreOrLessEquals(viewportSize.height));
  final image = tester.widget<Image>(
    find.descendant(of: hero, matching: find.byType(Image)),
  );
  expect(image.fit, BoxFit.contain);
}

void expectHeroBehind(WidgetTester tester, ValueKey<String> key, Finder above) {
  final hero = find.byKey(key);
  expect(hero, findsOneWidget);
  expect(above, findsOneWidget);

  expect(tester.getTopLeft(hero).dy, lessThan(tester.getBottomLeft(above).dy));
}

Future<void> pumpBackupScreen(
  WidgetTester tester, {
  required FakeBackupRepository repository,
  FakeCloudSyncRepository? sync,
  ThemeData? theme,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        backupRepositoryProvider.overrideWithValue(repository),
        cloudSyncRepositoryProvider.overrideWithValue(
          sync ?? FakeCloudSyncRepository(const SyncStatus.disabled()),
        ),
        notificationAutoStartProvider.overrideWithValue(false),
      ],
      child: MaterialApp(
        theme: theme ?? testLightTheme(),
        home: const BackupScreen(),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

FilePickerPlatform? installFilePicker(FilePickerPlatform picker) {
  FilePickerPlatform? previous;
  try {
    previous = FilePickerPlatform.instance;
  } catch (_) {
    previous = null;
  }
  FilePickerPlatform.instance = picker;
  return previous;
}

List<Override> testOverrides(
  FakeSettingsRepository settings, {
  List<TaskItem> tasks = const [],
  List<Asset>? assets,
  List<Room>? rooms,
  Stream<List<TaskItem>>? taskStream,
  Stream<List<Asset>>? assetStream,
  Stream<List<Room>>? roomStream,
  WeatherSnapshot? weather,
  BackupState? backupState,
  List<InboxNotification> notifications = const [],
  int unreadNotifications = 0,
  Map<String, List<MaintenanceRecord>> taskRecords = const {},
  AuthSession? session = signedInTestSession,
  bool includeAuthOverrides = true,
  AsyncValue<AppProfile>? profileState,
  FakeNotificationScheduler? notificationScheduler,
  MaintenanceRepository? maintenanceRepository,
  AssetRepository? assetRepository,
  WeatherRepository? weatherRepository,
  AppPermissionGateway? permissionGateway,
  PermissionEducationRepository? permissionEducationRepository,
}) {
  final now = DateTime(2026);
  final streak = StreakState(currentStreak: 0, bestStreak: 0, updatedAt: now);
  final things = assets ?? makeThings(now);
  final homeRooms = rooms ?? makeRooms(now);
  final recordOverrides = <String, List<MaintenanceRecord>>{};
  for (final task in tasks) {
    recordOverrides[task.plan.id] = taskRecords[task.plan.id] ?? const [];
  }
  for (final notification in notifications) {
    final planId = notification.planId;
    if (planId != null) {
      recordOverrides.putIfAbsent(
        planId,
        () => taskRecords[planId] ?? const [],
      );
    }
  }
  for (final entry in taskRecords.entries) {
    recordOverrides[entry.key] = entry.value;
  }
  final effectiveGateway =
      permissionGateway ??
      FakeAppPermissionGateway(
        states: {
          AppPermissionKind.location: AppPermissionState.granted,
          AppPermissionKind.notifications: AppPermissionState.granted,
        },
      );
  final defaultDeviceState = settings.permissionEducationSeenValue
      ? PermissionEducationDeviceState(completedAt: DateTime(2026))
      : const PermissionEducationDeviceState();
  return [
    notificationAutoStartProvider.overrideWithValue(false),
    backupAutoStartProvider.overrideWithValue(false),
    if (includeAuthOverrides) ...[
      authSessionProvider.overrideWithValue(AsyncData(session)),
      authStateProvider.overrideWithValue(
        AsyncData(
          AuthStateChange(
            event: AuthEventType.initialSession,
            session: session,
          ),
        ),
      ),
    ],
    startupThemeSettingsProvider.overrideWithValue(
      ThemeStartupSettings(
        preference: settings.themePreferenceValue,
        timeOfDayEnabled: settings.timeOfDayThemeEnabledValue,
      ),
    ),
    notificationSchedulerProvider.overrideWithValue(
      notificationScheduler ?? FakeNotificationScheduler(),
    ),
    permissionCoordinatorProvider.overrideWithValue(effectiveGateway),
    devicePermissionGatewayProvider.overrideWithValue(
      AppPermissionGatewayDeviceAdapter(effectiveGateway),
    ),
    permissionEducationRepositoryProvider.overrideWithValue(
      permissionEducationRepository ??
          FakePermissionEducationRepository(initialState: defaultDeviceState),
    ),
    weatherRepositoryProvider.overrideWithValue(
      weatherRepository ?? CountingWeatherRepository(),
    ),
    settingsRepositoryProvider.overrideWithValue(settings),
    maintenanceRepositoryProvider.overrideWithValue(
      maintenanceRepository ?? FakeMaintenanceRepository(initialTasks: tasks),
    ),
    assetRepositoryProvider.overrideWithValue(
      assetRepository ??
          StartupAssetRepository(assets: things, rooms: homeRooms),
    ),
    profileProvider.overrideWithValue(
      profileState ?? AsyncData(settings.profileValue),
    ),
    homeLocationProvider.overrideWithValue(
      AsyncData(settings.homeLocationValue),
    ),
    weatherProvider.overrideWithValue(AsyncData(weather)),
    backupStateProvider.overrideWithValue(
      AsyncData(backupState ?? const BackupState()),
    ),
    notificationsProvider.overrideWithValue(AsyncData(notifications)),
    unreadNotificationsProvider.overrideWithValue(
      AsyncData(unreadNotifications),
    ),
    notificationPreferencesProvider.overrideWithValue(
      AsyncData(settings.notificationPreferencesValue),
    ),
    notificationPermissionStateProvider.overrideWithValue(
      const AsyncData(NotificationPermissionState(notificationsEnabled: true)),
    ),
    streakRefreshProvider.overrideWithValue(AsyncData(streak)),
    taskStream == null
        ? tasksProvider.overrideWithValue(AsyncData(tasks))
        : tasksProvider.overrideWith((ref) => seededStream(tasks, taskStream)),
    for (final task in tasks) ...[
      taskDetailProvider(task.plan.id).overrideWithValue(AsyncData(task)),
    ],
    for (final entry in recordOverrides.entries)
      taskRecordsProvider(entry.key).overrideWithValue(AsyncData(entry.value)),
    areasProvider.overrideWithValue(AsyncData(makeAreas(now))),
    roomStream == null
        ? roomsProvider.overrideWithValue(AsyncData(homeRooms))
        : roomsProvider.overrideWith(
            (ref) => seededStream(homeRooms, roomStream),
          ),
    assetStream == null
        ? assetsProvider.overrideWithValue(AsyncData(things))
        : assetsProvider.overrideWith(
            (ref) => seededStream(things, assetStream),
          ),
    roomAssetsProvider('room_kitchen').overrideWithValue(AsyncData(things)),
    for (final thing in things) ...[
      assetDetailProvider(thing.id).overrideWithValue(AsyncData(thing)),
      assetTasksProvider(thing.id).overrideWithValue(
        AsyncData(tasks.where((task) => task.asset.id == thing.id).toList()),
      ),
      assetSavedTasksProvider(thing.id).overrideWithValue(
        AsyncData(tasks.where((task) => task.asset.id == thing.id).toList()),
      ),
      assetTagsProvider(thing.id).overrideWithValue(const AsyncData([])),
      assetPhotosProvider(thing.id).overrideWithValue(const AsyncData([])),
      assetRecordsProvider(thing.id).overrideWithValue(
        AsyncData(
          tasks
              .where((task) => task.asset.id == thing.id)
              .expand(
                (task) =>
                    recordOverrides[task.plan.id] ??
                    const <MaintenanceRecord>[],
              )
              .toList(),
        ),
      ),
    ],
    dashboardProvider.overrideWithValue(
      AsyncData(
        DashboardSummary(
          todayTasks: tasks
              .where((task) => task.status == TaskStatus.dueToday)
              .length,
          upcomingTasks: tasks
              .where((task) => task.status == TaskStatus.upcoming)
              .length,
          overdueTasks: tasks
              .where((task) => task.status == TaskStatus.overdue)
              .length,
          health: const HealthScoreBreakdown(
            score: 100,
            groupScores: {},
            activeWeights: {},
          ),
          streak: streak,
          completionRate: tasks.isEmpty ? 1 : 0,
          completedThisMonth: 0,
        ),
      ),
    ),
    statisticsProvider.overrideWithValue(
      const AsyncData(
        StatisticsSummary(
          completionRate: 1,
          overdueRate: 0,
          completedByMonth: {},
          taskDistribution: {},
        ),
      ),
    ),
  ];
}

Stream<T> seededStream<T>(T initialValue, Stream<T> updates) {
  return Stream<T>.multi((controller) {
    controller.add(initialValue);
    final subscription = updates.listen(
      controller.add,
      onError: controller.addError,
      onDone: controller.close,
    );
    controller.onCancel = subscription.cancel;
  });
}

WeatherSnapshot makeWeather({
  double temperature = 26,
  double apparentTemperature = 24,
  double windSpeed = 12,
  int humidity = 56,
  String locationLabel = 'Baghdad',
}) {
  final now = DateTime(2026, 6, 18, 9);
  return WeatherSnapshot(
    location: HomeLocation(
      label: locationLabel,
      latitude: 33.3152,
      longitude: 44.3661,
      timezone: 'Asia/Baghdad',
    ),
    updatedAt: now,
    temperature: temperature,
    apparentTemperature: apparentTemperature,
    weatherCode: 0,
    windSpeed: windSpeed,
    precipitation: 0,
    humidity: humidity,
    forecast: [
      WeatherForecastDay(
        date: now,
        weatherCode: 0,
        temperatureMax: 30,
        temperatureMin: 20,
        precipitationProbabilityMax: 0,
        windSpeedMax: 16,
      ),
    ],
  );
}

List<Area> makeAreas(DateTime now) {
  return [
    Area(
      id: 'area_first_floor',
      name: 'Main Level',
      kind: AreaKind.indoor,
      sortOrder: 0,
      createdAt: now,
      updatedAt: now,
    ),
    Area(
      id: 'area_second_floor',
      name: 'Upper Level',
      kind: AreaKind.indoor,
      sortOrder: 1,
      createdAt: now,
      updatedAt: now,
    ),
    Area(
      id: 'area_outdoor_garden',
      name: 'Garden',
      kind: AreaKind.outdoor,
      sortOrder: 2,
      createdAt: now,
      updatedAt: now,
    ),
  ];
}

List<Room> makeRooms(DateTime now) {
  return [
    Room(
      id: 'room_general',
      areaId: 'area_first_floor',
      name: 'General',
      roomType: RoomType.other,
      sortOrder: 0,
      createdAt: now,
      updatedAt: now,
    ),
    Room(
      id: 'room_kitchen',
      areaId: 'area_first_floor',
      name: 'Kitchen',
      roomType: RoomType.kitchen,
      sortOrder: 1,
      createdAt: now,
      updatedAt: now,
    ),
    Room(
      id: 'room_garden',
      areaId: 'area_outdoor_garden',
      name: 'Garden',
      roomType: RoomType.garden,
      sortOrder: 0,
      createdAt: now,
      updatedAt: now,
    ),
  ];
}

TaskItem makeTaskItem(
  DateTime dueDate, {
  String id = 'plan_feed_fish',
  String title = 'Feed the fish',
  TaskStatus status = TaskStatus.dueToday,
  bool preserveDueTime = false,
  bool isEnabled = true,
}) {
  final now = DateTime(2026);
  final asset = Asset(
    id: 'asset_fish',
    name: 'Fish',
    assetType: AssetType.pet,
    roomId: 'room_kitchen',
    createdAt: now,
    updatedAt: now,
  );
  final room = Room(
    id: 'room_kitchen',
    areaId: 'area_first_floor',
    name: 'Kitchen',
    roomType: RoomType.kitchen,
    createdAt: now,
    updatedAt: now,
  );
  return TaskItem(
    plan: MaintenancePlan(
      id: id,
      assetId: asset.id,
      title: title,
      recurrence: const RecurrenceRule(interval: 1, unit: RecurrenceUnit.days),
      priority: PriorityLevel.medium,
      nextDueDate: preserveDueTime ? dueDate : DateUtils.dateOnly(dueDate),
      isEnabled: isEnabled,
      createdAt: now,
      updatedAt: now,
    ),
    asset: asset,
    room: room,
    status: status,
  );
}

List<Asset> makeThings(DateTime now) {
  return [
    makeThing('asset_dishwasher', 'Dishwasher', AssetType.device, now: now),
    makeThing('asset_basil', 'Basil', AssetType.plant, now: now),
  ];
}

Asset makeThing(String id, String name, AssetType type, {DateTime? now}) {
  final timestamp = now ?? DateTime(2026);
  return Asset(
    id: id,
    name: name,
    assetType: type,
    roomId: 'room_kitchen',
    placement: 'North wall',
    createdAt: timestamp,
    updatedAt: timestamp,
    deviceDetails: type == AssetType.device
        ? const DeviceDetails(brand: 'Bosch')
        : null,
    petDetails: type == AssetType.pet ? const PetDetails(species: 'Cat') : null,
    plantDetails: type == AssetType.plant
        ? const PlantDetails(sunlight: Sunlight.medium)
        : null,
    safetyDetails: type == AssetType.safety
        ? const SafetyDetails(safetyType: 'Detector')
        : null,
  );
}

class FakeBackupRepository implements BackupRepository {
  FakeBackupRepository({
    BackupState? state,
    BackupPreview? preview,
    this.exportDelay,
    this.exportError,
    this.exportCompleter,
  }) : state = state ?? const BackupState(),
       preview = preview ?? defaultBackupPreview;

  BackupState state;
  BackupPreview preview;
  String? inspectedPath;
  bool? automaticBackupsEnabled;
  var exportCount = 0;
  var restoreCount = 0;
  final Duration? exportDelay;
  final Object? exportError;
  final Completer<String>? exportCompleter;

  @override
  Future<String> exportBackup({
    BackupTrigger trigger = BackupTrigger.manual,
    String? passphrase,
  }) async {
    exportCount++;
    if (exportCompleter != null) {
      final path = await exportCompleter!.future;
      if (exportError != null) {
        throw exportError!;
      }
      state = BackupState(
        lastBackup: BackupStatus(
          successful: true,
          updatedAt: DateTime(2026, 7, 12, 9),
          createdAt: DateTime(2026, 7, 12, 9),
          trigger: trigger,
          path: path,
          sizeBytes: 1024,
        ),
        automaticBackupsEnabled: state.automaticBackupsEnabled,
      );
      return state.lastBackup!.path!;
    }
    if (exportDelay != null) {
      await Future<void>.delayed(exportDelay!);
    }
    if (exportError != null) {
      throw exportError!;
    }
    state = BackupState(
      lastBackup: BackupStatus(
        successful: true,
        updatedAt: DateTime(2026, 7, 12, 9),
        createdAt: DateTime(2026, 7, 12, 9),
        trigger: trigger,
        path: 'C:\\backups\\owntend-backup.zip',
        sizeBytes: 1024,
      ),
      automaticBackupsEnabled: state.automaticBackupsEnabled,
    );
    return state.lastBackup!.path!;
  }

  @override
  Future<String?> exportAutomaticBackupIfDue() async => null;

  @override
  Future<BackupState> backupState() async => state;

  @override
  Future<void> setAutomaticBackupsEnabled(bool enabled) async {
    automaticBackupsEnabled = enabled;
    state = BackupState(
      lastBackup: state.lastBackup,
      automaticBackupsEnabled: enabled,
    );
  }

  @override
  Future<BackupPreview> inspectBackup(
    String backupPath, {
    String? passphrase,
  }) async {
    inspectedPath = backupPath;
    return preview;
  }

  @override
  Future<void> restoreBackup(String backupPath, {String? passphrase}) async {
    restoreCount++;
  }
}

class FakeCloudSyncRepository implements CloudSyncRepository {
  FakeCloudSyncRepository(this.currentStatus, {this.enableFuture});

  SyncStatus currentStatus;
  Future<void>? enableFuture;
  var enableCount = 0;
  var disableCount = 0;
  var fullReconcileCount = 0;
  var syncNowCount = 0;

  @override
  Future<void> disable() async {
    disableCount++;
    currentStatus = const SyncStatus.disabled();
  }

  @override
  Future<void> enable() {
    enableCount++;
    return enableFuture ?? Future<void>.value();
  }

  @override
  Future<void> fullReconcile() async {
    fullReconcileCount++;
  }

  @override
  Future<void> retry() async {}

  @override
  Future<SyncStatus> status() async => currentStatus;

  @override
  Future<void> syncNow() async {
    syncNowCount++;
  }

  @override
  Future<void> unlink() async {}

  @override
  Stream<SyncStatus> watchStatus() => Stream.value(currentStatus);
}

final class FakePlatformFile extends PlatformFile {
  FakePlatformFile(this._path, {this.fileSize = 2048});

  final String _path;
  final int fileSize;

  @override
  String get name => _path.split(RegExp(r'[\\/]')).last;

  @override
  Uri get uri => Uri.file(_path);

  @override
  String? get path => _path;

  @override
  XFile get xFile => XFile(_path);

  @override
  Future<int> length() async => fileSize;

  @override
  Future<Uint8List> readAsBytes() async => Uint8List(0);

  @override
  Stream<Uint8List> readAsByteStream() => Stream.value(Uint8List(0));
}

class FakeFilePicker extends FilePickerPlatform {
  FakeFilePicker(this.path);

  final String? path;
  var pickCount = 0;

  @override
  Future<List<PlatformFile>> pickFiles({
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    dynamic Function(FilePickerStatus)? onFileLoading,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    int compressionQuality = 0,
    String? dialogTitle,
    String? initialDirectory,
    bool lockParentWindow = false,
    bool readSequential = false,
    AndroidOptions androidOptions = const AndroidOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
  }) async {
    pickCount++;
    if (path == null) {
      return const [];
    }
    return [FakePlatformFile(path!)];
  }
}

final defaultBackupPreview = BackupPreview(
  path: 'C:\\backups\\selected.zip',
  createdAt: DateTime(2026, 7, 12, 9),
  formatVersion: 2,
  schemaVersion: 12,
  backupSizeBytes: 1024,
  databaseSizeBytes: 512,
  fileCount: 1,
  counts: const {'maintenance_plans': 1, 'assets': 1, 'maintenance_records': 1},
  includedData: const ['tasks'],
  excludedData: const [
    'Android scheduled alarm handles are recreated from restored tasks and settings',
  ],
);

class FakeAppPermissionGateway implements AppPermissionGateway {
  FakeAppPermissionGateway({
    Map<AppPermissionKind, AppPermissionState>? states,
    Map<AppPermissionKind, AppPermissionState>? requestResults,
  }) : states = states ?? <AppPermissionKind, AppPermissionState>{},
       requestResults =
           requestResults ?? <AppPermissionKind, AppPermissionState>{};

  final Map<AppPermissionKind, AppPermissionState> states;
  final Map<AppPermissionKind, AppPermissionState> requestResults;
  final List<AppPermissionKind> requests = [];
  final List<AppPermissionKind> prompted = [];
  var openAppSettingsCount = 0;
  var openLocationSettingsCount = 0;

  @override
  Future<AppPermissionState> check(AppPermissionKind kind) async =>
      states[kind] ?? AppPermissionState.unavailable;

  @override
  Future<AppPermissionState> request(AppPermissionKind kind) async {
    requests.add(kind);
    if (!prompted.contains(kind)) {
      prompted.add(kind);
    }
    final result =
        requestResults[kind] ?? states[kind] ?? AppPermissionState.denied;
    states[kind] = result;
    return result;
  }

  @override
  Future<bool> wasPrompted(AppPermissionKind kind) async =>
      prompted.contains(kind);

  @override
  Future<void> markPrompted(AppPermissionKind kind) async {
    prompted.add(kind);
  }

  @override
  Future<bool> openAppPermissionSettings() async {
    openAppSettingsCount++;
    return true;
  }

  @override
  Future<bool> openLocationServiceSettings() async {
    openLocationSettingsCount++;
    return true;
  }
}

class AppPermissionGatewayDeviceAdapter implements DevicePermissionGateway {
  AppPermissionGatewayDeviceAdapter(this.gateway);
  final AppPermissionGateway gateway;

  AppPermissionKind _map(PermissionCapability cap) => switch (cap) {
    PermissionCapability.deviceLocation => AppPermissionKind.location,
    PermissionCapability.notifications => AppPermissionKind.notifications,
  };

  @override
  Future<AppPermissionState> check(PermissionCapability capability) =>
      gateway.check(_map(capability));

  @override
  Future<DeviceLocationAccessState> checkLocationAccess() async {
    final state = await gateway.check(AppPermissionKind.location);
    return DeviceLocationAccessState(
      permissionState: state == AppPermissionState.serviceDisabled
          ? AppPermissionState.denied
          : state,
      serviceEnabled: state == AppPermissionState.unavailable
          ? null
          : state != AppPermissionState.serviceDisabled,
    );
  }

  @override
  Future<AppPermissionState> request(PermissionCapability capability) =>
      gateway.request(_map(capability));

  @override
  Future<bool> openSettings(PermissionCapability capability) async {
    final kind = _map(capability);
    if (kind == AppPermissionKind.location) {
      await gateway.openLocationServiceSettings();
    } else {
      await gateway.openAppPermissionSettings();
    }
    return true;
  }
}

class FakePermissionEducationRepository
    implements PermissionEducationRepository {
  FakePermissionEducationRepository({
    PermissionEducationDeviceState? initialState,
  }) : deviceState = initialState ?? const PermissionEducationDeviceState();

  PermissionEducationDeviceState deviceState;

  @override
  Future<PermissionEducationDeviceState> loadDeviceState() async {
    return deviceState;
  }

  @override
  Future<void> saveDeviceState(PermissionEducationDeviceState state) async {
    deviceState = state;
  }
}

class FakeSettingsRepository implements SettingsRepository {
  FakeSettingsRepository({
    required this.onboardingCompletedValue,
    this.permissionEducationSeenValue = true,
    this.themePreferenceValue = ThemePreference.system,
    this.timeOfDayThemeEnabledValue = false,
    this.appLanguageValue = AppLanguage.en,
    this.appLanguageExplicitValue = false,
    this.profileFailure,
  });

  final _appLanguageController = StreamController<AppLanguage>.broadcast();
  final _appLocalePreferenceController =
      StreamController<AppLocalePreference>.broadcast();
  final _themeController = StreamController<ThemePreference>.broadcast();
  final _timeOfDayThemeController = StreamController<bool>.broadcast();
  final _onboardingController = StreamController<bool>.broadcast();
  final _permissionEducationController = StreamController<bool>.broadcast();
  final _profileController = StreamController<AppProfile>.broadcast();
  final _notificationPreferencesController =
      StreamController<NotificationPreferences>.broadcast();

  AppLanguage appLanguageValue;
  bool appLanguageExplicitValue;
  DateTime appLanguageUpdatedAt = DateTime.fromMillisecondsSinceEpoch(0);
  ThemePreference themePreferenceValue;
  bool timeOfDayThemeEnabledValue;
  bool onboardingCompletedValue;
  bool permissionEducationSeenValue;
  AppProfile profileValue = const AppProfile();
  HomeLocation? homeLocationValue;
  NotificationPreferences notificationPreferencesValue =
      const NotificationPreferences();
  final Object? profileFailure;
  int notificationSaveCount = 0;

  @override
  Future<AppLanguage> appLanguage() async => appLanguageValue;

  @override
  Future<void> setAppLanguage(AppLanguage language) async {
    await setAppLocalePreference(language);
  }

  @override
  Future<AppLocalePreference> appLocalePreference() async =>
      AppLocalePreference(
        language: appLanguageValue,
        isExplicit: appLanguageExplicitValue,
        updatedAt: appLanguageUpdatedAt,
      );

  @override
  Future<void> setAppLocalePreference(AppLanguage language) async {
    appLanguageValue = language;
    appLanguageExplicitValue = true;
    appLanguageUpdatedAt = DateTime.now();
    _appLanguageController.add(language);
    _appLocalePreferenceController.add(await appLocalePreference());
  }

  @override
  Stream<AppLanguage> watchAppLanguage() async* {
    yield appLanguageValue;
    yield* _appLanguageController.stream;
  }

  @override
  Stream<AppLocalePreference> watchAppLocalePreference() async* {
    yield await appLocalePreference();
    yield* _appLocalePreferenceController.stream;
  }

  @override
  Future<ThemePreference> themePreference() async => themePreferenceValue;

  @override
  Future<void> setThemePreference(ThemePreference preference) async {
    themePreferenceValue = preference;
    _themeController.add(preference);
  }

  @override
  Stream<ThemePreference> watchThemePreference() async* {
    yield themePreferenceValue;
    yield* _themeController.stream;
  }

  @override
  Future<bool> timeOfDayThemeEnabled() async => timeOfDayThemeEnabledValue;

  @override
  Future<void> setTimeOfDayThemeEnabled(bool enabled) async {
    timeOfDayThemeEnabledValue = enabled;
    _timeOfDayThemeController.add(enabled);
  }

  @override
  Stream<bool> watchTimeOfDayThemeEnabled() async* {
    yield timeOfDayThemeEnabledValue;
    yield* _timeOfDayThemeController.stream;
  }

  @override
  Future<bool> onboardingCompleted() async => onboardingCompletedValue;

  @override
  Future<void> setOnboardingCompleted(bool completed) async {
    onboardingCompletedValue = completed;
    _onboardingController.add(completed);
  }

  @override
  Stream<bool> watchOnboardingCompleted() async* {
    yield onboardingCompletedValue;
    yield* _onboardingController.stream;
  }

  @override
  Future<bool> permissionEducationSeen() async => permissionEducationSeenValue;

  @override
  Future<void> setPermissionEducationSeen(bool seen) async {
    permissionEducationSeenValue = seen;
    _permissionEducationController.add(seen);
  }

  @override
  Stream<bool> watchPermissionEducationSeen() async* {
    yield permissionEducationSeenValue;
    yield* _permissionEducationController.stream;
  }

  @override
  Future<AppProfile> profile() async {
    if (profileFailure case final failure?) throw failure;
    return profileValue;
  }

  @override
  Stream<AppProfile> watchProfile() async* {
    yield profileValue;
    yield* _profileController.stream;
  }

  @override
  Future<void> setProfile({String? nickname}) async {
    profileValue = AppProfile(
      nickname: nickname?.trim().isEmpty ?? true ? null : nickname!.trim(),
      displayName: profileValue.displayName,
      avatarPath: profileValue.avatarPath,
    );
    _profileController.add(profileValue);
  }

  @override
  Future<HomeLocation?> homeLocation() async => homeLocationValue;

  @override
  Stream<HomeLocation?> watchHomeLocation() async* {
    yield homeLocationValue;
  }

  @override
  Future<void> setHomeLocation(HomeLocation? location) async {
    homeLocationValue = location;
  }

  @override
  Future<NotificationPreferences> notificationPreferences() async =>
      notificationPreferencesValue;

  @override
  Stream<NotificationPreferences> watchNotificationPreferences() async* {
    yield notificationPreferencesValue;
    yield* _notificationPreferencesController.stream;
  }

  @override
  Future<void> setNotificationPreferences(
    NotificationPreferences preferences,
  ) async {
    notificationSaveCount++;
    notificationPreferencesValue = preferences;
    _notificationPreferencesController.add(preferences);
  }

  @override
  Future<void> mergeNotificationPreferences({
    required NotificationPreferences baseline,
    required NotificationPreferences desired,
  }) async {
    await setNotificationPreferences(desired);
  }

  Future<void> close() async {
    await _appLanguageController.close();
    await _appLocalePreferenceController.close();
    await _themeController.close();
    await _timeOfDayThemeController.close();
    await _onboardingController.close();
    await _permissionEducationController.close();
    await _profileController.close();
    await _notificationPreferencesController.close();
  }
}

class FakeNotificationScheduler implements NotificationScheduler {
  int refreshCount = 0;
  int permissionRequestCount = 0;
  int clearCount = 0;
  final snoozed = <String, Duration>{};
  final cancelled = <String>[];

  @override
  Future<void> initialize() async {}

  @override
  Future<NotificationPermissionState> permissionState() async {
    return const NotificationPermissionState(notificationsEnabled: true);
  }

  @override
  Future<void> refreshSchedules() async {
    refreshCount++;
  }

  @override
  Future<void> clearAllScheduledReminders() async {
    clearCount++;
    cancelled.clear();
    snoozed.clear();
  }

  @override
  Future<void> cancelPlanReminders(String planId) async {
    cancelled.add(planId);
    snoozed.remove(planId);
  }

  @override
  Future<void> requestPermissions() async {
    permissionRequestCount++;
  }

  @override
  Future<void> sendTestReminder() async {}

  @override
  Future<void> snoozePlan(String planId, Duration duration) async {
    snoozed[planId] = duration;
  }
}

class StartupAssetRepository implements AssetRepository {
  StartupAssetRepository({required this.assets, required this.rooms});

  final List<Asset> assets;
  final List<Room> rooms;
  final List<String> savedAreaNames = [];

  @override
  Future<List<Asset>> listAssets({String? roomId}) async => roomId == null
      ? assets
      : assets.where((asset) => asset.roomId == roomId).toList();

  @override
  Future<List<Room>> listRooms({String? areaId}) async => areaId == null
      ? rooms
      : rooms.where((room) => room.areaId == areaId).toList();

  @override
  Future<List<Area>> listAreas() async => const [];

  @override
  Future<String> saveArea({
    String? id,
    required String name,
    required AreaKind kind,
    int? sortOrder,
  }) async {
    savedAreaNames.add(name.trim());
    return id ?? 'area-${savedAreaNames.length}';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeMonetizationRepository extends MonetizationRepository {
  final taskOperations = <Map<String, dynamic>>[];

  @override
  Future<PointDebitResult> createTask(Map<String, dynamic> operation) async {
    taskOperations.add(operation);
    return const PointDebitResult(
      balance: 6,
      charged: 1,
      alreadyProcessed: false,
    );
  }
}

class FakeOfflineCreationDraftStore extends OfflineCreationDraftStore {
  final drafts = <String, Map<String, dynamic>>{};

  @override
  Future<void> save(String key, Map<String, dynamic> value) async {
    drafts[key] = value;
  }

  @override
  Future<Map<String, dynamic>?> load(String key) async => drafts[key];

  @override
  Future<void> clear(String key) async {
    drafts.remove(key);
  }
}

class FakeMaintenanceRepository implements MaintenanceRepository {
  FakeMaintenanceRepository({
    this.archiveFailure,
    this.enableFailure,
    this.initialTasks = const [],
  });

  final savedTitles = <String>[];
  final archivedPlanIds = <String>[];
  final restoredPlanIds = <String>[];
  final enabledChanges = <({String planId, bool enabled})>[];
  final Object? archiveFailure;
  final Object? enableFailure;
  final List<TaskItem> initialTasks;
  var undoCount = 0;

  @override
  Stream<List<TaskItem>> watchTasks() => Stream.value(const []);

  @override
  Stream<List<TaskItem>> watchSavedTasks() => Stream.value(const []);

  @override
  Stream<List<TaskItem>> watchArchivedTasks() => Stream.value(const []);

  @override
  Stream<TaskItem?> watchTask(String planId) => Stream.value(null);

  @override
  Stream<List<TaskItem>> watchTasksForAsset(String assetId) =>
      Stream.value(const []);

  @override
  Stream<List<TaskItem>> watchSavedTasksForAsset(String assetId) =>
      Stream.value(const []);

  @override
  Future<List<TaskItem>> listTasks() async => initialTasks;

  @override
  Future<List<TaskItem>> listSavedTasks() async => const [];

  @override
  Future<List<TaskItem>> listArchivedTasks() async => const [];

  @override
  Future<TaskItem?> getTask(String planId) async => null;

  @override
  Future<List<TaskItem>> listTasksForAsset(String assetId) async => const [];

  @override
  Future<List<TaskItem>> listSavedTasksForAsset(String assetId) async =>
      const [];

  @override
  Future<String> savePlan({
    String? id,
    required String assetId,
    required String title,
    String? instructions,
    required RecurrenceRule recurrence,
    required PriorityLevel priority,
    required DateTime nextDueDate,
    int reminderDaysBefore = 0,
    TaskMetadata? metadata,
  }) async {
    savedTitles.add(title);
    return id ?? 'plan_${savedTitles.length}';
  }

  @override
  Future<bool> completePlan(
    String planId, {
    DateTime? completedAt,
    DateTime? expectedNextDueDate,
    String? notes,
  }) async => true;

  @override
  Future<LocalMaintenanceCompletionResult> completePlanResult(
    String planId, {
    DateTime? completedAt,
    DateTime? expectedNextDueDate,
    String? notes,
  }) async {
    final ok = await completePlan(
      planId,
      completedAt: completedAt,
      expectedNextDueDate: expectedNextDueDate,
      notes: notes,
    );
    final completed = completedAt ?? DateTime.now();
    final previousDue = expectedNextDueDate ?? completed;
    return LocalMaintenanceCompletionResult(
      status: ok
          ? LocalMaintenanceCompletionStatus.applied
          : LocalMaintenanceCompletionStatus.occurrenceChanged,
      operationId: ok ? 'fake-completion-$planId' : null,
      previousDueDate: ok ? previousDue : null,
      nextDueDate: ok ? previousDue.add(const Duration(days: 1)) : null,
    );
  }

  @override
  Future<void> undoCompletion({
    required String planId,
    required String completionId,
    required DateTime previousDueDate,
    required DateTime expectedCurrentNextDueDate,
  }) async {
    undoCount++;
  }

  @override
  Future<void> archivePlan(String planId) async {
    if (archiveFailure case final failure?) {
      throw failure;
    }
    archivedPlanIds.add(planId);
  }

  @override
  Future<void> restorePlan(String planId) async {
    restoredPlanIds.add(planId);
  }

  @override
  Future<void> setTaskEnabled(String planId, bool enabled) async {
    if (enableFailure case final failure?) {
      throw failure;
    }
    enabledChanges.add((planId: planId, enabled: enabled));
  }

  @override
  Future<void> skipPlanOccurrence(
    String planId, {
    DateTime? skippedAt,
    String? reason,
  }) async {}

  @override
  Future<void> postponePlan(
    String planId,
    DateTime nextDueDate, {
    String? reason,
  }) async {}

  @override
  Future<void> deletePlan(String planId) async {}

  @override
  Future<List<MaintenanceRecord>> listRecordsForPlan(String planId) async =>
      const [];

  @override
  Stream<List<MaintenanceRecord>> watchRecordsForPlan(String planId) =>
      Stream.value(const []);

  @override
  Stream<List<MaintenanceRecord>> watchRecordsForAsset(String assetId) =>
      Stream.value(const []);

  @override
  Future<List<MaintenanceRecord>> listRecordsForAsset(String assetId) async =>
      const [];
}

class FakeStreakService implements StreakService {
  var refreshCount = 0;

  @override
  Future<StreakState> current() async =>
      StreakState(currentStreak: 0, bestStreak: 0, updatedAt: DateTime(2026));

  @override
  Future<StreakState> refresh(DateTime now) async {
    refreshCount++;
    return StreakState(currentStreak: 0, bestStreak: 0, updatedAt: now);
  }
}

class CountingWeatherRepository implements WeatherRepository {
  CountingWeatherRepository({this.deviceLocation, this.settingsRepository});

  final HomeLocation? deviceLocation;
  final FakeSettingsRepository? settingsRepository;
  var refreshCount = 0;
  var useDeviceLocationCount = 0;

  @override
  Future<WeatherSnapshot?> cachedWeather() async => null;

  @override
  Future<WeatherSnapshot?> refreshWeather() async {
    refreshCount++;
    return null;
  }

  @override
  Future<List<HomeLocation>> searchLocations(String query) async => const [];

  @override
  Future<HomeLocation?> useDeviceLocation() async {
    useDeviceLocationCount++;
    if (deviceLocation != null) {
      await settingsRepository?.setHomeLocation(deviceLocation);
    }
    return deviceLocation;
  }

  @override
  Future<HomeLocation?> useCurrentLocationHomeArea() async =>
      useDeviceLocation();

  @override
  Stream<WeatherSnapshot?> watchWeather() => const Stream.empty();
}

class HangingWeatherRepository implements WeatherRepository {
  final releaseRefresh = Completer<void>();
  var refreshCount = 0;

  @override
  Future<WeatherSnapshot?> cachedWeather() async => null;

  @override
  Future<WeatherSnapshot?> refreshWeather() async {
    refreshCount++;
    await releaseRefresh.future;
    return null;
  }

  @override
  Future<List<HomeLocation>> searchLocations(String query) async => const [];

  @override
  Future<HomeLocation?> useDeviceLocation() async => null;

  @override
  Future<HomeLocation?> useCurrentLocationHomeArea() async =>
      useDeviceLocation();

  @override
  Stream<WeatherSnapshot?> watchWeather() => const Stream.empty();
}
