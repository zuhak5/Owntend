import '../../../core/sync/account_safety_barrier.dart';
import '../../../core/utils/redacting_logger.dart';
import '../domain/auth_repository.dart';

class AccountSafetyAuthRepository implements AuthRepository {
  AccountSafetyAuthRepository(
    this._delegate, {
    required AccountSafetyBarrier barrier,
  }) : _barrier = barrier;

  final AuthRepository _delegate;
  final AccountSafetyBarrier _barrier;

  @override
  AuthSession? get currentSession => _delegate.currentSession;

  @override
  Stream<AuthStateChange> watchAuthState() => _delegate.watchAuthState();

  @override
  Future<void> signInWithGoogle() => _delegate.signInWithGoogle();

  @override
  Future<void> signOut({bool allDevices = false}) async {
    final session = _delegate.currentSession;
    if (session == null) {
      await _delegate.signOut(allDevices: allDevices);
      return;
    }

    final expectedUserId = session.userId;
    var barrierAttempted = false;
    try {
      barrierAttempted = true;
      await _barrier.prepareForSignOut(expectedUserId);
      if (_delegate.currentSession?.userId != expectedUserId) {
        throw StateError(
          'The authenticated account changed while preparing sign-out.',
        );
      }
      await _delegate.signOut(allDevices: allDevices);
    } finally {
      if (barrierAttempted) {
        try {
          await _barrier.releaseAfterSignOut(expectedUserId);
        } on Object catch (error, stackTrace) {
          AppLogger.warning(
            'auth_sign_out_barrier_release_failed',
            error: error,
            stackTrace: stackTrace,
          );
        }
      }
    }
  }

  @override
  Future<void> deleteAccount() => _delegate.deleteAccount();
}
