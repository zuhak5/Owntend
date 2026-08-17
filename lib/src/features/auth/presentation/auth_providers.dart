import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/app_config.dart';
import '../../../core/database/app_database.dart';
import '../../../core/sync/account_safety_barrier.dart';
import '../../../core/sync/background_sync_scheduler.dart';
import '../data/account_safety_auth_repository.dart';
import '../data/native_google_sign_in.dart';
import '../data/supabase_auth_repository.dart';
import '../domain/auth_repository.dart';

typedef AccountDeletionLocalCleanup = Future<void> Function(String userId);
typedef AccountDeletionLifecycleHook = Future<void> Function(String userId);
typedef AccountScopedBackgroundCancellation = Future<void> Function();

final appConfigProvider = Provider<AppConfig>((ref) => AppConfig.test());

final supabaseClientProvider = Provider<SupabaseClient?>((ref) => null);

final accountDeletionLocalCleanupProvider =
    Provider<AccountDeletionLocalCleanup>((ref) => (_) async {});

final accountDeletionPrepareProvider = Provider<AccountDeletionLifecycleHook>(
  (ref) => (_) async {},
);

final accountDeletionCancelProvider = Provider<AccountDeletionLifecycleHook>(
  (ref) => (_) async {},
);

final accountScopedBackgroundCancellationProvider =
    Provider<AccountScopedBackgroundCancellation>(
      (ref) => cancelAccountScopedBackgroundWork,
    );

final accountSafetyBarrierProvider = Provider<AccountSafetyBarrier>((ref) {
  return AccountSafetyBarrier(
    prepareAccountScope: ref.watch(accountDeletionPrepareProvider),
    cancelBackgroundWork: ref.watch(
      accountScopedBackgroundCancellationProvider,
    ),
    releaseAccountScope: ref.watch(accountDeletionCancelProvider),
  );
});

final appBuildInfoProvider = FutureProvider<AppBuildInfo>((ref) async {
  final packageInfo = await PackageInfo.fromPlatform();
  return AppBuildInfo(
    version: packageInfo.version,
    buildNumber: packageInfo.buildNumber,
    databaseSchema: AppDatabase.currentSchemaVersion,
  );
});

final authRepositoryProvider = Provider<AuthRepository?>((ref) {
  final config = ref.watch(appConfigProvider);
  final client = ref.watch(supabaseClientProvider);
  if (client == null) {
    return null;
  }
  final delegate = SupabaseAuthRepository(
    client,
    NativeGoogleSignInGateway(serverClientId: config.googleWebClientId),
    onAccountDeletionPrepared: ref.watch(accountDeletionPrepareProvider),
    onAccountDeletionCancelled: ref.watch(accountDeletionCancelProvider),
    onAccountDeleted: ref.watch(accountDeletionLocalCleanupProvider),
  );
  return AccountSafetyAuthRepository(
    delegate,
    barrier: ref.watch(accountSafetyBarrierProvider),
  );
});

final authStateProvider = StreamProvider<AuthStateChange>((ref) {
  final repository = ref.watch(authRepositoryProvider);
  if (repository == null) {
    return Stream<AuthStateChange>.value(
      const AuthStateChange(event: AuthEventType.initialSession, session: null),
    );
  }
  return repository.watchAuthState().handleError((
    Object error,
    StackTrace stackTrace,
  ) {
    // Keep auth stream failures contained. Riverpod exposes the failure to
    // account UI while the authenticated cache remains available.
  });
});

final authSessionProvider = Provider<AsyncValue<AuthSession?>>((ref) {
  return ref.watch(authStateProvider).whenData((state) => state.session);
});

class AppBuildInfo {
  const AppBuildInfo({
    required this.version,
    required this.buildNumber,
    required this.databaseSchema,
  });

  final String version;
  final String buildNumber;
  final int databaseSchema;

  String get label =>
      'App $version ($buildNumber) - database schema $databaseSchema';
}
