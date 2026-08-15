class AuthSession {
  const AuthSession({
    required this.userId,
    this.email,
    String? displayName,
    this.fullName,
    this.name,
    this.avatarUrl,
    this.providers = const <String>{},
  }) : displayName = displayName ?? fullName ?? name;

  final String userId;
  final String? email;
  final String? displayName;
  final String? fullName;
  final String? name;
  final String? avatarUrl;
  final Set<String> providers;

  bool get isGoogleUser => providers.contains('google');
}

enum AuthEventType {
  initialSession,
  signedIn,
  signedOut,
  tokenRefreshed,
  userUpdated,
  userDeleted,
  mfaChallengeVerified,
}

class AuthStateChange {
  const AuthStateChange({required this.event, required this.session});

  final AuthEventType event;
  final AuthSession? session;

  bool hasSameIdentityAndEvent(AuthStateChange other) {
    return event == other.event &&
        session?.userId == other.session?.userId &&
        session?.email == other.session?.email &&
        session?.displayName == other.session?.displayName &&
        session?.fullName == other.session?.fullName &&
        session?.name == other.session?.name &&
        session?.avatarUrl == other.session?.avatarUrl &&
        _sameProviders(session?.providers, other.session?.providers);
  }
}

bool _sameProviders(Set<String>? first, Set<String>? second) {
  if (identical(first, second)) return true;
  if (first == null || second == null || first.length != second.length) {
    return false;
  }
  return first.containsAll(second);
}

abstract interface class AuthRepository {
  AuthSession? get currentSession;
  Stream<AuthStateChange> watchAuthState();
  Future<void> signInWithGoogle();
  Future<void> signOut({bool allDevices = false});
  Future<void> deleteAccount();
}
