import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:owntend/src/features/auth/domain/auth_repository.dart';
import 'package:owntend/src/features/auth/presentation/auth_providers.dart';

void main() {
  test('auth state provider exposes repository stream failures', () async {
    final container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(
          const _FailingAuthRepository(),
        ),
      ],
    );
    addTearDown(container.dispose);

    final errorState = Completer<AsyncValue<AuthStateChange>>();
    final subscription = container.listen(authStateProvider, (previous, next) {
      if (next.hasError && !errorState.isCompleted) errorState.complete(next);
    }, fireImmediately: true);
    addTearDown(subscription.close);

    final state = await errorState.future.timeout(const Duration(seconds: 2));
    expect(state.hasError, isTrue);
    expect(state.error, isA<StateError>());
  });
}

class _FailingAuthRepository implements AuthRepository {
  const _FailingAuthRepository();

  @override
  AuthSession? get currentSession =>
      const AuthSession(userId: 'cached-user', providers: {'google'});

  @override
  Stream<AuthStateChange> watchAuthState() =>
      Stream<AuthStateChange>.error(StateError('auth stream unavailable'));

  @override
  Future<void> deleteAccount() async {}

  @override
  Future<void> signInWithGoogle() async {}

  @override
  Future<void> signOut({bool allDevices = false}) async {}
}
