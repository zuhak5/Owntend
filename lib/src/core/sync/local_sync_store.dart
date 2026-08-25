import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../data/repositories.dart';
import '../database/app_database.dart';
import '../services/restore_journal.dart';
import '../supabase/supabase_failure.dart';
import '../utils/redacting_logger.dart';
import 'sync_contracts.dart';
import 'sync_dtos.dart';

part 'local_store/account_store.dart';
part 'local_store/media_store.dart';
part 'local_store/mutation_store.dart';
part 'local_store/outbox_store.dart';
part 'local_store/remote_store.dart';

/// Settings key holding the restore-generation commit marker. It is written
/// inside the restore import transaction and is intentionally absent from
/// `allowedRemoteSettingKeys`, so it never synchronizes.
const restoreGenerationSettingKey = 'restore_generation';

abstract class _LocalSyncStoreBase {
  AppDatabase get db;
  Future<Directory> Function() get _documentsDirectory;
  Future<void> Function(File file) get _deleteFile;
  Future<SyncAccountData> account();
  Future<T> withOutboxSuppressed<T>(Future<T> Function() action);
  Future<void> applyRemoteRecords(List<SyncRecord> records);
  Future<void> _saveShadow(SyncRecord record);
  Future<void> _upsertLocal(SyncRecord record);
  Future<SyncRecord?> readMutation(LocalSyncMutation mutation, String deviceId);
  Future<void> _deleteLocal(SyncRecord record);
  Future<void> _enqueueLocalMediaCleanup(String relativePath);

  /// WP-004 (F-006): durable skip promises for masked incremental-feed
  /// records. See [LocalSyncStore.skippedFeedEntriesForDrain].
  Future<List<SyncSkippedFeedEntryRow>> skippedFeedEntriesForDrain();
  Future<void> clearSkippedFeedEntry(String entity, String recordKey);

  /// WP-006 (F-015): count of payloads that failed structural decoding during
  /// queue dependency resolution or acknowledgement processing. Corrupt
  /// payloads previously vanished into silent catches; they are now
  /// observable without storing any payload content.
  int payloadParseFailures = 0;
}

class LocalSyncStore extends _LocalSyncStoreBase
    with
        _LocalSyncAccountStore,
        _LocalSyncOutboxStore,
        _LocalSyncRemoteStore,
        _LocalSyncMutationStore,
        _LocalSyncMediaStore
    implements RestoreCommitProbe {
  LocalSyncStore(
    this.db, {
    Future<Directory> Function()? documentsDirectory,
    Future<void> Function(File file)? deleteFile,
  }) : _documentsDirectory =
           documentsDirectory ?? getApplicationDocumentsDirectory,
       _deleteFile = deleteFile ?? _deleteFileFromDisk;

  @override
  final AppDatabase db;
  @override
  final Future<Directory> Function() _documentsDirectory;
  @override
  final Future<void> Function(File file) _deleteFile;
  static Future<void> _deleteFileFromDisk(File file) async {
    await file.delete();
  }
}

const _localSyncUuid = Uuid();
