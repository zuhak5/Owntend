import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../domain/contracts.dart';
import '../supabase/secure_supabase_storage.dart';
import '../sync/local_sync_store.dart';
import '../utils/redacting_logger.dart';
import 'sidecar_registry.dart';

/// Journal format 3 stores advisory progress and the explicit user-authorized
/// cloud disposition. Whether the SQLite import
/// actually committed is proven by reading the restore-generation marker that
/// was written inside the import transaction itself
/// (`LocalSyncStore.restoreGenerationSettingKey == journalId`). A pre-commit
/// journal label can therefore never claim an uncommitted database.
const int kCurrentRestoreJournalVersion = 3;

/// Canonical media roots restored as one generation.
const List<String> kRestoreMediaRoots = ['photos', 'profile', 'cloud_media'];

enum RestorePhase {
  validated,
  safetyBackupComplete,
  servicesSuspended,
  mediaStaged,
  dbCommitStarted,
  dbCommitComplete,
  mediaActivated,
  cloudIntentDurable,
  derivedRebuilt,
  cleanupPending,
  terminal,
}

class RestoreJournalEntry {
  const RestoreJournalEntry({
    required this.version,
    required this.journalId,
    required this.accountScope,
    required this.archivePath,
    required this.archiveHash,
    this.safetyBackupPath,
    this.safetyBackupHash,
    this.mediaToken,
    required this.phase,
    required this.cloudDisposition,
    required this.createdAt,
    required this.updatedAt,
  });

  final int version;
  final String journalId;
  final String accountScope;
  final String archivePath;
  final String archiveHash;
  final String? safetyBackupPath;
  final String? safetyBackupHash;
  final String? mediaToken;
  final RestorePhase phase;
  final RestoreCloudDisposition cloudDisposition;
  final DateTime createdAt;
  final DateTime updatedAt;

  RestoreJournalEntry copyWith({
    RestorePhase? phase,
    String? safetyBackupPath,
    String? safetyBackupHash,
    String? mediaToken,
    RestoreCloudDisposition? cloudDisposition,
    DateTime? updatedAt,
  }) {
    return RestoreJournalEntry(
      version: version,
      journalId: journalId,
      accountScope: accountScope,
      archivePath: archivePath,
      archiveHash: archiveHash,
      safetyBackupPath: safetyBackupPath ?? this.safetyBackupPath,
      safetyBackupHash: safetyBackupHash ?? this.safetyBackupHash,
      mediaToken: mediaToken ?? this.mediaToken,
      phase: phase ?? this.phase,
      cloudDisposition: cloudDisposition ?? this.cloudDisposition,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'version': version,
    'journal_id': journalId,
    'account_scope': accountScope,
    'archive_path': archivePath,
    'archive_hash': archiveHash,
    if (safetyBackupPath != null) 'safety_backup_path': safetyBackupPath,
    if (safetyBackupHash != null) 'safety_backup_hash': safetyBackupHash,
    if (mediaToken != null) 'media_token': mediaToken,
    'phase': phase.name,
    'cloud_disposition': cloudDisposition.name,
    'created_at': createdAt.toUtc().toIso8601String(),
    'updated_at': updatedAt.toUtc().toIso8601String(),
  };

  factory RestoreJournalEntry.fromJson(Map<String, dynamic> json) {
    return RestoreJournalEntry(
      version: json['version'] as int? ?? kCurrentRestoreJournalVersion,
      journalId: json['journal_id'] as String,
      accountScope: json['account_scope'] as String,
      archivePath: json['archive_path'] as String,
      archiveHash: json['archive_hash'] as String,
      safetyBackupPath: json['safety_backup_path'] as String?,
      safetyBackupHash: json['safety_backup_hash'] as String?,
      mediaToken: json['media_token'] as String?,
      phase: RestorePhase.values.byName(json['phase'] as String),
      cloudDisposition: RestoreCloudDisposition.values.byName(
        json['cloud_disposition'] as String,
      ),
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }
}

/// Process-durable storage for the one active restore transaction.
///
/// Production never falls back to process memory: secure-storage read/write/delete
/// failures are surfaced so startup can fail closed instead of losing recovery
/// authority.
class RestoreJournalStore {
  RestoreJournalStore({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            aOptions: owntendAndroidSecureStorageOptions,
          );

  static const _activeKey = 'owntend_active_restore_journal_v3';

  final FlutterSecureStorage _storage;

  Future<void> saveEntry(RestoreJournalEntry entry) async {
    try {
      await _storage.write(key: _activeKey, value: jsonEncode(entry.toJson()));
    } on Object catch (error) {
      throw StateError('Durable restore journal write failed: $error');
    }
  }

  Future<RestoreJournalEntry?> getActiveEntry() async {
    final String? raw;
    try {
      raw = await _storage.read(key: _activeKey);
    } on Object catch (error) {
      throw StateError('Durable restore journal read failed: $error');
    }
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Restore journal root is not an object.');
      }
      return RestoreJournalEntry.fromJson(decoded);
    } on Object catch (error) {
      throw StateError('Durable restore journal is invalid: $error');
    }
  }

  Future<void> clearActiveEntry() async {
    try {
      await _storage.delete(key: _activeKey);
    } on Object catch (error) {
      throw StateError('Durable restore journal clear failed: $error');
    }
  }
}

/// Explicit test double. Production code must use [RestoreJournalStore].
class InMemoryRestoreJournalStore extends RestoreJournalStore {
  InMemoryRestoreJournalStore() : super(storage: const FlutterSecureStorage());

  RestoreJournalEntry? _entry;

  @override
  Future<void> saveEntry(RestoreJournalEntry entry) async {
    _entry = entry;
  }

  @override
  Future<RestoreJournalEntry?> getActiveEntry() async => _entry;

  @override
  Future<void> clearActiveEntry() async {
    _entry = null;
  }
}

/// Reads the transactional restore-generation marker from the live database.
///
/// The marker equals the active journal id only when the import transaction
/// actually committed; a rolled-back transaction leaves the previous value.
abstract class RestoreCommitProbe {
  Future<String?> readRestoreGenerationMarker();
}

class _DirectoryMediaGeneration {
  _DirectoryMediaGeneration({
    required this.canonicalRoot,
    required this.live,
    required this.staged,
    required this.previous,
  });

  final String canonicalRoot;
  final Directory live;
  final Directory staged;
  final Directory previous;

  Future<bool> get liveExists => live.exists();
  Future<bool> get stagedExists => staged.exists();
  Future<bool> get previousExists => previous.exists();
}

List<_DirectoryMediaGeneration> _mediaGenerations(
  Directory appDir,
  String token,
) {
  return [
    for (final root in kRestoreMediaRoots)
      _DirectoryMediaGeneration(
        canonicalRoot: root,
        live: Directory(p.join(appDir.path, root)),
        staged: Directory(p.join(appDir.path, '$root.restore-$token')),
        previous: Directory(p.join(appDir.path, '$root.previous-$token')),
      ),
  ];
}

/// Activates staged media after the imported database generation has been
/// proven committed. Idempotent across process death: each root converges to
/// `live = staged content` exactly once, keeping the old generation in
/// `.previous-*` until cleanup.
///
/// Per-root states and transitions:
/// - live + staged              : activation not started -> perform renames.
/// - no live, staged + previous : died between renames -> finish rename.
/// - no live, staged, no previous : first-generation root -> expose staged.
/// - live, no staged            : already activated -> nothing to do.
///
/// WP-005 (F-012): this is the single activation implementation.
/// [OwntendBackupService] delegates here with its sidecar registration and
/// failpoint hooks instead of maintaining a parallel rename sequence.
Future<void> activateStagedMediaGenerations({
  required Directory appDir,
  required String token,
  void Function(String root)? onRootActivated,
  void Function(String root)? onPreviousArchived,
  void Function(String root)? onRootActivating,
}) async {
  for (final generation in _mediaGenerations(appDir, token)) {
    if (!await generation.stagedExists) {
      continue;
    }
    // Called before any rename for this root so injected crashes reproduce
    // the exact pre-activation interruption states.
    onRootActivating?.call(generation.canonicalRoot);
    final hadLive = await generation.liveExists;
    if (hadLive) {
      if (await generation.previousExists) {
        await generation.previous.delete(recursive: true);
      }
      await generation.live.rename(generation.previous.path);
      onPreviousArchived?.call(generation.canonicalRoot);
    }
    await generation.staged.rename(generation.live.path);
    onRootActivated?.call(generation.canonicalRoot);
  }
}

/// Deletes staged media without ever touching the canonical live folders.
/// Used before the database commit has been proven; `.previous-*`
/// generations are restored first if a partial activation left one behind.
Future<void> rollbackStagedMediaGenerations({
  required Directory appDir,
  required String token,
}) async {
  for (final generation in _mediaGenerations(appDir, token).reversed) {
    if (await generation.stagedExists) {
      await generation.staged.delete(recursive: true);
    }
    if (await generation.previousExists && !await generation.liveExists) {
      await generation.previous.rename(generation.live.path);
    }
  }
}

/// Removes retained previous generations after successful activation.
Future<void> cleanupPreviousMediaGenerations({
  required Directory appDir,
  required String token,
}) async {
  for (final generation in _mediaGenerations(appDir, token)) {
    if (await generation.previousExists) {
      await generation.previous.delete(recursive: true);
    }
  }
}

class RestoreJournalResolver {
  RestoreJournalResolver({
    required this.journalStore,
    this.localSyncStore,
    this.commitProbe,
    Future<Directory> Function()? documentsDirectory,
  }) : _documentsDirectoryOverride = documentsDirectory;

  final RestoreJournalStore journalStore;
  final LocalSyncStore? localSyncStore;
  final RestoreCommitProbe? commitProbe;
  final Future<Directory> Function()? _documentsDirectoryOverride;

  Future<Directory> _appDir() async {
    final override = _documentsDirectoryOverride;
    if (override != null) return override();
    return getApplicationDocumentsDirectory();
  }

  RestoreCommitProbe get _probe {
    final explicit = commitProbe;
    if (explicit != null) return explicit;
    final store = localSyncStore;
    if (store == null) {
      throw StateError(
        'Restore recovery requires the local synchronization store to verify '
        'the committed restore generation.',
      );
    }
    return store;
  }

  Future<bool> _databaseCommitted(RestoreJournalEntry entry) async {
    final marker = await _probe.readRestoreGenerationMarker();
    return marker == entry.journalId;
  }

  Future<void> resolveActiveJournal() async {
    final entry = await journalStore.getActiveEntry();
    if (entry == null) return;
    if (entry.phase == RestorePhase.terminal) {
      await journalStore.clearActiveEntry();
      return;
    }

    if (entry.version > kCurrentRestoreJournalVersion) {
      throw StateError(
        'Active restore journal version (${entry.version}) is newer than supported ($kCurrentRestoreJournalVersion). Update Owntend to complete restore.',
      );
    }
    if (entry.version < kCurrentRestoreJournalVersion) {
      throw StateError(
        'Active restore journal uses the retired format ${entry.version}; no compatibility path is provided.',
      );
    }

    AppLogger.info(
      'restore_journal_recovery_started',
      fields: {'phase': entry.phase.name},
    );

    final appDir = await _appDir();
    final committed = await _databaseCommitted(entry);

    if (committed) {
      await _validateAccountScope(entry);
      if (entry.mediaToken != null) {
        await activateStagedMediaGenerations(
          appDir: appDir,
          token: entry.mediaToken!,
        );
      }
      await _makeCloudIntentDurable(entry);
      if (entry.mediaToken != null) {
        await cleanupPreviousMediaGenerations(
          appDir: appDir,
          token: entry.mediaToken!,
        );
      }
      await journalStore.clearActiveEntry();
      AppLogger.info('restore_journal_rolled_forward_commit_verified');
      return;
    }

    if (entry.mediaToken != null) {
      await rollbackStagedMediaGenerations(
        appDir: appDir,
        token: entry.mediaToken!,
      );
    }
    await journalStore.clearActiveEntry();
    AppLogger.info('restore_journal_rolled_back_commit_unverified');
  }

  Future<void> _validateAccountScope(RestoreJournalEntry entry) async {
    final store = localSyncStore;
    if (store == null) {
      throw StateError(
        'Restore recovery requires the local synchronization store after database commit.',
      );
    }
    final account = await store.existingAccount();
    final boundUserId = account?.boundUserId;
    if (entry.accountScope == 'localOnly') {
      if (entry.cloudDisposition == RestoreCloudDisposition.updateCloud) {
        throw StateError(
          'Restore recovery cloud intent is inconsistent with local-only scope.',
        );
      }
      return;
    }
    if (boundUserId != null && boundUserId != entry.accountScope) {
      throw StateError(
        'Restore recovery is blocked because local data is bound to a different account.',
      );
    }
    if (entry.cloudDisposition == RestoreCloudDisposition.updateCloud &&
        boundUserId != entry.accountScope) {
      throw StateError(
        'Restore recovery cannot update cloud data without the expected local account binding.',
      );
    }
  }

  Future<void> _makeCloudIntentDurable(RestoreJournalEntry entry) async {
    final store = localSyncStore;
    if (store == null) {
      throw StateError(
        'Restore recovery requires the local synchronization store after database commit.',
      );
    }
    if (entry.cloudDisposition == RestoreCloudDisposition.updateCloud) {
      await store.enqueueRestoreSnapshot(DateTime.now());
    } else {
      await store.pauseAfterLocalRestore();
    }
  }
}

class RestoreRecoveryCoordinator {
  RestoreRecoveryCoordinator({
    required this.journalStore,
    required this.localSyncStore,
    SidecarRegistryStore? sidecarRegistry,
  }) : sidecarRegistry = sidecarRegistry ?? SidecarRegistryStore();

  final RestoreJournalStore journalStore;
  final LocalSyncStore localSyncStore;
  final SidecarRegistryStore sidecarRegistry;

  Future<void> recover() async {
    await RestoreJournalResolver(
      journalStore: journalStore,
      localSyncStore: localSyncStore,
    ).resolveActiveJournal();

    try {
      final appDir = await getApplicationDocumentsDirectory();
      await sidecarRegistry.sweepOrphans(appDir: appDir);
    } on Object catch (error) {
      AppLogger.warning('restore_sidecar_startup_sweep_failed', error: error);
    }
  }
}
