import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/user_facing_errors.dart';

enum SupabaseFailureKind {
  configuration,
  cancelled,
  authentication,
  offline,
  permissionDenied,
  conflict,
  storage,
  incompatibleSchema,
  unknown,
}

const dataApiAclContractMismatchCode = 'data_api_acl_contract_mismatch';
const maintenanceCompletionRpcContractMismatchCode =
    'maintenance_completion_rpc_contract_mismatch';
const maintenanceCompletionPayloadRejectedCode =
    'maintenance_completion_payload_rejected';

class SupabaseFailure implements Exception {
  const SupabaseFailure({
    required this.kind,
    required this.message,
    this.retryable = false,
    this.diagnosticCode,
    this.sqlState,
  });

  final SupabaseFailureKind kind;
  final String message;
  final bool retryable;
  final String? diagnosticCode;
  final String? sqlState;

  Map<String, String> safeDiagnosticFields({
    required String entity,
    required String operation,
  }) => {
    'sync_entity': entity,
    'sync_operation': operation,
    'diagnostic_code': ?diagnosticCode,
    'sql_state': ?sqlState,
  };

  @override
  String toString() => message;

  static SupabaseFailure from(Object error) {
    if (error is SupabaseFailure) {
      return error;
    }
    if (error is SocketException ||
        error is TimeoutException ||
        error is http.ClientException) {
      return const SupabaseFailure(
        kind: SupabaseFailureKind.offline,
        message: 'Cloud sync is unavailable while offline.',
        retryable: true,
      );
    }
    if (error is AuthException) {
      if (_isMissingSession(error.code, error.message)) {
        return const SupabaseFailure(
          kind: SupabaseFailureKind.authentication,
          message:
              'This cloud session expired or was revoked. '
              'Your local data is safe.',
        );
      }
      return SupabaseFailure(
        kind: SupabaseFailureKind.authentication,
        message: error.message,
      );
    }
    if (error is PostgrestException) {
      final normalized = '${error.code} ${error.message}'.toLowerCase();
      if (_isMissingSession(error.code, error.message)) {
        return const SupabaseFailure(
          kind: SupabaseFailureKind.authentication,
          message:
              'This cloud session expired or was revoked. '
              'Your local data is safe.',
        );
      }
      if (normalized.contains('429') ||
          normalized.contains('too many requests') ||
          RegExp(r'\b5\d\d\b').hasMatch(normalized) ||
          error.code == 'PGRST000' ||
          error.code == 'PGRST001' ||
          error.code == 'PGRST002') {
        return const SupabaseFailure(
          kind: SupabaseFailureKind.offline,
          message: 'Cloud backup is temporarily unavailable.',
          retryable: true,
        );
      }
      if (error.code == '42501' && _isDataApiAclMismatch(error)) {
        return const SupabaseFailure(
          kind: SupabaseFailureKind.incompatibleSchema,
          message:
              'Cloud data permissions do not match this Owntend build. '
              'Install the latest release.',
          retryable: false,
          diagnosticCode: dataApiAclContractMismatchCode,
          sqlState: '42501',
        );
      }
      if (error.code == '42501' || error.code == 'PGRST301') {
        return const SupabaseFailure(
          kind: SupabaseFailureKind.permissionDenied,
          message: 'Cloud access was denied.',
        );
      }
      if (error.code == 'PT409') {
        return const SupabaseFailure(
          kind: SupabaseFailureKind.conflict,
          message:
              'This maintenance completion conflicts with newer cloud data.',
        );
      }
      if (error.code == '23505' ||
          error.code == '40001' ||
          error.code == 'PGRST116') {
        return const SupabaseFailure(
          kind: SupabaseFailureKind.conflict,
          message: 'The cloud record changed on another device.',
          retryable: true,
        );
      }
      if (error.code == '42P01' ||
          error.code == '42703' ||
          (error.code == '23514' && normalized.contains('protocol')) ||
          error.code == '0A000' ||
          error.code == 'PGRST202') {
        return const SupabaseFailure(
          kind: SupabaseFailureKind.incompatibleSchema,
          message:
              'This Owntend build is not compatible with the cloud sync '
              'protocol. Install the latest release.',
        );
      }
    }
    if (error is StorageException) {
      final status = int.tryParse(error.statusCode ?? '');
      if (status == 401 || status == 403) {
        return const SupabaseFailure(
          kind: SupabaseFailureKind.permissionDenied,
          message: 'Cloud media access was denied.',
        );
      }
      return SupabaseFailure(
        kind: SupabaseFailureKind.storage,
        message: error.message,
        retryable:
            status == null || status == 408 || status == 429 || status >= 500,
      );
    }
    if (isLocalDatabaseBusyError(error)) {
      return const SupabaseFailure(
        kind: SupabaseFailureKind.unknown,
        message:
            'Owntend is finishing another local database operation. '
            'Sync will retry shortly.',
        retryable: true,
      );
    }
    if (looksLikeRawDatabaseError(error)) {
      return const SupabaseFailure(
        kind: SupabaseFailureKind.unknown,
        message:
            'Owntend could not finish a local database operation. '
            'Your changes remain on this device.',
        retryable: true,
      );
    }
    return const SupabaseFailure(
      kind: SupabaseFailureKind.unknown,
      message: 'An unexpected cloud error occurred.',
    );
  }
}

bool _isDataApiAclMismatch(PostgrestException error) {
  final message = error.message.toLowerCase();
  final hint = (error.hint ?? '').toLowerCase();
  final explicitlyDeniedObject =
      message.contains('permission denied for table') ||
      message.contains('permission denied for column') ||
      message.contains('permission denied for relation');
  final privilegeHint =
      hint.contains('grant') &&
      (hint.contains('privilege') ||
          hint.contains('select') ||
          hint.contains('insert') ||
          hint.contains('update') ||
          hint.contains('delete'));
  return explicitlyDeniedObject || privilegeHint;
}

bool _isMissingSession(String? code, String message) {
  final normalized = '${code ?? ''} $message'.toLowerCase();
  return normalized.contains('session_not_found') ||
      normalized.contains('session from session_id claim') ||
      normalized.contains('session id claim in jwt does not exist');
}
