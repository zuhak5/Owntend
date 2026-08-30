import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:owntend/src/core/domain/contracts.dart';
import 'package:owntend/src/core/sync/sync_contracts.dart';
import 'package:owntend/src/core/services/feedback_messenger.dart';
import 'package:owntend/src/ui/feedback/feedback_coordinator.dart';

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

  group('backup screen status', () {
    testWidgets(
      'backup screen renders polished status and toggles automation',
      (tester) async {
        final repository = FakeBackupRepository(
          state: BackupState(
            lastBackup: BackupStatus(
              successful: true,
              updatedAt: DateTime(2026, 7, 10, 14, 30),
              createdAt: DateTime(2026, 7, 10, 14, 30),
              trigger: BackupTrigger.manual,
              path: 'C:\\backups\\owntend-backup.zip',
              sizeBytes: 3 * 1024 * 1024,
              message: 'Backup verified and ready.',
            ),
          ),
        );

        await pumpBackupScreen(tester, repository: repository);

        expect(find.text('Latest backup'), findsOneWidget);
        expect(find.text('Export diagnostics'), findsNothing);
        expect(find.text('Available'), findsOneWidget);
        expect(find.text('Backup complete'), findsOneWidget);
        expect(find.text('Create backup'), findsWidgets);
        expect(find.text('Share latest backup'), findsOneWidget);
        expect(find.text('Automatic local backups'), findsOneWidget);

        await tester.tap(find.byType(Switch));
        await tester.pumpAndSettle();

        expect(repository.automaticBackupsEnabled, isFalse);
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('create backup button', () {
    testWidgets('backup passphrases preserve intentional whitespace', (
      tester,
    ) async {
      final repository = FakeBackupRepository();
      await pumpBackupScreen(tester, repository: repository);

      await tester.tap(find.widgetWithText(FilledButton, 'Create backup'));
      await tester.pumpAndSettle();
      final dialog = find.byType(AlertDialog);
      final fields = find.descendant(
        of: dialog,
        matching: find.byType(TextField),
      );
      expect(fields, findsNWidgets(2));
      const passphrase = ' secret12 ';
      await tester.enterText(fields.at(0), passphrase);
      await tester.enterText(fields.at(1), passphrase);
      await tester.tap(
        find.descendant(
          of: dialog,
          matching: find.widgetWithText(FilledButton, 'Create backup'),
        ),
      );
      await tester.pumpAndSettle();

      expect(repository.lastExportPassphrase, passphrase);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'backup button stays inline and never flickers for fast success',
      (tester) async {
        final repository = FakeBackupRepository(
          exportCompleter: Completer<String>()
            ..complete('C:\\backups\\owntend-backup.zip'),
        );

        await pumpBackupScreen(tester, repository: repository);

        final button = find.widgetWithText(FilledButton, 'Create backup');
        final initialSize = tester.getSize(button);

        await tester.tap(button);
        await tester.pumpAndSettle();
        // The passphrase dialog guards the export; confirm with the
        // device-protected (empty) choice.
        final dialogConfirm = find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Create backup'),
        );
        await tester.tap(dialogConfirm);
        await tester.pumpAndSettle();

        expect(repository.exportCount, 1);
        expect(find.text('Creating backup...'), findsNothing);
        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(
          find.widgetWithText(FilledButton, 'Create backup'),
          findsOneWidget,
        );
        expect(tester.getSize(button), initialSize);

        await tester.pumpAndSettle();

        expect(find.text('Create backup'), findsWidgets);
        expect(find.text('Creating backup...'), findsNothing);
        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(find.textContaining('owntend-backup.zip'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('backup button shows inline loading after the delay', (
      tester,
    ) async {
      final completer = Completer<String>();
      final repository = FakeBackupRepository(exportCompleter: completer);

      await pumpBackupScreen(tester, repository: repository);

      final button = find.widgetWithText(FilledButton, 'Create backup');
      final initialSize = tester.getSize(button);

      await tester.tap(button);
      await tester.pumpAndSettle();
      final dialogConfirm = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Create backup'),
      );
      // Dialog dismissal is animated while the export is already in flight;
      // fixed pumps avoid waiting on the intentionally endless busy indicator.
      await tester.tap(dialogConfirm);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      expect(repository.exportCount, 1);
      expect(find.text('Creating backup...'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(tester.getSize(button), initialSize);

      await tester.pump(const Duration(milliseconds: 401));
      expect(find.text('Creating backup...'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(tester.getSize(button), initialSize);

      completer.complete('C:\\backups\\owntend-backup.zip');
      await tester.pumpAndSettle();

      expect(find.text('Creating backup...'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.textContaining('owntend-backup.zip'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('backup button ignores repeated taps while running', (
      tester,
    ) async {
      final completer = Completer<String>();
      final repository = FakeBackupRepository(exportCompleter: completer);

      await pumpBackupScreen(tester, repository: repository);

      final button = find.widgetWithText(FilledButton, 'Create backup');

      await tester.tap(button);
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Create backup'),
        ),
      );
      // Fixed pumps: the busy indicator runs until the completer fires.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      // A second tap while the export is running is ignored.
      await tester.tap(button);
      await tester.pump();

      expect(repository.exportCount, 1);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      completer.complete('C:\\backups\\owntend-backup.zip');
      await tester.pumpAndSettle();

      expect(find.textContaining('owntend-backup.zip'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('backup button resets after failure', (tester) async {
      final repository = FakeBackupRepository(
        exportCompleter: Completer<String>()
          ..complete('C:\\backups\\owntend-backup.zip'),
        exportError: StateError('disk full'),
      );

      await pumpBackupScreen(tester, repository: repository);

      final button = find.widgetWithText(FilledButton, 'Create backup');
      await tester.tap(button);
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Create backup'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Creating backup...'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(
        find.widgetWithText(FilledButton, 'Create backup'),
        findsOneWidget,
      );
      expect(find.textContaining('could not be completed'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('backup button does not update after disposal', (tester) async {
      final completer = Completer<String>();
      final repository = FakeBackupRepository(exportCompleter: completer);

      await pumpBackupScreen(tester, repository: repository);

      await tester.tap(find.widgetWithText(FilledButton, 'Create backup'));
      await tester.pump();

      await tester.pumpWidget(const SizedBox.shrink());
      completer.complete('C:\\backups\\owntend-backup.zip');
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });

  group('restore preview flow', () {
    testWidgets(
      'restore preserves passphrase bytes and forwards the local-only choice',
      (tester) async {
        final repository = FakeBackupRepository(
          requireRestorePassphrase: true,
          preview: BackupPreview(
            path: 'C:\\backups\\selected.owntend-backup',
            createdAt: DateTime(2026, 8, 30, 9),
            formatVersion: 1,
            schemaVersion: 1,
            backupSizeBytes: 1024,
            databaseSizeBytes: 512,
            fileCount: 0,
            counts: const {},
            includedData: const [],
            excludedData: const [],
            warnings: const [],
          ),
        );
        final picker = FakeFilePicker('C:\\backups\\selected.owntend-backup');
        final previousPicker = installFilePicker(picker);
        addTearDown(() {
          if (previousPicker != null) {
            FilePickerPlatform.instance = previousPicker;
          }
        });
        final sync = FakeCloudSyncRepository(
          const SyncStatus(phase: SyncPhase.ready, enabled: true),
        );
        await pumpBackupScreen(tester, repository: repository, sync: sync);

        await tester.tap(find.text('Choose Owntend backup'));
        await tester.pumpAndSettle();
        expect(find.text('Backup passphrase'), findsOneWidget);
        const passphrase = ' secret12 ';
        await tester.enterText(find.byType(TextField), passphrase);
        await tester.tap(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.widgetWithText(FilledButton, 'Restore backup'),
          ),
        );
        await tester.pumpAndSettle();

        final restoreButton = find.widgetWithText(
          FilledButton,
          'Restore this backup',
        );
        await tester.scrollUntilVisible(restoreButton, 300);
        await tester.pumpAndSettle();
        await tester.tap(restoreButton);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Restore locally and pause cloud backup'));
        await tester.pumpAndSettle();

        expect(repository.inspectedPassphrases, [null, passphrase]);
        expect(repository.lastRestorePassphrase, passphrase);
        expect(
          repository.lastRestoreCloudDisposition,
          RestoreCloudDisposition.localOnlyPaused,
        );
        expect(sync.disableCount, 1);
        expect(sync.fullReconcileCount, 0);
      },
    );

    testWidgets(
      'backup screen accepts only an Owntend backup and opens restore dialog',
      (tester) async {
        final repository = FakeBackupRepository(
          preview: BackupPreview(
            path: 'C:\\backups\\selected.owntend-backup',
            createdAt: DateTime(2026, 7, 11, 8, 15),
            formatVersion: 2,
            schemaVersion: 12,
            backupSizeBytes: 2 * 1024 * 1024,
            databaseSizeBytes: 640 * 1024,
            fileCount: 7,
            counts: const {
              'maintenance_plans': 4,
              'assets': 3,
              'maintenance_records': 9,
              'notifications': 2,
            },
            includedData: const ['tasks', 'items', 'history'],
            excludedData: const [
              'Android scheduled alarm handles are recreated from restored tasks and settings',
            ],
            warnings: const ['This backup was created on another device.'],
          ),
        );
        final picker = FakeFilePicker('C:\\backups\\selected.owntend-backup');
        final previousPicker = installFilePicker(picker);
        addTearDown(() {
          if (previousPicker != null) {
            FilePickerPlatform.instance = previousPicker;
          }
        });

        await pumpBackupScreen(
          tester,
          repository: repository,
          sync: FakeCloudSyncRepository(
            const SyncStatus(phase: SyncPhase.ready, enabled: true),
          ),
        );

        await tester.tap(find.text('Choose Owntend backup'));
        await tester.pumpAndSettle();

        expect(picker.pickCount, 1);
        expect(picker.lastAllowedExtensions, ['owntend-backup']);
        expect(
          repository.inspectedPath,
          'C:\\backups\\selected.owntend-backup',
        );
        expect(find.textContaining('Backup from'), findsOneWidget);
        expect(find.text('Tasks 4'), findsOneWidget);
        expect(find.text('Items 3'), findsOneWidget);
        expect(find.text('History 9'), findsOneWidget);
        expect(
          find.text(
            'This backup contains a compatibility warning. Review it before restoring.',
          ),
          findsOneWidget,
        );

        final restoreButton = find.widgetWithText(
          FilledButton,
          'Restore this backup',
        );
        await tester.ensureVisible(restoreButton);
        await tester.pumpAndSettle();
        await tester.tap(restoreButton);
        await tester.pumpAndSettle();

        expect(find.text('Restore this backup?'), findsOneWidget);
        expect(find.text('Restore and update cloud backup'), findsOneWidget);
        expect(
          find.text('Restore locally and pause cloud backup'),
          findsOneWidget,
        );
        expect(
          find.textContaining('A safety copy is created before restore starts'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('backup screen smoke', () {
    testWidgets('backup screen smokes in the permanent light narrow layout', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 760);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await pumpBackupScreen(
        tester,
        repository: FakeBackupRepository(),
        theme: testLightTheme(),
      );

      expect(find.text('Backup & Restore'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Restore from a backup'), 240);
      expect(find.text('Restore from a backup'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
