import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/presentation/auth_providers.dart';
import 'background_sync_scheduler.dart';
import 'local_sync_store.dart';
import 'observed_sync_repository.dart';
import 'supabase_sync_gateway.dart';
import 'sync_coordinator.dart';
import 'sync_contracts.dart';
import 'sync_connectivity.dart';

final localSyncStoreProvider = Provider<LocalSyncStore?>((ref) => null);

final syncConnectivityInstanceProvider = Provider<SyncConnectivity>((ref) {
  return PlatformSyncConnectivity();
});

final syncConnectivityProvider = StreamProvider<bool>((ref) {
  return ref.watch(syncConnectivityInstanceProvider).watchOnline();
});

typedef MaintenanceCompletionReminderReconciler = Future<void> Function();

final maintenanceCompletionReminderReconcilerProvider =
    Provider<MaintenanceCompletionReminderReconciler?>((ref) => null);

final syncCoordinatorProvider = Provider<SyncCoordinator?>((ref) {
  final client = ref.watch(supabaseClientProvider);
  final authRepository = ref.watch(authRepositoryProvider);
  final localStore = ref.watch(localSyncStoreProvider);
  if (client == null || authRepository == null || localStore == null) {
    return null;
  }
  final gateway = SupabaseSyncGateway(client);
  final coordinator = SyncCoordinator(
    authRepository,
    localStore,
    gateway,
    connectivity: ref.watch(syncConnectivityInstanceProvider),
    realtime: gateway,
    configureBackgroundSync: configureCloudSyncBackgroundTask,
    reconcileMaintenanceCompletionReminders: ref.watch(
      maintenanceCompletionReminderReconcilerProvider,
    ),
    autoEnableOnAuthChange: false,
  );
  ref.onDispose(coordinator.dispose);
  return coordinator;
});

final cloudSyncRepositoryProvider = Provider<CloudSyncRepository>((ref) {
  final coordinator = ref.watch(syncCoordinatorProvider);
  if (coordinator == null) return const DisabledCloudSyncRepository();
  return ObservedCloudSyncRepository(coordinator);
});

final syncStatusProvider = StreamProvider<SyncStatus>((ref) {
  return ref.watch(cloudSyncRepositoryProvider).watchStatus();
});
