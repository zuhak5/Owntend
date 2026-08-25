/// WP-011 (F-019): notification routes are validated by exact top-level
/// segment matching. The previous `startsWith(prefix)` form accepted hostile
/// look-alikes such as `/assets-anything`.
String? validatedNotificationRoute(String payload) {
  final route = payload.trim();
  if (route.isEmpty || !route.startsWith('/')) {
    return null;
  }
  final uri = Uri.tryParse(route);
  if (uri == null || uri.hasFragment) {
    return null;
  }
  const allowedRoots = {
    'maintenance',
    'notifications',
    'assets',
    'calendar',
    'search',
    'settings',
    'account',
    'backup',
    'trash',
    'statistics',
    'more',
  };
  final segments = uri.pathSegments;
  if (segments.isEmpty) return null;
  final root = segments.first;
  // `/permissions/setup` is the single two-segment exception.
  final allowed =
      allowedRoots.contains(root) ||
      (root == 'permissions' && segments.length == 2 && segments[1] == 'setup');
  if (!allowed) {
    return null;
  }
  return uri.toString();
}
