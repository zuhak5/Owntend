import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../sync/local_sync_store.dart';
import '../utils/redacting_logger.dart';

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

class RestoreJournalStore {
  RestoreJournalStore({this.storage});

  final FlutterSecureStorage? storage;
  static const _activeKey = 'owntend_active_restore_journal_v1';
  static RestoreJournalEntry? _inMemoryFallback;

  Future<void> saveEntry(RestoreJournalEntry entry) async {
    _inMemoryFallback = entry;
    final jsonStr = jsonEncode(entry.toJson());
    final s = storage;
    if (s != null) {
      try {
        await s.write(key: _activeKey, value: jsonStr);
      } catch (e) {
        throw Exception('Durable restore journal write failed: $e');
      }
    }
  }

  Future<RestoreJournalEntry?> getActiveEntry() async {
    final s = storage;
    if (s != null) {
      try {
        final raw = await s.read(key: _activeKey);
        if (raw != null && raw.trim().isNotEmpty) {
          final json = jsonDecode(raw) as Map<String, dynamic>;
          return RestoreJournalEntry.fromJson(json);
        }
      } catch (_) {}
    }
    return _inMemoryFallback;
  }

  Future<void> clearActiveEntry() async {
    _inMemoryFallback = null;
    final s = storage;
    if (s != null) {
      try {
        await s.delete(key: _activeKey);
      } catch (_) {}
    }
  }
}

class RestoreJournalResolver {
  RestoreJournalResolver({required this.journalStore, this.localSyncStore});

  final RestoreJournalStore journalStore;
  final LocalSyncStore? localSyncStore;

  Future<void> resolveActiveJournal() async {
    final entry = await journalStore.getActiveEntry();
    if (entry == null || entry.phase == RestorePhase.terminal) {
      return;
    }

    if (entry.version > kCurrentRestoreJournalVersion) {
      throw Exception(
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
    } else {
      if (entry.mediaToken != null) {
        await _finalizeMediaSwap(entry.mediaToken!);
      }
      if (entry.updateCloudIntent && localSyncStore != null) {
        await localSyncStore!.enqueueRestoreSnapshot(DateTime.now());
      } else if (localSyncStore != null) {
        await localSyncStore!.pauseAfterLocalRestore();
      }
      await journalStore.clearActiveEntry();
      AppLogger.info('restore_journal_rolled_forward_post_db_commit');
    }
  }

  Future<void> _cleanupStagedMedia(String token) async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      for (final root in ['photos', 'profile', 'cloud_media']) {
        final staged = Directory(p.join(appDir.path, '$root.restore-$token'));
        if (await staged.exists()) {
          await staged.delete(recursive: true);
        }
      }
    } catch (_) {}
  }

  Future<void> _finalizeMediaSwap(String token) async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      for (final root in ['photos', 'profile', 'cloud_media']) {
        final previous = Directory(
          p.join(appDir.path, '$root.previous-$token'),
        );
        if (await previous.exists()) {
          await previous.delete(recursive: true);
        }
        final staged = Directory(p.join(appDir.path, '$root.restore-$token'));
        final destination = Directory(p.join(appDir.path, root));
        if (await staged.exists() && !await destination.exists()) {
          await staged.rename(destination.path);
        }
      }
    } catch (_) {}
  }
}
