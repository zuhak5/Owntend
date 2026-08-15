import 'package:google_sign_in/google_sign_in.dart';

import '../../../core/supabase/supabase_failure.dart';

class GoogleSignInTokens {
  const GoogleSignInTokens({required this.idToken, required this.accessToken});

  final String idToken;
  final String accessToken;
}

abstract interface class GoogleSignInGateway {
  Future<GoogleSignInTokens> signIn();
  Future<GoogleSignInTokens?> reauthenticateSilently();
  Future<void> signOut();
  Future<void> disconnect();
}

class NativeGoogleSignInGateway implements GoogleSignInGateway {
  // Supabase's native Google token exchange currently requires an access
  // token in addition to the ID token. Request only the identity scopes needed
  // for that exchange; broader Google API scopes do not belong here.
  static const _authorizationScopes = <String>['email', 'profile'];

  NativeGoogleSignInGateway({
    required this.serverClientId,
    GoogleSignIn? googleSignIn,
  }) : _googleSignIn = googleSignIn ?? GoogleSignIn.instance;

  final String serverClientId;
  final GoogleSignIn _googleSignIn;
  Future<void>? _initialization;

  Future<void> _initialize() async {
    final existing = _initialization;
    if (existing != null) {
      await existing;
      return;
    }
    final init = _googleSignIn.initialize(serverClientId: serverClientId);
    _initialization = init;
    try {
      await init;
    } catch (_) {
      if (identical(_initialization, init)) {
        _initialization = null;
      }
      rethrow;
    }
  }

  @override
  Future<GoogleSignInTokens> signIn() async {
    try {
      await _initialize();
      final account = await _googleSignIn.authenticate();
      return await _tokensFor(account);
    } on GoogleSignInException catch (error) {
      throw _mapGoogleException(error);
    }
  }

  @override
  Future<GoogleSignInTokens?> reauthenticateSilently() async {
    try {
      await _initialize();
      final attempt = _googleSignIn.attemptLightweightAuthentication();
      if (attempt == null) return null;
      final account = await attempt;
      return account == null ? null : await _tokensFor(account);
    } on GoogleSignInException catch (error) {
      throw _mapGoogleException(error);
    }
  }

  Future<GoogleSignInTokens> _tokensFor(GoogleSignInAccount account) async {
    final idToken = account.authentication.idToken;
    final authorizationClient = account.authorizationClient;
    final authorization =
        await authorizationClient.authorizationForScopes(
          _authorizationScopes,
        ) ??
        await authorizationClient.authorizeScopes(_authorizationScopes);
    if (idToken == null) {
      throw const SupabaseFailure(
        kind: SupabaseFailureKind.authentication,
        message: 'Google did not return the ID token required to sign in.',
      );
    }
    return GoogleSignInTokens(
      idToken: idToken,
      accessToken: authorization.accessToken,
    );
  }

  SupabaseFailure _mapGoogleException(GoogleSignInException error) =>
      switch (error.code) {
        GoogleSignInExceptionCode.canceled ||
        GoogleSignInExceptionCode.interrupted => const SupabaseFailure(
          kind: SupabaseFailureKind.cancelled,
          message: 'Google sign-in was cancelled.',
        ),
        GoogleSignInExceptionCode.clientConfigurationError ||
        GoogleSignInExceptionCode.providerConfigurationError =>
          const SupabaseFailure(
            kind: SupabaseFailureKind.configuration,
            message: 'Google sign-in is not configured for this app build.',
          ),
        _ => const SupabaseFailure(
          kind: SupabaseFailureKind.authentication,
          message: 'Google sign-in failed.',
        ),
      };

  @override
  Future<void> signOut() async {
    await _initialize();
    await _googleSignIn.signOut();
  }

  @override
  Future<void> disconnect() async {
    await _initialize();
    await _googleSignIn.disconnect();
  }
}
