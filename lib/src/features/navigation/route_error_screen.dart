import '../../ui/presentation_support.dart';

/// Localized recovery surface for unknown/malformed deep links. It never
/// echoes the failing URI or the underlying exception.
class RouteNotFoundScreen extends StatelessWidget {
  const RouteNotFoundScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Symbols.link_off_rounded,
                  size: 56,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  semanticLabel: context.l10n.routeErrorTitle,
                ),
                const SizedBox(height: 16),
                Text(
                  context.l10n.routeErrorTitle,
                  style: Theme.of(context).textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  context.l10n.routeErrorMessage,
                  style: Theme.of(context).textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: () => context.go('/'),
                  icon: const Icon(Symbols.home_rounded),
                  label: Text(context.l10n.routeErrorAction),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
