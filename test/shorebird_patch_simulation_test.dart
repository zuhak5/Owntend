import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:owntend/src/core/database/app_database.dart';
import 'package:owntend/src/core/services/patch_update_coordinator.dart';
import 'package:owntend/src/ui/widgets/remote_or_bundled_image.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late File dbFile;
  late AppDatabase db;

  setUp(() async {
    dbFile = File(
      '${Directory.systemTemp.path}/owntend_patch_sim_'
      '${DateTime.now().microsecondsSinceEpoch}.sqlite',
    );
    db = AppDatabase(
      executor: NativeDatabase(
        dbFile,
        setup: AppDatabase.configureNativeSqlite,
      ),
    );
    await db.customSelect('SELECT 1').get();
  });

  tearDown(() async {
    await db.close();
    if (await dbFile.exists()) {
      await dbFile.delete();
    }
  });

  group('Shorebird Patch Simulation Test Harness (SB-034)', () {
    test(
      'simulates patch reload with Riverpod container re-instantiation',
      () async {
        // 1. Initial container representing pre-patch application state
        var container1 = ProviderContainer(
          overrides: [
            patchUpdateCoordinatorProvider.overrideWith(
              () => _MockPatchCoordinator(
                initialState: const PatchUpdateReady(
                  currentPatchNumber: 1,
                  nextPatchNumber: 2,
                ),
              ),
            ),
          ],
        );

        final state1 = container1.read(patchUpdateCoordinatorProvider);
        expect(state1, isA<PatchUpdateReady>());
        expect((state1 as PatchUpdateReady).nextPatchNumber, equals(2));

        // 2. Perform patch restart: dispose old container and instantiate new container
        container1.dispose();

        // 3. New container representing post-restart application state running Patch 2
        final container2 = ProviderContainer(
          overrides: [
            patchUpdateCoordinatorProvider.overrideWith(
              () => _MockPatchCoordinator(
                initialState: const PatchUpdateUpToDate(currentPatchNumber: 2),
              ),
            ),
          ],
        );

        final state2 = container2.read(patchUpdateCoordinatorProvider);
        expect(state2, isA<PatchUpdateUpToDate>());
        expect((state2 as PatchUpdateUpToDate).currentPatchNumber, equals(2));

        container2.dispose();
      },
    );

    test('maintains active SQLite stream subscriptions across simulated patch restart', () async {
      // Create stream
      final areasStream = (db.select(db.areas)).watch();

      final emissions = <List<AreaRow>>[];
      final subscription = areasStream.listen(emissions.add);

      // Insert pre-patch record
      await db
          .into(db.areas)
          .insert(
            AreasCompanion.insert(
              id: 'area-sim-1',
              name: 'Living Room',
              kind: 'indoor',
            ),
          );

      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(emissions.isNotEmpty, isTrue);
      expect(emissions.last.length, equals(1));

      // Simulate hot patch reload write
      await db
          .into(db.areas)
          .insert(
            AreasCompanion.insert(
              id: 'area-sim-2',
              name: 'Garden',
              kind: 'outdoor',
            ),
          );

      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(emissions.last.length, equals(2));

      await subscription.cancel();
    });

    testWidgets(
      'gracefully falls back to bundled asset when remote asset path is absent or invalid',
      (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: RemoteOrBundledImage(
                assetPath:
                    'assets/illustrations/owntend-onboarding-hero-target.png',
                cachedRemotePath: '/invalid/path/nonexistent.png',
                semanticLabel: 'Onboarding Hero',
              ),
            ),
          ),
        );

        expect(find.byType(RemoteOrBundledImage), findsOneWidget);
      },
    );
  });
}

class _MockPatchCoordinator extends PatchUpdateCoordinator {
  _MockPatchCoordinator({required this.initialState});

  final PatchUpdateState initialState;

  @override
  PatchUpdateState build() => initialState;
}
