import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:owntend/main.dart';
import 'package:owntend/l10n/app_localizations.dart';
import 'package:owntend/src/features/trash/presentation/trash_actions.dart';
import 'package:owntend/src/core/services/native_capabilities.dart';

import 'package:owntend/src/core/domain/models.dart';
import 'package:owntend/src/core/domain/contracts.dart';
import 'package:owntend/src/core/sync/sync_contracts.dart';
import 'package:owntend/src/core/sync/local_sync_store.dart';
import 'package:owntend/src/core/sync/supabase_sync_gateway.dart';
import 'package:owntend/src/core/sync/sync_coordinator.dart';
import 'package:owntend/src/features/auth/domain/auth_repository.dart';
import 'package:owntend/src/core/services/feedback_messenger.dart';
import 'package:owntend/src/features/monetization/monetization.dart';
import 'package:owntend/src/ui/feedback/feedback_coordinator.dart';

import 'support/widget_test_fakes.dart';
import 'test_theme.dart';

void main() {
  setUp(() {
    FeedbackCoordinator.instance.resetForTesting();
    addTearDown(FeedbackCoordinator.instance.resetForTesting);
  });

  for (final outcome in ['success', 'failure', 'account-change']) {
    final restoreFails = outcome == 'failure';
    testWidgets('task detail Trash Undo after route closes ($outcome)', (
      tester,
    ) async {
      final settings = FakeSettingsRepository(onboardingCompletedValue: true);
      addTearDown(settings.close);
      final auth = _MutableAuthRepository();
      final task = makeTaskItem(DateTime.now(), id: 'undo-after-pop');
      final repository = _RestoringMaintenanceRepository(
        task,
        restoreFails: restoreFails,
      );
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => const Scaffold(body: Text('Home after delete')),
          ),
          GoRoute(
            path: '/maintenance/:id',
            builder: (_, state) =>
                TaskDetailScreen(planId: state.pathParameters['id']!),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...testOverrides(
              settings,
              tasks: [task],
              maintenanceRepository: repository,
            ),
            authRepositoryProvider.overrideWithValue(auth),
          ],
          child: MaterialApp.router(
            theme: testLightTheme(),
            scaffoldMessengerKey: hkRootScaffoldMessengerKey,
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();
      unawaited(router.push('/maintenance/${task.plan.id}'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Task actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Move task to Trash'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Move to Trash'));
      await tester.pumpAndSettle();
      expect(repository.archivedPlanIds, [task.plan.id]);
      expect(find.text('Home after delete'), findsOneWidget);
      expect(find.text('Undo'), findsOneWidget);
      if (outcome == 'account-change') auth.session = null;
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(
        repository.restoredPlanIds,
        outcome != 'success' ? isEmpty : [task.plan.id],
      );
      expect(
        find.text(
          outcome != 'success'
              ? 'Undo failed. Please try again.'
              : 'Task restored.',
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }

  for (final entity in ['asset', 'room', 'area']) {
    testWidgets('$entity Trash Undo survives its originating route', (
      tester,
    ) async {
      final settings = FakeSettingsRepository(onboardingCompletedValue: true);
      addTearDown(settings.close);
      final repository = _TrashAssetRepository();
      final asset = makeThing('trash-asset', 'Item', AssetType.general);
      final room = makeRooms(DateTime(2026)).first;
      final area = makeAreas(DateTime(2026)).first;
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => const Scaffold(body: Text('Home')),
          ),
          GoRoute(
            path: '/delete',
            builder: (_, _) => Scaffold(
              body: Consumer(
                builder: (context, ref, _) => TextButton(
                  onPressed: () async {
                    final moved = switch (entity) {
                      'asset' => await deleteThingWithConfirmation(
                        context,
                        ref,
                        asset,
                      ),
                      'room' => await deleteRoomWithConfirmation(
                        context,
                        ref,
                        room,
                      ),
                      _ => await deleteAreaWithConfirmation(context, ref, area),
                    };
                    if (moved && context.mounted) context.pop();
                  },
                  child: const Text('Delete'),
                ),
              ),
            ),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: testOverrides(settings, assetRepository: repository),
          child: MaterialApp.router(
            scaffoldMessengerKey: hkRootScaffoldMessengerKey,
            theme: testLightTheme(),
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();
      unawaited(router.push('/delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Move to Trash'));
      await tester.pumpAndSettle();
      expect(find.text('Home'), findsOneWidget);
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(repository.restored, [entity]);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('task editor can open date picker for a long overdue task', (
    tester,
  ) async {
    final settings = FakeSettingsRepository(onboardingCompletedValue: true);
    addTearDown(settings.close);
    final task = makeTaskItem(
      DateTime.now().subtract(const Duration(days: 800)),
      id: 'old-task',
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...testOverrides(settings, tasks: [task]),
          offlineCreationDraftStoreProvider.overrideWithValue(
            FakeOfflineCreationDraftStore(),
          ),
        ],
        child: MaterialApp(
          theme: testLightTheme(),
          home: Scaffold(body: PlanEditorDialog(task: task)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final dateButton = find.widgetWithIcon(OutlinedButton, Icons.event);
    await tester.ensureVisible(dateButton);
    await tester.tap(dateButton);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(DatePickerDialog), findsOneWidget);
  });

  testWidgets('asset editor cannot save before existing tags finish loading', (
    tester,
  ) async {
    final settings = FakeSettingsRepository(onboardingCompletedValue: true);
    addTearDown(settings.close);
    final asset = makeThing('slow-tags', 'Tagged item', AssetType.general);
    final tags = Completer<List<Tag>>();
    final repository = _RecordingAssetRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...testOverrides(settings, assetRepository: repository),
          assetTagsProvider(asset.id).overrideWith((ref) async* {
            ref.keepAlive();
            yield await tags.future;
          }),
          offlineCreationDraftStoreProvider.overrideWithValue(
            FakeOfflineCreationDraftStore(),
          ),
        ],
        child: MaterialApp(
          theme: testLightTheme(),
          home: Scaffold(body: AssetEditorDialog(asset: asset)),
        ),
      ),
    );
    await tester.pump();
    final saveButton = find.widgetWithText(FilledButton, 'Save item');
    final saveWhileLoading = tester.widget<FilledButton>(saveButton).onPressed;
    tags.complete([
      Tag(id: 'tag-1', name: 'Keep me', createdAt: DateTime(2026)),
    ]);
    await tester.pumpAndSettle();
    expect(saveWhileLoading, isNull);
    expect(tester.widget<FilledButton>(saveButton).onPressed, isNotNull);
    expect(find.text('Keep me'), findsOneWidget);
    await tester.tap(saveButton);
    await tester.pumpAndSettle();
    expect(repository.savedTags, ['Keep me']);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'closing asset editor during tag loading leaves no stale ref use',
    (tester) async {
      final settings = FakeSettingsRepository(onboardingCompletedValue: true);
      addTearDown(settings.close);
      final asset = makeThing('closing-tags', 'Tagged item', AssetType.general);
      final tags = Completer<List<Tag>>();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...testOverrides(settings),
            assetTagsProvider(asset.id).overrideWith((ref) async* {
              ref.keepAlive();
              yield await tags.future;
            }),
            offlineCreationDraftStoreProvider.overrideWithValue(
              FakeOfflineCreationDraftStore(),
            ),
          ],
          child: MaterialApp(
            theme: testLightTheme(),
            home: Builder(
              builder: (context) {
                return Scaffold(
                  body: TextButton(
                    onPressed: () =>
                        showAssetEditorSheet(context, asset: asset),
                    child: const Text('Open asset editor'),
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open asset editor'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      tags.complete(const []);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  for (final language in ['en', 'ar']) {
    for (final selectedDate in [DateTime(1980, 2, 3), DateTime(2080, 4, 5)]) {
      for (final editor in ['asset', 'task']) {
        testWidgets('$language $editor picker retains $selectedDate', (
          tester,
        ) async {
          final settings = FakeSettingsRepository(
            onboardingCompletedValue: true,
          );
          addTearDown(settings.close);
          final task = makeTaskItem(selectedDate);
          final asset = Asset(
            id: 'dated-asset',
            name: 'Dated item',
            roomId: 'room_kitchen',
            assetType: AssetType.general,
            purchaseDate: selectedDate,
            createdAt: DateTime(2026),
            updatedAt: DateTime(2026),
          );
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                ...testOverrides(settings, assets: [asset], tasks: [task]),
                offlineCreationDraftStoreProvider.overrideWithValue(
                  FakeOfflineCreationDraftStore(),
                ),
              ],
              child: MaterialApp(
                locale: Locale(language),
                supportedLocales: AppLocalizations.supportedLocales,
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                theme: testLightTheme(),
                home: Scaffold(
                  body: editor == 'asset'
                      ? AssetEditorDialog(asset: asset)
                      : PlanEditorDialog(task: task),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final button = editor == 'task'
              ? find.widgetWithIcon(OutlinedButton, Icons.event)
              : find
                    .byWidgetPredicate(
                      (widget) =>
                          widget is OutlinedButton && widget.child is Row,
                    )
                    .first;
          // Asset's first outlined button is its purchase-date control.
          final dateButton = editor == 'asset'
              ? find.byType(OutlinedButton).first
              : button;
          await tester.ensureVisible(dateButton);
          await tester.tap(dateButton);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          final picker = tester.widget<DatePickerDialog>(
            find.byType(DatePickerDialog),
          );
          expect(picker.initialDate, selectedDate);
          expect(picker.firstDate.isAfter(selectedDate), isFalse);
          expect(picker.lastDate.isBefore(selectedDate), isFalse);
        });
      }
    }

    testWidgets('$language future task can open postpone picker', (
      tester,
    ) async {
      final settings = FakeSettingsRepository(onboardingCompletedValue: true);
      addTearDown(settings.close);
      final selectedDate = DateTime(2080, 4, 5);
      final task = makeTaskItem(selectedDate);
      await tester.pumpWidget(
        ProviderScope(
          overrides: testOverrides(settings, tasks: [task]),
          child: MaterialApp(
            locale: Locale(language),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            theme: testLightTheme(),
            home: Scaffold(
              body: Consumer(
                builder: (context, ref, _) => TextButton(
                  onPressed: () => postponeTaskWithDialog(context, ref, task),
                  child: const Text('Postpone'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Postpone'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        tester
            .widget<DatePickerDialog>(find.byType(DatePickerDialog))
            .initialDate,
        selectedDate,
      );
    });

    testWidgets(
      '$language asset initialization failure is explicit and retryable',
      (tester) async {
        final settings = FakeSettingsRepository(onboardingCompletedValue: true);
        addTearDown(settings.close);
        final asset = makeThing(
          'failed-tags',
          'Tagged item',
          AssetType.general,
        );
        var attempts = 0;
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              ...testOverrides(settings),
              assetTagsProvider(asset.id).overrideWith((ref) async* {
                ref.keepAlive();
                if (++attempts == 1) throw StateError('private tag failure');
                yield [
                  Tag(id: 'tag-1', name: 'Keep me', createdAt: DateTime(2026)),
                ];
              }),
              offlineCreationDraftStoreProvider.overrideWithValue(
                FakeOfflineCreationDraftStore(),
              ),
            ],
            child: MaterialApp(
              locale: Locale(language),
              supportedLocales: AppLocalizations.supportedLocales,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              theme: testLightTheme(),
              home: Scaffold(body: AssetEditorDialog(asset: asset)),
            ),
          ),
        );
        await tester.pump();
        await tester.pump();
        await tester.pumpAndSettle();
        final l10n = AppLocalizations.of(
          tester.element(find.byType(AssetEditorDialog)),
        );
        expect(
          find.text(l10n.somethingWentWrongPleaseTryAgain),
          findsOneWidget,
        );
        expect(find.textContaining('private tag failure'), findsNothing);
        expect(find.byType(TextField), findsNothing);
        expect(
          tester
              .widget<FilledButton>(
                find.widgetWithText(FilledButton, l10n.saveItem),
              )
              .onPressed,
          isNull,
        );
        await tester.tap(find.text(l10n.retry));
        await tester.pumpAndSettle();
        expect(find.text('Keep me'), findsOneWidget);
        expect(
          tester
              .widget<FilledButton>(
                find.widgetWithText(FilledButton, l10n.saveItem),
              )
              .onPressed,
          isNotNull,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'asset editor waits for draft and preserves restored tags on save',
    (tester) async {
      final settings = FakeSettingsRepository(onboardingCompletedValue: true);
      addTearDown(settings.close);
      final asset = makeThing('draft-item', 'Original item', AssetType.general);
      final draft = Completer<Map<String, dynamic>?>();
      final repository = _RecordingAssetRepository();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...testOverrides(
              settings,
              assets: [asset],
              assetRepository: repository,
            ),
            offlineCreationDraftStoreProvider.overrideWithValue(
              _DelayedDraftStore(draft.future),
            ),
          ],
          child: MaterialApp(
            theme: testLightTheme(),
            home: Scaffold(body: AssetEditorDialog(asset: asset)),
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(TextField), findsNothing);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Save item'),
            )
            .onPressed,
        isNull,
      );
      draft.complete({
        'name': 'Restored draft',
        'tags': 'Preserved tag',
        'asset_type': 'general',
        'room_id': 'room_kitchen',
      });
      await tester.pumpAndSettle();
      expect(find.text('Restored draft'), findsOneWidget);
      expect(find.text('Preserved tag'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Save item'));
      await tester.pumpAndSettle();
      expect(repository.savedTags, ['Preserved tag']);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('asset draft failure can be retried without partial editing', (
    tester,
  ) async {
    final settings = FakeSettingsRepository(onboardingCompletedValue: true);
    addTearDown(settings.close);
    final asset = makeThing('failed-draft', 'Original item', AssetType.general);
    final draftStore = _RetryDraftStore();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...testOverrides(settings, assets: [asset]),
          offlineCreationDraftStoreProvider.overrideWithValue(draftStore),
        ],
        child: MaterialApp(
          theme: testLightTheme(),
          home: Scaffold(body: AssetEditorDialog(asset: asset)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Retry'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Recovered draft'), findsOneWidget);
    expect(draftStore.loads, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'completion Undo survives navigation away from the originating route',
    (tester) async {
      final settings = FakeSettingsRepository(onboardingCompletedValue: true);
      addTearDown(settings.close);
      final task = makeTaskItem(DateTime.now());
      final maintenance = FakeMaintenanceRepository(initialTasks: [task]);
      final scheduler = FakeNotificationScheduler();
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => const Scaffold(body: Text('Home')),
          ),
          GoRoute(
            path: '/complete',
            builder: (_, _) => Scaffold(
              body: Consumer(
                builder: (context, ref, _) => TextButton(
                  onPressed: () async {
                    await completeTaskWithFeedback(context, ref, task);
                    if (context.mounted) context.pop();
                  },
                  child: const Text('Complete'),
                ),
              ),
            ),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...testOverrides(
              settings,
              tasks: [task],
              maintenanceRepository: maintenance,
              notificationScheduler: scheduler,
            ),
            streakServiceProvider.overrideWithValue(FakeStreakService()),
            nativeCapabilitiesProvider.overrideWithValue(
              _FixedNativeCapabilities(),
            ),
          ],
          child: MaterialApp.router(
            scaffoldMessengerKey: hkRootScaffoldMessengerKey,
            theme: testLightTheme(),
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();
      unawaited(router.push('/complete'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Complete'));
      await tester.pumpAndSettle();
      expect(find.text('Home'), findsOneWidget);
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(maintenance.undoCount, 1);
      expect(scheduler.refreshCount, 2);
      expect(find.text('Completion undone.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('startup observes a task read failure while profile is pending', (
    tester,
  ) async {
    final profile = Completer<AppProfile>();
    final tasks = Completer<List<TaskItem>>();
    final settings = _DelayedProfileSettings(profile.future);
    addTearDown(settings.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...testOverrides(
            settings,
            maintenanceRepository: _DelayedTasksRepository(tasks.future),
          ),
          cloudSyncRepositoryProvider.overrideWithValue(
            FakeCloudSyncRepository(
              const SyncStatus(phase: SyncPhase.ready, enabled: true),
            ),
          ),
        ],
        child: const OwntendApp(),
      ),
    );
    await tester.pump();
    tasks.completeError(StateError('task read failed before profile'));
    await tester.pump();
    profile.complete(const AppProfile());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Finalizing Owntend needs attention'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('signed-out cleanup owns failures from both independent tasks', (
    tester,
  ) async {
    final settings = FakeSettingsRepository(onboardingCompletedValue: true);
    addTearDown(settings.close);
    final scheduler = _FailingCleanupScheduler();
    final inbox = _StartupInbox(fails: true);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...testOverrides(settings, notificationScheduler: scheduler),
          notificationInboxRepositoryProvider.overrideWithValue(inbox),
          cloudSyncRepositoryProvider.overrideWithValue(
            FakeCloudSyncRepository(
              const SyncStatus(phase: SyncPhase.ready, enabled: true),
            ),
          ),
        ],
        child: const OwntendApp(),
      ),
    );
    await tester.pump();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(OwntendApp)),
    );
    final controller = container.read(startupBootstrapControllerProvider);
    await controller.handleAuthState(
      const AuthStateChange(event: AuthEventType.signedOut, session: null),
    );
    await tester.pump();
    expect(scheduler.clearCount, 1);
    expect(inbox.clears, 1);
    expect(controller.currentState.kind, StartupBootstrapKind.unauthenticated);
    expect(tester.takeException(), isNull);
  });

  for (final scenario in [
    (name: 'failure retains session', clearsSession: false, fails: true),
    (name: 'no-op retains session', clearsSession: false, fails: false),
    (
      name: 'late failure after session cleared',
      clearsSession: true,
      fails: true,
    ),
    (name: 'successful sign-out', clearsSession: true, fails: false),
  ]) {
    testWidgets(
      'startup sign-out reflects repository truth: ${scenario.name}',
      (tester) async {
        final settings = FakeSettingsRepository(
          onboardingCompletedValue: true,
          profileFailure: StateError('profile unavailable'),
        );
        final auth = _FailingSignOutRepository(
          clearsSession: scenario.clearsSession,
          fails: scenario.fails,
        );
        final syncStore = _StartupSyncStore();
        when(() => syncStore.watchAccount())
            .thenAnswer((_) => const Stream.empty());
        when(() => syncStore.watchPendingCount())
            .thenAnswer((_) => const Stream.empty());
        when(() => syncStore.existingAccount()).thenAnswer((_) async => null);
        when(() => syncStore.pendingCount()).thenAnswer((_) async => 0);
        when(() => syncStore.pendingMediaCleanupCount())
            .thenAnswer((_) async => 0);
        when(() => syncStore.nextRetryAt()).thenAnswer((_) async => null);
        when(() => syncStore.payloadParseFailures).thenReturn(0);
        addTearDown(settings.close);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              ...testOverrides(settings),
              authRepositoryProvider.overrideWithValue(auth),
              syncCoordinatorProvider.overrideWith((ref) {
                final coordinator = SyncCoordinator(
                  auth,
                  syncStore,
                  _StartupSyncGateway(),
                  listenToAuthChanges: false,
                );
                ref.onDispose(coordinator.dispose);
                return coordinator;
              }),
              notificationInboxRepositoryProvider.overrideWithValue(
                _StartupInbox(),
              ),
              cloudSyncRepositoryProvider.overrideWithValue(
                FakeCloudSyncRepository(
                  const SyncStatus(phase: SyncPhase.ready, enabled: true),
                ),
              ),
            ],
            child: const OwntendApp(),
          ),
        );
        await tester.pump();
        final container = ProviderScope.containerOf(
          tester.element(find.byType(OwntendApp)),
        );
        final controller = container.read(startupBootstrapControllerProvider);
        final originalCoordinator = container.read(syncCoordinatorProvider)!;
        expect(
          controller.currentState.kind,
          StartupBootstrapKind.startupFailed,
        );
        await controller.signOutFromStartup();
        await tester.pump();
        expect(auth.signOutCalls, 1);
        expect(
          auth.currentSession,
          scenario.clearsSession ? isNull : isNotNull,
        );
        expect(
          controller.currentState.kind,
          scenario.clearsSession
              ? StartupBootstrapKind.unauthenticated
              : StartupBootstrapKind.startupFailed,
        );
        if (!scenario.clearsSession) {
          expect(
            container.read(syncCoordinatorProvider),
            same(originalCoordinator),
          );
          expect(originalCoordinator.scheduleBlocked, isTrue);
          expect(controller.currentState.canContinueOffline, isFalse);
          expect(
            find.text('Finalizing Owntend needs attention'),
            findsOneWidget,
          );
          await controller.retryStartupRestore();
          await tester.pump();
        }
        final replacement = container.read(syncCoordinatorProvider)!;
        expect(replacement, isNot(same(originalCoordinator)));
        expect(replacement.scheduleBlocked, isFalse);
        expect(originalCoordinator.scheduleBlocked, isTrue);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      },
    );
  }
}

class _StartupSyncStore extends Mock implements LocalSyncStore {}

class _StartupSyncGateway extends Mock implements SupabaseSyncGateway {}

class _DelayedProfileSettings extends FakeSettingsRepository {
  _DelayedProfileSettings(this.result) : super(onboardingCompletedValue: true);

  final Future<AppProfile> result;

  @override
  Future<AppProfile> profile() => result;
}

class _DelayedTasksRepository extends FakeMaintenanceRepository {
  _DelayedTasksRepository(this.result);

  final Future<List<TaskItem>> result;

  @override
  Future<List<TaskItem>> listTasks() => result;
}

class _FailingSignOutRepository implements AuthRepository {
  _FailingSignOutRepository({this.clearsSession = false, this.fails = true});

  final bool clearsSession;
  final bool fails;
  int signOutCalls = 0;
  AuthSession? _session = signedInTestSession;

  @override
  AuthSession? get currentSession => _session;

  @override
  Stream<AuthStateChange> watchAuthState() => const Stream.empty();

  @override
  Future<void> signOut({bool allDevices = false}) async {
    signOutCalls++;
    if (clearsSession) _session = null;
    if (fails) throw StateError('sign-out barrier unavailable');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _StartupInbox implements NotificationInboxRepository {
  _StartupInbox({this.fails = false});

  final bool fails;
  int clears = 0;

  @override
  Future<void> clear() async {
    clears++;
    if (fails) throw StateError('inbox cleanup unavailable');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FailingCleanupScheduler extends FakeNotificationScheduler {
  @override
  Future<void> clearAllScheduledReminders() async {
    clearCount++;
    throw StateError('platform cleanup unavailable');
  }
}

class _DelayedDraftStore extends FakeOfflineCreationDraftStore {
  _DelayedDraftStore(this.result);
  final Future<Map<String, dynamic>?> result;
  @override
  Future<Map<String, dynamic>?> load(String key) => result;
}

class _RetryDraftStore extends FakeOfflineCreationDraftStore {
  int loads = 0;
  @override
  Future<Map<String, dynamic>?> load(String key) async {
    if (++loads == 1) throw StateError('draft unavailable');
    return {
      'name': 'Recovered draft',
      'tags': 'Recovered tag',
      'asset_type': 'general',
      'room_id': 'room_kitchen',
    };
  }
}

class _RecordingAssetRepository extends StartupAssetRepository {
  _RecordingAssetRepository() : super(assets: const [], rooms: const []);
  List<String>? savedTags;
  @override
  Future<String> saveAsset({
    String? id,
    required String name,
    AssetType assetType = AssetType.general,
    required String roomId,
    String? placement,
    String? notes,
    DateTime? purchaseDate,
    List<String>? tagNames,
    DeviceDetails? deviceDetails,
    PetDetails? petDetails,
    PlantDetails? plantDetails,
    SafetyDetails? safetyDetails,
    DateTime? expectedUpdatedAt,
  }) async {
    savedTags = tagNames;
    return id ?? 'new-item';
  }
}

class _FixedNativeCapabilities extends NativeCapabilities {
  @override
  Future<String?> getTimeZoneId() async => 'UTC';
}

class _RestoringMaintenanceRepository extends FakeMaintenanceRepository {
  _RestoringMaintenanceRepository(TaskItem task, {required this.restoreFails})
    : super(initialTasks: [task]);
  final bool restoreFails;
  @override
  Future<void> restorePlan(String planId) async {
    if (restoreFails) throw StateError('restoration failed');
    await super.restorePlan(planId);
  }
}

class _MutableAuthRepository implements AuthRepository {
  AuthSession? session = signedInTestSession;
  @override
  AuthSession? get currentSession => session;
  @override
  Stream<AuthStateChange> watchAuthState() => const Stream.empty();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TrashAssetRepository extends StartupAssetRepository {
  _TrashAssetRepository() : super(assets: const [], rooms: const []);
  final restored = <String>[];
  @override
  Future<void> trashAsset(String id) async {}
  @override
  Future<void> trashRoom(String id) async {}
  @override
  Future<void> trashArea(String id) async {}
  @override
  Future<void> restoreAsset(String id) async {
    restored.add('asset');
  }

  @override
  Future<void> restoreRoom(String id) async {
    restored.add('room');
  }

  @override
  Future<void> restoreArea(String id) async {
    restored.add('area');
  }
}
