part of '../../../../main.dart';

class _AppRouteBackdrop extends StatelessWidget {
  const _AppRouteBackdrop({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return hk_ui.ProductivityBackdrop(
      child: Theme(
        data: theme.copyWith(scaffoldBackgroundColor: Colors.transparent),
        child: child,
      ),
    );
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    observers: [owntendSentryNavigatorObserver()],
    routes: [
      ShellRoute(
        builder: (context, state, child) => HomeShell(child: child),
        routes: [
          GoRoute(
            path: '/',
            pageBuilder: (context, state) =>
                _appRoutePage(context, state, const DashboardScreen()),
          ),
          GoRoute(
            path: '/assets',
            pageBuilder: (context, state) =>
                _appRoutePage(context, state, const RoomsScreen()),
          ),
          GoRoute(
            path: '/assets/room/:roomId',
            pageBuilder: (context, state) => _appRoutePage(
              context,
              state,
              RoomDetailScreen(roomId: state.pathParameters['roomId']!),
            ),
          ),
          GoRoute(
            path: '/assets/thing/:assetId',
            pageBuilder: (context, state) => _appRoutePage(
              context,
              state,
              ThingDetailScreen(assetId: state.pathParameters['assetId']!),
            ),
          ),
          GoRoute(
            path: '/maintenance',
            pageBuilder: (context, state) => _appRoutePage(
              context,
              state,
              MaintenanceScreen(
                initialFilter: state.uri.queryParameters['filter'],
              ),
              bodyHasBackdrop: true,
            ),
          ),
          GoRoute(
            path: '/maintenance/:planId',
            pageBuilder: (context, state) => _appRoutePage(
              context,
              state,
              TaskDetailScreen(planId: state.pathParameters['planId']!),
            ),
          ),
          GoRoute(
            path: '/calendar',
            pageBuilder: (context, state) => _appRoutePage(
              context,
              state,
              const CalendarScreen(),
              bodyHasBackdrop: true,
            ),
          ),
          GoRoute(
            path: '/more',
            pageBuilder: (context, state) =>
                _appRoutePage(context, state, const MoreScreen()),
          ),
          GoRoute(
            path: '/search',
            pageBuilder: (context, state) =>
                _appRoutePage(context, state, const SearchScreen()),
          ),
          GoRoute(
            path: '/trash',
            pageBuilder: (context, state) =>
                _appRoutePage(context, state, const TrashScreen()),
          ),
          GoRoute(
            path: '/statistics',
            pageBuilder: (context, state) =>
                _appRoutePage(context, state, const StatisticsScreen()),
          ),

          GoRoute(
            path: '/settings',
            pageBuilder: (context, state) =>
                _appRoutePage(context, state, const SettingsScreen()),
          ),
          GoRoute(path: '/profile', redirect: (context, state) => '/account'),
          GoRoute(
            path: '/account',
            pageBuilder: (context, state) =>
                _appRoutePage(context, state, const AccountScreenHost()),
          ),
          GoRoute(
            path: '/backup',
            pageBuilder: (context, state) => _appRoutePage(
              context,
              state,
              const BackupScreen(),
              bodyHasBackdrop: true,
            ),
          ),
          GoRoute(
            path: '/notifications',
            pageBuilder: (context, state) =>
                _appRoutePage(context, state, const NotificationsScreen()),
          ),
          GoRoute(
            path: '/permissions/setup',
            pageBuilder: (context, state) => _appRoutePage(
              context,
              state,
              PermissionSetupScreen(
                sponsoredContent: const HkNativeAdCard(
                  placement: 'permission_setup',
                ),
                onChooseLocationManually: (context) =>
                    showModalBottomSheet<HomeLocation>(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: Colors.transparent,
                      builder: (_) => const LocationPickerSheet(),
                    ),
              ),
            ),
          ),
        ],
      ),
    ],
  );
});

class AccountScreenHost extends ConsumerWidget {
  const AccountScreenHost({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider).value ?? const AppProfile();
    return AccountScreen(
      profile: profile,
      onSaveNickname: (nickname) => _saveAccountNickname(ref, nickname),
      sponsoredContent: const HkNativeAdCard(placement: 'account'),
    );
  }
}

Future<void> _saveAccountNickname(WidgetRef ref, String? nickname) async {
  await ref.read(settingsRepositoryProvider).setProfile(nickname: nickname);
  ref.invalidate(profileProvider);
  unawaited(_syncProfileIfEnabled(ref));
}
