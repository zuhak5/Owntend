import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:owntend/l10n/app_localizations.dart';
import 'package:owntend/main.dart';
import 'package:owntend/src/core/domain/models.dart';
import 'package:material_symbols_icons/symbols.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final testArea = Area(
    id: 'area-1',
    name: 'Living Zone',
    kind: AreaKind.indoor,
    sortOrder: 0,
    createdAt: DateTime.utc(2026, 1, 1),
    updatedAt: DateTime.utc(2026, 1, 1),
  );

  final testRoom = Room(
    id: 'room-1',
    areaId: 'area-1',
    name: 'Living Room',
    roomType: RoomType.living,
    notes: 'Main living space',
    sortOrder: 0,
    createdAt: DateTime.utc(2026, 1, 1),
    updatedAt: DateTime.utc(2026, 1, 1),
  );

  final testAsset = Asset(
    id: 'asset-1',
    roomId: 'room-1',
    assetType: AssetType.general,
    name: 'Sofa',
    createdAt: DateTime.utc(2026, 1, 1),
    updatedAt: DateTime.utc(2026, 1, 1),
  );

  group('RoomDetailScreen route rehydration and error states', () {
    testWidgets('reconstructs room detail from roomId identity', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            areasProvider.overrideWith((ref) => Stream.value(<Area>[testArea])),
            roomsProvider.overrideWith((ref) => Stream.value(<Room>[testRoom])),
            roomAssetsProvider('room-1')
                .overrideWith((ref) => Stream.value(<Asset>[testAsset])),
            tasksProvider.overrideWith((ref) => Stream.value(<TaskItem>[])),
          ],
          child: const MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: Locale('en'),
            home: RoomDetailScreen(roomId: 'room-1'),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Living Room'), findsWidgets);
      expect(find.text('Living Zone'), findsOneWidget);
      expect(find.text('Sofa'), findsOneWidget);
    });

    testWidgets('shows explicit roomNotFound state when room does not exist', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            roomsProvider.overrideWith((ref) => Stream.value(<Room>[])),
            roomAssetsProvider('missing-room')
                .overrideWith((ref) => Stream.value(<Asset>[])),
            tasksProvider.overrideWith((ref) => Stream.value(<TaskItem>[])),
            areasProvider.overrideWith((ref) => Stream.value(<Area>[])),
          ],
          child: const MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: Locale('en'),
            home: RoomDetailScreen(roomId: 'missing-room'),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Room not found.'), findsOneWidget);
    });

    testWidgets('shows Arabic roomNotFound state in RTL locale', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            roomsProvider.overrideWith((ref) => Stream.value(<Room>[])),
            roomAssetsProvider('missing-room')
                .overrideWith((ref) => Stream.value(<Asset>[])),
            tasksProvider.overrideWith((ref) => Stream.value(<TaskItem>[])),
            areasProvider.overrideWith((ref) => Stream.value(<Area>[])),
          ],
          child: const MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: Locale('ar'),
            home: RoomDetailScreen(roomId: 'missing-room'),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('لم يتم العثور على الغرفة.'), findsOneWidget);
    });
  });

  group('Editor dirty state exit guard', () {
    testWidgets('clean RoomEditorDialog exits immediately on close', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            areasProvider.overrideWith((ref) => Stream.value(<Area>[testArea])),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('en'),
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () => showRoomEditorSheet(
                    context,
                    areaId: 'area-1',
                    room: testRoom,
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Edit room'), findsOneWidget);

      // Close without making changes
      await tester.tap(find.byIcon(Symbols.close_rounded));
      await tester.pumpAndSettle();

      // Dialog closed immediately
      expect(find.text('Edit room'), findsNothing);
      expect(find.text('Discard unsaved changes?'), findsNothing);
    });

    testWidgets(
      'dirty RoomEditorDialog prompts on close and preserves changes on cancel',
      (tester) async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              areasProvider.overrideWith(
                (ref) => Stream.value(<Area>[testArea]),
              ),
            ],
            child: MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              locale: const Locale('en'),
              home: Scaffold(
                body: Builder(
                  builder: (context) => ElevatedButton(
                    onPressed: () => showRoomEditorSheet(
                      context,
                      areaId: 'area-1',
                      room: testRoom,
                    ),
                    child: const Text('Open'),
                  ),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();

        // Modify room name
        await tester.enterText(
          find.byType(TextField).first,
          'Living Room Modified',
        );
        await tester.pump();

        // Tap close
        await tester.tap(find.byIcon(Symbols.close_rounded));
        await tester.pumpAndSettle();

        // Confirmation dialog appears
        expect(find.text('Discard unsaved changes?'), findsOneWidget);
        expect(
          find.text(
            'You have unsaved changes that will be lost if you leave now.',
          ),
          findsOneWidget,
        );

        // Tap 'Keep editing'
        await tester.tap(find.text('Keep editing'));
        await tester.pumpAndSettle();

        // Editor remains open with modified text
        expect(find.text('Edit room'), findsOneWidget);
        expect(find.text('Living Room Modified'), findsOneWidget);

        // Tap close again and choose 'Discard'
        await tester.tap(find.byIcon(Symbols.close_rounded));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Discard'));
        await tester.pumpAndSettle();

        // Editor is closed
        expect(find.text('Edit room'), findsNothing);
      },
    );

    testWidgets('dirty editor prompt is localized in Arabic', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            areasProvider.overrideWith((ref) => Stream.value(<Area>[testArea])),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('ar'),
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () => showRoomEditorSheet(
                    context,
                    areaId: 'area-1',
                    room: testRoom,
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byType(TextField).first,
        'غرفة المعيشة الجديدة',
      );
      await tester.pump();

      await tester.tap(find.byIcon(Symbols.close_rounded));
      await tester.pumpAndSettle();

      expect(
        find.text('هل تريد تجاهل التغييرات غير المحفوظة؟'),
        findsOneWidget,
      );
      expect(find.text('متابعة التعديل'), findsOneWidget);
      expect(find.text('تجاهل'), findsOneWidget);

      await tester.tap(find.text('تجاهل'));
      await tester.pumpAndSettle();

      expect(find.text('هل تريد تجاهل التغييرات غير المحفوظة؟'), findsNothing);
    });
  });
}
