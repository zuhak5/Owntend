import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:owntend/main.dart';
import 'package:owntend/l10n/app_localizations.dart';
import 'package:owntend/src/core/database/app_database.dart';
import 'package:owntend/src/core/domain/models.dart';
import 'package:owntend/src/core/sync/local_sync_store.dart';
import 'package:owntend/src/core/sync/sync_connectivity.dart';
import 'package:owntend/src/core/sync/sync_dtos.dart';
import 'package:owntend/src/features/monetization/monetization.dart';
import 'package:owntend/src/ui/feedback/feedback_coordinator.dart';

import 'support/widget_test_fakes.dart';
import 'test_theme.dart';

void main() {
  late AppDatabase db;
  late DriftAssetRepository repository;
  late Asset asset;

  setUp(() async {
    db = AppDatabase(executor: NativeDatabase.memory());
    repository = DriftAssetRepository(db);
    final areaId = await repository.saveArea(
      id: 'area_first_floor',
      name: 'Home',
      kind: AreaKind.indoor,
    );
    final roomId = await repository.saveRoom(
      id: 'room_kitchen',
      areaId: areaId,
      name: 'Kitchen',
    );
    final assetId = await repository.saveAsset(
      id: 'edited-item',
      name: 'Original',
      roomId: roomId,
      assetType: AssetType.safety,
    );
    asset = (await repository.getAsset(assetId))!;
    await LocalSyncStore(db).bindIdentity(signedInTestSession.userId);
    await db.delete(db.syncOutbox).go();
  });

  tearDown(() async {
    FeedbackCoordinator.instance.resetForTesting();
    await db.close();
  });

  for (final scenario in [
    'own pull',
    'route closed',
    'local save failure',
    'newer draft',
  ]) {
    testWidgets(
      'type-change editor preserves the complete form with $scenario',
      (tester) async {
        final settings = FakeSettingsRepository(onboardingCompletedValue: true);
        addTearDown(settings.close);
        final monetization = _PullingTypeChangeRepository(
          LocalSyncStore(db),
          asset,
        );
        final drafts = FakeOfflineCreationDraftStore();
        final editorVisible = ValueNotifier(true);
        addTearDown(editorVisible.dispose);
        if (scenario == 'local save failure') {
          await db.customStatement('''
          CREATE TRIGGER fail_editor_save BEFORE UPDATE ON assets
          WHEN NEW.name = 'Edited name'
          BEGIN SELECT RAISE(ABORT, 'injected local write failure'); END;
        ''');
        }
        final rooms = await repository.listRooms();
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              ...testOverrides(
                settings,
                assetRepository: repository,
                assets: [asset],
                rooms: rooms,
              ),
              monetizationRepositoryProvider.overrideWithValue(monetization),
              localSyncStoreProvider.overrideWithValue(LocalSyncStore(db)),
              syncConnectivityInstanceProvider.overrideWithValue(
                const AlwaysOnlineSyncConnectivity(),
              ),
              offlineCreationDraftStoreProvider.overrideWithValue(drafts),
            ],
            child: MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              theme: testLightTheme(),
              home: Scaffold(
                body: ValueListenableBuilder<bool>(
                  valueListenable: editorVisible,
                  builder: (context, visible, child) => visible
                      ? AssetEditorDialog(asset: asset, roomId: asset.roomId)
                      : const Text('Editor closed'),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.enterText(
          find.widgetWithText(TextField, 'Item name *'),
          'Edited name',
        );
        tester
            .widget<DropdownButtonFormField<AssetType>>(
              find.byKey(const ValueKey('asset-item-type-picker')),
            )
            .onChanged!(AssetType.general);
        await tester.pumpAndSettle();
        final save = find.widgetWithText(FilledButton, 'Save item');
        await tester.ensureVisible(save);
        await tester.tap(save);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        final labels = AppLocalizations.of(
          tester.element(find.byType(AlertDialog)),
        );
        await tester.tap(find.text(labels.confirmPointChargeAction));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        await tester.runAsync(() async {
          for (
            var attempt = 0;
            attempt < 50 && monetization.commits == 0;
            attempt++
          ) {
            await Future<void>.delayed(const Duration(milliseconds: 10));
          }
        });
        expect(monetization.commits, 1);
        expect(drafts.drafts.values.single['name'], 'Edited name');
        expect(drafts.drafts.values.single['asset_type'], 'general');
        if (scenario == 'route closed' || scenario == 'newer draft') {
          editorVisible.value = false;
          await tester.pump();
          expect(find.byType(AssetEditorDialog), findsNothing);
        }
        if (scenario == 'newer draft') {
          // A reopened editor persists a replacement form under the same key
          // before its quote/confirmation. The first continuation owns only the
          // draft it saved, even if that later confirmation is cancelled.
          final key = drafts.drafts.keys.single;
          await drafts.save(key, {
            ...drafts.drafts[key]!,
            'name': 'Newer unfinished form',
          });
        }
        await tester.runAsync(() async {
          monetization.responseGate.complete();
          for (var attempt = 0; attempt < 50; attempt++) {
            if (scenario == 'local save failure' || drafts.drafts.isEmpty) {
              break;
            }
            await Future<void>.delayed(const Duration(milliseconds: 10));
          }
        });
        await tester.pumpAndSettle();
        expect(monetization.commits, 1);
        final updated = (await repository.getAsset(asset.id))!;
        expect(updated.assetType, AssetType.general);
        if (scenario == 'local save failure') {
          expect(updated.name, 'Original');
          expect(drafts.drafts.values.single['name'], 'Edited name');
          // The saved form reopens against the now-canonical type and can finish
          // as an ordinary CAS edit without another authoritative charge.
          await db.customStatement('DROP TRIGGER fail_editor_save');
          editorVisible.value = false;
          await tester.pump();
          asset = updated;
          editorVisible.value = true;
          await tester.pumpAndSettle();
          expect(find.text('Edited name'), findsOneWidget);
          final retry = find.widgetWithText(FilledButton, 'Save item');
          await tester.ensureVisible(retry);
          await tester.runAsync(() async {
            await tester.tap(retry);
            for (
              var attempt = 0;
              attempt < 50 && drafts.drafts.isNotEmpty;
              attempt++
            ) {
              await Future<void>.delayed(const Duration(milliseconds: 10));
            }
          });
          await tester.pumpAndSettle();
          expect((await repository.getAsset(asset.id))!.name, 'Edited name');
          expect(monetization.commits, 1);
        } else {
          expect(updated.name, 'Edited name');
        }
        if (scenario == 'newer draft') {
          expect(
            drafts.drafts,
            hasLength(1),
            reason: 'An older save must retain the newer unfinished draft.',
          );
          expect(drafts.drafts.values.single['name'], 'Newer unfinished form');
        } else {
          expect(drafts.drafts, isEmpty);
        }
        expect(tester.takeException(), isNull);
      },
    );
  }
}

class _PullingTypeChangeRepository extends MonetizationRepository {
  _PullingTypeChangeRepository(this.store, this.original);
  final LocalSyncStore store;
  final Asset original;
  int commits = 0;
  final responseGate = Completer<void>();

  @override
  String get currentUserId => signedInTestSession.userId;

  @override
  Future<AuthoritativeQuote> quoteAssetTypeChange({
    required String assetId,
    required String targetType,
  }) async => const AuthoritativeQuote(charge: 1, balance: 5, revision: 1);

  @override
  Future<AuthoritativeMutationResult> changeAssetType(
    Map<String, dynamic> operation,
  ) async {
    commits++;
    final canonical = <String, dynamic>{
      'id': original.id,
      'user_id': currentUserId,
      'name': original.name,
      'asset_type': operation['target_type'],
      'room_id': original.roomId,
      'placement': original.placement,
      'notes': original.notes,
      'purchase_date': original.purchaseDate?.toUtc().toIso8601String(),
      'created_at': original.createdAt.toUtc().toIso8601String(),
      'updated_at': original.updatedAt
          .add(const Duration(seconds: 5))
          .toUtc()
          .toIso8601String(),
      'archived_at': null,
      'revision': 2,
    };
    // The real feed applier commits the server's type change before the RPC
    // response reaches the editor. The editor must not reject its own change.
    await store.applyRemoteRecords([
      SyncRecord.fromRemote(syncSpecByEntity['asset']!, canonical),
    ]);
    await responseGate.future;
    return AuthoritativeMutationResult(
      status: 'applied',
      charged: 1,
      balance: 4,
      alreadyProcessed: false,
      asset: canonical,
    );
  }
}
