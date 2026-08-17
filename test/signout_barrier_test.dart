import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:owntend/src/core/database/app_database.dart';
import 'package:owntend/src/core/sync/account_safety_barrier.dart';
import 'package:owntend/src/core/sync/local_sync_store.dart';
import 'package:owntend/src/features/auth/data/account_safety_auth_repository.dart';
import 'package:owntend/src/features/auth/domain/auth_repository.dart';

void main() {
  late AppDatabase database;
  late LocalSyncStore store;

  setUp(() async {
    database = AppDatabase(executor: NativeDatabase.memory());
    store = LocalSyncStore(database);
    await database
        .into(database.areas)
        .insert(
          AreasCompanion.insert(
            id: 'private-area',
            name: 'Private area',
            kind: 'indoor',
          ),
        );
    await store.setEnabled(
      enabled: true,
      boundUserId: 'user-1',
      migrationState: 'active',
    );
  });

  tearDown(() => database.close());

  test('ordinary sign-out keeps local account data and binding intact', () async {
    final events = <String>[];
    final delegate = _FakeAuthRepository(events: events);
    final barrier = AccountSafetyBarrier(
      prepareAccountScope: (userId) async {
        events.add('prepare:$userId');
        expect((await store.account()).boundUserId, userId);
      },
      cancelBackgroundWork: () async {
        events.add('cancel-background');
      },
      releaseAccountScope: (userId) async {
        events.add('release:$userId');
      },
    );
    final repository = AccountSafetyAuthRepository(delegate, barrier: barrier);

    await repository.signOut();

    expect(
      events,
      <String>[
        'prepare:user-1',
        'cancel-background',
        'delegate-sign-out',
        'release:user-1',
      ],
    );
    expect(delegate.currentSession, isNull);
    final account = await store.account();
    expect(account.boundUserId, 'user-1');
    expect(account.enabled, isTrue);
    expect(account.migrationState, 'active');
    expect(
      await (database.select(
        database.areas,
      )..where((area) => area.id.equals('private-area'))).get(),
      hasLength(1),
    );
  });

  test('background cancellation failure prevents auth sign-out', () async {
    final events = <String>[];
    final delegate = _FakeAuthRepository(events: events);
    final barrier = AccountSafetyBarrier(
      prepareAccountScope: (userId) async {
        events.add('prepare:$userId');
      },
      cancelBackgroundWork: () async {
        events.add('cancel-background');
        throw StateError('scheduler unavailable');
      },
      releaseAccountScope: (userId) async {
        events.add('release:$userId');
      },
    );
    final repository = AccountSafetyAuthRepository(delegate, barrier: barrier);

    await expectLater(repository.signOut(), throwsStateError);

    expect(
      events,
      <String>[
        'prepare:user-1',
        'cancel-background',
        'release:user-1',
      ],
    );
    expect(delegate.signOutCalls, 0);
    expect(delegate.currentSession?.userId, 'user-1');
    expect((await store.account()).boundUserId, 'user-1');
    expect(
      await (database.select(
        database.areas,
      )..where((area) => area.id.equals('private-area'))).get(),
      hasLength(1),
    );
  });
}

class _FakeAuthRepository implements AuthRepository {
  _FakeAuthRepository({required this.events});

  final List<String> events;
  AuthSession? _session = const AuthSession(userId: 'user-1');
  int signOutCalls = 0;

  @override
  AuthSession? get currentSession => _session;

  @override
  Future<void> deleteAccount() async {}

  @override
  Future<void> signInWithGoogle() async {}

  @override
  Future<void> signOut({bool allDevices = false}) async {
    signOutCalls++;
    events.add('delegate-sign-out');
    _session = null;
  }

  @override
  Stream<AuthStateChange> watchAuthState() => const Stream.empty();
}
