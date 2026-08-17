import 'package:flutter_test/flutter_test.dart';
import 'package:owntend/src/core/sync/account_safety_barrier.dart';
import 'package:owntend/src/features/auth/data/account_safety_auth_repository.dart';
import 'package:owntend/src/features/auth/domain/auth_repository.dart';

void main() {
  test('scope preparation failure prevents delegate sign-out', () async {
    final events = <String>[];
    final delegate = _RecordingAuthRepository(events);
    final repository = AccountSafetyAuthRepository(
      delegate,
      barrier: AccountSafetyBarrier(
        prepareAccountScope: (userId) async {
          events.add('prepare:$userId');
          throw StateError('realtime teardown failed');
        },
        cancelBackgroundWork: () async {
          events.add('cancel-background');
        },
        releaseAccountScope: (userId) async {
          events.add('release:$userId');
        },
      ),
    );

    await expectLater(repository.signOut(), throwsStateError);

    expect(delegate.signOutCalls, 0);
    expect(delegate.currentSession?.userId, 'user-1');
    expect(events, <String>['prepare:user-1', 'release:user-1']);
  });

  test('account identity change during the barrier fails closed', () async {
    final events = <String>[];
    final delegate = _RecordingAuthRepository(events);
    final repository = AccountSafetyAuthRepository(
      delegate,
      barrier: AccountSafetyBarrier(
        prepareAccountScope: (userId) async {
          events.add('prepare:$userId');
          delegate.session = const AuthSession(userId: 'user-2');
        },
        cancelBackgroundWork: () async {
          events.add('cancel-background');
        },
        releaseAccountScope: (userId) async {
          events.add('release:$userId');
        },
      ),
    );

    await expectLater(repository.signOut(), throwsStateError);

    expect(delegate.signOutCalls, 0);
    expect(delegate.currentSession?.userId, 'user-2');
    expect(
      events,
      <String>[
        'prepare:user-1',
        'cancel-background',
        'release:user-1',
      ],
    );
  });

  test(
    'successful barrier runs before delegate sign-out and forwards scope',
    () async {
      final events = <String>[];
      final delegate = _RecordingAuthRepository(events);
      final repository = AccountSafetyAuthRepository(
        delegate,
        barrier: AccountSafetyBarrier(
          prepareAccountScope: (userId) async {
            events.add('prepare:$userId');
          },
          cancelBackgroundWork: () async {
            events.add('cancel-background');
          },
          releaseAccountScope: (userId) async {
            events.add('release:$userId');
          },
        ),
      );

      await repository.signOut(allDevices: true);

      expect(delegate.signOutCalls, 1);
      expect(delegate.lastAllDevices, isTrue);
      expect(delegate.currentSession, isNull);
      expect(
        events,
        <String>[
          'prepare:user-1',
          'cancel-background',
          'delegate-sign-out',
          'release:user-1',
        ],
      );
    },
  );

  test(
    'barrier release failure does not turn a completed sign-out into failure',
    () async {
      final events = <String>[];
      final delegate = _RecordingAuthRepository(events);
      final repository = AccountSafetyAuthRepository(
        delegate,
        barrier: AccountSafetyBarrier(
          prepareAccountScope: (userId) async {
            events.add('prepare:$userId');
          },
          cancelBackgroundWork: () async {
            events.add('cancel-background');
          },
          releaseAccountScope: (userId) async {
            events.add('release:$userId');
            throw StateError('resume failed');
          },
        ),
      );

      await repository.signOut();

      expect(delegate.signOutCalls, 1);
      expect(delegate.currentSession, isNull);
    },
  );
}

class _RecordingAuthRepository implements AuthRepository {
  _RecordingAuthRepository(this.events);

  final List<String> events;
  AuthSession? session = const AuthSession(userId: 'user-1');
  int signOutCalls = 0;
  bool? lastAllDevices;

  @override
  AuthSession? get currentSession => session;

  @override
  Future<void> deleteAccount() async {}

  @override
  Future<void> signInWithGoogle() async {}

  @override
  Future<void> signOut({bool allDevices = false}) async {
    signOutCalls++;
    lastAllDevices = allDevices;
    events.add('delegate-sign-out');
    session = null;
  }

  @override
  Stream<AuthStateChange> watchAuthState() => const Stream.empty();
}
