part of '../../../../main.dart';

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  static const _paths = ['/', '/assets', '/maintenance', '/calendar', '/more'];

  @override
  Widget build(BuildContext context) {
    final uri = GoRouterState.of(context).uri;
    final path = uri.path;
    final selectedIndex = _selectedIndex(path);
    final showBottomNav = const {
      '/',
      '/assets',
      '/maintenance',
      '/calendar',
      '/more',
    }.contains(path);
    return Scaffold(
      extendBody: showBottomNav,
      body: widget.child,
      bottomNavigationBar: showBottomNav
          ? hk_ui.SereneBottomNavigationBar(
              selectedIndex: selectedIndex,
              destinations: const [
                hk_ui.SereneBottomNavDestination(
                  icon: Symbols.home_rounded,
                  selectedIcon: Symbols.home_filled_rounded,
                  label: hk_ui.SereneBottomNavLabel.home,
                ),
                hk_ui.SereneBottomNavDestination(
                  icon: Symbols.inventory_2_rounded,
                  selectedIcon: Symbols.inventory_2_rounded,
                  label: hk_ui.SereneBottomNavLabel.rooms,
                ),
                hk_ui.SereneBottomNavDestination(
                  icon: Symbols.task_alt_rounded,
                  selectedIcon: Symbols.task_alt_rounded,
                  label: hk_ui.SereneBottomNavLabel.tasks,
                ),
                hk_ui.SereneBottomNavDestination(
                  icon: Symbols.calendar_month_rounded,
                  selectedIcon: Symbols.calendar_month_rounded,
                  label: hk_ui.SereneBottomNavLabel.calendar,
                ),
                hk_ui.SereneBottomNavDestination(
                  icon: Symbols.settings_rounded,
                  selectedIcon: Symbols.settings_rounded,
                  label: hk_ui.SereneBottomNavLabel.tools,
                ),
              ],
              onDestinationSelected: (index) => context.go(_paths[index]),
            )
          : null,
    );
  }

  int _selectedIndex(String path) {
    if (path == '/assets') {
      return 1;
    }
    if (path == '/maintenance') {
      return 2;
    }
    if (path == '/calendar') {
      return 3;
    }
    if (path == '/more') {
      return 4;
    }
    return 0;
  }
}
