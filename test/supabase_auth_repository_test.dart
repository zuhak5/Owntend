import 'package:flutter_test/flutter_test.dart';
import 'package:owntend/src/core/supabase/supabase_failure.dart';
import 'package:owntend/src/core/utils/redacting_logger.dart';
import 'package:owntend/src/features/auth/data/account_deletion_recovery_store.dart';
import 'package:owntend/src/features/auth/data/native_google_sign_in.dart';
import 'package:owntend/src/features/auth/data/supabase_auth_repository.dart';
import 'package:owntend/src/features/auth/domain/auth_repository.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _MockSupabaseClient extends Mock implements SupabaseClient {}

class _MockGoTrueClient extends Mock implements GoTrueClient {}

class _MockFunctionsClient extends Mock implements FunctionsClient {}

class _MockSession extends Mock implements Session {}

class _MockUser extends Mock implements User {}

class _MemoryAccountDeletionRecoveryStore
    implements AccountDeletionRecoveryStore {
  AccountDeletionRecoveryOperation? operation;

  @override
  Future<void> clear() async => operation = null;

  @override
  Future<AccountDeletionRecoveryOperation?> read() async => operation;

  @override
  Future<void> write(AccountDeletionRecoveryOperation value) async {
    operation = value;
  }
}

class _FakeGoogleSignInGateway implements GoogleSignInGateway {
  Object? signInError;
  Object? silentReauthenticationError;
  Object? signOutError;
  Object? disconnectError;
  GoogleSignInTokens? silentReauthenticationTokens;
  var signInCalls = 0;
  var silentReauthenticationCalls = 0;
  var signOutCalls = 0;
  var disconnectCalls = 0;

  @override
  Future<GoogleSignInTokens> signIn() async {
    signInCalls++;
    final error = signInError;
    if (error != null) {
      throw error;
    }
    return const GoogleSignInTokens(
      idToken: 'google-id-token',
      accessToken: 'google-access-token',
    );
  }

  @override
  Future<GoogleSignInTokens?> reauthenticateSilently() async {
    silentReauthenticationCalls++;
    final error = silentReauthenticationError;
    if (error != null) {
      throw error;
    }
    return silentReauthenticationTokens;
  }

  @override
  Future<void> signOut() async {
    signOutCalls++;
    final error = signOutError;
    if (error != null) throw error;
  }

  @override
  Future<void> disconnect() async {
    disconnectCalls++;
    final error = disconnectError;
    if (error != null) throw error;
  }
}

void main() {
  late _FakeGoogleSignInGateway googleSignIn;
  late _MemoryAccountDeletionRecoveryStore recoveryStore;
  const recoveryKey = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';

  setUpAll(() {
    registerFallbackValue(OAuthProvider.google);
  });

  setUp(() {
    AppLogger.clearForTesting();
    googleSignIn = _FakeGoogleSignInGateway();
    recoveryStore = _MemoryAccountDeletionRecoveryStore();
  });

  test('repository exposes no session for a fresh client', () {
    final client = SupabaseClient(
      'https://example.supabase.co',
      'sb_publishable_test',
    );
    final repository = SupabaseAuthRepository(
      client,
      googleSignIn,
      onAccountDeletionPrepared: (_) async {},
      onAccountDeletionCancelled: (_) async {},
      onAccountDeleted: (_) async {},
      accountDeletionRecoveryStore: recoveryStore,
      accountDeletionRecoveryKeyFactory: () => recoveryKey,
    );

    expect(repository.currentSession, isNull);
  });

  test('auth stream immediately replays the current session state', () async {
    final client = SupabaseClient(
      'https://example.supabase.co',
      'sb_publishable_test',
    );
    final repository = SupabaseAuthRepository(
      client,
      googleSignIn,
      onAccountDeletionPrepared: (_) async {},
      onAccountDeletionCancelled: (_) async {},
      onAccountDeleted: (_) async {},
      accountDeletionRecoveryStore: recoveryStore,
      accountDeletionRecoveryKeyFactory: () => recoveryKey,
    );

    final state = await repository.watchAuthState().first;

    expect(state.event, AuthEventType.initialSession);
    expect(state.session, isNull);
  });

  test('native Google tokens are exchanged for a Supabase session', () async {
    final client = _MockSupabaseClient();
    final auth = _MockGoTrueClient();
    when(() => client.auth).thenReturn(auth);
    when(
      () => auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: 'google-id-token',
        accessToken: 'google-access-token',
      ),
    ).thenAnswer((_) async => AuthResponse());
    final repository = SupabaseAuthRepository(
      client,
      googleSignIn,
      onAccountDeletionPrepared: (_) async {},
      onAccountDeletionCancelled: (_) async {},
      onAccountDeleted: (_) async {},
      accountDeletionRecoveryStore: recoveryStore,
      accountDeletionRecoveryKeyFactory: () => recoveryKey,
    );

    await repository.signInWithGoogle();

    verify(
      () => auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: 'google-id-token',
        accessToken: 'google-access-token',
      ),
    ).called(1);
  });

  test('normal sign out does not revoke Google authorization', () async {
    final client = _MockSupabaseClient();
    final auth = _MockGoTrueClient();
    when(() => client.auth).thenReturn(auth);
    when(() => auth.signOut(scope: SignOutScope.local))
        .thenAnswer((_) async {});
    final repository = SupabaseAuthRepository(
      client,
      googleSignIn,
      onAccountDeletionPrepared: (_) async {},
      onAccountDeletionCancelled: (_) async {},
      onAccountDeleted: (_) async {},
      accountDeletionRecoveryStore: recoveryStore,
      accountDeletionRecoveryKeyFactory: () => recoveryKey,
    );

    await repository.signOut();

    verify(() => auth.signOut(scope: SignOutScope.local)).called(1);
    expect(googleSignIn.signOutCalls, 1);
    expect(googleSignIn.disconnectCalls, 0);
  });

  test('revoked session is cleared without exposing the JWT error', () async {
    final client = _MockSupabaseClient();
    final auth = _MockGoTrueClient();
    when(() => client.auth).thenReturn(auth);
    when(
      () => auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: 'google-id-token',
        accessToken: 'google-access-token',
      ),
    ).thenThrow(
      const AuthException(
        'Session from session_id claim in JWT does not exist',
        code: 'session_not_found',
      ),
    );
    when(() => auth.signOut(scope: SignOutScope.local))
        .thenAnswer((_) async {});
    final repository = SupabaseAuthRepository(
      client,
      googleSignIn,
      onAccountDeletionPrepared: (_) async {},
      onAccountDeletionCancelled: (_) async {},
      onAccountDeleted: (_) async {},
      accountDeletionRecoveryStore: recoveryStore,
      accountDeletionRecoveryKeyFactory: () => recoveryKey,
    );

    await expectLater(
      repository.signInWithGoogle(),
      throwsA(
        isA<SupabaseFailure>()
            .having(
              (failure) => failure.kind,
              'kind',
              SupabaseFailureKind.authentication,
            )
            .having(
              (failure) => failure.message,
              'message',
              'This cloud session expired or was revoked. '
                  'Your local data is safe.',
            ),
      ),
    );

    verify(() => auth.signOut(scope: SignOutScope.local)).called(1);
    expect(googleSignIn.signOutCalls, 1);
    expect(googleSignIn.disconnectCalls, 0);
  });

  test('native picker cancellation remains a cancelled failure', () async {
    googleSignIn.signInError = const SupabaseFailure(
      kind: SupabaseFailureKind.cancelled,
      message: 'Google sign-in was cancelled.',
    );
    final client = _MockSupabaseClient();
    final repository = SupabaseAuthRepository(
      client,
      googleSignIn,
      onAccountDeletionPrepared: (_) async {},
      onAccountDeletionCancelled: (_) async {},
      onAccountDeleted: (_) async {},
      accountDeletionRecoveryStore: recoveryStore,
      accountDeletionRecoveryKeyFactory: () => recoveryKey,
    );

    await expectLater(
      repository.signInWithGoogle(),
      throwsA(
        isA<SupabaseFailure>().having(
          (failure) => failure.kind,
          'kind',
          SupabaseFailureKind.cancelled,
        ),
      ),
    );
  });

  test(
    'account deletion reauthenticates, invokes, cleans, and signs out',
    () async {
      final client = _MockSupabaseClient();
      final auth = _MockGoTrueClient();
      final functions = _MockFunctionsClient();
      final session = _MockSession();
      final user = _MockUser();
      when(() => client.auth).thenReturn(auth);
      when(() => client.functions).thenReturn(functions);
      when(() => auth.currentSession).thenReturn(session);
      when(() => session.user).thenReturn(user);
      when(() => user.id).thenReturn('user-1');
      when(
        () => auth.signInWithIdToken(
          provider: OAuthProvider.google,
          idToken: 'google-id-token',
          accessToken: 'google-access-token',
        ),
      ).thenAnswer((_) async => AuthResponse(session: session));
      when(
        () => functions.invoke(
          'delete-account',
          body: const {
            'confirmation': 'delete-my-account',
            'recovery_key': recoveryKey,
          },
        ),
      ).thenAnswer(
        (_) async => FunctionResponse(
          data: const {
            'deleted': true,
            'status': 'deleted',
            'user_id': 'user-1',
          },
          status: 200,
        ),
      );
      when(() => auth.signOut(scope: SignOutScope.local))
          .thenAnswer((_) async {});
      googleSignIn.silentReauthenticationTokens = const GoogleSignInTokens(
        idToken: 'google-id-token',
        accessToken: 'google-access-token',
      );
      String? preparedUserId;
      String? cancelledUserId;
      String? cleanedUserId;
      final repository = SupabaseAuthRepository(
        client,
        googleSignIn,
        onAccountDeletionPrepared: (userId) async => preparedUserId = userId,
        onAccountDeletionCancelled: (userId) async => cancelledUserId = userId,
        onAccountDeleted: (userId) async => cleanedUserId = userId,
        accountDeletionRecoveryStore: recoveryStore,
        accountDeletionRecoveryKeyFactory: () => recoveryKey,
      );

      await repository.deleteAccount();

      expect(googleSignIn.silentReauthenticationCalls, 1);
      expect(googleSignIn.signInCalls, 0);
      expect(preparedUserId, 'user-1');
      expect(cancelledUserId, isNull);
      expect(cleanedUserId, 'user-1');
      verify(
        () => functions.invoke(
          'delete-account',
          body: const {
            'confirmation': 'delete-my-account',
            'recovery_key': recoveryKey,
          },
        ),
      ).called(1);
      verify(() => auth.signOut(scope: SignOutScope.local)).called(1);
      expect(googleSignIn.signOutCalls, 0);
      expect(googleSignIn.disconnectCalls, 1);
    },
  );

  test(
    'account deletion falls back to Google sign out after disconnect fails',
    () async {
      final client = _MockSupabaseClient();
      final auth = _MockGoTrueClient();
      final functions = _MockFunctionsClient();
      final session = _MockSession();
      final user = _MockUser();
      when(() => client.auth).thenReturn(auth);
      when(() => client.functions).thenReturn(functions);
      when(() => auth.currentSession).thenReturn(session);
      when(() => session.user).thenReturn(user);
      when(() => user.id).thenReturn('user-1');
      when(
        () => auth.signInWithIdToken(
          provider: OAuthProvider.google,
          idToken: 'google-id-token',
          accessToken: 'google-access-token',
        ),
      ).thenAnswer((_) async => AuthResponse(session: session));
      when(
        () => functions.invoke(
          'delete-account',
          body: const {
            'confirmation': 'delete-my-account',
            'recovery_key': recoveryKey,
          },
        ),
      ).thenAnswer(
        (_) async => FunctionResponse(
          data: const {
            'deleted': true,
            'status': 'deleted',
            'user_id': 'user-1',
          },
          status: 200,
        ),
      );
      when(() => auth.signOut(scope: SignOutScope.local))
          .thenAnswer((_) async {});
      googleSignIn.disconnectError = StateError('provider details');
      final repository = SupabaseAuthRepository(
        client,
        googleSignIn,
        onAccountDeletionPrepared: (_) async {},
        onAccountDeletionCancelled: (_) async {},
        onAccountDeleted: (_) async {},
        accountDeletionRecoveryStore: recoveryStore,
        accountDeletionRecoveryKeyFactory: () => recoveryKey,
      );

      await repository.deleteAccount();

      expect(googleSignIn.disconnectCalls, 1);
      expect(googleSignIn.signOutCalls, 1);
      final disconnectEvents = AppLogger.snapshot().where(
        (event) => event.event == 'auth_google_disconnect_failed',
      );
      expect(disconnectEvents, hasLength(1));
      expect(disconnectEvents.single.error, isNull);
      expect(disconnectEvents.single.errorType, isNull);
      expect(disconnectEvents.single.fields, const {
        'provider': 'google',
        'fallback': 'sign_out',
      });
    },
  );

  test(
    'cloud deletion with failed local cleanup clears authentication once',
    () async {
      final client = _MockSupabaseClient();
      final auth = _MockGoTrueClient();
      final functions = _MockFunctionsClient();
      final session = _MockSession();
      final user = _MockUser();
      when(() => client.auth).thenReturn(auth);
      when(() => client.functions).thenReturn(functions);
      when(() => auth.currentSession).thenReturn(session);
      when(() => session.user).thenReturn(user);
      when(() => user.id).thenReturn('user-1');
      when(
        () => auth.signInWithIdToken(
          provider: OAuthProvider.google,
          idToken: 'google-id-token',
          accessToken: 'google-access-token',
        ),
      ).thenAnswer((_) async => AuthResponse(session: session));
      when(
        () => functions.invoke(
          'delete-account',
          body: const {
            'confirmation': 'delete-my-account',
            'recovery_key': recoveryKey,
          },
        ),
      ).thenAnswer(
        (_) async => FunctionResponse(
          data: const {
            'deleted': true,
            'status': 'deleted',
            'user_id': 'user-1',
          },
          status: 200,
        ),
      );
      when(() => auth.signOut(scope: SignOutScope.local))
          .thenAnswer((_) async {});
      final repository = SupabaseAuthRepository(
        client,
        googleSignIn,
        onAccountDeletionPrepared: (_) async {},
        onAccountDeletionCancelled: (_) async {},
        onAccountDeleted: (_) async => throw StateError('local cleanup failed'),
        accountDeletionRecoveryStore: recoveryStore,
        accountDeletionRecoveryKeyFactory: () => recoveryKey,
      );

      await expectLater(
        repository.deleteAccount(),
        throwsA(
          isA<SupabaseFailure>()
              .having((failure) => failure.retryable, 'retryable', isTrue)
              .having(
                (failure) => failure.message,
                'message',
                contains('local cleanup is still pending'),
              ),
        ),
      );

      verify(() => auth.signOut(scope: SignOutScope.local)).called(1);
      expect(googleSignIn.disconnectCalls, 1);
      expect(googleSignIn.signOutCalls, 0);
    },
  );

  test('account deletion rejects incomplete or mismatched receipts', () async {
    final invalidReceipts = <Map<String, Object?>>[
      {'deleted': true, 'status': 'deleted'},
      {'deleted': true, 'status': 'deleted', 'user_id': 'user-2'},
      {'deleted': true, 'status': 'already_deleted', 'user_id': 'user-1'},
      {'deleted': false, 'status': 'deleted', 'user_id': 'user-1'},
    ];

    for (final receipt in invalidReceipts) {
      final client = _MockSupabaseClient();
      final auth = _MockGoTrueClient();
      final functions = _MockFunctionsClient();
      final session = _MockSession();
      final user = _MockUser();
      final gateway = _FakeGoogleSignInGateway();
      when(() => client.auth).thenReturn(auth);
      when(() => client.functions).thenReturn(functions);
      when(() => auth.currentSession).thenReturn(session);
      when(() => session.user).thenReturn(user);
      when(() => user.id).thenReturn('user-1');
      when(
        () => auth.signInWithIdToken(
          provider: OAuthProvider.google,
          idToken: 'google-id-token',
          accessToken: 'google-access-token',
        ),
      ).thenAnswer((_) async => AuthResponse(session: session));
      when(
        () => functions.invoke(
          'delete-account',
          body: const {
            'confirmation': 'delete-my-account',
            'recovery_key': recoveryKey,
          },
        ),
      ).thenAnswer((_) async => FunctionResponse(data: receipt, status: 200));
      when(
        () => functions.invoke(
          'account-deletion-status',
          body: const {
            'recovery_key': recoveryKey,
            'expected_user_id': 'user-1',
          },
        ),
      ).thenThrow(
        FunctionException(
          status: 404,
          details: {'error': 'recovery_not_found'},
        ),
      );
      String? cancelledUserId;
      final repository = SupabaseAuthRepository(
        client,
        gateway,
        onAccountDeletionPrepared: (_) async {},
        onAccountDeletionCancelled: (userId) async {
          cancelledUserId = userId;
        },
        onAccountDeleted: (_) async {},
        accountDeletionRecoveryStore: recoveryStore,
        accountDeletionRecoveryKeyFactory: () => recoveryKey,
      );

      await expectLater(
        repository.deleteAccount(),
        throwsA(
          isA<SupabaseFailure>()
              .having(
                (failure) => failure.kind,
                'kind',
                SupabaseFailureKind.unknown,
              )
              .having(
                (failure) => failure.message,
                'message',
                'The cloud account deletion receipt was invalid.',
              ),
        ),
        reason: 'Receipt should be rejected: $receipt',
      );

      expect(cancelledUserId, isNull);
      verifyNever(() => auth.signOut(scope: SignOutScope.local));
      expect(gateway.disconnectCalls, 0);
      expect(gateway.signOutCalls, 0);
    }
  });

  test('account deletion rejects reauthentication as another user', () async {
    final client = _MockSupabaseClient();
    final auth = _MockGoTrueClient();
    final functions = _MockFunctionsClient();
    final originalSession = _MockSession();
    final originalUser = _MockUser();
    final otherSession = _MockSession();
    final otherUser = _MockUser();
    when(() => client.auth).thenReturn(auth);
    when(() => client.functions).thenReturn(functions);
    when(() => auth.currentSession).thenReturn(originalSession);
    when(() => originalSession.user).thenReturn(originalUser);
    when(() => originalUser.id).thenReturn('user-1');
    when(() => otherSession.user).thenReturn(otherUser);
    when(() => otherUser.id).thenReturn('user-2');
    when(
      () => auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: 'google-id-token',
        accessToken: 'google-access-token',
      ),
    ).thenAnswer((_) async => AuthResponse(session: otherSession));
    when(() => auth.signOut(scope: SignOutScope.local))
        .thenAnswer((_) async {});
    final repository = SupabaseAuthRepository(
      client,
      googleSignIn,
      onAccountDeletionPrepared: (_) async {},
      onAccountDeletionCancelled: (_) async {},
      onAccountDeleted: (_) async {},
      accountDeletionRecoveryStore: recoveryStore,
      accountDeletionRecoveryKeyFactory: () => recoveryKey,
    );

    await expectLater(
      repository.deleteAccount(),
      throwsA(
        isA<SupabaseFailure>().having(
          (failure) => failure.kind,
          'kind',
          SupabaseFailureKind.permissionDenied,
        ),
      ),
    );

    verifyNever(
      () => functions.invoke(
        'delete-account',
        body: const {
          'confirmation': 'delete-my-account',
          'recovery_key': recoveryKey,
        },
      ),
    );
    verify(() => auth.signOut(scope: SignOutScope.local)).called(1);
    expect(googleSignIn.signOutCalls, 1);
    expect(googleSignIn.disconnectCalls, 0);
  });

  test(
    'prepare failure rolls back an armed account-deletion barrier',
    () async {
      final client = _MockSupabaseClient();
      final auth = _MockGoTrueClient();
      final functions = _MockFunctionsClient();
      final session = _MockSession();
      final user = _MockUser();
      when(() => client.auth).thenReturn(auth);
      when(() => client.functions).thenReturn(functions);
      when(() => auth.currentSession).thenReturn(session);
      when(() => session.user).thenReturn(user);
      when(() => user.id).thenReturn('user-1');
      when(
        () => auth.signInWithIdToken(
          provider: OAuthProvider.google,
          idToken: 'google-id-token',
          accessToken: 'google-access-token',
        ),
      ).thenAnswer((_) async => AuthResponse(session: session));
      String? cancelledUserId;
      final repository = SupabaseAuthRepository(
        client,
        googleSignIn,
        onAccountDeletionPrepared: (_) async {
          throw StateError('later prepare stage failed');
        },
        onAccountDeletionCancelled: (userId) async {
          cancelledUserId = userId;
        },
        onAccountDeleted: (_) async {},
        accountDeletionRecoveryStore: recoveryStore,
        accountDeletionRecoveryKeyFactory: () => recoveryKey,
      );

      await expectLater(
        repository.deleteAccount(),
        throwsA(isA<SupabaseFailure>()),
      );

      expect(cancelledUserId, 'user-1');
      verifyNever(
        () => functions.invoke(
          'delete-account',
          body: const {
            'confirmation': 'delete-my-account',
            'recovery_key': recoveryKey,
          },
        ),
      );
    },
  );

  test(
    'storage cleanup failure keeps the recoverable deletion prepared',
    () async {
      final client = _MockSupabaseClient();
      final auth = _MockGoTrueClient();
      final functions = _MockFunctionsClient();
      final session = _MockSession();
      final user = _MockUser();
      when(() => client.auth).thenReturn(auth);
      when(() => client.functions).thenReturn(functions);
      when(() => auth.currentSession).thenReturn(session);
      when(() => session.user).thenReturn(user);
      when(() => user.id).thenReturn('user-1');
      when(
        () => auth.signInWithIdToken(
          provider: OAuthProvider.google,
          idToken: 'google-id-token',
          accessToken: 'google-access-token',
        ),
      ).thenAnswer((_) async => AuthResponse(session: session));
      when(
        () => functions.invoke(
          'delete-account',
          body: const {
            'confirmation': 'delete-my-account',
            'recovery_key': recoveryKey,
          },
        ),
      ).thenThrow(
        FunctionException(
          status: 503,
          details: {'error': 'storage_cleanup_failed'},
        ),
      );
      when(
        () => functions.invoke(
          'account-deletion-status',
          body: const {
            'recovery_key': recoveryKey,
            'expected_user_id': 'user-1',
          },
        ),
      ).thenAnswer(
        (_) async => FunctionResponse(
          data: const {'deleted': false, 'status': 'pending'},
          status: 202,
        ),
      );
      when(() => auth.signOut(scope: SignOutScope.local))
          .thenAnswer((_) async {});
      String? preparedUserId;
      String? cancelledUserId;
      String? cleanedUserId;
      final repository = SupabaseAuthRepository(
        client,
        googleSignIn,
        onAccountDeletionPrepared: (userId) async => preparedUserId = userId,
        onAccountDeletionCancelled: (userId) async => cancelledUserId = userId,
        onAccountDeleted: (userId) async => cleanedUserId = userId,
        accountDeletionRecoveryStore: recoveryStore,
        accountDeletionRecoveryKeyFactory: () => recoveryKey,
      );

      await expectLater(
        repository.deleteAccount(),
        throwsA(
          isA<SupabaseFailure>()
              .having(
                (failure) => failure.kind,
                'kind',
                SupabaseFailureKind.storage,
              )
              .having((failure) => failure.retryable, 'retryable', isTrue),
        ),
      );

      expect(preparedUserId, 'user-1');
      expect(cancelledUserId, isNull);
      expect(cleanedUserId, isNull);
      expect(recoveryStore.operation?.recoveryKey, recoveryKey);
      verifyNever(() => auth.signOut(scope: SignOutScope.local));
      expect(googleSignIn.signOutCalls, 0);
      expect(googleSignIn.disconnectCalls, 0);
    },
  );

  test(
    'transport loss is reconciled as deleted by authoritative status',
    () async {
      final client = _MockSupabaseClient();
      final auth = _MockGoTrueClient();
      final functions = _MockFunctionsClient();
      final session = _MockSession();
      final user = _MockUser();
      when(() => client.auth).thenReturn(auth);
      when(() => client.functions).thenReturn(functions);
      when(() => auth.currentSession).thenReturn(session);
      when(() => session.user).thenReturn(user);
      when(() => user.id).thenReturn('user-1');
      when(
        () => auth.signInWithIdToken(
          provider: OAuthProvider.google,
          idToken: 'google-id-token',
          accessToken: 'google-access-token',
        ),
      ).thenAnswer((_) async => AuthResponse(session: session));
      when(
        () => functions.invoke(
          'delete-account',
          body: const {
            'confirmation': 'delete-my-account',
            'recovery_key': recoveryKey,
          },
        ),
      ).thenThrow(StateError('response lost'));
      when(
        () => functions.invoke(
          'account-deletion-status',
          body: const {
            'recovery_key': recoveryKey,
            'expected_user_id': 'user-1',
          },
        ),
      ).thenAnswer(
        (_) async => FunctionResponse(
          data: const {
            'deleted': true,
            'status': 'deleted',
            'user_id': 'user-1',
          },
          status: 200,
        ),
      );
      when(() => auth.signOut(scope: SignOutScope.local))
          .thenAnswer((_) async {});
      String? cancelledUserId;
      String? cleanedUserId;
      final repository = SupabaseAuthRepository(
        client,
        googleSignIn,
        onAccountDeletionPrepared: (_) async {},
        onAccountDeletionCancelled: (userId) async => cancelledUserId = userId,
        onAccountDeleted: (userId) async => cleanedUserId = userId,
        accountDeletionRecoveryStore: recoveryStore,
        accountDeletionRecoveryKeyFactory: () => recoveryKey,
      );

      await repository.deleteAccount();

      expect(cancelledUserId, isNull);
      expect(cleanedUserId, 'user-1');
      expect(recoveryStore.operation, isNull);
      expect(googleSignIn.disconnectCalls, 1);
    },
  );

  test('pending status retains and reuses the same recovery key', () async {
    final client = _MockSupabaseClient();
    final auth = _MockGoTrueClient();
    final functions = _MockFunctionsClient();
    final session = _MockSession();
    final user = _MockUser();
    var deleteCalls = 0;
    when(() => client.auth).thenReturn(auth);
    when(() => client.functions).thenReturn(functions);
    when(() => auth.currentSession).thenReturn(session);
    when(() => session.user).thenReturn(user);
    when(() => user.id).thenReturn('user-1');
    when(
      () => auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: 'google-id-token',
        accessToken: 'google-access-token',
      ),
    ).thenAnswer((_) async => AuthResponse(session: session));
    when(
      () => functions.invoke(
        'delete-account',
        body: const {
          'confirmation': 'delete-my-account',
          'recovery_key': recoveryKey,
        },
      ),
    ).thenAnswer((_) async {
      deleteCalls++;
      if (deleteCalls == 1) throw StateError('response lost');
      return FunctionResponse(
        data: const {'deleted': true, 'status': 'deleted', 'user_id': 'user-1'},
        status: 200,
      );
    });
    when(
      () => functions.invoke(
        'account-deletion-status',
        body: const {'recovery_key': recoveryKey, 'expected_user_id': 'user-1'},
      ),
    ).thenAnswer(
      (_) async => FunctionResponse(
        data: const {'deleted': false, 'status': 'pending'},
        status: 202,
      ),
    );
    when(() => auth.signOut(scope: SignOutScope.local))
        .thenAnswer((_) async {});
    String? cancelledUserId;
    final repository = SupabaseAuthRepository(
      client,
      googleSignIn,
      onAccountDeletionPrepared: (_) async {},
      onAccountDeletionCancelled: (userId) async => cancelledUserId = userId,
      onAccountDeleted: (_) async {},
      accountDeletionRecoveryStore: recoveryStore,
      accountDeletionRecoveryKeyFactory: () => recoveryKey,
    );

    await expectLater(
      repository.deleteAccount(),
      throwsA(
        isA<SupabaseFailure>()
            .having((failure) => failure.retryable, 'retryable', isTrue)
            .having(
              (failure) => failure.message,
              'message',
              contains('still pending'),
            ),
      ),
    );
    expect(recoveryStore.operation?.recoveryKey, recoveryKey);
    expect(cancelledUserId, isNull);

    await repository.deleteAccount();

    expect(deleteCalls, 2);
    expect(recoveryStore.operation, isNull);
  });

  test(
    'temporarily unavailable status retains the logical operation',
    () async {
      final client = _MockSupabaseClient();
      final auth = _MockGoTrueClient();
      final functions = _MockFunctionsClient();
      final session = _MockSession();
      final user = _MockUser();
      when(() => client.auth).thenReturn(auth);
      when(() => client.functions).thenReturn(functions);
      when(() => auth.currentSession).thenReturn(session);
      when(() => session.user).thenReturn(user);
      when(() => user.id).thenReturn('user-1');
      when(
        () => auth.signInWithIdToken(
          provider: OAuthProvider.google,
          idToken: 'google-id-token',
          accessToken: 'google-access-token',
        ),
      ).thenAnswer((_) async => AuthResponse(session: session));
      when(
        () => functions.invoke(
          'delete-account',
          body: const {
            'confirmation': 'delete-my-account',
            'recovery_key': recoveryKey,
          },
        ),
      ).thenThrow(StateError('response lost'));
      when(
        () => functions.invoke(
          'account-deletion-status',
          body: const {
            'recovery_key': recoveryKey,
            'expected_user_id': 'user-1',
          },
        ),
      ).thenThrow(
        FunctionException(
          status: 503,
          details: {'error': 'recovery_temporarily_unavailable'},
        ),
      );
      String? cancelledUserId;
      final repository = SupabaseAuthRepository(
        client,
        googleSignIn,
        onAccountDeletionPrepared: (_) async {},
        onAccountDeletionCancelled: (userId) async => cancelledUserId = userId,
        onAccountDeleted: (_) async {},
        accountDeletionRecoveryStore: recoveryStore,
        accountDeletionRecoveryKeyFactory: () => recoveryKey,
      );

      await expectLater(
        repository.deleteAccount(),
        throwsA(
          isA<SupabaseFailure>()
              .having(
                (failure) => failure.kind,
                'kind',
                SupabaseFailureKind.offline,
              )
              .having((failure) => failure.retryable, 'retryable', isTrue),
        ),
      );

      expect(recoveryStore.operation?.recoveryKey, recoveryKey);
      expect(cancelledUserId, isNull);
    },
  );

  test(
    'restart recovery completes cleanup from a final status receipt',
    () async {
      final client = _MockSupabaseClient();
      final auth = _MockGoTrueClient();
      final functions = _MockFunctionsClient();
      recoveryStore.operation = const AccountDeletionRecoveryOperation(
        expectedUserId: 'user-1',
        recoveryKey: recoveryKey,
      );
      when(() => client.auth).thenReturn(auth);
      when(() => client.functions).thenReturn(functions);
      when(
        () => functions.invoke(
          'account-deletion-status',
          body: const {
            'recovery_key': recoveryKey,
            'expected_user_id': 'user-1',
          },
        ),
      ).thenAnswer(
        (_) async => FunctionResponse(
          data: const {
            'deleted': true,
            'status': 'deleted',
            'user_id': 'user-1',
          },
          status: 200,
        ),
      );
      when(() => auth.signOut(scope: SignOutScope.local))
          .thenAnswer((_) async {});
      String? preparedUserId;
      String? cleanedUserId;
      final repository = SupabaseAuthRepository(
        client,
        googleSignIn,
        onAccountDeletionPrepared: (userId) async => preparedUserId = userId,
        onAccountDeletionCancelled: (_) async {},
        onAccountDeleted: (userId) async => cleanedUserId = userId,
        accountDeletionRecoveryStore: recoveryStore,
        accountDeletionRecoveryKeyFactory: () => recoveryKey,
      );

      await repository.resumePendingAccountDeletion();

      expect(preparedUserId, 'user-1');
      expect(cleanedUserId, 'user-1');
      expect(recoveryStore.operation, isNull);
      expect(googleSignIn.signInCalls, 0);
      expect(googleSignIn.disconnectCalls, 1);
    },
  );

  test('recent reauthentication rejection is a safe cancellation', () async {
    final client = _MockSupabaseClient();
    final auth = _MockGoTrueClient();
    final functions = _MockFunctionsClient();
    final session = _MockSession();
    final user = _MockUser();
    when(() => client.auth).thenReturn(auth);
    when(() => client.functions).thenReturn(functions);
    when(() => auth.currentSession).thenReturn(session);
    when(() => session.user).thenReturn(user);
    when(() => user.id).thenReturn('user-1');
    when(
      () => auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: 'google-id-token',
        accessToken: 'google-access-token',
      ),
    ).thenAnswer((_) async => AuthResponse(session: session));
    when(
      () => functions.invoke(
        'delete-account',
        body: const {
          'confirmation': 'delete-my-account',
          'recovery_key': recoveryKey,
        },
      ),
    ).thenThrow(
      FunctionException(
        status: 401,
        details: {'error': 'recent_reauthentication_required'},
      ),
    );
    String? cancelledUserId;
    final repository = SupabaseAuthRepository(
      client,
      googleSignIn,
      onAccountDeletionPrepared: (_) async {},
      onAccountDeletionCancelled: (userId) async => cancelledUserId = userId,
      onAccountDeleted: (_) async {},
      accountDeletionRecoveryStore: recoveryStore,
      accountDeletionRecoveryKeyFactory: () => recoveryKey,
    );

    await expectLater(
      repository.deleteAccount(),
      throwsA(
        isA<SupabaseFailure>().having(
          (failure) => failure.kind,
          'kind',
          SupabaseFailureKind.authentication,
        ),
      ),
    );

    expect(cancelledUserId, 'user-1');
    expect(recoveryStore.operation, isNull);
    verifyNever(
      () =>
          functions.invoke('account-deletion-status', body: any(named: 'body')),
    );
  });
}
