import 'dart:async';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:owntend/src/core/data/repositories.dart';
import 'package:owntend/src/core/database/app_database.dart';
import 'package:owntend/src/core/domain/models.dart';
import 'package:owntend/src/core/sync/local_sync_store.dart';
import 'package:owntend/src/core/sync/supabase_sync_gateway.dart';
import 'package:owntend/src/core/sync/sync_coordinator.dart';
import 'package:owntend/src/features/auth/domain/auth_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _url = String.fromEnvironment('OWNTEND_TEST_SUPABASE_URL');
const _anonKey = String.fromEnvironment('OWNTEND_TEST_SUPABASE_ANON_KEY');
const _serviceRoleKey = String.fromEnvironment(
  'OWNTEND_TEST_SUPABASE_SERVICE_ROLE_KEY',
);

class _StaticAuthRepository implements AuthRepository {
  _StaticAuthRepository(String userId)
    : _session = AuthSession(userId: userId, providers: const {'google'});

  final AuthSession _session;

  @override
  AuthSession get currentSession => _session;

  @override
  Stream<AuthStateChange> watchAuthState() => Stream.value(
    AuthStateChange(event: AuthEventType.initialSession, session: _session),
  );

  @override
  Future<void> deleteAccount() => throw UnsupportedError('not used');

  @override
  Future<void> signInWithGoogle() => throw UnsupportedError('not used');

  @override
  Future<void> signOut({bool allDevices = false}) =>
      throw UnsupportedError('not used');
}

Future<SupabaseClient> _signedInClient(String email, String password) async {
  final client = SupabaseClient(_url, _anonKey);
  await client.auth.signInWithPassword(email: email, password: password);
  return client;
}

void main() {
  if (_url.isEmpty || _anonKey.isEmpty || _serviceRoleKey.isEmpty) {
    test(
      'local backend integration configuration is supplied by its explicit gate',
      () {},
      skip:
          'Run the local-backend CI command with disposable Supabase defines.',
    );
    return;
  }

  late SupabaseClient admin;
  late SupabaseClient userADevice1;
  late SupabaseClient userADevice2;
  late SupabaseClient userB;
  late String userAId;
  late String userBId;

  const password = 'Owntend-local-backend-1!';
  final nonce = DateTime.now().microsecondsSinceEpoch;
  final userAEmail = 'owntend-a-$nonce@example.invalid';
  final userBEmail = 'owntend-b-$nonce@example.invalid';

  setUpAll(() async {
    final uri = Uri.parse(_url);
    if (!const {'127.0.0.1', 'localhost', '::1'}.contains(uri.host)) {
      fail('The integration suite refuses to use a non-loopback backend.');
    }

    admin = SupabaseClient(_url, _serviceRoleKey);
    final createdA = await admin.auth.admin.createUser(
      AdminUserAttributes(
        email: userAEmail,
        password: password,
        emailConfirm: true,
      ),
    );
    final createdB = await admin.auth.admin.createUser(
      AdminUserAttributes(
        email: userBEmail,
        password: password,
        emailConfirm: true,
      ),
    );
    userAId = createdA.user!.id;
    userBId = createdB.user!.id;
    userADevice1 = await _signedInClient(userAEmail, password);
    userADevice2 = await _signedInClient(userAEmail, password);
    userB = await _signedInClient(userBEmail, password);
  });

  tearDownAll(() async {
    await userADevice1.dispose();
    await userADevice2.dispose();
    await userB.dispose();
    await admin.auth.admin.deleteUser(userAId);
    await admin.auth.admin.deleteUser(userBId);
    await admin.dispose();
  });

  test(
    'RLS isolates two users and the owner feed carries canonical payloads',
    () async {
      await userADevice1.from('areas').insert({
        'user_id': userAId,
        'id': 'backend-area',
        'name': 'Backend Area',
        'kind': 'indoor',
        'sort_order': 0,
      });

      final ownerRows = await userADevice2
          .from('areas')
          .select('id,name')
          .eq('id', 'backend-area');
      expect(ownerRows, hasLength(1));
      final otherRows = await userB
          .from('areas')
          .select('id')
          .eq('id', 'backend-area');
      expect(otherRows, isEmpty);
      await expectLater(
        userB.from('areas').insert({
          'user_id': userAId,
          'id': 'cross-user-area',
          'name': 'Forbidden Area',
          'kind': 'indoor',
          'sort_order': 0,
        }),
        throwsA(isA<PostgrestException>()),
      );

      final feed = Map<String, dynamic>.from(
        await userADevice2.rpc<Map<String, dynamic>>(
          'fetch_user_change_feed',
          params: {'p_since_seq': 0, 'p_limit': 100},
        ) as Map,
      );
      expect(feed['contract_version'], 1);
      final changes = List<Map<String, dynamic>>.from(
        (feed['changes'] as List).map(
          (item) => Map<String, dynamic>.from(item as Map),
        ),
      );
      expect(
        changes,
        contains(
          isA<Map<String, dynamic>>()
              .having((entry) => entry['entity_type'], 'entity', 'area')
              .having(
                (entry) => (entry['payload'] as Map?)?['name'],
                'payload name',
                'Backend Area',
              ),
        ),
      );
    },
  );

  test(
    'two application stores converge through snapshot, outbox, and feed',
    () async {
      final database1 = AppDatabase(executor: NativeDatabase.memory());
      final database2 = AppDatabase(executor: NativeDatabase.memory());
      final store1 = LocalSyncStore(database1);
      final store2 = LocalSyncStore(database2);
      final auth = _StaticAuthRepository(userAId);
      final coordinator1 = SyncCoordinator(
        auth,
        store1,
        SupabaseSyncGateway(userADevice1),
        listenToAuthChanges: false,
      );
      final coordinator2 = SyncCoordinator(
        auth,
        store2,
        SupabaseSyncGateway(userADevice2),
        listenToAuthChanges: false,
      );
      addTearDown(() async {
        await coordinator1.dispose();
        await coordinator2.dispose();
        await database1.close();
        await database2.close();
      });

      await coordinator1.enable();
      await coordinator2.enable();
      expect(
        (await DriftAssetRepository(
          database2,
        ).listAreas()).map((area) => area.name),
        contains('Backend Area'),
      );

      await DriftAssetRepository(database1).saveArea(
        id: 'device-one-area',
        name: 'Device One',
        kind: AreaKind.indoor,
      );
      expect(await store1.pendingCount(), greaterThan(0));
      await coordinator1.syncNow();
      expect(await store1.pendingCount(), 0);

      await coordinator2.syncIncremental();
      final device2Areas = await DriftAssetRepository(database2).listAreas();
      expect(
        device2Areas,
        contains(
          isA<Area>()
              .having((area) => area.id, 'id', 'device-one-area')
              .having((area) => area.name, 'name', 'Device One'),
        ),
      );
    },
  );

  test(
    'prepare-upload-finalize verifies Storage facts and owner isolation',
    () async {
      await userADevice1.from('rooms').insert({
        'user_id': userAId,
        'id': 'backend-room',
        'area_id': 'backend-area',
        'name': 'Backend Room',
        'sort_order': 0,
      });
      await userADevice1.from('assets').insert({
        'user_id': userAId,
        'id': 'backend-asset',
        'room_id': 'backend-room',
        'name': 'Backend Asset',
        'asset_type': 'general',
      });

      const digest =
          '9f64a747e1b97f131fabb6b447296c9b6f0201e79fb3c5356e6c77e89b6a806a';
      final prepared = Map<String, dynamic>.from(
        await userADevice1.rpc<Map<String, dynamic>>(
          'prepare_asset_photo_upload',
          params: {
            'p_asset_id': 'backend-asset',
            'p_photo_id': 'backend-photo',
            'p_object_size': 4,
            'p_mime_type': 'image/jpeg',
            'p_client_sha256_digest': digest,
            'p_idempotency_key': 'local-backend-media-0001',
          },
        ) as Map,
      );
      final stagingPath = prepared['staging_path'] as String;
      final stagingId = prepared['staging_id'] as String;
      final bytes = Uint8List.fromList(const [0xff, 0xd8, 0xff, 0xd9]);
      await userADevice1.storage
          .from('user-media')
          .uploadBinary(
            stagingPath,
            bytes,
            fileOptions: const FileOptions(
              contentType: 'image/jpeg',
              upsert: false,
            ),
          );

      final finalized = Map<String, dynamic>.from(
        await userADevice1.rpc<Map<String, dynamic>>(
          'finalize_asset_photo_upload',
          params: {
            'p_staging_id': stagingId,
            'p_asset_id': 'backend-asset',
            'p_photo_id': 'backend-photo',
            'p_expected_revision': 1,
          },
        ) as Map,
      );
      expect(finalized['digest_verification'], 'client_advisory');
      expect(
        await userADevice2.storage.from('user-media').download(stagingPath),
        bytes,
      );
      await expectLater(
        userB.storage.from('user-media').download(stagingPath),
        throwsA(isA<StorageException>()),
      );
      await expectLater(
        userB.rpc<void>(
          'prepare_asset_photo_upload',
          params: {
            'p_asset_id': 'backend-asset',
            'p_photo_id': 'cross-user-photo',
            'p_object_size': 4,
            'p_mime_type': 'image/jpeg',
            'p_client_sha256_digest': digest,
            'p_idempotency_key': 'cross-user-media-0001',
          },
        ),
        throwsA(isA<PostgrestException>()),
      );
    },
  );
}
