import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:owntend/main.dart';
import 'package:owntend/src/core/domain/models.dart';
import 'package:owntend/l10n/app_localizations.dart';
import 'package:owntend/src/core/services/feedback_messenger.dart';
import 'package:owntend/src/ui/feedback/feedback_coordinator.dart';
import 'package:intl/intl.dart' hide TextDirection;

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

  group('statistics chart legend', () {
    testWidgets('statistics distribution legend uses two centered lines', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: testLightTheme(),
          home: const Scaffold(
            body: SizedBox(
              width: 260,
              height: 260,
              child: TaskDistributionChart(
                data: {
                  AssetType.device: 6,
                  AssetType.plant: 5,
                  AssetType.pet: 4,
                  AssetType.safety: 3,
                  AssetType.general: 3,
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final labels = [
        'Device or appliance 6',
        'Plant 5',
        'Pet 4',
        'Safety item 3',
        'General item 3',
      ];
      final firstRowY = tester.getCenter(find.text(labels[0])).dy;
      final secondRowY = tester.getCenter(find.text(labels[3])).dy;

      for (final label in labels) {
        expect(find.text(label), findsOneWidget);
        expect(
          find.ancestor(
            of: find.text(label),
            matching: find.byType(SingleChildScrollView),
          ),
          findsNothing,
        );
      }
      for (final label in labels.take(3)) {
        expect(tester.getCenter(find.text(label)).dy, closeTo(firstRowY, 1));
      }
      for (final label in labels.skip(3)) {
        expect(tester.getCenter(find.text(label)).dy, closeTo(secondRowY, 1));
      }
      expect(secondRowY, greaterThan(firstRowY));
      expect(tester.takeException(), isNull);
    });
  });

  group('task trash flows', () {
    testWidgets('swiping moves a task to Trash with countdown and Undo', (
      tester,
    ) async {
      final settings = FakeSettingsRepository(onboardingCompletedValue: true);
      addTearDown(settings.close);
      final task = makeTaskItem(
        DateUtils.dateOnly(DateTime.now()),
        id: 'plan_today',
      );
      final maintenance = FakeMaintenanceRepository(initialTasks: [task]);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...testOverrides(
              settings,
              tasks: [task],
              maintenanceRepository: maintenance,
            ),
          ],
          child: const OwntendApp(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tasks').last);
      await tester.pumpAndSettle();
      await dragSwipeRowPastThreshold(
        tester,
        find.byKey(const ValueKey('task-delete-plan_today')),
        dialogTitle: 'Move task to Trash?',
      );

      expect(find.text('Move task to Trash?'), findsOneWidget);
      await tester.tap(find.text('Move to Trash'));
      await tester.pumpAndSettle();
      expect(maintenance.archivedPlanIds, ['plan_today']);
      expect(find.text('Task moved to Trash.'), findsOneWidget);
      expect(find.text('Undo'), findsOneWidget);
      await tester.tap(find.text('Undo'));
      for (var index = 0; index < 4; index++) {
        await tester.pump();
      }
      expect(maintenance.restoredPlanIds, ['plan_today']);
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
    });

    testWidgets('Trash Undo expires without permanently deleting the task', (
      tester,
    ) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures();
      final settings = FakeSettingsRepository(onboardingCompletedValue: true);
      addTearDown(settings.close);
      final task = makeTaskItem(
        DateUtils.dateOnly(DateTime.now()),
        id: 'plan_expiry',
      );
      final maintenance = FakeMaintenanceRepository(initialTasks: [task]);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...testOverrides(
              settings,
              tasks: [task],
              maintenanceRepository: maintenance,
            ),
          ],
          child: const OwntendApp(),
        ),
      );
      FeedbackCoordinator.instance.resetForTesting();
      hkRootScaffoldMessengerKey.currentState?.clearSnackBars();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tasks').last);
      await tester.pumpAndSettle();
      await dragSwipeRowPastThreshold(
        tester,
        find.byKey(const ValueKey('task-delete-plan_expiry')),
        dialogTitle: 'Move task to Trash?',
      );
      expect(find.text('Move task to Trash?'), findsOneWidget);
      await tester.tap(find.text('Move to Trash'));
      await tester.pumpAndSettle();
      expect(find.text('Task moved to Trash.'), findsOneWidget);

      hkRootScaffoldMessengerKey.currentState?.hideCurrentSnackBar();
      await tester.pumpAndSettle();
      await tester.pump();
      expect(find.text('Task moved to Trash.'), findsNothing);
      expect(maintenance.archivedPlanIds, ['plan_expiry']);
      expect(maintenance.restoredPlanIds, isEmpty);
    });

    testWidgets('cancelled swipe confirmation leaves the task active', (
      tester,
    ) async {
      final settings = FakeSettingsRepository(onboardingCompletedValue: true);
      addTearDown(settings.close);
      final task = makeTaskItem(
        DateUtils.dateOnly(DateTime.now()),
        id: 'plan_cancelled',
      );
      final maintenance = FakeMaintenanceRepository(initialTasks: [task]);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...testOverrides(
              settings,
              tasks: [task],
              maintenanceRepository: maintenance,
            ),
          ],
          child: const OwntendApp(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tasks').last);
      await tester.pumpAndSettle();
      final row = find.byKey(const ValueKey('task-delete-plan_cancelled'));
      await dragSwipeRowPastThreshold(
        tester,
        row,
        dialogTitle: 'Move task to Trash?',
      );

      expect(find.text('Move task to Trash?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(maintenance.archivedPlanIds, isEmpty);
      expect(row, findsOneWidget);
      expect(find.text('Task moved to Trash.'), findsNothing);
      expect(find.text('Move to Trash'), findsNothing);
    });

    testWidgets('swipe archive failure leaves the task active and reports it', (
      tester,
    ) async {
      final settings = FakeSettingsRepository(onboardingCompletedValue: true);
      addTearDown(settings.close);
      final task = makeTaskItem(
        DateUtils.dateOnly(DateTime.now()),
        id: 'plan_failure',
      );
      final maintenance = FakeMaintenanceRepository(
        archiveFailure: StateError('archive unavailable'),
        initialTasks: [task],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...testOverrides(
              settings,
              tasks: [task],
              maintenanceRepository: maintenance,
            ),
          ],
          child: const OwntendApp(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tasks').last);
      await tester.pumpAndSettle();
      await dragSwipeRowPastThreshold(
        tester,
        find.byKey(const ValueKey('task-delete-plan_failure')),
        dialogTitle: 'Move task to Trash?',
      );

      expect(find.text('Move task to Trash?'), findsOneWidget);
      await tester.tap(find.text('Move to Trash'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        find.text(
          lookupAppLocalizations(const Locale('en'))
              .theTaskCouldNotBeUpdatedPleaseTryAgain,
        ),
        findsOneWidget,
      );
      expect(find.text('Task moved to Trash.'), findsNothing);
      expect(find.text('Move to Trash'), findsNothing);
      expect(maintenance.archivedPlanIds, isEmpty);
      expect(maintenance.restoredPlanIds, isEmpty);
    });
  });

  group('calendar grid', () {
    testWidgets(
      'calendar renders an aligned month grid and selected day tasks',
      (tester) async {
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;

        final settings = FakeSettingsRepository(onboardingCompletedValue: true);
        addTearDown(settings.close);
        final today = DateUtils.dateOnly(DateTime.now());
        final task = makeTaskItem(today);
        final tomorrowTask = makeTaskItem(
          today.add(const Duration(days: 1)),
          id: 'plan_calendar_tomorrow',
          title: 'Tomorrow calendar task',
          status: TaskStatus.upcoming,
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: testOverrides(settings, tasks: [task, tomorrowTask]),
            child: const OwntendApp(),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Calendar').last);
        await tester.pumpAndSettle();

        expect(
          find.text(
            DateFormat.yMMMM().format(DateTime(today.year, today.month)),
          ),
          findsOneWidget,
        );
        for (final weekday in [
          'Sun',
          'Mon',
          'Tue',
          'Wed',
          'Thu',
          'Fri',
          'Sat',
        ]) {
          expect(find.text(weekday), findsOneWidget);
        }
        expect(
          find.byKey(ValueKey('calendar-day-${today.toIso8601String()}')),
          findsOneWidget,
        );
        expect(
          find.text(DateFormat.yMMMMEEEEd().format(today)),
          findsOneWidget,
        );
        expect(find.text('Feed the fish'), findsOneWidget);
        expect(find.text('Tomorrow calendar task'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  });
}
