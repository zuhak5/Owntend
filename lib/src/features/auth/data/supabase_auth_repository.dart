import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/observability/sentry_logger_bridge.dart';
import '../../../core/observability/sentry_scope.dart';
import '../../../core/observability/sentry_tracing.dart';
import '../../../core/supabase/supabase_failure.dart';
import '../../../core/utils/redacting_logger.dart';
import '../domain/auth_repository.dart';
import 'account_deletion_recovery_store.dart';
import 'native_google_sign_in.dart';

class SupabaseAuthRepository implements AuthRepository {
  SupabaseAuthRepository(
    this._client,
    this._googleSignIn, {
    required this.onAccountDeletionPrepared,
    required this.onAccountDeletionCancelled,
    required this.onAccountDeleted,
    AccountDeletionRecoveryStore? accountDeletionRecoveryStore,
    AccountDeletionRecoveryKeyFactory? accountDeletionRecoveryKeyFactory,
  }) : _accountDeletionRecoveryStore =
           accountDeletionRecoveryStore ?? SecureAccountDeletionRecoveryStore(),
       _accountDeletionRecoveryKeyFactory =
           accountDeletionRecoveryKeyFactory ??
           createAccountDeletionRecoveryKey;

  final SupabaseClient _client;
  final GoogleSignInGateway _googleSignIn;
  final Future<void> Function(String userId) onAccountDeletionPrepared;
  final Future<void> Function(String userId) onAccountDeletionCancelled;
  final Future<void> Function(String userId) onAccountDeleted;
  final AccountDeletionRecoveryStore _accountDeletionRecoveryStore;
  final AccountDeletionRecoveryKeyFactory _accountDeletionRecoveryKeyFactory;

  @override
  AuthSession? get currentSession =>
      _sessionFromSupabase(_client.auth.currentSession);

  @override
  Stream<AuthStateChange> watchAuthState() async* {
    try {
      await resumePendingAccountDeletion();
    } on Object {
      AppLogger.warning('auth_account_delete_recovery_deferred');
    }
    var previous = AuthStateChange(
      event: AuthEventType.initialSession,
      session: currentSession,
    );
    unawaited(_recordAuthState(previous));
    yield previous;
    await for (final state in _client.auth.onAuthStateChange) {
      final next = AuthStateChange(
        event: _eventFromSupabase(state.event),
        session: _sessionFromSupabase(state.session),
      );
      if (!next.hasSameIdentityAndEvent(previous)) {
        unawaited(_recordAuthState(next));
        yield next;
      }
      previous = next;
    }
  }

  Future<void> resumePendingAccountDeletion() async {
    final operation = await _accountDeletionRecoveryStore.read();
    if (operation == null) return;

    await onAccountDeletionPrepared(operation.expectedUserId);

    if (operation.phase != AccountDeletionJournalPhase.prepared) {
      await _completeAccountDeletion(operation);
      return;
    }

    final status = await _accountDeletionStatus(operation);
    switch (status) {
      case _AccountDeletionStatus.deleted:
        await _completeAccountDeletion(operation);
        return;
      case _AccountDeletionStatus.notFound:
      case _AccountDeletionStatus.pending:
      case _AccountDeletionStatus.temporarilyUnavailable:
        AppLogger.warning('auth_account_delete_recovery_retained');
        return;
    }
  }

  @override
  Future<void> signInWithGoogle() async {
    try {
      await traceOwntendOperation<void>('auth.google_sign_in', () async {
        final tokens = await _googleSignIn.signIn();
        await traceOwntendOperation<void>(
          'auth.supabase_token_exchange',
          () async {
            await _client.auth.signInWithIdToken(
              provider: OAuthProvider.google,
              idToken: tokens.idToken,
              accessToken: tokens.accessToken,
            );
          },
          attributes: const {'provider': 'google', 'execution': 'main'},
        );
      }, attributes: const {'provider': 'google', 'execution': 'main'});
      await setSentryAuthenticated(
        authenticated: true,
        event: 'auth.signed_in',
      );
    } on Object catch (error, stackTrace) {
      final failure = SupabaseFailure.from(error);
      reportOperationFailure(
        operation: 'auth_google_sign_in_failed',
        error: failure,
        stackTrace: stackTrace,
        fields: const {'provider': 'google', 'execution': 'main'},
      );
      await _throwAuthFailure(error);
    }
  }

  @override
  Future<void> signOut({bool allDevices = false}) async {
    try {
      await traceOwntendOperation<void>('auth.sign_out', () async {
        await _client.auth.signOut(
          scope: allDevices ? SignOutScope.global : SignOutScope.local,
        );
        await _googleSignIn.signOut();
      }, attributes: const {'provider': 'google', 'execution': 'main'});
      await clearSentryAccountScope(event: 'auth.signed_out');
    } on Object catch (error, stackTrace) {
      final failure = SupabaseFailure.from(error);
      reportOperationFailure(
        operation: 'auth_sign_out_failed',
        error: failure,
        stackTrace: stackTrace,
        fields: const {'provider': 'google', 'execution': 'main'},
      );
      throw failure;
    }
  }

  @override
  Future<void> deleteAccount() async {
    try {
      await traceOwntendOperation<void>(
        'auth.account_delete',
        _deleteAccount,
        attributes: const {'provider': 'google', 'execution': 'main'},
      );
      await clearSentryAccountScope(event: 'auth.account_deleted');
    } on Object catch (error, stackTrace) {
      final failure = SupabaseFailure.from(error);
      reportOperationFailure(
        operation: 'auth_account_delete_failed',
        error: failure,
        stackTrace: stackTrace,
        fields: const {'provider': 'google', 'execution': 'main'},
      );
      throw failure;
    }
  }

  Future<void> _deleteAccount() async {
    var deletionPrepared = false;
    var requestStarted = false;
    var createdOperation = false;
    String? originalUserId;
    AccountDeletionRecoveryOperation? operation;
    try {
      final currentUser = _client.auth.currentSession?.user;
      originalUserId = currentUser?.id;
      final originalEmail = currentUser?.email;
      if (originalUserId == null) {
        throw const SupabaseFailure(
          kind: SupabaseFailureKind.authentication,
          message: 'Sign in again before deleting your account.',
        );
      }

      // Reuse the already authenticated Google identity when the platform can
      // refresh it without account selection. Fall back to the interactive
      // flow only when lightweight reauthentication is unavailable.
      final tokens =
          await _googleSignIn.reauthenticateSilently() ??
          await _googleSignIn.signIn();

      if (tokens.email != null &&
          originalEmail != null &&
          tokens.email!.trim().toLowerCase() !=
              originalEmail.trim().toLowerCase()) {
        throw const SupabaseFailure(
          kind: SupabaseFailureKind.permissionDenied,
          message:
              'Authenticate with the same Google account before deleting it.',
        );
      }

      final reauthenticated = await _client.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: tokens.idToken,
        accessToken: tokens.accessToken,
      );
      if (reauthenticated.session?.user.id != originalUserId) {
        await _clearLocalAuthentication();
        throw const SupabaseFailure(
          kind: SupabaseFailureKind.permissionDenied,
          message:
              'Authenticate with the same Google account before deleting it.',
        );
      }

      operation = await _accountDeletionRecoveryStore.read();
      if (operation != null && operation.expectedUserId != originalUserId) {
        throw const SupabaseFailure(
          kind: SupabaseFailureKind.permissionDenied,
          message:
              'A pending account-deletion operation belongs to a different '
              'cloud identity.',
        );
      }
      if (operation == null) {
        operation = AccountDeletionRecoveryOperation(
          expectedUserId: originalUserId,
          recoveryKey: _accountDeletionRecoveryKeyFactory(),
        );
        if (!operation.isValid) {
          throw StateError('The account-deletion recovery key was invalid.');
        }
        await _accountDeletionRecoveryStore.write(operation);
        createdOperation = true;
      }

      deletionPrepared = true;
      await onAccountDeletionPrepared(originalUserId);
      FunctionResponse response;
      requestStarted = true;
      try {
        response = await _client.functions.invoke(
          'delete-account',
          body: {
            'confirmation': 'delete-my-account',
            'recovery_key': operation.recoveryKey,
          },
        );
      } on Object catch (error) {
        final functionCode = _functionErrorCode(error);
        if (createdOperation &&
            functionCode != 'invalid_session' &&
            _isSafePreDestructiveFailure(error)) {
          rethrow;
        }
        await _resolveAmbiguousDeletion(operation, sourceError: error);
        return;
      }
      if (!_isDeletionReceipt(response.data, originalUserId)) {
        await _resolveAmbiguousDeletion(operation);
        return;
      }
      await _completeAccountDeletion(operation);
    } on Object catch (error) {
      final functionErrorCode = _functionErrorCode(error);
      final safeCancellation =
          !requestStarted ||
          (createdOperation &&
              functionErrorCode != 'invalid_session' &&
              _isSafePreDestructiveFailure(error));
      if (safeCancellation && operation != null) {
        await _accountDeletionRecoveryStore.clear();
      }
      if (safeCancellation && deletionPrepared && originalUserId != null) {
        await _cancelPreparedDeletion(originalUserId);
      }
      if (functionErrorCode == 'recent_reauthentication_required') {
        throw const SupabaseFailure(
          kind: SupabaseFailureKind.authentication,
          message: 'Authenticate with Google again, then retry deletion.',
        );
      }
      if (functionErrorCode == 'storage_cleanup_failed') {
        throw const SupabaseFailure(
          kind: SupabaseFailureKind.storage,
          message:
              'Private media cleanup did not finish. Sign in and retry '
              'account deletion.',
          retryable: true,
        );
      }
      await _throwAuthFailure(error);
    }
  }

  Future<void> _resolveAmbiguousDeletion(
    AccountDeletionRecoveryOperation operation, {
    Object? sourceError,
  }) async {
    final status = await _accountDeletionStatus(operation);
    switch (status) {
      case _AccountDeletionStatus.deleted:
        await _completeAccountDeletion(operation);
        return;
      case _AccountDeletionStatus.notFound:
        if (sourceError != null) throw sourceError;
        throw const SupabaseFailure(
          kind: SupabaseFailureKind.unknown,
          message: 'The cloud account deletion receipt was invalid.',
        );
      case _AccountDeletionStatus.pending:
        if (_functionErrorCode(sourceError) == 'storage_cleanup_failed') {
          throw const SupabaseFailure(
            kind: SupabaseFailureKind.storage,
            message:
                'Private media cleanup did not finish. Sign in and retry '
                'account deletion.',
            retryable: true,
          );
        }
        throw const SupabaseFailure(
          kind: SupabaseFailureKind.unknown,
          message:
              'Account deletion is still pending. Retry to check the same '
              'deletion operation.',
          retryable: true,
        );
      case _AccountDeletionStatus.temporarilyUnavailable:
        throw const SupabaseFailure(
          kind: SupabaseFailureKind.offline,
          message:
              'Account deletion could not be confirmed yet. Retry to check '
              'the same deletion operation.',
          retryable: true,
        );
    }
  }

  Future<_AccountDeletionStatus> _accountDeletionStatus(
    AccountDeletionRecoveryOperation operation,
  ) async {
    try {
      final response = await _client.functions.invoke(
        'account-deletion-status',
        body: {
          'recovery_key': operation.recoveryKey,
          'expected_user_id': operation.expectedUserId,
        },
      );
      if (_isDeletionReceipt(response.data, operation.expectedUserId)) {
        return _AccountDeletionStatus.deleted;
      }
      final data = response.data;
      if (data is Map &&
          data['deleted'] == false &&
          data['status'] == 'pending') {
        return _AccountDeletionStatus.pending;
      }
      return _AccountDeletionStatus.temporarilyUnavailable;
    } on Object catch (error) {
      return switch (_functionErrorCode(error)) {
        'recovery_not_found' => _AccountDeletionStatus.notFound,
        'recovery_temporarily_unavailable' =>
          _AccountDeletionStatus.temporarilyUnavailable,
        _ => _AccountDeletionStatus.temporarilyUnavailable,
      };
    }
  }

  Future<void> _completeAccountDeletion(
    AccountDeletionRecoveryOperation operation,
  ) async {
    var currentOp = operation;
    try {
      if (currentOp.phase == AccountDeletionJournalPhase.prepared) {
        currentOp = currentOp.copyWith(
          phase: AccountDeletionJournalPhase.remoteCompleted,
        );
        await _accountDeletionRecoveryStore.write(currentOp);
      }

      if (currentOp.phase == AccountDeletionJournalPhase.remoteCompleted) {
        await traceOwntendOperation<void>(
          'auth.account_delete.local_cleanup',
          () async => onAccountDeleted(currentOp.expectedUserId),
          attributes: const {'execution': 'main'},
        );
        currentOp = currentOp.copyWith(
          phase: AccountDeletionJournalPhase.localDatabaseCleared,
        );
        await _accountDeletionRecoveryStore.write(currentOp);
      }

      if (currentOp.phase == AccountDeletionJournalPhase.localDatabaseCleared) {
        await _clearLocalAuthentication(isAccountDeletion: true);
        currentOp = currentOp.copyWith(
          phase: AccountDeletionJournalPhase.localProviderCleared,
        );
        await _accountDeletionRecoveryStore.write(currentOp);
      }

      // Terminal boundary: local cleanup is done, but the deletion receipt may
      // only be treated as acknowledged once the server returns a matching
      // acknowledgment for this exact identity. Until then the journal keeps
      // the capability and a restart retries exactly this step.
      if (currentOp.phase == AccountDeletionJournalPhase.localProviderCleared ||
          currentOp.phase ==
              AccountDeletionJournalPhase.acknowledgementPending) {
        try {
          await _acknowledgeAccountDeletion(currentOp);
        } on Object {
          await _accountDeletionRecoveryStore.write(
            currentOp.copyWith(
              phase: AccountDeletionJournalPhase.acknowledgementPending,
            ),
          );
          AppLogger.warning('auth_account_delete_acknowledgement_pending');
          throw SupabaseFailure(
            kind: SupabaseFailureKind.unknown,
            message:
                'The account was deleted, but the server has not yet '
                'confirmed final cleanup. Restart Owntend to finish.',
            retryable: true,
          );
        }
        currentOp = currentOp.copyWith(
          phase: AccountDeletionJournalPhase.acknowledged,
        );
        await _accountDeletionRecoveryStore.write(currentOp);
      }

      await _accountDeletionRecoveryStore.clear();
    } on Object catch (error) {
      if (error is SupabaseFailure && error.retryable) rethrow;
      AppLogger.warning(
        'auth_account_delete_cleanup_step_failed',
        error: error,
      );
      try {
        await _clearLocalAuthentication(isAccountDeletion: true);
      } on Object {
        // Ensure local auth is cleared even if local cleanup throws
      }
      throw const SupabaseFailure(
        kind: SupabaseFailureKind.unknown,
        message:
            'The account was deleted, but local cleanup is still pending. '
            'Restart Owntend to finish cleanup.',
        retryable: true,
      );
    }
  }

  /// Acknowledges terminal deletion and validates the server receipt.
  ///
  /// This is a durable protocol transition, not telemetry: any network error,
  /// non-success status, or response that does not carry an explicit
  /// `acknowledged` receipt for the exact expected identity throws so the
  /// caller persists [AccountDeletionJournalPhase.acknowledgementPending] and
  /// retries at startup. Recovery material is cleared only after strict
  /// success.
  Future<void> _acknowledgeAccountDeletion(
    AccountDeletionRecoveryOperation operation,
  ) async {
    Object? failure;
    try {
      final response = await _client.functions.invoke(
        'account-deletion-status',
        body: {
          'recovery_key': operation.recoveryKey,
          'expected_user_id': operation.expectedUserId,
          'action': 'acknowledge',
        },
      );
      final data = response.data;
      final acknowledged =
          data is Map &&
          data['deleted'] == true &&
          data['status'] == 'acknowledged' &&
          data['user_id'] == operation.expectedUserId;
      if (!acknowledged) {
        failure = const SupabaseFailure(
          kind: SupabaseFailureKind.unknown,
          message: 'ACKNOWLEDGEMENT_RECEIPT_INVALID',
          retryable: true,
        );
      }
    } on Object catch (error) {
      failure = error;
    }
    if (failure != null) {
      // Only a stable technical marker reaches logs; never raw payloads.
      AppLogger.warning('auth_account_delete_acknowledgement_failed');
      throw failure;
    }
  }

  Future<void> _cancelPreparedDeletion(String userId) async {
    try {
      await onAccountDeletionCancelled(userId);
    } on Object catch (error, stackTrace) {
      reportOperationFailure(
        operation: 'auth_account_delete_cancel_cleanup_failed',
        error: error,
        stackTrace: stackTrace,
        fields: const {'execution': 'main'},
      );
      // Preserve the original remote deletion failure for the caller.
    }
  }

  Future<void> _clearLocalAuthentication({
    bool isAccountDeletion = false,
  }) async {
    try {
      await _client.auth.signOut(scope: SignOutScope.local);
    } on Object {
      // GoTrue normally clears local state before any remote work.
    }
    try {
      if (isAccountDeletion) {
        try {
          await _googleSignIn.disconnect();
        } on Object {
          AppLogger.warning(
            'auth_google_disconnect_failed',
            fields: const {'provider': 'google', 'fallback': 'sign_out'},
          );
          await _googleSignIn.signOut();
        }
      } else {
        await _googleSignIn.signOut();
      }
    } on Object {
      // Supabase recovery must not depend on Google cleanup.
    }
    try {
      await clearSentryAccountScope(event: 'auth.signed_out');
    } on Object {
      // Observability must never prevent local authentication cleanup.
    }
  }

  Future<Never> _throwAuthFailure(Object error) async {
    if (_isRevokedSessionError(error)) {
      try {
        await _client.auth.signOut(scope: SignOutScope.local);
      } on Object {
        // GoTrue removes local session state before contacting the server.
      }
      try {
        await _googleSignIn.signOut();
      } on Object {
        // Supabase recovery must not depend on Google cleanup.
      }
      try {
        await clearSentryAccountScope(event: 'auth.signed_out');
      } on Object {
        // Observability must never block session recovery.
      }
    }
    throw SupabaseFailure.from(error);
  }

  Future<void> _recordAuthState(AuthStateChange state) async {
    final event = switch (state.event) {
      AuthEventType.initialSession => 'auth.initial_session',
      AuthEventType.signedIn => 'auth.signed_in',
      AuthEventType.signedOut => 'auth.signed_out',
      AuthEventType.tokenRefreshed => 'auth.token_refreshed',
      AuthEventType.userDeleted => 'auth.account_deleted',
      _ => 'auth.state_changed',
    };
    try {
      if (state.session == null ||
          state.event == AuthEventType.signedOut ||
          state.event == AuthEventType.userDeleted) {
        await clearSentryAccountScope(event: event);
      } else {
        await setSentryAuthenticated(authenticated: true, event: event);
      }
    } on Object {
      // Scope updates are best-effort and must not affect auth state delivery.
    }
  }
}

AuthEventType _eventFromSupabase(AuthChangeEvent event) {
  return switch (event.name) {
    'initialSession' => AuthEventType.initialSession,
    'signedIn' => AuthEventType.signedIn,
    'signedOut' => AuthEventType.signedOut,
    'tokenRefreshed' => AuthEventType.tokenRefreshed,
    'userUpdated' => AuthEventType.userUpdated,
    'userDeleted' => AuthEventType.userDeleted,
    'mfaChallengeVerified' => AuthEventType.mfaChallengeVerified,
    _ => AuthEventType.initialSession,
  };
}

AuthSession? _sessionFromSupabase(Session? session) {
  final user = session?.user;
  if (user == null) {
    return null;
  }
  final metadata = user.userMetadata;
  final providers = <String>{
    for (final identity in user.identities ?? const <UserIdentity>[])
      identity.provider,
  };
  final appProvider = user.appMetadata['provider'] as String?;
  if (appProvider != null) {
    providers.add(appProvider);
  }
  if (!providers.contains('google')) {
    return null;
  }
  final fullName = metadata?['full_name'] as String?;
  final name = metadata?['name'] as String?;
  return AuthSession(
    userId: user.id,
    email: user.email,
    fullName: fullName,
    name: name,
    avatarUrl:
        metadata?['avatar_url'] as String? ?? metadata?['picture'] as String?,
    providers: providers,
  );
}

bool _isRevokedSessionError(Object error) {
  final (String? code, String message) = switch (error) {
    AuthException value => (value.code, value.message),
    PostgrestException value => (value.code, value.message),
    _ => (null, ''),
  };
  final normalized = '${code ?? ''} $message'.toLowerCase();
  return normalized.contains('session_not_found') ||
      normalized.contains('session from session_id claim') ||
      normalized.contains('session id claim in jwt does not exist') ||
      normalized.contains('invalid refresh token') ||
      normalized.contains('refresh_token_not_found') ||
      normalized.contains('user not found') ||
      normalized.contains('user_not_found');
}

bool _isDeletionReceipt(Object? data, String expectedUserId) {
  return data is Map &&
      data['deleted'] == true &&
      (data['status'] == 'deleted' || data['status'] == 'acknowledged') &&
      data['user_id'] == expectedUserId;
}

bool _isSafePreDestructiveFailure(Object error) {
  return const {
    'deletion_origin_forbidden',
    'invalid_session',
    'deletion_confirmation_required',
    'recovery_key_required',
    'deletion_server_misconfigured',
    'deletion_reauthentication_claims_required',
    'recent_reauthentication_required',
    'reauthentication_required',
    'reauthentication_user_mismatch',
    'account_lookup_failed',
  }.contains(_functionErrorCode(error));
}

String? _functionErrorCode(Object? error) {
  if (error is! FunctionException) return null;
  final details = error.details;
  if (details is Map && details['error'] is String) {
    return details['error'] as String;
  }
  return null;
}

enum _AccountDeletionStatus {
  deleted,
  pending,
  notFound,
  temporarilyUnavailable,
}
