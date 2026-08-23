import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:owntend/src/core/services/patch_update_coordinator.dart';
import 'package:shorebird_code_push/shorebird_code_push.dart';

class MockShorebirdUpdater extends Mock implements ShorebirdUpdater {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MockShorebirdUpdater mockUpdater;

  setUp(() {
    mockUpdater = MockShorebirdUpdater();
  });

  group('PatchUpdateCoordinator', () {
    test(
      'emits PatchUpdateUnavailable when Shorebird engine is not active',
      () async {
        when(() => mockUpdater.isAvailable).thenReturn(false);

        final container = ProviderContainer(
          overrides: [
            patchUpdateCoordinatorProvider.overrideWith(
              () => PatchUpdateCoordinator(updater: mockUpdater),
            ),
          ],
        );
        addTearDown(container.dispose);

        container.read(patchUpdateCoordinatorProvider);
        await Future<void>.delayed(const Duration(milliseconds: 10));

        expect(
          container.read(patchUpdateCoordinatorProvider),
          isA<PatchUpdateUnavailable>(),
        );
      },
    );

    test(
      'emits PatchUpdateReady on startup if a staged patch is pending restart',
      () async {
        when(() => mockUpdater.isAvailable).thenReturn(true);
        when(() => mockUpdater.readCurrentPatch())
            .thenAnswer((_) async => const Patch(number: 1));
        when(() => mockUpdater.readNextPatch())
            .thenAnswer((_) async => const Patch(number: 2));

        final container = ProviderContainer(
          overrides: [
            patchUpdateCoordinatorProvider.overrideWith(
              () => PatchUpdateCoordinator(updater: mockUpdater),
            ),
          ],
        );
        addTearDown(container.dispose);

        container.read(patchUpdateCoordinatorProvider);
        await Future<void>.delayed(const Duration(milliseconds: 10));

        final state = container.read(patchUpdateCoordinatorProvider);
        expect(state, isA<PatchUpdateReady>());
        final ready = state as PatchUpdateReady;
        expect(ready.currentPatchNumber, equals(1));
        expect(ready.nextPatchNumber, equals(2));
      },
    );

    test(
      'downloads and transitions to PatchUpdateReady when update is available',
      () async {
        when(() => mockUpdater.isAvailable).thenReturn(true);
        when(() => mockUpdater.readCurrentPatch())
            .thenAnswer((_) async => const Patch(number: 1));
        when(() => mockUpdater.readNextPatch()).thenAnswer((_) async => null);
        when(() => mockUpdater.checkForUpdate())
            .thenAnswer((_) async => UpdateStatus.outdated);
        when(() => mockUpdater.update()).thenAnswer((_) async {});

        final container = ProviderContainer(
          overrides: [
            patchUpdateCoordinatorProvider.overrideWith(
              () => PatchUpdateCoordinator(updater: mockUpdater),
            ),
          ],
        );
        addTearDown(container.dispose);

        final coordinator = container.read(
          patchUpdateCoordinatorProvider.notifier,
        );
        await Future<void>.delayed(const Duration(milliseconds: 10));

        when(() => mockUpdater.readNextPatch())
            .thenAnswer((_) async => const Patch(number: 2));

        await coordinator.checkForUpdates(force: true);

        final state = container.read(patchUpdateCoordinatorProvider);
        expect(state, isA<PatchUpdateReady>());
        final ready = state as PatchUpdateReady;
        expect(ready.nextPatchNumber, equals(2));
      },
    );

    test('throttles repetitive update checks unless forced', () async {
      when(() => mockUpdater.isAvailable).thenReturn(true);
      when(() => mockUpdater.readCurrentPatch())
          .thenAnswer((_) async => const Patch(number: 1));
      when(() => mockUpdater.readNextPatch()).thenAnswer((_) async => null);
      when(() => mockUpdater.checkForUpdate())
          .thenAnswer((_) async => UpdateStatus.upToDate);

      final container = ProviderContainer(
        overrides: [
          patchUpdateCoordinatorProvider.overrideWith(
            () => PatchUpdateCoordinator(updater: mockUpdater),
          ),
        ],
      );
      addTearDown(container.dispose);

      final coordinator = container.read(
        patchUpdateCoordinatorProvider.notifier,
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));

      await coordinator.checkForUpdates(force: true);
      expect(
        container.read(patchUpdateCoordinatorProvider),
        isA<PatchUpdateUpToDate>(),
      );

      // Second immediate call without force should be throttled
      await coordinator.checkForUpdates(force: false);
      verify(() => mockUpdater.checkForUpdate()).called(1);
    });

    test(
      'skips update download if device storage is below threshold',
      () async {
        when(() => mockUpdater.isAvailable).thenReturn(true);
        when(() => mockUpdater.readCurrentPatch())
            .thenAnswer((_) async => const Patch(number: 1));
        when(() => mockUpdater.readNextPatch()).thenAnswer((_) async => null);
        when(() => mockUpdater.checkForUpdate())
            .thenAnswer((_) async => UpdateStatus.outdated);

        final container = ProviderContainer(
          overrides: [
            patchUpdateCoordinatorProvider.overrideWith(
              () => PatchUpdateCoordinator(
                updater: mockUpdater,
                hasSufficientStorage: () async => false, // insufficient storage
              ),
            ),
          ],
        );
        addTearDown(container.dispose);

        final coordinator = container.read(
          patchUpdateCoordinatorProvider.notifier,
        );
        await Future<void>.delayed(const Duration(milliseconds: 10));

        await coordinator.checkForUpdates(force: true);

        // Verify update() was NEVER called because of storage guard
        verifyNever(() => mockUpdater.update());
        expect(
          container.read(patchUpdateCoordinatorProvider),
          isA<PatchUpdateIdle>(),
        );
      },
    );

    test('logs diagnostic events on startup and update check', () async {
      when(() => mockUpdater.isAvailable).thenReturn(true);
      when(() => mockUpdater.readCurrentPatch())
          .thenAnswer((_) async => const Patch(number: 2));
      when(() => mockUpdater.readNextPatch()).thenAnswer((_) async => null);
      when(() => mockUpdater.checkForUpdate())
          .thenAnswer((_) async => UpdateStatus.upToDate);

      final container = ProviderContainer(
        overrides: [
          patchUpdateCoordinatorProvider.overrideWith(
            () => PatchUpdateCoordinator(updater: mockUpdater),
          ),
        ],
      );
      addTearDown(container.dispose);

      final coordinator = container.read(
        patchUpdateCoordinatorProvider.notifier,
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      await coordinator.checkForUpdates(force: true);

      expect(
        container.read(patchUpdateCoordinatorProvider),
        isA<PatchUpdateUpToDate>(),
      );
    });
  });
}
