import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:owntend/src/features/auth/data/native_google_sign_in.dart';
import 'package:mocktail/mocktail.dart';

class _MockGoogleSignIn extends Mock implements GoogleSignIn {}

class _MockGoogleSignInAccount extends Mock implements GoogleSignInAccount {}

class _MockGoogleSignInAuthorizationClient extends Mock
    implements GoogleSignInAuthorizationClient {}

void main() {
  const serverClientId = '123-example.apps.googleusercontent.com';
  late _MockGoogleSignIn googleSignIn;
  late NativeGoogleSignInGateway gateway;

  setUpAll(() {
    registerFallbackValue(<String>[]);
  });

  setUp(() {
    googleSignIn = _MockGoogleSignIn();
    gateway = NativeGoogleSignInGateway(
      serverClientId: serverClientId,
      googleSignIn: googleSignIn,
    );
  });

  test('successful initialization is shared and retained', () async {
    final initialization = Completer<void>();
    when(() => googleSignIn.initialize(serverClientId: serverClientId))
        .thenAnswer((_) => initialization.future);
    when(() => googleSignIn.signOut()).thenAnswer((_) async {});
    when(() => googleSignIn.disconnect()).thenAnswer((_) async {});

    final signOut = gateway.signOut();
    final disconnect = gateway.disconnect();
    verify(() => googleSignIn.initialize(serverClientId: serverClientId))
        .called(1);

    initialization.complete();
    await Future.wait([signOut, disconnect]);
    await gateway.signOut();

    verifyNever(() => googleSignIn.initialize(serverClientId: serverClientId));
    verify(() => googleSignIn.signOut()).called(2);
    verify(() => googleSignIn.disconnect()).called(1);
  });

  test(
    'concurrent callers share a failed attempt and only a later action retries',
    () async {
      final firstInitialization = Completer<void>();
      var initializationCalls = 0;
      when(() => googleSignIn.initialize(serverClientId: serverClientId))
          .thenAnswer((_) {
            initializationCalls++;
            return initializationCalls == 1
                ? firstInitialization.future
                : Future<void>.value();
          });
      when(() => googleSignIn.signOut()).thenAnswer((_) async {});

      final first = gateway.signOut();
      final second = gateway.signOut();
      final firstExpectation = expectLater(first, throwsA(isA<StateError>()));
      final secondExpectation = expectLater(second, throwsA(isA<StateError>()));

      firstInitialization.completeError(StateError('temporary init failure'));
      await Future.wait([firstExpectation, secondExpectation]);

      expect(initializationCalls, 1);
      verifyNever(() => googleSignIn.signOut());

      await gateway.signOut();

      expect(initializationCalls, 2);
      verify(() => googleSignIn.signOut()).called(1);
    },
  );

  test('sign-in requests only the approved identity scopes in order', () async {
    final account = _MockGoogleSignInAccount();
    final authorizationClient = _MockGoogleSignInAuthorizationClient();
    final authorizationCalls = <String>[];
    final requestedScopes = <List<String>>[];
    when(() => googleSignIn.initialize(serverClientId: serverClientId))
        .thenAnswer((_) async {});
    when(() => googleSignIn.authenticate()).thenAnswer((_) async => account);
    when(() => account.email).thenReturn('user@example.com');
    when(() => account.authentication)
        .thenReturn(const GoogleSignInAuthentication(idToken: 'id-token'));
    when(() => account.authorizationClient).thenReturn(authorizationClient);
    when(() => authorizationClient.authorizationForScopes(any()))
        .thenAnswer((invocation) async {
          authorizationCalls.add('existing');
          requestedScopes.add(
            List<String>.from(invocation.positionalArguments.single as List),
          );
          return null;
        });
    when(() => authorizationClient.authorizeScopes(any())).thenAnswer((
      invocation,
    ) async {
      authorizationCalls.add('interactive');
      requestedScopes.add(
        List<String>.from(invocation.positionalArguments.single as List),
      );
      return const GoogleSignInClientAuthorization(accessToken: 'access-token');
    });

    final tokens = await gateway.signIn();

    expect(tokens.idToken, 'id-token');
    expect(tokens.accessToken, 'access-token');
    expect(tokens.email, 'user@example.com');
    expect(authorizationCalls, ['existing', 'interactive']);
    expect(requestedScopes, [
      ['email', 'profile'],
      ['email', 'profile'],
    ]);
  });

  test(
    'lightweight reauthentication reuses the existing Google account',
    () async {
      final account = _MockGoogleSignInAccount();
      final authorizationClient = _MockGoogleSignInAuthorizationClient();
      when(() => googleSignIn.initialize(serverClientId: serverClientId))
          .thenAnswer((_) async {});
      when(() => googleSignIn.attemptLightweightAuthentication())
          .thenAnswer((_) => Future.value(account));
      when(() => account.email).thenReturn('silent@example.com');
      when(() => account.authentication).thenReturn(
        const GoogleSignInAuthentication(idToken: 'silent-id-token'),
      );
      when(() => account.authorizationClient).thenReturn(authorizationClient);
      when(() => authorizationClient.authorizationForScopes(any())).thenAnswer(
        (_) async => const GoogleSignInClientAuthorization(
          accessToken: 'silent-access-token',
        ),
      );

      final tokens = await gateway.reauthenticateSilently();

      expect(tokens?.idToken, 'silent-id-token');
      expect(tokens?.accessToken, 'silent-access-token');
      expect(tokens?.email, 'silent@example.com');
      verify(() => googleSignIn.attemptLightweightAuthentication()).called(1);
      verifyNever(() => googleSignIn.authenticate());
      verifyNever(() => authorizationClient.authorizeScopes(any()));
    },
  );

  test(
    'lightweight reauthentication reports unavailable without a chooser',
    () async {
      when(() => googleSignIn.initialize(serverClientId: serverClientId))
          .thenAnswer((_) async {});
      when(() => googleSignIn.attemptLightweightAuthentication())
          .thenReturn(null);

      expect(await gateway.reauthenticateSilently(), isNull);

      verifyNever(() => googleSignIn.authenticate());
    },
  );
}
