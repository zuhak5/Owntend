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
import '../supabase/supabase_failure.dart';
import 'sync_contracts.dart';
import 'sync_dtos.dart';

part 'local_store/account_store.dart';
part 'local_store/media_store.dart';
part 'local_store/mutation_store.dart';
part 'local_store/outbox_store.dart';
part 'local_store/remote_store.dart';

abstract class _LocalSyncStoreBase {
  AppDatabase get db;
  Future<Directory> Function() get _documentsDirectory;
  Future<void> Function(File file) get _deleteFile;
  Future<SyncAccountData> account();
  Future<T> withOutboxSuppressed<T>(Future<T> Function() action);
  Future<void> applyRemoteRecords(List<SyncRecord> records);
  Future<void> _saveShadow(SyncRecord record);
  Future<void> _deleteLocal(SyncRecord record);
  Future<void> _enqueueLocalMediaCleanup(String relativePath);
}

class LocalSyncStore extends _LocalSyncStoreBase
    with
        _LocalSyncAccountStore,
        _LocalSyncOutboxStore,
        _LocalSyncRemoteStore,
        _LocalSyncMutationStore,
        _LocalSyncMediaStore {
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
