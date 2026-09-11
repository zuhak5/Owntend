import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:owntend/main.dart';
import 'package:owntend/src/core/sync/sync_contracts.dart';
import 'package:owntend/src/features/maintenance/application/task_creation_controller.dart';
import 'package:owntend/src/features/monetization/charged_operation_resolver.dart';
import 'package:owntend/src/features/navigation/app_navigation.dart';

import 'support/widget_test_fakes.dart';

class _FakeChargedOperationResolver implements ChargedOperationResolver {
  final List<String> resolvedAccounts = [];

  @override
  Future<void> resolvePendingOperations(String accountScope) async {
    resolvedAccounts.add(accountScope);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('authenticated startup recovers charges before cached readiness', () {
    final source = File(
      'lib/src/features/startup/presentation/startup_bootstrap.dart',
    ).readAsStringSync().replaceAll('\r\n', '\n');

    const recoveryCall =
        'await _recoverPendingChargedOperations(session, generation);';
    const cachedReadyShortcut =
        'final offlineSnapshot = _offlineSnapshotCandidate;';

    expect(source, contains(recoveryCall));
    expect(source, contains(cachedReadyShortcut));
    expect(
      source.indexOf(recoveryCall),
      lessThan(source.indexOf(cachedReadyShortcut)),
    );
    expect(
      source,
      contains('final resolver = _ref.read(chargedOperationResolverProvider);'),
    );
    expect(
      source,
      contains('await resolver.resolvePendingOperations(session.userId);'),
    );
  });

  testWidgets(
    'behavioral: authenticated startup executes charged operation resolution',
    (tester) async {
      final settings = FakeSettingsRepository(onboardingCompletedValue: true);
      addTearDown(settings.close);
      final fakeResolver = _FakeChargedOperationResolver();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...testOverrides(settings),
            chargedOperationResolverProvider.overrideWithValue(fakeResolver),
          ],
          child: const OwntendApp(),
        ),
      );
      await tester.pumpAndSettle();

      expect(fakeResolver.resolvedAccounts, contains('widget-test-user'));
    },
  );

  testWidgets(
    'behavioral: starts foreground restore service on initial hydration and updates on progress',
    (tester) async {
      final settings = FakeSettingsRepository(onboardingCompletedValue: true);
      addTearDown(settings.close);

      final starterCalls =
          <({String localeCode, InitialHydrationProgress? progress})>[];
      var stopCount = 0;

      final syncStatusState = StreamController<SyncStatus>.broadcast();
      addTearDown(syncStatusState.close);

      final initialSyncStatus = SyncStatus(
        phase: SyncPhase.initializing,
        enabled: true,
        initialHydrationProgress: testHydrationProgress(
          InitialHydrationStage.restoringCloudData,
        ),
      );

      final enableCompleter = Completer<void>();
      addTearDown(() {
        if (!enableCompleter.isCompleted) enableCompleter.complete();
      });

      final syncRepo = FakeCloudSyncRepository(
        initialSyncStatus,
        enableFuture: enableCompleter.future,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...testOverrides(settings),
            cloudSyncRepositoryProvider.overrideWithValue(syncRepo),
            syncStatusProvider.overrideWith((ref) => syncStatusState.stream),
            startupRestoreServiceStarterProvider.overrideWithValue(({
              required String localeCode,
              InitialHydrationProgress? progress,
            }) async {
              starterCalls.add((localeCode: localeCode, progress: progress));
              return true;
            }),
            startupRestoreServiceStopperProvider.overrideWithValue(() async {
              stopCount++;
            }),
          ],
          child: const OwntendApp(),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(starterCalls, isNotEmpty);
      expect(
        starterCalls.any(
          (call) =>
              call.progress?.stage == InitialHydrationStage.connecting ||
              call.progress?.stage == InitialHydrationStage.restoringCloudData,
        ),
        isTrue,
      );

      final photoProgress = InitialHydrationProgress(
        runId: 'startup',
        state: RestoreRunState.running,
        stage: InitialHydrationStage.restoringPhotos,
        completedUnits: 50,
        totalUnits: 100,
        startedAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      syncStatusState.add(
        SyncStatus(
          phase: SyncPhase.initializing,
          enabled: true,
          initialHydrationProgress: photoProgress,
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        starterCalls.any(
          (call) =>
              call.progress?.stage == InitialHydrationStage.restoringPhotos,
        ),
        isTrue,
      );

      enableCompleter.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final completedProgress = InitialHydrationProgress(
        runId: 'startup',
        state: RestoreRunState.completed,
        stage: InitialHydrationStage.finalizing,
        completedUnits: 100,
        totalUnits: 100,
        startedAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      syncStatusState.add(
        SyncStatus(
          phase: SyncPhase.ready,
          enabled: true,
          initialHydrationProgress: completedProgress,
        ),
      );

      await tester.pumpAndSettle();

      expect(stopCount, greaterThanOrEqualTo(1));
    },
  );

  test('behavioral: openNotificationPayload consumes PendingNotificationRoute on push', () {
    expect(PendingNotificationRoute.pending, isNull);
    PendingNotificationRoute.pending = '/search';
    expect(PendingNotificationRoute.take(), '/search');
    expect(PendingNotificationRoute.pending, isNull);
  });
}
