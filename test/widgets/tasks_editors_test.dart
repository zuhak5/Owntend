import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:owntend/main.dart';
import 'package:owntend/src/core/domain/models.dart';
import 'package:owntend/src/core/sync/sync_connectivity.dart';
import 'package:owntend/src/features/maintenance/application/task_creation_controller.dart';
import 'package:owntend/src/core/services/charged_operation_journal/charged_operation_store.dart';
import 'package:owntend/src/features/monetization/monetization.dart';
import 'package:owntend/l10n/app_localizations.dart';
import 'package:owntend/src/core/services/feedback_messenger.dart';
import 'package:owntend/src/ui/feedback/feedback_coordinator.dart';
import 'package:owntend/src/ui/components.dart' as hk_ui;
import 'package:material_symbols_icons/symbols.dart';

import '../support/widget_test_fakes.dart';
import '../test_theme.dart';

void main() {
  setUp(() {
    addTearDown(FeedbackCoordinator.instance.resetForTesting);
    addTearDown(() {
      try {
        hkRootScaffoldMessengerKey.currentState?.clearSnackBars();
      } catch (_) {}
    });
    addTearDown(
      TestWidgetsFlutterBinding
          .instance
          .platformDispatcher
          .clearAccessibilityFeaturesTestValue,
    );
    FeedbackCoordinator.instance.resetForTesting();
    try {
      hkRootScaffoldMessengerKey.currentState?.clearSnackBars();
    } catch (_) {}
    TestWidgetsFlutterBinding
            .instance
            .platformDispatcher
            .accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures();
  });

  group('editor sheets', () {
    testWidgets('editor sheets keep their header next to the drag handle', (
      tester,
    ) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;

      final settings = FakeSettingsRepository(onboardingCompletedValue: true);
      addTearDown(settings.close);
      final cases = <(String, String, void Function(BuildContext))>[
        (
          'Add room',
          'Create room',
          (context) => showRoomEditorSheet(context, areaId: 'area_first_floor'),
        ),
        (
          'Add item',
          'Create item',
          (context) => showAssetEditorSheet(context, roomId: 'room_kitchen'),
        ),
        (
          'Add task',
          'Create task',
          (context) =>
              showPlanEditorSheet(context, assetId: 'asset_dishwasher'),
        ),
      ];

      for (final sheetCase in cases) {
        await tester.pumpWidget(
          ProviderScope(
            overrides: testOverrides(settings),
            child: MaterialApp(
              theme: testLightTheme(),
              home: Builder(
                builder: (context) => Scaffold(
                  body: TextButton(
                    onPressed: () => sheetCase.$3(context),
                    child: const Text('Open editor'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open editor'));
        await tester.pumpAndSettle();

        final handle = find.byKey(const ValueKey('editor-sheet-drag-handle'));
        expect(handle, findsOneWidget);
        final bottomSheet = tester.widget<BottomSheet>(
          find.byType(BottomSheet),
        );
        expect(bottomSheet.showDragHandle, isFalse);
        expect(find.text(sheetCase.$1), findsOneWidget);
        expect(find.text(sheetCase.$2), findsOneWidget);
        final gap =
            tester.getTopLeft(find.text(sheetCase.$1)).dy -
            tester.getBottomLeft(handle).dy;
        expect(gap, lessThan(64));
        expect(tester.takeException(), isNull);

        await tester.tap(find.byTooltip('Close'));
        await tester.pumpAndSettle();
      }
    });

    testWidgets('editor save remains hittable above the software keyboard', (
      tester,
    ) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;

      final settings = FakeSettingsRepository(onboardingCompletedValue: true);
      addTearDown(settings.close);
      final repository = StartupAssetRepository(
        assets: const [],
        rooms: const [],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: testOverrides(settings, assetRepository: repository),
          child: MaterialApp(
            theme: testLightTheme(),
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => showAreaEditorSheet(context),
                  child: const Text('Open editor'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open editor'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'Keyboard area');
      tester.view.viewInsets = const FakeViewPadding(bottom: 320);
      await tester.pumpAndSettle();

      final hitSurface = find.byKey(const ValueKey('editor-modal-hit-surface'));
      expect(hitSurface, findsOneWidget);
      expect(tester.getSize(hitSurface).height, closeTo(844, 1));
      final save = find.text('Create area');
      expect(save, findsOneWidget);
      expect(tester.getBottomLeft(save).dy, lessThan(524));
      await tester.tap(save);
      await tester.pumpAndSettle();

      expect(repository.savedAreaNames, ['Keyboard area']);
      expect(find.text('Create area'), findsNothing);
    });
  });

  group('task card completion', () {
    testWidgets('TaskCard animates completion and blocks duplicate taps', (
      tester,
    ) async {
      final result = Completer<bool>();
      var completionCalls = 0;
      final task = makeTaskItem(
        DateUtils.dateOnly(DateTime.now()),
        id: 'animated_completion',
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: testLightTheme(),
          home: Scaffold(
            body: hk_ui.TaskCard(
              task: task,
              onComplete: () {
                completionCalls++;
                return result.future;
              },
            ),
          ),
        ),
      );

      await tester.tap(find.byTooltip('Complete task'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 260));
      expect(completionCalls, 1);
      expect(
        find.byKey(const ValueKey('task-completion-sweep')),
        findsOneWidget,
      );

      await tester.tap(find.byTooltip('Complete task'), warnIfMissed: false);
      await tester.pump();
      expect(completionCalls, 1);

      result.complete(false);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('task-completion-sweep')), findsNothing);
    });
  });

  group('swipe delete rows', () {
    testWidgets(
      'SwipeDelete labels trash action and restores below threshold',
      (tester) async {
        var calls = 0;
        await pumpSwipeRows(
          tester,
          rows: [
            swipeTestRow(
              'label',
              onAction: () async {
                calls++;
                return true;
              },
            ),
          ],
        );

        final row = find.byKey(const ValueKey('swipe-row-label'));
        final gesture = await tester.startGesture(tester.getCenter(row));
        await gesture.moveBy(const Offset(-70, 0));
        await tester.pump();

        expect(find.text('Move to Trash'), findsOneWidget);
        expect(find.text('Swipe to move to Trash'), findsOneWidget);
        expect(find.text('Review'), findsNothing);
        expect(find.text('Release to review'), findsNothing);

        await gesture.up();
        await tester.pumpAndSettle();

        expect(calls, 0);
        expect(row, findsOneWidget);
        expect(find.text('Move to Trash'), findsNothing);
      },
    );

    testWidgets('SwipeDelete closes before running threshold action', (
      tester,
    ) async {
      var calls = 0;
      var backgroundClosedWhenActionStarted = false;
      await pumpSwipeRows(
        tester,
        rows: [
          swipeTestRow(
            'confirm',
            onAction: () async {
              calls++;
              backgroundClosedWhenActionStarted =
                  find.text('Move to Trash').evaluate().isEmpty &&
                  find.text('Swipe to move to Trash').evaluate().isEmpty &&
                  find.text('Release to move to Trash').evaluate().isEmpty;
              return false;
            },
          ),
        ],
      );

      await tester.drag(
        find.byKey(const ValueKey('swipe-row-confirm')),
        const Offset(-500, 0),
      );
      await tester.pump(const Duration(milliseconds: 1500));
      expect(calls, 1);
      expect(backgroundClosedWhenActionStarted, isTrue);
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('swipe-row-confirm')), findsOneWidget);
      expect(find.text('Move to Trash'), findsNothing);
    });

    testWidgets('SwipeDelete restores row when threshold action fails', (
      tester,
    ) async {
      var calls = 0;
      await pumpSwipeRows(
        tester,
        rows: [
          swipeTestRow(
            'failure',
            onAction: () async {
              calls++;
              throw StateError('unavailable');
            },
          ),
        ],
      );

      await tester.drag(
        find.byKey(const ValueKey('swipe-row-failure')),
        const Offset(-500, 0),
      );
      await waitForSwipeBackgroundToClose(tester);
      await tester.pump(const Duration(milliseconds: 800));
      await tester.pumpAndSettle();

      expect(calls, 1);
      expect(find.byKey(const ValueKey('swipe-row-failure')), findsOneWidget);
      expect(find.text('Move to Trash'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('SwipeDelete keeps only one row visually open', (tester) async {
      await pumpSwipeRows(
        tester,
        rows: [
          swipeTestRow('first', onAction: () async => true),
          swipeTestRow('second', onAction: () async => true),
        ],
      );

      final first = find.byKey(const ValueKey('swipe-row-first'));
      final second = find.byKey(const ValueKey('swipe-row-second'));
      final firstGesture = await tester.startGesture(tester.getCenter(first));
      await firstGesture.moveBy(const Offset(-70, 0));
      await tester.pump();
      expect(find.text('Move to Trash'), findsOneWidget);

      final secondGesture = await tester.startGesture(tester.getCenter(second));
      await secondGesture.moveBy(const Offset(-70, 0));
      await tester.pump();
      expect(find.text('Move to Trash'), findsOneWidget);

      await firstGesture.up();
      await secondGesture.up();
      await tester.pumpAndSettle();
      expect(find.text('Move to Trash'), findsNothing);
    });

    testWidgets('SwipeDelete mirrors trailing swipe direction in RTL', (
      tester,
    ) async {
      var calls = 0;
      await pumpSwipeRows(
        tester,
        locale: const Locale('ar'),
        rows: [
          swipeTestRow(
            'rtl',
            onAction: () async {
              calls++;
              return false;
            },
          ),
        ],
      );

      await tester.drag(
        find.byKey(const ValueKey('swipe-row-rtl')),
        const Offset(500, 0),
      );
      await tester.pump(const Duration(milliseconds: 1500));
      await tester.pumpAndSettle();

      expect(calls, 1);
      expect(find.byKey(const ValueKey('swipe-row-rtl')), findsOneWidget);
    });
  });

  group('task card states', () {
    testWidgets('TaskCard shows disabled state and enable action', (
      tester,
    ) async {
      final changes = <bool>[];
      final task = makeTaskItem(
        DateUtils.dateOnly(DateTime.now()),
        id: 'disabled_card',
        isEnabled: false,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: testLightTheme(),
          home: Scaffold(
            body: hk_ui.TaskCard(
              task: task,
              onComplete: () async => true,
              onSnooze: () {},
              onSetEnabled: (enabled) async => changes.add(enabled),
              onArchive: () {},
            ),
          ),
        ),
      );

      expect(find.text('Disabled'), findsOneWidget);
      expect(find.byTooltip('Complete task'), findsNothing);

      await tester.tap(find.byTooltip('Task actions'));
      await tester.pumpAndSettle();

      expect(find.text('Enable task'), findsOneWidget);
      expect(find.text('Snooze'), findsNothing);
      expect(find.text('Move task to Trash'), findsOneWidget);

      await tester.tap(find.text('Enable task'));
      await tester.pump();

      expect(changes, [true]);
    });
  });

  group('task audio feedback', () {
    testWidgets('custom task feedback audio assets are packaged WAV files', (
      tester,
    ) async {
      for (final path in [
        'assets/audio/task_done.wav',
        'assets/audio/task_delete.wav',
      ]) {
        final bytes = await rootBundle.load(path);
        expect(bytes.lengthInBytes, greaterThan(44));
        expect(String.fromCharCodes(bytes.buffer.asUint8List(0, 4)), 'RIFF');
      }
    });
  });

  group('tasks screen', () {
    testWidgets('tasks screen groups work by urgency and shows locations', (
      tester,
    ) async {
      final settings = FakeSettingsRepository(onboardingCompletedValue: true);
      addTearDown(settings.close);
      final now = DateUtils.dateOnly(DateTime.now());
      final tasks = [
        makeTaskItem(
          now.subtract(const Duration(days: 1)),
          id: 'plan_overdue',
          title: 'Replace filter',
          status: TaskStatus.overdue,
        ),
        makeTaskItem(now, id: 'plan_today', status: TaskStatus.dueToday),
        makeTaskItem(
          now.add(const Duration(days: 1)),
          id: 'plan_tomorrow',
          title: 'Flush heater',
          status: TaskStatus.upcoming,
        ),
        makeTaskItem(
          now.add(const Duration(days: 3)),
          id: 'plan_next',
          title: 'Clean vent',
          status: TaskStatus.upcoming,
        ),
        makeTaskItem(
          now.add(const Duration(days: 20)),
          id: 'plan_later',
          title: 'Service pump',
          status: TaskStatus.upcoming,
        ),
      ];

      await tester.pumpWidget(
        ProviderScope(
          overrides: testOverrides(settings, tasks: tasks),
          child: const OwntendApp(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tasks').last);
      await tester.pumpAndSettle();

      expect(find.text('Overdue'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.byType(hk_ui.HkStateIllustration),
        ),
        findsNothing,
      );
      expect(find.text('Today'), findsOneWidget);
      expect(find.text('Tomorrow'), findsOneWidget);
      expect(find.text('Next 7 days'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Today')).dy,
        lessThan(tester.getTopLeft(find.text('Tomorrow')).dy),
      );
      expect(
        tester.getTopLeft(find.text('Tomorrow')).dy,
        lessThan(tester.getTopLeft(find.text('Next 7 days')).dy),
      );
      expect(find.text('1 task'), findsAtLeastNWidgets(3));
      expect(find.text('Fish · Kitchen'), findsWidgets);
      expect(find.text('Due now'), findsOneWidget);
      expect(find.text('Overdue by 1 day'), findsOneWidget);

      await tester.drag(find.byType(ListView).last, const Offset(0, -500));
      await tester.pumpAndSettle();

      expect(find.text('Later'), findsOneWidget);
      expect(find.text('1 task'), findsAtLeastNWidgets(3));
      expect(tester.takeException(), isNull);
    });

    testWidgets('tapping a task opens task detail', (tester) async {
      final settings = FakeSettingsRepository(onboardingCompletedValue: true);
      addTearDown(settings.close);
      final task = makeTaskItem(
        DateUtils.dateOnly(DateTime.now()),
        id: 'plan_today',
        title: 'Replace filter',
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: testOverrides(settings, tasks: [task]),
          child: const OwntendApp(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tasks').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Replace filter').first);
      await tester.pumpAndSettle();

      expect(find.text('Next due'), findsOneWidget);
      expect(find.text('Timeline'), findsOneWidget);
      expect(find.text('Open item'), findsOneWidget);
    });

    testWidgets('task detail disables task and cancels reminders', (
      tester,
    ) async {
      final settings = FakeSettingsRepository(onboardingCompletedValue: true);
      addTearDown(settings.close);
      final scheduler = FakeNotificationScheduler();
      final task = makeTaskItem(
        DateUtils.dateOnly(DateTime.now()),
        id: 'plan_disable',
        title: 'Replace filter',
      );
      final maintenance = FakeMaintenanceRepository(initialTasks: [task]);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...testOverrides(
              settings,
              tasks: [task],
              notificationScheduler: scheduler,
              maintenanceRepository: maintenance,
            ),
          ],
          child: const OwntendApp(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tasks').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Replace filter').first);
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Task actions').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Disable task'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(maintenance.enabledChanges, [
        (planId: 'plan_disable', enabled: false),
      ]);
      expect(scheduler.cancelled, ['plan_disable']);
      expect(scheduler.refreshCount, 1);
      expect(find.text('Task disabled.'), findsOneWidget);
    });
  });

  group('rooms and items', () {
    testWidgets('room detail opens grouped items', (tester) async {
      final settings = FakeSettingsRepository(onboardingCompletedValue: true);
      addTearDown(settings.close);

      await tester.pumpWidget(
        ProviderScope(
          overrides: testOverrides(settings),
          child: const OwntendApp(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rooms').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kitchen').first);
      await tester.pumpAndSettle();

      expect(find.textContaining('Devices & Appliances'), findsOneWidget);
      expect(find.text('Dishwasher'), findsOneWidget);
      expect(find.text('Basil'), findsOneWidget);
    });

    testWidgets('tapping an item opens item detail', (tester) async {
      final settings = FakeSettingsRepository(onboardingCompletedValue: true);
      addTearDown(settings.close);

      await tester.pumpWidget(
        ProviderScope(
          overrides: testOverrides(settings),
          child: const OwntendApp(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rooms').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kitchen').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dishwasher').first);
      await tester.pumpAndSettle();

      expect(find.text('Related tasks'), findsOneWidget);
      expect(find.text('No tasks yet'), findsOneWidget);
      final addPhoto = find.byKey(const ValueKey('item-add-photo'));
      final addTask = find.byKey(const ValueKey('item-add-task'));
      expect(tester.getSize(addPhoto), tester.getSize(addTask));
      expect(
        tester.getCenter(addPhoto).dy,
        closeTo(tester.getCenter(addTask).dy, 1),
      );
      final photoIcon = find.descendant(
        of: addPhoto,
        matching: find.byIcon(Symbols.add_photo_alternate_rounded),
      );
      final photoLabel = find.descendant(
        of: addPhoto,
        matching: find.text('Add photo'),
      );
      final taskIcon = find.descendant(
        of: addTask,
        matching: find.byIcon(Symbols.add_task_rounded),
      );
      final taskLabel = find.descendant(
        of: addTask,
        matching: find.text('Add task'),
      );
      final photoContentCenter =
          (tester.getTopLeft(photoIcon).dx +
              tester.getBottomRight(photoLabel).dx) /
          2;
      final taskContentCenter =
          (tester.getTopLeft(taskIcon).dx +
              tester.getBottomRight(taskLabel).dx) /
          2;
      expect(photoContentCenter, closeTo(tester.getCenter(addPhoto).dx, 1));
      expect(taskContentCenter, closeTo(tester.getCenter(addTask).dx, 1));
      expect(
        tester.getCenter(photoIcon).dy,
        closeTo(tester.getCenter(photoLabel).dy, 1),
      );
      expect(
        tester.getCenter(taskIcon).dy,
        closeTo(tester.getCenter(taskLabel).dy, 1),
      );
    });
  });

  group('item and task editors', () {
    testWidgets('item editor renders dynamic detail fields', (tester) async {
      final cases = <AssetType, List<String>>{
        AssetType.device: ['Device details', 'Brand', 'Power source'],
        AssetType.pet: ['Pet details', 'Pet Type', 'Breed', 'Vet phone'],
        AssetType.plant: ['Plant details', 'Sunlight', 'Watering interval'],
        AssetType.safety: ['Safety details', 'Safety type', 'Test interval'],
        AssetType.general: ['Item type', 'Placement', 'Tags'],
      };

      for (final entry in cases.entries) {
        final settings = FakeSettingsRepository(onboardingCompletedValue: true);
        final asset = makeThing('thing_${entry.key.name}', 'Sample', entry.key);
        addTearDown(settings.close);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              ...testOverrides(settings),
              assetTagsProvider(asset.id)
                  .overrideWithValue(const AsyncData([])),
            ],
            child: MaterialApp(
              theme: testLightTheme(),
              home: Scaffold(
                body: AssetEditorDialog(asset: asset, roomId: 'room_kitchen'),
              ),
            ),
          ),
        );
        await tester.pump();

        for (final label in entry.value) {
          expect(find.text(label), findsOneWidget);
        }
        if (entry.key == AssetType.pet) {
          final currentPetType = find.text('Cat');
          await tester.ensureVisible(currentPetType);
          await tester.pumpAndSettle();
          await tester.tap(currentPetType);
          await tester.pumpAndSettle();
          await tester.tap(find.text('Fish').last);
          await tester.pumpAndSettle();
          expect(find.text('Fish Type'), findsOneWidget);
          expect(find.text('Goldfish'), findsOneWidget);
        }
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(const SizedBox.shrink());
      }
    });

    testWidgets('task editor can create and add another task', (tester) async {
      final maintenance = FakeMaintenanceRepository();
      final monetization = FakeMonetizationRepository();
      final drafts = FakeOfflineCreationDraftStore();
      final now = DateTime(2026);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            maintenanceRepositoryProvider.overrideWithValue(maintenance),
            monetizationRepositoryProvider.overrideWithValue(monetization),
            taskCreationOperationStoreProvider.overrideWithValue(
              TaskCreationOperationStore(),
            ),
            offlineCreationDraftStoreProvider.overrideWithValue(drafts),
            syncConnectivityInstanceProvider.overrideWithValue(
              const AlwaysOnlineSyncConnectivity(),
            ),
            notificationSchedulerProvider.overrideWithValue(
              FakeNotificationScheduler(),
            ),
            assetsProvider.overrideWithValue(AsyncData(makeThings(now))),
          ],
          child: MaterialApp(
            theme: testLightTheme(),
            home: const Scaffold(
              body: PlanEditorDialog(assetId: 'asset_dishwasher'),
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.enterText(
        find.widgetWithText(TextField, 'Task title'),
        'Clean seals',
      );
      await tester.pump();
      final createAnother = find.widgetWithText(
        OutlinedButton,
        'Create & add another',
      );
      expect(tester.widget<OutlinedButton>(createAnother).onPressed, isNotNull);
      tester.widget<OutlinedButton>(createAnother).onPressed!();
      for (
        var attempt = 0;
        attempt < 20 && maintenance.savedTitles.isEmpty;
        attempt++
      ) {
        await tester.pump(const Duration(milliseconds: 10));
      }
      expect(maintenance.savedTitles, ['Clean seals']);
      expect(find.text('Task created.'), findsOneWidget);
      final titleField = tester.widget<TextField>(
        find.widgetWithText(TextField, 'Task title'),
      );
      expect(titleField.controller?.text, isEmpty);

      await tester.enterText(
        find.widgetWithText(TextField, 'Task title'),
        'Check hoses',
      );
      await tester.pump();
      tester.widget<OutlinedButton>(createAnother).onPressed!();
      for (
        var attempt = 0;
        attempt < 20 && maintenance.savedTitles.length < 2;
        attempt++
      ) {
        await tester.pump(const Duration(milliseconds: 10));
      }

      expect(maintenance.savedTitles, ['Clean seals', 'Check hoses']);
    });
  });

  group('point shortage dialog', () {
    testWidgets(
      'point shortage dialog remains visible when rewards are unavailable',
      (tester) async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              monetizationConfigProvider.overrideWithValue(
                const AsyncData(MonetizationConfig.failClosed()),
              ),
              pointWalletProvider.overrideWithValue(
                AsyncData(
                  PointWallet(
                    balance: 0,
                    timeZone: 'Asia/Baghdad',
                    updatedAt: DateTime.utc(2026, 8, 9),
                  ),
                ),
              ),
              monetizationRepositoryProvider.overrideWithValue(null),
            ],
            child: MaterialApp(
              locale: const Locale('en'),
              supportedLocales: AppLocalizations.supportedLocales,
              localizationsDelegates: const [
                AppLocalizations.delegate,
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              theme: testLightTheme(),
              home: Scaffold(
                body: Consumer(
                  builder: (context, ref, _) => FilledButton(
                    onPressed: () => showPointShortageDialog(
                      context,
                      ref,
                      attemptedAction: 'task',
                    ),
                    child: const Text('Create task'),
                  ),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Create task'));
        await tester.pumpAndSettle();
        expect(find.text('You need 1 point'), findsOneWidget);

        await tester.tap(find.byKey(const ValueKey('point-shortage-watch-ad')));
        await tester.pump();

        expect(find.byType(AlertDialog), findsOneWidget);
        expect(
          find.text('Point rewards are temporarily unavailable.'),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('point-shortage-status')),
          findsOneWidget,
        );
        expect(find.text('Keep editing'), findsOneWidget);
      },
    );
  });
}
