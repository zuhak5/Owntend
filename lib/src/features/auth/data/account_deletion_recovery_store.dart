import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../../core/supabase/secure_supabase_storage.dart';

typedef AccountDeletionRecoveryKeyFactory = String Function();

final RegExp _recoveryKeyPattern = RegExp(r'^[A-Za-z0-9_-]{43}$');

/// Durable phases of the account-deletion cleanup protocol.
///
/// Every phase is actually written by [the repository]
/// (`supabase_auth_repository.dart`) before the next transition; there are no
/// speculative intermediate states. `acknowledgementPending` records that
/// local cleanup finished but the server has not yet proven the terminal
/// acknowledgment, so a restart must retry only that step.
enum AccountDeletionJournalPhase {
  prepared,
  remoteCompleted,
  localDatabaseCleared,
  localProviderCleared,
  acknowledgementPending,
  acknowledged;

  static AccountDeletionJournalPhase parse(String? value) {
    if (value == null) return prepared;
    return AccountDeletionJournalPhase.values.firstWhere(
      (e) => e.name == value,
      orElse: () => prepared,
    );
  }
}

class AccountDeletionRecoveryOperation {
  const AccountDeletionRecoveryOperation({
    required this.expectedUserId,
    required this.recoveryKey,
    this.operationId,
    this.phase = AccountDeletionJournalPhase.prepared,
    this.createdAt,
  });

  final String expectedUserId;
  final String recoveryKey;
  final String? operationId;
  final AccountDeletionJournalPhase phase;
  final String? createdAt;

  bool get isValid =>
      expectedUserId.isNotEmpty && _recoveryKeyPattern.hasMatch(recoveryKey);

  AccountDeletionRecoveryOperation copyWith({
    String? expectedUserId,
    String? recoveryKey,
    String? operationId,
    AccountDeletionJournalPhase? phase,
    String? createdAt,
  }) {
    return AccountDeletionRecoveryOperation(
      expectedUserId: expectedUserId ?? this.expectedUserId,
      recoveryKey: recoveryKey ?? this.recoveryKey,
      operationId: operationId ?? this.operationId,
      phase: phase ?? this.phase,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, String> toJson() {
    final result = <String, String>{
      'expected_user_id': expectedUserId,
      'recovery_key': recoveryKey,
      'phase': phase.name,
    };
    if (operationId != null) result['operation_id'] = operationId!;
    if (createdAt != null) result['created_at'] = createdAt!;
    return result;
  }

  static AccountDeletionRecoveryOperation? fromJson(Object? value) {
    if (value is! Map) return null;
    final operation = AccountDeletionRecoveryOperation(
      expectedUserId: value['expected_user_id'] as String? ?? '',
      recoveryKey: value['recovery_key'] as String? ?? '',
      operationId: value['operation_id'] as String?,
      phase: AccountDeletionJournalPhase.parse(value['phase'] as String?),
      createdAt: value['created_at'] as String?,
    );
    return operation.isValid ? operation : null;
  }
}

abstract interface class AccountDeletionRecoveryStore {
  Future<AccountDeletionRecoveryOperation?> read();
  Future<void> write(AccountDeletionRecoveryOperation operation);
  Future<void> clear();
}

class SecureAccountDeletionRecoveryStore
    implements AccountDeletionRecoveryStore {
  SecureAccountDeletionRecoveryStore({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            aOptions: owntendAndroidSecureStorageOptions,
          );

  static const _storageKey = 'owntend.account-deletion-recovery.v1';

  final FlutterSecureStorage _storage;

  @override
  Future<AccountDeletionRecoveryOperation?> read() async {
    final encoded = await _storage.read(key: _storageKey);
    if (encoded == null || encoded.isEmpty) return null;
    try {
      final operation = AccountDeletionRecoveryOperation.fromJson(
        jsonDecode(encoded),
      );
      if (operation != null) return operation;
    } on FormatException {
      // A malformed record cannot safely identify a logical operation.
    }
    await clear();
    return null;
  }

  @override
  Future<void> write(AccountDeletionRecoveryOperation operation) {
    if (!operation.isValid) {
      throw ArgumentError('Invalid account-deletion recovery operation.');
    }
    return _storage.write(
      key: _storageKey,
      value: jsonEncode(operation.toJson()),
    );
  }

  @override
  Future<void> clear() => _storage.delete(key: _storageKey);
}

String createAccountDeletionRecoveryKey() {
  final random = math.Random.secure();
  final bytes = Uint8List(32);
  for (var index = 0; index < bytes.length; index++) {
    bytes[index] = random.nextInt(256);
  }
  return base64UrlEncode(bytes).replaceAll('=', '');
}
