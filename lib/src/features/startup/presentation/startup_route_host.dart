import 'package:flutter/material.dart';

/// Provides route infrastructure for startup surfaces that replace the
/// authenticated app router while bootstrap is incomplete.
///
/// Startup UI still needs a Navigator for popup menus, dialogs, and other
/// pageless routes even when the authenticated GoRouter subtree is withheld.
class StartupRouteHost extends StatelessWidget {
  const StartupRouteHost({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Navigator(
      pages: <Page<void>>[
        MaterialPage<void>(
          key: const ValueKey('owntend-startup-root'),
          child: child,
        ),
      ],
      onDidRemovePage: (_) {},
    );
  }
}
