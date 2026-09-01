import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:owntend/main.dart';
import 'package:owntend/l10n/app_localizations.dart';
import 'package:owntend/src/core/services/native_capabilities.dart';
import 'package:owntend/src/core/services/feedback_messenger.dart';
import 'package:owntend/src/ui/feedback/feedback_coordinator.dart';
import 'package:owntend/src/ui/components.dart' as hk_ui;

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

  group('toast feedback', () {
    testWidgets(
      'app toasts use standard durations and replace stale messages',
      (tester) async {
        late BuildContext toastContext;
        await tester.pumpWidget(
          MaterialApp(
            theme: testLightTheme(),
            home: Scaffold(
              body: Builder(
                builder: (context) {
                  toastContext = context;
                  return const SizedBox();
                },
              ),
            ),
          ),
        );

        hk_ui.showToast(toastContext, content: const Text('First message'));
        await tester.pump();
        expect(find.text('First message'), findsOneWidget);

        hk_ui.showToast(
          toastContext,
          content: const Text('Undo message'),
          action: SnackBarAction(label: 'Undo', onPressed: () {}),
        );
        await tester.pumpAndSettle();
        expect(find.text('First message'), findsNothing);
        expect(find.text('Undo message'), findsOneWidget);

        hk_ui.showToast(
          toastContext,
          content: const Text('Error message'),
          severity: hk_ui.HkToastSeverity.error,
        );
        await tester.pumpAndSettle();
        expect(find.text('Undo message'), findsNothing);
        expect(find.text('Error message'), findsOneWidget);
      },
    );
  });

  group('task deletion snackbars', () {
    testWidgets('task deletion snackbar uses semantic colors in both themes', (
      tester,
    ) async {
      for (final theme in [testLightTheme(), testDarkTheme()]) {
        late BuildContext toastContext;
        await tester.pumpWidget(
          MaterialApp(
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            theme: theme,
            home: Scaffold(
              body: Builder(
                builder: (context) {
                  toastContext = context;
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
        );

        hk_ui.showTaskMovedToTrashSnackBar(toastContext, onUndo: () {});
        await tester.pumpAndSettle();

        final snackBar = tester.widget<SnackBar>(find.byType(SnackBar));
        expect(snackBar.behavior, SnackBarBehavior.floating);
        expect(find.text('Task moved to Trash.'), findsOneWidget);
        expect(find.text('Undo'), findsOneWidget);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        FeedbackCoordinator.instance.resetForTesting();
      }
    });

    testWidgets('task deletion snackbars queue undo callbacks', (tester) async {
      late BuildContext toastContext;
      var firstUndoCount = 0;
      var secondUndoCount = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: testLightTheme(),
          home: Scaffold(
            body: Builder(
              builder: (context) {
                toastContext = context;
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );

      hk_ui.showTaskMovedToTrashSnackBar(
        toastContext,
        onUndo: () => firstUndoCount++,
      );
      await tester.pump();
      hk_ui.showTaskMovedToTrashSnackBar(
        toastContext,
        onUndo: () => secondUndoCount++,
      );
      await tester.pump();

      expect(find.byType(SnackBar), findsOneWidget);
      FeedbackCoordinator.instance.handleAction();
      await tester.pump();

      expect(firstUndoCount, 1);
      expect(secondUndoCount, 1);
    });

    testWidgets(
      'task deletion snackbar fits narrow large-text layout without overflow',
      (tester) async {
        tester.view.physicalSize = const Size(320, 700);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = 1.8;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

        late BuildContext toastContext;
        await tester.pumpWidget(
          MaterialApp(
            theme: testLightTheme(),
            home: Scaffold(
              body: Builder(
                builder: (context) {
                  toastContext = context;
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
        );

        hk_ui.showTaskMovedToTrashSnackBar(toastContext, onUndo: () {});
        await tester.pump();

        final snackBar = find.byType(SnackBar);
        expect(snackBar, findsOneWidget);
        expect(tester.getTopLeft(snackBar).dx, greaterThanOrEqualTo(0));
        expect(tester.getBottomRight(snackBar).dx, lessThanOrEqualTo(320));
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('task completion toast', () {
    testWidgets('task completion toast keeps Undo with action timing', (
      tester,
    ) async {
      final streak = FakeStreakService();
      final task = makeTaskItem(DateTime(2026, 6, 28));
      final maintenance = FakeMaintenanceRepository(initialTasks: [task]);
      final scheduler = FakeNotificationScheduler();
      bool? completionResult;
      Object? completionError;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            maintenanceRepositoryProvider.overrideWithValue(maintenance),
            streakServiceProvider.overrideWithValue(streak),
            notificationSchedulerProvider.overrideWithValue(scheduler),
            nativeCapabilitiesProvider.overrideWithValue(
              _FixedNativeCapabilities(),
            ),
          ],
          child: MaterialApp(
            scaffoldMessengerKey: hkRootScaffoldMessengerKey,
            theme: testLightTheme(),
            home: Scaffold(
              body: Consumer(
                builder: (context, ref, child) => ElevatedButton(
                  onPressed: () async {
                    try {
                      completionResult = await completeTaskWithFeedback(
                        context,
                        ref,
                        task,
                      );
                    } catch (error) {
                      completionError = error;
                    }
                  },
                  child: const Text('Complete'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Complete'));
      for (var attempt = 0; attempt < 20; attempt++) {
        await tester.pump(const Duration(milliseconds: 100));
        if (find.text('Task completed.').evaluate().isNotEmpty) {
          break;
        }
      }

      expect(completionError, isNull);
      expect(completionResult, isTrue);
      expect(find.text('Task completed.'), findsOneWidget);
      expect(find.text('Undo'), findsOneWidget);
      expect(
        tester.widget<SnackBar>(find.byType(SnackBar)).duration,
        const Duration(seconds: 5),
      );
      expect(scheduler.refreshCount, 1);
      expect(scheduler.cancelled, isEmpty);

      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(maintenance.undoCount, 1);
      expect(scheduler.refreshCount, 2);
      expect(find.text('Completion undone.'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
    });

    testWidgets('task completion toast disappears after action duration', (
      tester,
    ) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures();
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      late BuildContext toastContext;
      await tester.pumpWidget(
        MaterialApp(
          scaffoldMessengerKey: hkRootScaffoldMessengerKey,
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          theme: testLightTheme(),
          home: Scaffold(
            body: Builder(
              builder: (context) {
                toastContext = context;
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      FeedbackCoordinator.instance.resetForTesting();
      hkRootScaffoldMessengerKey.currentState?.clearSnackBars();

      final controller = hk_ui.showToast(
        toastContext,
        content: const Text('Task completed.'),
        action: SnackBarAction(label: 'Undo', onPressed: () {}),
      );
      await tester.pumpAndSettle();
      expect(find.text('Task completed.'), findsOneWidget);

      controller?.close();
      await tester.pumpAndSettle();
      await tester.pump();
      expect(find.text('Task completed.'), findsNothing);
    });
  });
}

class _FixedNativeCapabilities extends NativeCapabilities {
  @override
  Future<String?> getTimeZoneId() async => 'UTC';
}
