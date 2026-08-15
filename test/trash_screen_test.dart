import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:owntend/l10n/app_localizations.dart';
import 'package:owntend/main.dart';
import 'package:owntend/src/core/domain/contracts.dart';
import 'package:owntend/src/core/domain/models.dart';
import 'package:owntend/src/ui/feedback/feedback_coordinator.dart';

import 'test_theme.dart';

class _FakeAssetRepo implements AssetRepository {
  _FakeAssetRepo({this.archivedAreas = const []});

  final List<Area> archivedAreas;
  bool emptyTrashCalled = false;

  @override
  Future<void> emptyTrash() async {
    emptyTrashCalled = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSearchRepo implements SearchRepository {
  @override
  Future<void> rebuildIndex() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUp(FeedbackCoordinator.instance.resetForTesting);
  tearDown(FeedbackCoordinator.instance.resetForTesting);

  testWidgets('TrashScreen shows empty state when no trashed items exist', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          archivedAreasProvider.overrideWith((ref) => Stream.value(const [])),
          archivedRoomsProvider.overrideWith((ref) => Stream.value(const [])),
          archivedAssetsProvider.overrideWith((ref) => Stream.value(const [])),
          archivedTasksProvider.overrideWith((ref) => Stream.value(const [])),
        ],
        child: MaterialApp(
          theme: testLightTheme(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const TrashScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Trash is empty'), findsOneWidget);
    expect(find.text('Empty Trash'), findsNothing);
  });

  testWidgets(
    'TrashScreen shows Empty Trash button and prompts confirmation dialog',
    (tester) async {
      final fakeAssetRepo = _FakeAssetRepo(
        archivedAreas: [
          Area(
            id: 'area_1',
            name: 'Old Shed',
            kind: AreaKind.outdoor,
            sortOrder: 0,
            createdAt: DateTime.utc(2026, 8, 1),
            updatedAt: DateTime.utc(2026, 8, 1),
            archivedAt: DateTime.utc(2026, 8, 2),
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            assetRepositoryProvider.overrideWithValue(fakeAssetRepo),
            searchRepositoryProvider.overrideWithValue(_FakeSearchRepo()),
            archivedAreasProvider.overrideWith(
              (ref) => Stream.value(fakeAssetRepo.archivedAreas),
            ),
            archivedRoomsProvider.overrideWith((ref) => Stream.value(const [])),
            archivedAssetsProvider.overrideWith(
              (ref) => Stream.value(const []),
            ),
            archivedTasksProvider.overrideWith((ref) => Stream.value(const [])),
          ],
          child: MaterialApp(
            theme: testLightTheme(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const TrashScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Old Shed'), findsOneWidget);
      final emptyTrashButton = find.text('Empty Trash');
      expect(emptyTrashButton, findsOneWidget);

      // Tap Empty Trash button
      await tester.tap(emptyTrashButton);
      await tester.pumpAndSettle();

      // Verify confirmation dialog
      expect(find.text('Empty Trash?'), findsOneWidget);
      expect(
        find.text(
          'All items in Trash will be permanently deleted. This action cannot be undone.',
        ),
        findsOneWidget,
      );

      // Confirm
      final confirmAction = find.text('Empty');
      expect(confirmAction, findsOneWidget);
      await tester.tap(confirmAction);
      await tester.pumpAndSettle();

      expect(fakeAssetRepo.emptyTrashCalled, isTrue);
    },
  );
}
