import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../supabase/secure_supabase_storage.dart';
import '../sync/local_sync_store.dart';
import '../utils/redacting_logger.dart';
import 'sidecar_registry.dart';

const int kCurrentRestoreJournalVersion = 1;

enum RestorePhase {
  validated,
  safetyBackupComplete,
  servicesSuspended,
  mediaStaged,
  dbCommitStarted,
  dbCommitComplete,
  mediaSwapped,
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
    required this.updateCloudIntent,
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
  final bool updateCloudIntent;
  final DateTime createdAt;
  final DateTime updatedAt;

  RestoreJournalEntry copyWith({
    RestorePhase? phase,
    String? safetyBackupPath,
    String? safetyBackupHash,
    String? mediaToken,
    bool? updateCloudIntent,
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
      updateCloudIntent: updateCloudIntent ?? this.updateCloudIntent,
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
    'update_cloud_intent': updateCloudIntent,
    'created_at': createdAt.toUtc().toIso8601String(),
    'updated_at': updatedAt.toUtc().toIso8601String(),
  };

  factory RestoreJournalEntry.fromJson(Map<String, dynamic> json) {
    return RestoreJournalEntry(
      version: json['version'] as int? ?? 1,
      journalId: json['journal_id'] as String,
      accountScope: json['account_scope'] as String,
      archivePath: json['archive_path'] as String,
      archiveHash: json['archive_hash'] as String,
      safetyBackupPath: json['safety_backup_path'] as String?,
      safetyBackupHash: json['safety_backup_hash'] as String?,
      mediaToken: json['media_token'] as String?,
      phase: RestorePhase.values.byName(json['phase'] as String),
      updateCloudIntent: json['update_cloud_intent'] as bool? ?? false,
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

  static const _activeKey = 'owntend_active_restore_journal_v1';

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

class RestoreJournalResolver {
  RestoreJournalResolver({required this.journalStore, this.localSyncStore});

  final RestoreJournalStore journalStore;
  final LocalSyncStore? localSyncStore;

  Future<void> resolveActiveJournal() async {
    var entry = await journalStore.getActiveEntry();
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

    AppLogger.info(
      'restore_journal_recovery_started',
      fields: {'phase': entry.phase.name},
    );

    if (entry.phase.index < RestorePhase.dbCommitStarted.index) {
      if (entry.mediaToken != null) {
        await _cleanupStagedMedia(entry.mediaToken!);
      }
      await journalStore.clearActiveEntry();
      AppLogger.info('restore_journal_rolled_back_pre_db_commit');
      return;
    }

    await _validateAccountScope(entry);
    if (entry.phase.index < RestorePhase.mediaSwapped.index &&
        entry.mediaToken != null) {
      await _finalizeMediaSwap(entry.mediaToken!);
      entry = entry.copyWith(
        phase: RestorePhase.mediaSwapped,
        updatedAt: DateTime.now(),
      );
      await journalStore.saveEntry(entry);
    }

    if (entry.phase.index < RestorePhase.cloudIntentDurable.index) {
      await _makeCloudIntentDurable(entry);
      entry = entry.copyWith(
        phase: RestorePhase.cloudIntentDurable,
        updatedAt: DateTime.now(),
      );
      await journalStore.saveEntry(entry);
    }

    await journalStore.clearActiveEntry();
    AppLogger.info('restore_journal_rolled_forward_post_db_commit');
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
      if (entry.updateCloudIntent) {
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
    if (entry.updateCloudIntent && boundUserId != entry.accountScope) {
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
    if (entry.updateCloudIntent) {
      await store.enqueueRestoreSnapshot(DateTime.now());
    } else {
      await store.pauseAfterLocalRestore();
    }
  }

  Future<void> _cleanupStagedMedia(String token) async {
    final appDir = await getApplicationDocumentsDirectory();
    for (final root in ['photos', 'profile', 'cloud_media']) {
      final staged = Directory(p.join(appDir.path, '$root.restore-$token'));
      if (await staged.exists()) {
        await staged.delete(recursive: true);
      }
    }
  }

  Future<void> _finalizeMediaSwap(String token) async {
    final appDir = await getApplicationDocumentsDirectory();
    for (final root in ['photos', 'profile', 'cloud_media']) {
      final previous = Directory(p.join(appDir.path, '$root.previous-$token'));
      if (await previous.exists()) {
        await previous.delete(recursive: true);
      }
      final staged = Directory(p.join(appDir.path, '$root.restore-$token'));
      final destination = Directory(p.join(appDir.path, root));
      if (await staged.exists() && !await destination.exists()) {
        await staged.rename(destination.path);
      }
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
