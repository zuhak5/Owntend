// ignore_for_file: prefer_initializing_formals
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'charged_operation_contracts.dart';

class TaskCreationOperationStore {
  TaskCreationOperationStore({FlutterSecureStorage? storage})
    : _storage = storage;

  final FlutterSecureStorage? _storage;
  final Map<String, String> _inMemoryFallback = {};
  static const _keyPrefix = 'task_creation_operation_';

  String _storageKey(String operationId) => '$_keyPrefix$operationId';

  Future<void> saveOperation(TaskCreationOperation operation) async {
    final key = _storageKey(operation.operationId);
    final value = jsonEncode(operation.toJson());
    _inMemoryFallback[key] = value;
    final storage = _storage;
    if (storage != null) {
      try {
        await storage.write(key: key, value: value);
      } catch (error) {
        // Enforce durable-write invariant: failure to persist durably throws
        throw TaskCreationFailure(
          'Durable write to secure storage failed: $error',
          code: TaskCreationFailureCode.draftSaveFailed,
        );
      }
    }
  }

  Future<TaskCreationOperation?> getOperation(String operationId) async {
    final key = _storageKey(operationId);
    final storage = _storage;
    if (storage != null) {
      try {
        final raw = await storage.read(key: key);
        if (raw != null && raw.trim().isNotEmpty) {
          final json = jsonDecode(raw) as Map<String, dynamic>;
          return TaskCreationOperation.fromJson(json);
        }
      } catch (_) {}
    }
    final raw = _inMemoryFallback[key];
    if (raw == null || raw.trim().isEmpty) return null;
    final json = jsonDecode(raw) as Map<String, dynamic>;
    return TaskCreationOperation.fromJson(json);
  }

  Future<List<TaskCreationOperation>> listOperationsForAccount(
    String accountScope,
  ) async {
    Map<String, String> all = {};
    final storage = _storage;
    if (storage != null) {
      try {
        all = await storage.readAll();
      } catch (_) {
        all = Map<String, String>.from(_inMemoryFallback);
      }
    } else {
      all = Map<String, String>.from(_inMemoryFallback);
    }
    final ops = <TaskCreationOperation>[];
    for (final entry in all.entries) {
      if (!entry.key.startsWith(_keyPrefix)) continue;
      try {
        final json = jsonDecode(entry.value) as Map<String, dynamic>;
        final op = TaskCreationOperation.fromJson(json);
        if (op.accountScope == accountScope) {
          ops.add(op);
        }
      } catch (_) {}
    }
    ops.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return ops;
  }

  Future<void> deleteOperation(String operationId) async {
    final key = _storageKey(operationId);
    _inMemoryFallback.remove(key);
    final storage = _storage;
    if (storage != null) {
      try {
        await storage.delete(key: key);
      } catch (_) {}
    }
  }

  Future<void> clearOperationsForAccount(String accountScope) async {
    final keys = <String>{..._inMemoryFallback.keys};
    final storage = _storage;
    if (storage != null) {
      try {
        keys.addAll((await storage.readAll()).keys);
      } catch (_) {
        rethrow;
      }
    }

    for (final key in keys) {
      if (!key.startsWith(_keyPrefix)) continue;
      String? encoded = _inMemoryFallback[key];
      if (storage != null) {
        encoded ??= await storage.read(key: key);
      }
      if (encoded == null) continue;
      try {
        final operation = TaskCreationOperation.fromJson(
          jsonDecode(encoded) as Map<String, dynamic>,
        );
        if (operation.accountScope != accountScope) continue;
      } on Object {
        // A malformed entry cannot be attributed safely to this account.
        continue;
      }
      _inMemoryFallback.remove(key);
      if (storage != null) await storage.delete(key: key);
    }
  }

  Future<void> purgeTerminalPayloads(String accountScope) async {
    final ops = await listOperationsForAccount(accountScope);
    for (final op in ops) {
      if (op.state == TaskCreationOperationState.reconciled ||
          op.state == TaskCreationOperationState.permanentRejected) {
        if (op.requestPayload.isNotEmpty) {
          final purged = op.copyWith(
            requestPayload: const {},
            updatedAt: DateTime.now(),
          );
          await saveOperation(purged);
        }
      }
    }
  }
}
