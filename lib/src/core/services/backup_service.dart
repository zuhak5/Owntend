import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' show UpdateKind, Variable;
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:uuid/uuid.dart';

import '../database/app_database.dart';
import '../domain/contracts.dart';
import '../supabase/secure_supabase_storage.dart';
import '../sync/local_sync_store.dart';
import '../utils/user_facing_errors.dart';
import 'backup/backup_container.dart';
import 'restore_journal.dart';
import 'sidecar_registry.dart';

const _uuid = Uuid();
const _currentFormatVersion = 1;
const _manifestName = 'manifest.json';
const _backupStateFileName = 'owntend-backup-state.json';
const _backupFolderName = 'backups';
const _backupFileExtension = '.owntend-backup';
const _maxBackupBytes = 256 * 1024 * 1024;
const _maxExtractedBytes = 512 * 1024 * 1024;
const _maxSingleEntryBytes = 256 * 1024 * 1024;
const _maxManifestBytes = 128 * 1024;
const _maxEntryCount = 10000;
const _minimumPassphraseLength = 8;
const _automaticBackupInterval = Duration(hours: 24);
const _maximumAutomaticBackups = 7;

const _mediaRoots = kRestoreMediaRoots;
const _allowedRootFiles = {_manifestName, AppDatabase.databaseFileName};
const _allowedRootDirectories = {'photos', 'profile', 'cloud_media'};

const _includedData = [
  'Tasks and due dates',
  'Items, rooms, areas, tags, and photos',
  'Task history, timeline, streaks, and statistics source data',
  'Notification preferences, inbox history, and snooze defaults',
  'Theme, profile, weather location, and app settings',
];

const _excludedData = [
  'Android scheduled alarm handles are recreated from restored tasks and settings',
];

const _currentSchemaTables = [
  'areas',
  'rooms',
  'assets',
  'device_details',
  'pet_details',
  'plant_details',
  'safety_details',
  'tags',
  'asset_tags',
  'asset_photos',
  'maintenance_plans',
  'maintenance_plan_metadata',
  'maintenance_records',
  'notification_inbox',
  'settings',
  'streaks',
];

class BackupException implements Exception {
  const BackupException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Thrown when a user-passphrase backup is inspected or restored without a
/// passphrase. The UI maps this to the passphrase prompt.
class BackupPassphraseRequiredException implements Exception {
  const BackupPassphraseRequiredException();

  @override
  String toString() => 'Passphrase required to open this backup.';
}

/// Injectable process-death simulation for restore tests. Each named
/// failpoint throws on its configured occurrence number; production leaves
/// the map empty.
class RestoreFailpoints {
  RestoreFailpoints([Map<String, int>? throwOnOccurrence])
    : _throwOnOccurrence = Map<String, int>.of(throwOnOccurrence ?? const {});

  final Map<String, int> _throwOnOccurrence;
  final Map<String, int> _occurrences = {};

  void maybeThrow(String name) {
    final limit = _throwOnOccurrence[name];
    if (limit == null) return;
    final seen = (_occurrences[name] ?? 0) + 1;
    _occurrences[name] = seen;
    if (seen == limit) {
      throw StateError('Injected restore failure at failpoint: $name');
    }
  }

  /// Runs [action], treating a wrapped failure as hitting the failpoint.
  Future<T> guard<T>(String name, Future<T> Function() action) async {
    maybeThrow(name);
    try {
      return await action();
    } on Object {
      final limit = _throwOnOccurrence[name];
      if (limit != null && (_occurrences[name] ?? 0) < limit) {
        _occurrences[name] = (_occurrences[name] ?? 0) + 1;
        if (_occurrences[name] == limit) {
          throw StateError('Injected restore failure at failpoint: $name');
        }
      }
      rethrow;
    }
  }
}

class OwntendBackupService
    implements BackupService, RestoreService, BackupRepository {
  OwntendBackupService(
    this.db, {
    RestoreJournalStore? journalStore,
    SidecarRegistryStore? sidecarRegistry,
    this.onBeforeRestoreBarrier,
    RestoreFailpoints? failpoints,
    this.onRestoreCommit,
  }) : journalStore = journalStore ?? RestoreJournalStore(),
       sidecarRegistry = sidecarRegistry ?? SidecarRegistryStore(),
       failpoints = failpoints ?? RestoreFailpoints();

  final AppDatabase db;
  final RestoreJournalStore journalStore;
  final SidecarRegistryStore sidecarRegistry;
  final Future<void> Function()? onBeforeRestoreBarrier;
  final RestoreFailpoints failpoints;

  /// WP-005 (F-007): invoked exactly once per verified restore commit so the
  /// owning layer can publish the database epoch. The service never touches
  /// Riverpod; it only reports that the imported generation is proven durable
  /// and fully activated. Every restore path through this service therefore
  /// rebuilds dependent streams, not just the backup screen.
  final void Function()? onRestoreCommit;

  static bool _operationInProgress = false;

  @override
  Future<String> exportBackup({
    BackupTrigger trigger = BackupTrigger.manual,
    String? passphrase,
  }) {
    return exportZip(trigger: trigger, passphrase: passphrase);
  }

  @override
  Future<String> exportZip({
    BackupTrigger trigger = BackupTrigger.manual,
    String? passphrase,
  }) {
    return _runExclusive(
      () => _exportContainerInternal(
        trigger: trigger,
        passphrase: passphrase,
        updateStatus: true,
      ),
    );
  }

  @override
  Future<String?> exportAutomaticBackupIfDue() async {
    final state = await backupState();
    if (!state.automaticBackupsEnabled) {
      return null;
    }
    final last = state.lastBackup;
    final lastCreated = last?.createdAt ?? last?.updatedAt;
    if (last != null &&
        last.successful &&
        lastCreated != null &&
        DateTime.now().toUtc().difference(lastCreated.toUtc()) <
            _automaticBackupInterval) {
      return null;
    }
    // Automatic exports never receive the user's passphrase; they are
    // encrypted with a device-local key held in platform secure storage.
    return exportZip(trigger: BackupTrigger.automatic);
  }

  @override
  Future<BackupState> backupState() async {
    final file = await _stateFile();
    if (!await file.exists()) {
      return const BackupState();
    }
    try {
      final decoded =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      return BackupState(
        automaticBackupsEnabled:
            decoded['automaticBackupsEnabled'] as bool? ?? true,
        lastBackup: _statusFromJson(
          decoded['lastBackup'] as Map<String, dynamic>?,
        ),
      );
    } catch (_) {
      return const BackupState();
    }
  }

  @override
  Future<void> setAutomaticBackupsEnabled(bool enabled) async {
    final current = await backupState();
    await _writeBackupState(
      BackupState(
        automaticBackupsEnabled: enabled,
        lastBackup: current.lastBackup,
      ),
    );
  }

  @override
  Future<BackupPreview> inspectBackup(
    String zipPath, {
    String? passphrase,
  }) async {
    final validation = await _validateBackup(zipPath, passphrase: passphrase);
    try {
      return validation.preview;
    } finally {
      await validation.dispose();
    }
  }

  @override
  Future<void> restoreBackup(String zipPath, {String? passphrase}) =>
      restoreZip(zipPath, passphrase: passphrase);

  @override
  Future<void> restore(String zipPath, {String? passphrase}) =>
      restoreZip(zipPath, passphrase: passphrase);

  @override
  Future<void> restoreZip(String zipPath, {String? passphrase}) {
    return _runExclusive(() => _restoreZipInternal(zipPath, passphrase));
  }

  Future<void> _restoreZipInternal(String zipPath, String? passphrase) async {
    final validation = await _validateBackup(
      zipPath,
      passphrase: passphrase,
      extractAll: true,
    );
    final archiveHash = await _fileSha256Hex(zipPath);
    final now = DateTime.now();
    final localSyncStore = LocalSyncStore(db);
    final syncAccount = await localSyncStore.account();
    final boundUserId = syncAccount.boundUserId?.trim();
    final accountScope = boundUserId == null || boundUserId.isEmpty
        ? 'localOnly'
        : boundUserId;
    final updateCloudIntent =
        accountScope != 'localOnly' &&
        await localSyncStore.hasCompleteSnapshotForUser(accountScope);

    var journalEntry = RestoreJournalEntry(
      version: kCurrentRestoreJournalVersion,
      journalId: _uuid.v7(),
      accountScope: accountScope,
      archivePath: zipPath,
      archiveHash: archiveHash,
      phase: RestorePhase.validated,
      updateCloudIntent: updateCloudIntent,
      createdAt: now,
      updatedAt: now,
    );
    await journalStore.saveEntry(journalEntry);

    String? safetyBackupPath;
    try {
      try {
        safetyBackupPath = await _exportContainerInternal(
          trigger: BackupTrigger.preRestore,
          passphrase: null,
          updateStatus: false,
        );
      } catch (error) {
        await journalStore.clearActiveEntry();
        throw BackupException(
          'Restore was stopped because Owntend could not create a safety copy of your current data. '
          'Free up storage, create a manual backup, then try restore again. Details: $error',
        );
      }

      final safetyBackupHash = await _fileSha256Hex(safetyBackupPath);
      journalEntry = journalEntry.copyWith(
        phase: RestorePhase.safetyBackupComplete,
        safetyBackupPath: safetyBackupPath,
        safetyBackupHash: safetyBackupHash,
        updatedAt: DateTime.now(),
      );
      await journalStore.saveEntry(journalEntry);

      if (onBeforeRestoreBarrier != null) {
        await onBeforeRestoreBarrier!();
      }
      journalEntry = journalEntry.copyWith(
        phase: RestorePhase.servicesSuspended,
        updatedAt: DateTime.now(),
      );
      await journalStore.saveEntry(journalEntry);

      final appDir = await getApplicationDocumentsDirectory();
      final extractedDb = File(
        p.join(
          validation.extractedDirectory.path,
          AppDatabase.databaseFileName,
        ),
      );
      final mediaToken = _uuid.v7();
      journalEntry = journalEntry.copyWith(
        phase: RestorePhase.mediaStaged,
        mediaToken: mediaToken,
        updatedAt: DateTime.now(),
      );
      await journalStore.saveEntry(journalEntry);
      failpoints.maybeThrow('journal:mediaStaged');

      // Staging copies media only. Canonical folders stay untouched until the
      // imported database generation is proven committed, so a crash can
      // never pair the old database with new media.
      final stagedGenerations = await _stageMediaFolders(
        appDir: appDir,
        extractedDir: validation.extractedDirectory,
        activeJournalId: journalEntry.journalId,
        token: mediaToken,
      );

      journalEntry = journalEntry.copyWith(
        phase: RestorePhase.dbCommitStarted,
        updatedAt: DateTime.now(),
      );
      await journalStore.saveEntry(journalEntry);
      failpoints.maybeThrow('journal:dbCommitStarted');

      try {
        await failpoints.guard('db:importCommit', () {
          return LocalSyncStore(db).withOutboxSuppressed(
            () => _importDatabaseFrom(
              extractedDb.path,
              generationMarker: journalEntry.journalId,
            ),
          );
        });
      } catch (_) {
        await rollbackStagedMediaGenerations(appDir: appDir, token: mediaToken);
        await journalStore.clearActiveEntry();
        rethrow;
      }
      failpoints.maybeThrow('db:importCommit:returned');

      // The import transaction committed (the generation marker is durable).
      // Persist the advisory phase, then activate the staged media.
      journalEntry = journalEntry.copyWith(
        phase: RestorePhase.dbCommitComplete,
        updatedAt: DateTime.now(),
      );
      await journalStore.saveEntry(journalEntry);
      failpoints.maybeThrow('journal:dbCommitComplete');

      await _activateStagedMedia(
        appDir: appDir,
        token: mediaToken,
        stagedGenerations: stagedGenerations,
        failpoints: failpoints,
      );

      journalEntry = journalEntry.copyWith(
        phase: RestorePhase.mediaActivated,
        updatedAt: DateTime.now(),
      );
      await journalStore.saveEntry(journalEntry);
      failpoints.maybeThrow('journal:mediaActivated');

      if (journalEntry.updateCloudIntent) {
        await localSyncStore.enqueueRestoreSnapshot(DateTime.now());
      } else {
        await localSyncStore.pauseAfterLocalRestore();
      }
      journalEntry = journalEntry.copyWith(
        phase: RestorePhase.cloudIntentDurable,
        updatedAt: DateTime.now(),
      );
      await journalStore.saveEntry(journalEntry);
      failpoints.maybeThrow('journal:cloudIntentDurable');

      final safetyBackup = File(safetyBackupPath);
      final safetyBackupStat = await safetyBackup.stat();
      final completedAt = DateTime.now().toUtc();
      await _recordStatus(
        BackupStatus(
          successful: true,
          updatedAt: completedAt,
          trigger: BackupTrigger.preRestore,
          path: safetyBackupPath,
          createdAt: completedAt,
          sizeBytes: safetyBackupStat.size,
          message:
              'Restore completed from ${p.basename(zipPath)}. Safety backup saved before restore.',
        ),
      );

      // Cleanup boundary: only after DB commit proof and full media
      // activation are the retained old generations removed.
      failpoints.maybeThrow('cleanup:previousGenerations');
      await cleanupPreviousMediaGenerations(appDir: appDir, token: mediaToken);
      await _removeRestoreSidecars(mediaToken);

      journalEntry = journalEntry.copyWith(
        phase: RestorePhase.terminal,
        updatedAt: DateTime.now(),
      );
      await journalStore.saveEntry(journalEntry);
      await journalStore.clearActiveEntry();

      // WP-005 (F-007): publish the restore epoch from the service layer so
      // every completion path rebuilds dependent streams. Fired only after
      // the commit marker, media activation, cloud intent, status recording,
      // and cleanup are all durable — the very last service action, because
      // the epoch bump may dispose the database connection this instance
      // holds.
      onRestoreCommit?.call();
    } finally {
      await validation.dispose();
    }
  }

  Future<T> _runExclusive<T>(Future<T> Function() action) async {
    if (_operationInProgress) {
      throw const BackupException(
        'Another backup or restore is already running. Wait for it to finish, then try again.',
      );
    }
    _operationInProgress = true;
    try {
      return await action();
    } finally {
      _operationInProgress = false;
    }
  }

  Future<String> _exportContainerInternal({
    required BackupTrigger trigger,
    required String? passphrase,
    required bool updateStatus,
  }) async {
    final createdAt = DateTime.now().toUtc();
    File? snapshot;
    File? partialBackup;
    final keyGuard = passphrase == null
        ? BackupContainerCodec.keyGuardDeviceKey
        : BackupContainerCodec.keyGuardUserPassphrase;
    if (passphrase != null && passphrase.length < _minimumPassphraseLength) {
      throw const BackupException(
        'Use a passphrase of at least 8 characters so the backup stays protected.',
      );
    }
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final tempDir = await getTemporaryDirectory();
      final backupDir = await _backupDirectory();
      snapshot = File(p.join(tempDir.path, 'owntend-${_uuid.v7()}.sqlite'));
      if (await snapshot.exists()) {
        await snapshot.delete();
      }

      await db.customStatement(
        "VACUUM INTO '${snapshot.path.replaceAll("'", "''")}'",
      );

      final databaseBytesCount = await snapshot.length();
      final databaseHash = (await sha256.bind(snapshot.openRead()).first)
          .toString();
      final manifestFiles = <Map<String, Object>>[];
      manifestFiles.add({
        'path': AppDatabase.databaseFileName,
        'bytes': databaseBytesCount,
        'sha256': databaseHash,
      });

      final userFiles = await _collectUserFiles(appDir);
      for (final entry in userFiles) {
        manifestFiles.add({
          'path': entry.path,
          'bytes': entry.bytes,
          'sha256': entry.sha256,
        });
      }
      final payloadBytes =
          databaseBytesCount +
          userFiles.fold<int>(0, (total, entry) => total + entry.bytes);

      final databaseSummary = _readDatabaseSummary(
        snapshot.path,
        manifestSchemaVersion: db.schemaVersion,
      );
      final manifest = <String, Object?>{
        'app': 'Owntend',
        'format': _currentFormatVersion,
        'schemaVersion': db.schemaVersion,
        'createdAt': createdAt.toIso8601String(),
        'trigger': trigger.name,
        'payloadBytes': payloadBytes,
        'database': {
          'path': AppDatabase.databaseFileName,
          'bytes': databaseBytesCount,
          'sha256': databaseHash,
        },
        'files': manifestFiles,
        'counts': databaseSummary.counts,
        'includedData': _includedData,
        'excludedData': _excludedData,
        'warnings': databaseSummary.warnings,
        'secretsIncluded': false,
      };

      final filename =
          '${_filePrefix(trigger)}-${_timestampForFile(createdAt)}-'
          '${_uuid.v7().substring(0, 8)}$_backupFileExtension';
      final backup = File(p.join(backupDir.path, filename));
      partialBackup = File('${backup.path}.partial');
      if (await partialBackup.exists()) {
        await partialBackup.delete();
      }

      // Write the authenticated streaming container: manifest frame first,
      // then the database snapshot and every media entry as AEAD chunks.
      final effectiveSecret = passphrase ?? await BackupAutoKeyStore.load();
      final random = await partialBackup.open(mode: FileMode.write);
      try {
        final writer = await BackupContainerWriter.start(
          output: random,
          passphrase: effectiveSecret,
          keyGuard: keyGuard,
          fastProfile:
              trigger == BackupTrigger.automatic ||
              trigger == BackupTrigger.preRestore,
        );
        await writer.writeFrame(utf8.encode(_prettyJson(manifest)));
        await writer.writeStream(snapshot.openRead());
        for (final entry in userFiles) {
          await writer.writeStream(entry.file.openRead());
        }
        writer.destroyKey();
        await random.flush();
      } finally {
        await random.close();
      }

      // Self-verification before the atomic rename: one authenticated
      // read-back pass whose decrypted payload length must equal the declared
      // total. The container is only published after this passes.
      await _verifyContainerSelf(partialBackup, effectiveSecret);

      final completed = await partialBackup.rename(backup.path);
      partialBackup = null;

      if (trigger == BackupTrigger.automatic) {
        await _pruneAutomaticBackups(backupDir);
      }
      if (updateStatus) {
        await _recordStatus(
          BackupStatus(
            successful: true,
            updatedAt: DateTime.now().toUtc(),
            trigger: trigger,
            path: completed.path,
            createdAt: createdAt,
            sizeBytes: await completed.length(),
            message: 'Backup completed.',
          ),
        );
      }
      return completed.path;
    } catch (error) {
      if (updateStatus) {
        await _recordStatus(
          BackupStatus(
            successful: false,
            updatedAt: DateTime.now().toUtc(),
            trigger: trigger,
            message: _friendlyError(error),
          ),
        );
      }
      if (error is BackupException) {
        rethrow;
      }
      throw BackupException(
        'Backup could not be created. Check available storage and try again. Details: $error',
      );
    } finally {
      if (snapshot != null && await snapshot.exists()) {
        await snapshot.delete();
      }
      if (partialBackup != null && await partialBackup.exists()) {
        await partialBackup.delete();
      }
    }
  }

  /// Authenticated read-back of a freshly written container. A single pass
  /// verifies every frame MAC, parses the manifest frame, and checks the
  /// decrypted payload length against the declared total.
  Future<void> _verifyContainerSelf(File file, String secret) async {
    final handle = await file.open(mode: FileMode.read);
    try {
      final reader = await BackupContainerReader.open(
        input: handle,
        passphrase: secret,
      );
      try {
        Map<String, dynamic>? manifest;
        var verifiedBytes = 0;
        var frameIndex = 0;
        while (true) {
          final frame = await reader.readFrame(handle);
          if (frame == null) break;
          if (frameIndex == 0) {
            try {
              manifest = jsonDecode(utf8.decode(frame)) as Map<String, dynamic>;
            } on Object {
              throw const BackupException(
                'Backup container failed self-verification: manifest unreadable.',
              );
            }
          } else {
            verifiedBytes += frame.length;
          }
          frameIndex++;
        }
        if (manifest == null) {
          throw const BackupException(
            'Backup container failed self-verification: manifest missing.',
          );
        }
        final declared = _readInt(manifest, 'payloadBytes', fallback: -1);
        if (declared < 0 || declared != verifiedBytes) {
          throw const BackupException(
            'Backup container failed self-verification. The backup was not saved.',
          );
        }
      } finally {
        reader.destroyKey();
      }
    } on BackupContainerFormatException catch (error) {
      throw BackupException(
        'Backup container failed self-verification (${error.message}). '
        'The backup was not saved.',
      );
    } finally {
      await handle.close();
    }
  }

  Future<List<_DiskBackupEntry>> _collectUserFiles(Directory appDir) async {
    final entries = <_DiskBackupEntry>[];
    for (final root in _mediaRoots) {
      final dir = Directory(p.join(appDir.path, root));
      if (!await dir.exists()) {
        continue;
      }
      await for (final entity in dir.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is! File) {
          continue;
        }
        final relative = p
            .relative(entity.path, from: appDir.path)
            .replaceAll('\\', '/');
        if (!_isAllowedBackupPath(relative)) {
          continue;
        }
        final size = await entity.length();
        final hash = (await sha256.bind(entity.openRead()).first).toString();
        entries.add(
          _DiskBackupEntry(
            path: relative,
            file: entity,
            bytes: size,
            sha256: hash,
          ),
        );
      }
    }
    entries.sort((a, b) => a.path.compareTo(b.path));
    return entries;
  }

  Future<_ValidatedBackup> _validateBackup(
    String zipPath, {
    String? passphrase,
    bool extractAll = false,
  }) async {
    final containerFile = File(zipPath);
    if (!await containerFile.exists()) {
      throw const BackupException(
        'Backup file was not found. Choose an existing Owntend backup.',
      );
    }
    final containerLength = await containerFile.length();
    if (containerLength == 0) {
      throw const BackupException(
        'Backup file is empty. Choose a complete Owntend backup.',
      );
    }
    if (containerLength > _maxBackupBytes) {
      throw const BackupException(
        'Backup file is too large to restore safely. Choose a smaller Owntend backup.',
      );
    }

    final handle = await containerFile.open(mode: FileMode.read);
    BackupContainerReader? reader;
    try {
      final headerBytes = await handle.read(BackupContainerCodec.headerLength);
      final BackupContainerHeader header;
      try {
        header = BackupContainerHeader.decode(headerBytes);
      } on BackupContainerFormatException {
        throw const BackupException(
          'This is not a recognizable Owntend backup. '
          'Choose a file created by Owntend.',
        );
      }

      var effectiveSecret = passphrase;
      if (header.keyGuard == BackupContainerCodec.keyGuardDeviceKey &&
          effectiveSecret == null) {
        effectiveSecret = await BackupAutoKeyStore.tryLoad();
        if (effectiveSecret == null) {
          throw const BackupException(
            'This automatic backup belongs to another device installation and cannot be opened here.',
          );
        }
      } else if (header.keyGuard ==
              BackupContainerCodec.keyGuardUserPassphrase &&
          effectiveSecret == null) {
        throw const BackupPassphraseRequiredException();
      }

      final BackupContainerReader opened;
      try {
        opened = await BackupContainerReader.open(
          input: handle,
          passphrase: effectiveSecret!,
        );
      } on Object {
        throw const BackupException(
          'The backup could not be decrypted. Check the passphrase and try again.',
        );
      }
      reader = opened;

      final manifestFrame = await reader.readFrame(handle);
      if (manifestFrame == null || manifestFrame.length > _maxManifestBytes) {
        throw const BackupException(
          'Backup manifest is missing or too large. This does not look like a valid Owntend backup.',
        );
      }
      final manifest = _parseManifest(manifestFrame);

      final formatVersion = _readInt(manifest, 'format', fallback: 0);
      final appName = manifest['app'];
      if (appName != 'Owntend' || formatVersion != _currentFormatVersion) {
        throw const BackupException(
          'Backup format is not recognized. Choose an Owntend backup file.',
        );
      }

      final manifestSchemaVersion = _readInt(
        manifest,
        'schemaVersion',
        fallback: 0,
      );
      if (manifestSchemaVersion > db.schemaVersion) {
        throw const BackupException(
          'Backup was created by a newer database schema. Update Owntend before restoring this file.',
        );
      }

      final entries = _validatedManifestEntries(manifest);

      final tempDir = Directory(
        p.join(
          (await getTemporaryDirectory()).path,
          'owntend-restore-${_uuid.v7()}',
        ),
      );

      if (!extractAll) {
        final createdAt =
            _readDateTime(manifest, 'createdAt') ??
            (await containerFile.lastModified()).toUtc();
        final preview = _previewFromManifest(
          manifest,
          entries: entries,
          path: zipPath,
          createdAt: createdAt,
          containerSizeBytes: containerLength,
          schemaVersionFallback: manifestSchemaVersion,
        );
        return _ValidatedBackup(
          reader: reader,
          handle: handle,
          extractedDirectory: tempDir,
          preview: preview,
          ownsReader: false,
        );
      }

      await tempDir.create(recursive: true);
      try {
        await _extractContainerPayload(
          handle,
          reader,
          manifest,
          entries,
          tempDir,
        );

        final extractedDb = File(
          p.join(tempDir.path, AppDatabase.databaseFileName),
        );
        if (!await extractedDb.exists()) {
          throw const BackupException(
            'Backup database could not be extracted. Choose a complete backup.',
          );
        }

        final summary = _readDatabaseSummary(
          extractedDb.path,
          manifestSchemaVersion: manifestSchemaVersion,
        );
        if (summary.schemaVersion > db.schemaVersion) {
          throw const BackupException(
            'Backup database is newer than this app. Update Owntend before restoring.',
          );
        }

        final createdAt =
            _readDateTime(manifest, 'createdAt') ??
            (await containerFile.lastModified()).toUtc();
        final warnings = <String>[
          ..._readStringList(manifest, 'warnings'),
          ...summary.warnings,
        ];
        return _ValidatedBackup(
          reader: reader,
          handle: handle,
          extractedDirectory: tempDir,
          preview: _previewFromManifest(
            manifest,
            entries: entries,
            path: zipPath,
            createdAt: createdAt,
            containerSizeBytes: containerLength,
            schemaVersionFallback: summary.schemaVersion == 0
                ? manifestSchemaVersion
                : summary.schemaVersion,
            countsOverride: summary.counts,
            extraWarnings: warnings,
          ),
          ownsReader: true,
        );
      } catch (_) {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
        rethrow;
      }
    } on BackupContainerFormatException catch (_) {
      reader?.destroyKey();
      await handle.close();
      throw const BackupException(
        'The backup could not be decrypted or its contents failed '
        'authentication. Check the passphrase and try again.',
      );
    } on Object {
      reader?.destroyKey();
      await handle.close();
      rethrow;
    }
  }

  Map<String, dynamic> _parseManifest(List<int> frame) {
    try {
      return jsonDecode(utf8.decode(frame)) as Map<String, dynamic>;
    } catch (_) {
      throw const BackupException(
        'Backup manifest is corrupted or the passphrase is wrong. Try again.',
      );
    }
  }

  List<_ManifestEntry> _validatedManifestEntries(
    Map<String, dynamic> manifest,
  ) {
    final rawFiles = manifest['files'];
    if (rawFiles is! List || rawFiles.isEmpty) {
      throw const BackupException(
        'Backup manifest is incomplete. Choose a newer complete backup.',
      );
    }
    if (rawFiles.length > _maxEntryCount) {
      throw const BackupException(
        'Backup contains too many entries to restore safely.',
      );
    }
    var total = 0;
    final seen = <String>{};
    final entries = <_ManifestEntry>[];
    for (final item in rawFiles) {
      if (item is! Map<String, dynamic>) {
        throw const BackupException('Backup manifest file list is corrupted.');
      }
      final pathValue = item['path'];
      final sizeValue = item['bytes'];
      final shaValue = item['sha256'];
      if (pathValue is! String || !_isAllowedBackupPath(pathValue)) {
        throw const BackupException(
          'Backup manifest contains an unsafe file path. Restore was blocked.',
        );
      }
      if (!seen.add(pathValue)) {
        throw const BackupException(
          'Backup contains duplicate files. Choose a clean backup file.',
        );
      }
      if (sizeValue is! num || shaValue is! String || shaValue.length != 64) {
        throw const BackupException('Backup manifest file list is corrupted.');
      }
      final size = sizeValue.toInt();
      if (size < 0 || size > _maxSingleEntryBytes) {
        throw const BackupException(
          'Backup contains an entry that is too large to restore safely.',
        );
      }
      total += size;
      if (total > _maxExtractedBytes) {
        throw const BackupException(
          'Backup expands to too much data to restore safely.',
        );
      }
      entries.add(
        _ManifestEntry(path: pathValue, bytes: size, sha256: shaValue),
      );
    }
    final hasDatabase = entries.any(
      (entry) => entry.path == AppDatabase.databaseFileName,
    );
    if (!hasDatabase) {
      throw const BackupException(
        'Backup is missing its manifest or Owntend database. Choose a complete backup.',
      );
    }
    return entries;
  }

  /// Streams the authenticated payload into staging files following the
  /// manifest exactly: entry boundaries come from declared sizes, hashes are
  /// verified incrementally, and every byte written is counted against the
  /// hard total before touching disk beyond the staging directory.
  Future<void> _extractContainerPayload(
    RandomAccessFile handle,
    BackupContainerReader reader,
    Map<String, dynamic> manifest,
    List<_ManifestEntry> entries,
    Directory tempDir,
  ) async {
    final declaredTotal = _readInt(manifest, 'payloadBytes', fallback: -1);
    var carried = BytesBuilder(copy: true);
    var carriedLength = 0;
    var totalWritten = 0;

    for (final entry in entries) {
      final target = File(p.joinAll([tempDir.path, ...entry.path.split('/')]));
      await target.parent.create(recursive: true);
      final sink = target.openWrite();
      final digestOutput = _DigestSink();
      final digest = sha256.startChunkedConversion(digestOutput);
      var entryWritten = 0;
      try {
        while (entryWritten < entry.bytes) {
          if (carriedLength > 0) {
            final take = carriedLength.clamp(0, entry.bytes - entryWritten);
            final chunk = carried.takeBytes();
            final part = chunk.sublist(0, take);
            final rest = chunk.sublist(take);
            sink.add(part);
            digest.add(part);
            entryWritten += take;
            totalWritten += take;
            carried = BytesBuilder(copy: true)..add(rest);
            carriedLength = rest.length;
            continue;
          }
          final frame = await reader.readFrame(handle);
          if (frame == null) {
            throw const BackupException(
              'Backup payload ended early. The file may be incomplete.',
            );
          }
          carried.add(frame);
          carriedLength += frame.length;
        }
      } finally {
        await sink.flush();
        await sink.close();
        digest.close();
      }
      if (entryWritten != entry.bytes) {
        throw const BackupException(
          'Backup entry actual size does not match declared size in archive.',
        );
      }
      digest.close();
      final actualHash = digestOutput.results;
      if (actualHash.toString() != entry.sha256) {
        throw const BackupException(
          'Backup checksum validation failed. The file may be corrupted.',
        );
      }
      if (totalWritten > _maxExtractedBytes) {
        throw const BackupException(
          'Backup expands to too much data to restore safely.',
        );
      }
    }

    // Trailing frames beyond the declared payload are a tamper signal.
    while (true) {
      final frame = await reader.readFrame(handle);
      if (frame == null) break;
      throw const BackupException(
        'Backup contains unexpected trailing data. Restore was blocked.',
      );
    }
    if (declaredTotal >= 0 && declaredTotal != totalWritten) {
      throw const BackupException(
        'Backup payload length does not match its manifest. Restore was blocked.',
      );
    }
  }

  BackupPreview _previewFromManifest(
    Map<String, dynamic> manifest, {
    required List<_ManifestEntry> entries,
    required String path,
    required DateTime createdAt,
    required int containerSizeBytes,
    required int schemaVersionFallback,
    Map<String, int>? countsOverride,
    List<String>? extraWarnings,
  }) {
    final databaseEntry = entries.firstWhere(
      (entry) => entry.path == AppDatabase.databaseFileName,
    );
    final warnings = <String>[
      ..._readStringList(manifest, 'warnings'),
      ...?extraWarnings,
    ];
    return BackupPreview(
      path: path,
      createdAt: createdAt,
      formatVersion: _readInt(manifest, 'format', fallback: 0),
      schemaVersion: schemaVersionFallback,
      backupSizeBytes: containerSizeBytes,
      databaseSizeBytes: databaseEntry.bytes,
      fileCount: entries.length - 1,
      counts: countsOverride ?? _countsFromManifest(manifest),
      includedData: _readStringList(
        manifest,
        'includedData',
        fallback: _includedData,
      ),
      excludedData: _readStringList(
        manifest,
        'excludedData',
        fallback: _excludedData,
      ),
      trigger: _triggerFromString(manifest['trigger'] as String?),
      warnings: warnings.toSet().toList(),
    );
  }

  Map<String, int> _countsFromManifest(Map<String, dynamic> manifest) {
    final raw = manifest['counts'];
    if (raw is! Map<String, dynamic>) return const {};
    return raw.map(
      (key, value) => MapEntry(key, (value as num?)?.toInt() ?? 0),
    );
  }

  @visibleForTesting
  bool isAllowedBackupPathForTest(String value) => _isAllowedBackupPath(value);

  _DatabaseSummary _readDatabaseSummary(
    String databasePath, {
    required int manifestSchemaVersion,
  }) {
    Database? sqliteDb;
    try {
      sqliteDb = sqlite3.open(databasePath, mode: OpenMode.readOnly);
      final integrity = sqliteDb.select('PRAGMA integrity_check');
      final integrityResult = integrity.isEmpty
          ? 'missing'
          : integrity.first.columnAt(0)?.toString();
      if (integrityResult != 'ok') {
        throw BackupException(
          'Backup database failed SQLite integrity check: $integrityResult',
        );
      }

      final schemaVersion = sqliteDb.userVersion;
      final effectiveSchema = schemaVersion == 0
          ? manifestSchemaVersion
          : schemaVersion;
      if (effectiveSchema != db.schemaVersion) {
        throw const BackupException(
          'Backup database schema is not compatible with this Owntend version.',
        );
      }

      final requiredTables = _requiredTablesForCurrentSchema();
      final missingTables = requiredTables
          .where((table) => !_tableExists(sqliteDb!, table))
          .toList();
      if (missingTables.isNotEmpty) {
        throw BackupException(
          'Backup database is incomplete. Missing tables: ${missingTables.join(', ')}.',
        );
      }

      final foreignKeyRows = sqliteDb.select('PRAGMA foreign_key_check');
      if (foreignKeyRows.isNotEmpty) {
        throw const BackupException(
          'Backup database has broken internal links. Restore was blocked.',
        );
      }

      final counts = <String, int>{};
      for (final table in _currentSchemaTables) {
        counts[table] = _tableExists(sqliteDb, table)
            ? _countRows(sqliteDb, table)
            : 0;
      }

      final warnings = <String>[];
      warnings.addAll(_validateStoredMediaPaths(sqliteDb));
      return _DatabaseSummary(
        schemaVersion: effectiveSchema,
        counts: counts,
        warnings: warnings,
      );
    } on BackupException {
      rethrow;
    } catch (error) {
      throw BackupException(
        'Backup database could not be read. The file may be corrupted. Details: $error',
      );
    } finally {
      sqliteDb?.close();
    }
  }

  Future<void> _importDatabaseFrom(
    String databasePath, {
    required String generationMarker,
  }) async {
    var attached = false;
    await db.customStatement('PRAGMA foreign_keys = OFF');
    try {
      await db.customStatement('ATTACH DATABASE ? AS restore', [databasePath]);
      attached = true;
      await db.transaction(() async {
        for (final table in _currentSchemaTables.reversed) {
          await db.customStatement('DELETE FROM ${_quoteIdentifier(table)}');
        }
        for (final table in _currentSchemaTables) {
          if (!await _attachedTableExists(table)) {
            continue;
          }
          final columns = await _sharedColumns(table);
          if (columns.isEmpty) {
            continue;
          }
          final columnList = columns.map(_quoteIdentifier).join(', ');
          await db.customStatement(
            'INSERT INTO ${_quoteIdentifier(table)} ($columnList) '
            'SELECT $columnList FROM restore.${_quoteIdentifier(table)}',
          );
        }
        await db.customStatement('DELETE FROM search_index');
        // Commit proof: written inside the same SQLite transaction as the
        // imported rows. Recovery reads this marker instead of trusting the
        // journal phase, so a crash after begin but before commit rolls back
        // and a crash after commit rolls forward even when the following
        // journal write never happened.
        await db.customUpdate(
          'DELETE FROM settings WHERE key = ?',
          variables: [Variable<String>(restoreGenerationSettingKey)],
          updates: {db.settings},
          updateKind: UpdateKind.delete,
        );
        await db.customInsert(
          'INSERT INTO settings(key, value, updated_at) '
          "VALUES (?, ?, CAST(strftime('%s', 'now') AS INTEGER)) "
          'ON CONFLICT(key) DO UPDATE SET '
          'value = excluded.value, updated_at = excluded.updated_at',
          variables: [
            Variable<String>(restoreGenerationSettingKey),
            Variable<String>(generationMarker),
          ],
          updates: {db.settings},
        );
        final violations = await db
            .customSelect('PRAGMA foreign_key_check')
            .get();
        if (violations.isNotEmpty) {
          throw const BackupException(
            'Restored data has broken internal links. Restore was cancelled.',
          );
        }
      });
    } finally {
      if (attached) {
        await db.customStatement('DETACH DATABASE restore');
      }
      await db.customStatement('PRAGMA foreign_keys = ON');
    }
  }

  Future<bool> _attachedTableExists(String table) async {
    final rows = await db
        .customSelect(
          "SELECT name FROM restore.sqlite_master WHERE type IN ('table', 'view') "
          "AND name = ${_sqlString(table)}",
        )
        .get();
    return rows.isNotEmpty;
  }

  Future<List<String>> _sharedColumns(String table) async {
    final current = await _tableColumns('main', table);
    final restored = await _tableColumns('restore', table);
    return current.where(restored.contains).toList();
  }

  Future<List<String>> _tableColumns(String schema, String table) async {
    final rows = await db
        .customSelect(
          'PRAGMA ${_quoteIdentifier(schema)}.table_info(${_sqlString(table)})',
        )
        .get();
    return rows.map((row) => row.read<String>('name')).toList();
  }

  Future<List<_MediaReplacement>> _stageMediaFolders({
    required Directory appDir,
    required Directory extractedDir,
    required String activeJournalId,
    String? token,
  }) async {
    final effectiveToken = token ?? _uuid.v7();
    final replacements = <_MediaReplacement>[];
    try {
      for (final root in kRestoreMediaRoots) {
        final source = Directory(p.join(extractedDir.path, root));
        final destination = Directory(p.join(appDir.path, root));
        final replacement = Directory(
          '${destination.path}.restore-$effectiveToken',
        );
        final backup = Directory(
          '${destination.path}.previous-$effectiveToken',
        );
        if (await replacement.exists()) {
          await replacement.delete(recursive: true);
        }
        if (await source.exists()) {
          await _copyDirectory(source, replacement);
          await sidecarRegistry.registerSidecar(
            SidecarEntry(
              token: effectiveToken,
              type: SidecarType.restoreStaged,
              canonicalRoot: root,
              activeJournalId: activeJournalId,
              createdAt: DateTime.now().toUtc(),
            ),
          );
        }
        replacements.add(
          _MediaReplacement(
            token: effectiveToken,
            canonicalRoot: root,
            destination: destination,
            replacement: replacement,
            backup: backup,
          ),
        );
      }
      return replacements;
    } catch (error) {
      await rollbackStagedMediaGenerations(
        appDir: appDir,
        token: effectiveToken,
      );
      throw BackupException(
        'Restore was stopped because media files could not be prepared. '
        'Free up storage and restore the backup again. Details: $error',
      );
    }
  }

  /// Activates the staged media generation only after the imported database
  /// has been proven committed. Per-root rename pairs are idempotent so a
  /// crash between roots converges during recovery.
  /// WP-005 (F-012): thin delegation to the single activation engine in
  /// [activateStagedMediaGenerations], preserving this service's failpoint
  /// and previous-backup sidecar contracts.
  Future<void> _activateStagedMedia({
    required Directory appDir,
    required String token,
    required List<_MediaReplacement> stagedGenerations,
    required RestoreFailpoints failpoints,
  }) async {
    await activateStagedMediaGenerations(
      appDir: appDir,
      token: token,
      onRootActivating: (canonicalRoot) =>
          failpoints.maybeThrow('media:activate:$canonicalRoot'),
      onPreviousArchived: (canonicalRoot) async {
        await sidecarRegistry.registerSidecar(
          SidecarEntry(
            token: token,
            type: SidecarType.previousBackup,
            canonicalRoot: canonicalRoot,
            activeJournalId: token,
            createdAt: DateTime.now().toUtc(),
          ),
        );
      },
    );
  }

  Future<void> _removeRestoreSidecars(String token) async {
    for (final root in kRestoreMediaRoots) {
      await sidecarRegistry.removeEntry(token, root, SidecarType.restoreStaged);
      await sidecarRegistry.removeEntry(
        token,
        root,
        SidecarType.previousBackup,
      );
    }
  }

  Future<void> _copyDirectory(Directory source, Directory destination) async {
    await destination.create(recursive: true);
    await for (final entity in source.list(
      recursive: true,
      followLinks: false,
    )) {
      final relative = p.relative(entity.path, from: source.path);
      final targetPath = p.join(destination.path, relative);
      if (entity is Directory) {
        await Directory(targetPath).create(recursive: true);
      } else if (entity is File) {
        await File(targetPath).parent.create(recursive: true);
        await entity.copy(targetPath);
      }
    }
  }

  Future<Directory> _backupDirectory() async {
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(appDir.path, _backupFolderName));
    await dir.create(recursive: true);
    return dir;
  }

  Future<File> _stateFile() async {
    final appDir = await getApplicationDocumentsDirectory();
    return File(p.join(appDir.path, _backupStateFileName));
  }

  Future<void> _recordStatus(BackupStatus status) async {
    final current = await backupState();
    await _writeBackupState(
      BackupState(
        automaticBackupsEnabled: current.automaticBackupsEnabled,
        lastBackup: status,
      ),
    );
  }

  Future<void> _writeBackupState(BackupState state) async {
    final file = await _stateFile();
    await file.writeAsString(
      _prettyJson({
        'automaticBackupsEnabled': state.automaticBackupsEnabled,
        'lastBackup': _statusToJson(state.lastBackup),
      }),
      flush: true,
    );
  }

  Future<void> _pruneAutomaticBackups(Directory backupDir) async {
    final files = <File>[];
    await for (final entity in backupDir.list(followLinks: false)) {
      if (entity is File &&
          p.basename(entity.path).startsWith('owntend-auto-') &&
          entity.path.endsWith(_backupFileExtension)) {
        files.add(entity);
      }
    }
    files.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
    for (final file in files.skip(_maximumAutomaticBackups)) {
      try {
        await file.delete();
      } catch (_) {
        // Old automatic backups should not block creating the new one.
      }
    }
  }

  bool _isAllowedBackupPath(String value) {
    final clean = value.replaceAll('\\', '/').replaceAll(RegExp(r'^\./+'), '');
    if (!_isSafeZipPath(clean)) {
      return false;
    }
    final withoutTrailing = clean.endsWith('/')
        ? clean.substring(0, clean.length - 1)
        : clean;
    if (withoutTrailing.isEmpty) {
      return false;
    }
    final parts = withoutTrailing.split('/');
    if (parts.length == 1) {
      return _allowedRootFiles.contains(withoutTrailing) ||
          _allowedRootDirectories.contains(withoutTrailing);
    }
    return _allowedRootDirectories.contains(parts.first);
  }

  bool _isSafeZipPath(String value) {
    final clean = value.replaceAll('\\', '/').replaceAll(RegExp(r'^\./+'), '');
    final withoutTrailing = clean.endsWith('/')
        ? clean.substring(0, clean.length - 1)
        : clean;
    final normalized = p.posix.normalize(withoutTrailing);
    return normalized == withoutTrailing &&
        !normalized.startsWith('/') &&
        !normalized.startsWith('../') &&
        !normalized.contains('/../') &&
        normalized != '.' &&
        normalized.trim().isNotEmpty;
  }
}

class _DigestSink implements Sink<Digest> {
  Digest? digest;

  Digest get results => digest!;

  @override
  void add(Digest data) => digest = data;

  @override
  void close() {}
}

class _ManifestEntry {
  const _ManifestEntry({
    required this.path,
    required this.bytes,
    required this.sha256,
  });

  final String path;
  final int bytes;
  final String sha256;
}

class _DiskBackupEntry {
  const _DiskBackupEntry({
    required this.path,
    required this.file,
    required this.bytes,
    required this.sha256,
  });

  final String path;
  final File file;
  final int bytes;
  final String sha256;
}

class _DatabaseSummary {
  const _DatabaseSummary({
    required this.schemaVersion,
    required this.counts,
    required this.warnings,
  });

  final int schemaVersion;
  final Map<String, int> counts;
  final List<String> warnings;
}

class _ValidatedBackup {
  const _ValidatedBackup({
    required this.reader,
    required this.handle,
    required this.extractedDirectory,
    required this.preview,
    required this.ownsReader,
  });

  final BackupContainerReader reader;
  final RandomAccessFile handle;
  final Directory extractedDirectory;
  final BackupPreview preview;

  /// When false (inspect-only), the reader key is destroyed on dispose but
  /// the caller's handle lifecycle belongs to this object as well.
  final bool ownsReader;

  Future<void> dispose() async {
    reader.destroyKey();
    await handle.close();
    if (await extractedDirectory.exists()) {
      await extractedDirectory.delete(recursive: true);
    }
  }
}

/// Device-local random key enabling automatic encrypted exports without ever
/// storing the user's chosen passphrase. Lives only in platform secure
/// storage, mirroring the existing account-deletion recovery-key pattern.
class BackupAutoKeyStore {
  BackupAutoKeyStore._();

  static const _storageKey = 'owntend.backup-auto-key.v1';

  static const FlutterSecureStorage _storage = FlutterSecureStorage(
    aOptions: owntendAndroidSecureStorageOptions,
  );

  static Future<String> load() async {
    final existing = await tryLoad();
    if (existing != null) return existing;
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    final value = base64UrlEncode(bytes).replaceAll('=', '');
    await _storage.write(key: _storageKey, value: value);
    return value;
  }

  static Future<String?> tryLoad() async {
    final value = await _storage.read(key: _storageKey);
    if (value == null || value.isEmpty) return null;
    return value;
  }
}

class _MediaReplacement {
  const _MediaReplacement({
    required this.token,
    required this.canonicalRoot,
    required this.destination,
    required this.replacement,
    required this.backup,
  });

  final String token;
  final String canonicalRoot;
  final Directory destination;
  final Directory replacement;
  final Directory backup;
}

String _quoteIdentifier(String value) => '"${value.replaceAll('"', '""')}"';

String _sqlString(String value) => "'${value.replaceAll("'", "''")}'";

Future<String> _fileSha256Hex(String filePath) async {
  final file = File(filePath);
  final digest = await sha256.bind(file.openRead()).first;
  return digest.toString();
}

String _prettyJson(Object? value) =>
    const JsonEncoder.withIndent('  ').convert(value);

int _readInt(Map<String, dynamic> value, String key, {required int fallback}) {
  final raw = value[key];
  return raw is num ? raw.toInt() : fallback;
}

DateTime? _readDateTime(Map<String, dynamic> value, String key) {
  final raw = value[key];
  if (raw is! String) {
    return null;
  }
  return DateTime.tryParse(raw)?.toUtc();
}

List<String> _readStringList(
  Map<String, dynamic> value,
  String key, {
  List<String> fallback = const [],
}) {
  final raw = value[key];
  if (raw is! List) {
    return fallback;
  }
  return raw.whereType<String>().toList();
}

BackupTrigger? _triggerFromString(String? value) {
  if (value == null) {
    return null;
  }
  for (final trigger in BackupTrigger.values) {
    if (trigger.name == value) {
      return trigger;
    }
  }
  return null;
}

BackupStatus? _statusFromJson(Map<String, dynamic>? value) {
  if (value == null) {
    return null;
  }
  final updatedAt = _readDateTime(value, 'updatedAt');
  if (updatedAt == null) {
    return null;
  }
  return BackupStatus(
    successful: value['successful'] as bool? ?? false,
    updatedAt: updatedAt,
    trigger:
        _triggerFromString(value['trigger'] as String?) ?? BackupTrigger.manual,
    path: value['path'] as String?,
    createdAt: _readDateTime(value, 'createdAt'),
    sizeBytes: (value['sizeBytes'] as num?)?.toInt(),
    message: value['message'] as String?,
  );
}

Map<String, Object?>? _statusToJson(BackupStatus? status) {
  if (status == null) {
    return null;
  }
  return {
    'successful': status.successful,
    'updatedAt': status.updatedAt.toUtc().toIso8601String(),
    'trigger': status.trigger.name,
    'path': status.path,
    'createdAt': status.createdAt?.toUtc().toIso8601String(),
    'sizeBytes': status.sizeBytes,
    'message': status.message,
  };
}

List<String> _requiredTablesForCurrentSchema() {
  return _currentSchemaTables;
}

bool _tableExists(Database db, String tableName) {
  return db.select(
    "SELECT name FROM sqlite_master WHERE type IN ('table', 'view') AND name = ?",
    [tableName],
  ).isNotEmpty;
}

int _countRows(Database db, String tableName) {
  final rows = db.select(
    'SELECT COUNT(*) AS count FROM "${tableName.replaceAll('"', '""')}"',
  );
  return (rows.first['count'] as int?) ?? 0;
}

List<String> _validateStoredMediaPaths(Database db) {
  final warnings = <String>[];
  final referencedPaths = <String>{};
  if (_tableExists(db, 'asset_photos')) {
    final rows = db.select('SELECT relative_path FROM asset_photos');
    for (final row in rows) {
      final path = row['relative_path'];
      if (path is String && path.trim().isNotEmpty) {
        referencedPaths.add(path);
      }
    }
  }
  if (_tableExists(db, 'settings')) {
    final rows = db.select("SELECT value FROM settings WHERE key = 'profile'");
    if (rows.isNotEmpty) {
      try {
        final profile =
            jsonDecode(rows.first['value'] as String) as Map<String, dynamic>;
        final avatarPath = profile['avatarPath'];
        if (avatarPath is String && avatarPath.trim().isNotEmpty) {
          referencedPaths.add(avatarPath);
        }
      } catch (_) {
        warnings.add('Profile settings could not be previewed.');
      }
    }
  }
  for (final path in referencedPaths) {
    final normalized = path.replaceAll('\\', '/');
    final root = normalized.split('/').first;
    final safe =
        p.posix.normalize(normalized) == normalized &&
        !normalized.startsWith('/') &&
        !normalized.startsWith('../') &&
        !normalized.contains('/../') &&
        _allowedRootDirectories.contains(root);
    if (!safe) {
      throw BackupException(
        'Backup database contains an unsafe media path: $path',
      );
    }
  }
  return warnings;
}

String _filePrefix(BackupTrigger trigger) {
  return switch (trigger) {
    BackupTrigger.manual => 'owntend-backup',
    BackupTrigger.automatic => 'owntend-auto',
    BackupTrigger.preRestore => 'owntend-before-restore',
  };
}

String _timestampForFile(DateTime value) {
  final utc = value.toUtc();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${utc.year}${two(utc.month)}${two(utc.day)}-'
      '${two(utc.hour)}${two(utc.minute)}${two(utc.second)}Z';
}

String _friendlyError(Object error) {
  if (error is BackupException) {
    return error.message;
  }
  return userFacingErrorMessage(
    error,
    fallback: 'The backup operation could not finish.',
  );
}
