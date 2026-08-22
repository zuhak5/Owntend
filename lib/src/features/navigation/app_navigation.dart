import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>();

const routeTransitionDuration = Duration(milliseconds: 260);
const routeTransitionReverseDuration = Duration(milliseconds: 180);

void openNotificationPayload(String payload) {
  final route = validatedNotificationRoute(payload);
  if (route == null) {
    return;
  }
  WidgetsBinding.instance.addPostFrameCallback((_) {
    final context = rootNavigatorKey.currentContext;
    if (context == null || !context.mounted) {
      return;
    }
    context.push(route);
  });
}

String? validatedNotificationRoute(String payload) {
  final route = payload.trim();
  if (route.isEmpty || !route.startsWith('/')) {
    return null;
  }
  final uri = Uri.tryParse(route);
  if (uri == null || uri.hasFragment) {
    return null;
  }
  const allowedPrefixes = [
    '/maintenance',
    '/notifications',
    '/assets',
    '/calendar',
    '/search',
    '/settings',
    '/account',
    '/backup',
    '/trash',
    '/statistics',
    '/more',
    '/permissions/setup',
  ];
  if (!allowedPrefixes.any((prefix) => uri.path.startsWith(prefix))) {
    return null;
  }
  return uri.toString();
}
