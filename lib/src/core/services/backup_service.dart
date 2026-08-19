import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:uuid/uuid.dart';

import '../database/app_database.dart';
import '../domain/contracts.dart';
import '../sync/local_sync_store.dart';
import '../utils/user_facing_errors.dart';
import 'restore_journal.dart';
import 'sidecar_registry.dart';

const _uuid = Uuid();
const _currentFormatVersion = 2;
const _minimumFormatVersion = 1;
const _manifestName = 'manifest.json';
const _backupStateFileName = 'owntend-backup-state.json';
const _backupFolderName = 'backups';
const _maxBackupBytes = 256 * 1024 * 1024;
const _maxExtractedBytes = 512 * 1024 * 1024;
const _maxSingleEntryBytes = 256 * 1024 * 1024;
const _maxManifestBytes = 128 * 1024;
const _maxEntryCount = 10000;
const _maxCompressionRatio = 100;
const _automaticBackupInterval = Duration(hours: 24);
const _maximumAutomaticBackups = 7;

const _mediaRoots = ['photos', 'profile', 'cloud_media'];
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
  'notifications',
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

class ZipBackupService
    implements BackupService, RestoreService, BackupRepository {
  ZipBackupService(
    this.db, {
    RestoreJournalStore? journalStore,
    SidecarRegistryStore? sidecarRegistry,
    this.onBeforeRestoreBarrier,
  }) : journalStore = journalStore ?? RestoreJournalStore(),
       sidecarRegistry = sidecarRegistry ?? SidecarRegistryStore();

  final AppDatabase db;
  final RestoreJournalStore journalStore;
  final SidecarRegistryStore sidecarRegistry;
  final Future<void> Function()? onBeforeRestoreBarrier;
  static bool _operationInProgress = false;

  @override
  Future<String> exportBackup({BackupTrigger trigger = BackupTrigger.manual}) {
    return exportZip(trigger: trigger);
  }

  @override
  Future<String> exportZip({BackupTrigger trigger = BackupTrigger.manual}) {
    return _runExclusive(
      () => _exportZipInternal(trigger: trigger, updateStatus: true),
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
  Future<BackupPreview> inspectBackup(String zipPath) async {
    final validation = await _validateBackup(zipPath, extractAll: false);
    try {
      return validation.preview;
    } finally {
      await validation.dispose();
    }
  }

  @override
  Future<void> restoreBackup(String zipPath) => restoreZip(zipPath);

  @override
  Future<void> restore(String zipPath) => restoreZip(zipPath);

  @override
  Future<void> restoreZip(String zipPath) {
    return _runExclusive(() => _restoreZipInternal(zipPath));
  }

  Future<void> _restoreZipInternal(String zipPath) async {
    final validation = await _validateBackup(zipPath, extractAll: true);
    final zipFile = File(zipPath);
    final archiveHash = _sha256Hex(await zipFile.readAsBytes());
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
        safetyBackupPath = await _exportZipInternal(
          trigger: BackupTrigger.preRestore,
          updateStatus: false,
        );
      } catch (error) {
        await journalStore.clearActiveEntry();
        throw BackupException(
          'Restore was stopped because Owntend could not create a safety copy of your current data. '
          'Free up storage, create a manual backup, then try restore again. Details: $error',
        );
      }

      final safetyBackupHash = _sha256Hex(
        await File(safetyBackupPath).readAsBytes(),
      );
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
      await _migrateExtractedDatabase(extractedDb);

      final mediaToken = _uuid.v7();
      journalEntry = journalEntry.copyWith(
        phase: RestorePhase.mediaStaged,
        mediaToken: mediaToken,
        updatedAt: DateTime.now(),
      );
      await journalStore.saveEntry(journalEntry);

      final mediaRestore = await _stageMediaFolders(
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

      try {
        await LocalSyncStore(db)
            .withOutboxSuppressed(() => _importDatabaseFrom(extractedDb.path));
      } catch (_) {
        await mediaRestore.rollback();
        await journalStore.clearActiveEntry();
        rethrow;
      }

      journalEntry = journalEntry.copyWith(
        phase: RestorePhase.dbCommitComplete,
        updatedAt: DateTime.now(),
      );
      await journalStore.saveEntry(journalEntry);

      await mediaRestore.commit();

      journalEntry = journalEntry.copyWith(
        phase: RestorePhase.mediaSwapped,
        updatedAt: DateTime.now(),
      );
      await journalStore.saveEntry(journalEntry);

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

      journalEntry = journalEntry.copyWith(
        phase: RestorePhase.terminal,
        updatedAt: DateTime.now(),
      );
      await journalStore.saveEntry(journalEntry);
      await journalStore.clearActiveEntry();
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

  Future<String> _exportZipInternal({
    required BackupTrigger trigger,
    required bool updateStatus,
  }) async {
    final createdAt = DateTime.now().toUtc();
    File? snapshot;
    File? partialBackup;
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

      final archive = Archive();
      final manifestFiles = <Map<String, Object>>[];
      final databaseBytes = await snapshot.readAsBytes();
      archive.addFile(
        ArchiveFile.bytes(AppDatabase.databaseFileName, databaseBytes),
      );
      manifestFiles.add(
        _fileManifest(AppDatabase.databaseFileName, databaseBytes),
      );

      for (final entry in await _collectUserFiles(appDir)) {
        archive.addFile(ArchiveFile.bytes(entry.path, entry.bytes));
        manifestFiles.add(_fileManifest(entry.path, entry.bytes));
      }

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
        'database': {
          'path': AppDatabase.databaseFileName,
          'bytes': databaseBytes.length,
          'sha256': _sha256Hex(databaseBytes),
        },
        'files': manifestFiles,
        'counts': databaseSummary.counts,
        'includedData': _includedData,
        'excludedData': _excludedData,
        'warnings': databaseSummary.warnings,
        'secretsIncluded': false,
      };
      archive.addFile(ArchiveFile.string(_manifestName, _prettyJson(manifest)));

      final filename =
          '${_filePrefix(trigger)}-${_timestampForFile(createdAt)}-${_uuid.v7().substring(0, 8)}.zip';
      final backup = File(p.join(backupDir.path, filename));
      partialBackup = File('${backup.path}.partial');
      if (await partialBackup.exists()) {
        await partialBackup.delete();
      }

      final bytes = ZipEncoder().encode(archive);
      await partialBackup.writeAsBytes(bytes, flush: true);
      final preview = await inspectBackup(partialBackup.path);
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
            createdAt: preview.createdAt,
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

  Future<List<_PreparedBackupEntry>> _collectUserFiles(Directory appDir) async {
    final entries = <_PreparedBackupEntry>[];
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
        entries.add(_PreparedBackupEntry(relative, await entity.readAsBytes()));
      }
    }
    entries.sort((a, b) => a.path.compareTo(b.path));
    return entries;
  }

  Future<_ValidatedBackup> _validateBackup(
    String zipPath, {
    required bool extractAll,
  }) async {
    final zipFile = File(zipPath);
    if (!await zipFile.exists()) {
      throw const BackupException(
        'Backup file was not found. Choose an existing Owntend ZIP backup.',
      );
    }
    final zipLength = await zipFile.length();
    if (zipLength == 0) {
      throw const BackupException(
        'Backup file is empty. Choose a complete Owntend ZIP backup.',
      );
    }
    if (zipLength > _maxBackupBytes) {
      throw const BackupException(
        'Backup file is too large to restore safely. Choose a smaller Owntend backup.',
      );
    }

    final archive = _decodeArchive(await zipFile.readAsBytes());
    _validateArchivePaths(archive);

    final manifestEntry = archive.findFile(_manifestName);
    final databaseEntry = archive.findFile(AppDatabase.databaseFileName);
    if (manifestEntry == null || databaseEntry == null) {
      throw const BackupException(
        'Backup is missing its manifest or Owntend database. Choose a complete backup ZIP.',
      );
    }
    if (manifestEntry.size > _maxManifestBytes) {
      throw const BackupException(
        'Backup manifest is too large. This does not look like a valid Owntend backup.',
      );
    }

    final manifest = _readManifest(manifestEntry);
    final formatVersion = _readInt(manifest, 'format', fallback: 1);
    final appName = manifest['app'];
    if (appName != 'Owntend' || formatVersion < _minimumFormatVersion) {
      throw const BackupException(
        'Backup format is not recognized. Choose an Owntend backup ZIP.',
      );
    }
    if (formatVersion > _currentFormatVersion) {
      throw const BackupException(
        'Backup was created by a newer Owntend version. Update the app, then try again.',
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

    final tempDir = Directory(
      p.join(
        (await getTemporaryDirectory()).path,
        'owntend-restore-${_uuid.v7()}',
      ),
    );
    await tempDir.create(recursive: true);
    try {
      final extractedBytes = await _extractArchive(
        archive,
        tempDir,
        extractAll: extractAll,
      );
      if (extractedBytes > _maxExtractedBytes) {
        throw const BackupException(
          'Backup expands to too much data to restore safely.',
        );
      }

      var extractedDb = File(
        p.join(tempDir.path, AppDatabase.databaseFileName),
      );
      if (!await extractedDb.exists()) {
        throw const BackupException(
          'Backup database could not be extracted. Choose a complete backup ZIP.',
        );
      }

      if (formatVersion >= 2) {
        _validateManifestFiles(manifest, archive);
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
          (await zipFile.lastModified()).toUtc();
      final warnings = <String>[
        if (formatVersion < _currentFormatVersion) 'This is an older backup format. Owntend will migrate it during restore.',
        ..._readStringList(manifest, 'warnings'),
        ...summary.warnings,
      ];
      return _ValidatedBackup(
        extractedDirectory: tempDir,
        preview: BackupPreview(
          path: zipPath,
          createdAt: createdAt,
          formatVersion: formatVersion,
          schemaVersion: summary.schemaVersion == 0
              ? manifestSchemaVersion
              : summary.schemaVersion,
          backupSizeBytes: zipLength,
          databaseSizeBytes: databaseEntry.size,
          fileCount: archive.files.where((file) => file.isFile).length - 2,
          counts: summary.counts,
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
        ),
      );
    } catch (_) {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
      rethrow;
    }
  }

  Archive _decodeArchive(List<int> bytes) {
    try {
      return ZipDecoder().decodeBytes(bytes);
    } catch (_) {
      throw const BackupException(
        'Backup ZIP could not be opened. The file may be corrupted or incomplete.',
      );
    }
  }

  @visibleForTesting
  void validateArchivePathsForTest(Archive archive) =>
      _validateArchivePaths(archive);

  @visibleForTesting
  bool isAllowedBackupPathForTest(String value) => _isAllowedBackupPath(value);

  void _validateArchivePaths(Archive archive) {
    if (archive.files.length > _maxEntryCount) {
      throw const BackupException(
        'Backup contains too many entries to restore safely.',
      );
    }
    final seen = <String>{};
    var totalSize = 0;
    for (final file in archive.files) {
      final name = file.name.replaceAll('\\', '/');
      if (!_isAllowedBackupPath(name)) {
        throw const BackupException(
          'Backup contains unsafe paths. Restore was blocked for safety.',
        );
      }
      if (file.isSymbolicLink) {
        throw const BackupException(
          'Backup contains a symbolic link. Restore was blocked for safety.',
        );
      }
      if (file.isFile && !seen.add(name)) {
        throw const BackupException(
          'Backup contains duplicate files. Choose a clean backup ZIP.',
        );
      }
      if (file.size > _maxSingleEntryBytes) {
        throw const BackupException(
          'Backup contains an entry that is too large to restore safely.',
        );
      }
      final dynamic rawContent = file.rawContent;
      final dynamic content = file.content;
      var contentLen = 0;
      if (rawContent != null && rawContent.length is int) {
        contentLen = rawContent.length as int;
      } else if (content != null && content is List) {
        contentLen = content.length;
      }
      if (file.size > 10 * 1024 * 1024 && contentLen > 0) {
        final ratio = file.size / contentLen;
        if (ratio > _maxCompressionRatio) {
          throw const BackupException(
            'Backup entry has an unsafe compression ratio. Restore was blocked for safety.',
          );
        }
      }
      totalSize += file.size;
      if (totalSize > _maxExtractedBytes) {
        throw const BackupException(
          'Backup expands to too much data to restore safely.',
        );
      }
    }
  }

  Map<String, dynamic> _readManifest(ArchiveFile manifestEntry) {
    try {
      final decoded = jsonDecode(
        utf8.decode(manifestEntry.content),
      ) as Map<String, dynamic>;
      return decoded;
    } catch (_) {
      throw const BackupException(
        'Backup manifest is corrupted. Choose another backup file.',
      );
    }
  }

  Future<int> _extractArchive(
    Archive archive,
    Directory tempDir, {
    required bool extractAll,
  }) async {
    var totalBytes = 0;
    for (final file in archive.files) {
      if (!file.isFile) {
        continue;
      }
      if (!extractAll &&
          file.name != AppDatabase.databaseFileName &&
          file.name != _manifestName) {
        continue;
      }
      final bytes = file.content as List<int>;
      if (bytes.length != file.size) {
        throw const BackupException(
          'Backup entry actual size does not match declared size in archive.',
        );
      }
      totalBytes += bytes.length;
      if (totalBytes > _maxExtractedBytes) {
        throw const BackupException(
          'Backup expands to too much data to restore safely.',
        );
      }
      final target = File(p.joinAll([tempDir.path, ...file.name.split('/')]));
      await target.parent.create(recursive: true);
      await target.writeAsBytes(bytes, flush: true);
    }
    return totalBytes;
  }

  void _validateManifestFiles(Map<String, dynamic> manifest, Archive archive) {
    final manifestFiles = manifest['files'];
    if (manifestFiles is! List || manifestFiles.isEmpty) {
      throw const BackupException(
        'Backup manifest is incomplete. Choose a newer complete backup.',
      );
    }
    final byPath = <String, Map<String, dynamic>>{};
    for (final item in manifestFiles) {
      if (item is! Map<String, dynamic>) {
        throw const BackupException('Backup manifest file list is corrupted.');
      }
      final path = item['path'] as String?;
      if (path == null || !_isAllowedBackupPath(path)) {
        throw const BackupException(
          'Backup manifest contains an unsafe file path. Restore was blocked.',
        );
      }
      byPath[path] = item;
    }

    final archivePaths = {
      for (final file in archive.files.where((file) => file.isFile))
        if (file.name != _manifestName) file.name,
    };
    if (!archivePaths.containsAll(byPath.keys) ||
        !byPath.keys.toSet().containsAll(archivePaths)) {
      throw const BackupException(
        'Backup file list does not match its manifest. The backup may be incomplete.',
      );
    }

    for (final entry in archive.files.where((file) => file.isFile)) {
      if (entry.name == _manifestName) {
        continue;
      }
      final expected = byPath[entry.name];
      if (expected == null) {
        throw const BackupException(
          'Backup contains files that are not listed in its manifest.',
        );
      }
      final bytes = entry.content;
      final expectedSize = expected['bytes'];
      final expectedSha = expected['sha256'];
      if (expectedSize is! num ||
          expectedSha is! String ||
          expectedSize.toInt() != bytes.length ||
          expectedSha != _sha256Hex(bytes)) {
        throw const BackupException(
          'Backup checksum validation failed. The file may be corrupted.',
        );
      }
    }
  }

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
      if (effectiveSchema > db.schemaVersion) {
        throw const BackupException(
          'Backup database is newer than this app. Update Owntend before restoring.',
        );
      }

      final requiredTables = _requiredTablesForSchema(effectiveSchema);
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

  Future<void> _migrateExtractedDatabase(File databaseFile) async {
    AppDatabase? restoreDb;
    try {
      restoreDb = AppDatabase(executor: NativeDatabase(databaseFile));
      await restoreDb.customSelect('SELECT 1').get();
    } catch (error) {
      throw BackupException(
        'Backup database could not be prepared for this app version. Details: $error',
      );
    } finally {
      await restoreDb?.close();
    }
  }

  Future<void> _importDatabaseFrom(String databasePath) async {
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

  Future<_StagedMediaRestore> _stageMediaFolders({
    required Directory appDir,
    required Directory extractedDir,
    required String activeJournalId,
    String? token,
  }) async {
    final effectiveToken = token ?? _uuid.v7();
    final replacements = <_MediaReplacement>[];
    try {
      for (final root in _mediaRoots) {
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
      for (final item in replacements) {
        if (await item.backup.exists()) {
          await item.backup.delete(recursive: true);
        }
        if (await item.destination.exists()) {
          await item.destination.rename(item.backup.path);
          await sidecarRegistry.registerSidecar(
            SidecarEntry(
              token: effectiveToken,
              type: SidecarType.previousBackup,
              canonicalRoot: item.canonicalRoot,
              activeJournalId: activeJournalId,
              createdAt: DateTime.now().toUtc(),
            ),
          );
        }
      }
      for (final item in replacements) {
        if (await item.replacement.exists()) {
          await item.replacement.rename(item.destination.path);
        }
      }
      return _StagedMediaRestore(replacements, sidecarRegistry);
    } catch (error) {
      await _StagedMediaRestore(replacements, sidecarRegistry).rollback();
      throw BackupException(
        'Restore was stopped because media files could not be prepared. '
        'Free up storage and restore the backup again. Details: $error',
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
          p.extension(entity.path) == '.zip') {
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

class _PreparedBackupEntry {
  const _PreparedBackupEntry(this.path, this.bytes);

  final String path;
  final List<int> bytes;
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
    required this.extractedDirectory,
    required this.preview,
  });

  final Directory extractedDirectory;
  final BackupPreview preview;

  Future<void> dispose() async {
    if (await extractedDirectory.exists()) {
      await extractedDirectory.delete(recursive: true);
    }
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

class _StagedMediaRestore {
  const _StagedMediaRestore(this.replacements, this.sidecarRegistry);

  final List<_MediaReplacement> replacements;
  final SidecarRegistryStore sidecarRegistry;

  Future<void> commit() async {
    for (final item in replacements) {
      for (final pair in [
        (item.backup, SidecarType.previousBackup),
        (item.replacement, SidecarType.restoreStaged),
      ]) {
        final directory = pair.$1;
        final type = pair.$2;
        try {
          if (await directory.exists()) {
            await directory.delete(recursive: true);
          }
          await sidecarRegistry.removeEntry(
            item.token,
            item.canonicalRoot,
            type,
          );
        } catch (e) {
          await sidecarRegistry.updateSidecarState(
            item.token,
            item.canonicalRoot,
            type,
            SidecarState.pendingCleanup,
            error: e.toString(),
          );
        }
      }
    }
  }

  Future<void> rollback() async {
    for (final item in replacements.reversed) {
      try {
        if (await item.destination.exists()) {
          await item.destination.delete(recursive: true);
        }
        if (await item.backup.exists()) {
          await item.backup.rename(item.destination.path);
          await sidecarRegistry.removeEntry(
            item.token,
            item.canonicalRoot,
            SidecarType.previousBackup,
          );
        }
        if (await item.replacement.exists()) {
          await item.replacement.delete(recursive: true);
          await sidecarRegistry.removeEntry(
            item.token,
            item.canonicalRoot,
            SidecarType.restoreStaged,
          );
        }
      } catch (e) {
        await sidecarRegistry.updateSidecarState(
          item.token,
          item.canonicalRoot,
          SidecarType.restoreStaged,
          SidecarState.pendingCleanup,
          error: e.toString(),
        );
      }
    }
  }
}

Map<String, Object> _fileManifest(String path, List<int> bytes) {
  return {'path': path, 'bytes': bytes.length, 'sha256': _sha256Hex(bytes)};
}

String _quoteIdentifier(String value) => '"${value.replaceAll('"', '""')}"';

String _sqlString(String value) => "'${value.replaceAll("'", "''")}'";

String _sha256Hex(List<int> bytes) => sha256.convert(bytes).toString();

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

List<String> _requiredTablesForSchema(int schemaVersion) {
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
