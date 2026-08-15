import 'package:flutter/widgets.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

NavigatorObserver owntendSentryNavigatorObserver({Hub? hub}) {
  return SentryNavigatorObserver(
    hub: hub,
    enableAutoTransactions: true,
    enableNewTraceOnNavigation: false,
    routeNameExtractor: (settings) =>
        RouteSettings(name: normalizeSentryRoute(settings?.name ?? '/unknown')),
  );
}

String normalizeSentryRoute(String route) {
  final uri = Uri.tryParse(route.trim());
  if (uri == null || !uri.path.startsWith('/')) return '/unknown';
  final segments = uri.pathSegments;
  if (segments.isEmpty) return '/';

  final normalized = <String>[];
  for (var index = 0; index < segments.length; index++) {
    final segment = segments[index];
    final previous = index == 0 ? '' : segments[index - 1];
    if (segment.startsWith(':') ||
        ((previous == 'room' || previous == 'thing') && index >= 2) ||
        (previous == 'maintenance' && index >= 1) ||
        _looksLikeIdentifier(segment)) {
      normalized.add(':id');
    } else {
      normalized.add(segment.toLowerCase());
    }
  }
  final result = '/${normalized.join('/')}';
  return _knownRouteShape(result) ? result : '/unknown';
}

bool _knownRouteShape(String route) {
  if (_knownRoutes.contains(route)) return true;
  return RegExp(r'^/(?:assets/(?:room|thing)|maintenance)/:id$')
      .hasMatch(route);
}

bool _looksLikeIdentifier(String segment) {
  return RegExp(r'^\d+$').hasMatch(segment) ||
      RegExp(
        r'^[0-9a-f]{8}-[0-9a-f-]{27,}$',
        caseSensitive: false,
      ).hasMatch(segment) ||
      RegExp(r'^[A-Za-z0-9_-]{20,}$').hasMatch(segment);
}

const _knownRoutes = <String>{
  '/',
  '/account',
  '/assets',
  '/backup',
  '/calendar',
  '/maintenance',
  '/more',
  '/notifications',
  '/permissions/setup',
  '/profile',
  '/search',
  '/settings',
  '/statistics',
  '/trash',
};
