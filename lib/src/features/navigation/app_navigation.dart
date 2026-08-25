import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../ui/widgets/notification_route_validation.dart';

export '../../ui/widgets/notification_route_validation.dart'
    show validatedNotificationRoute;

final rootNavigatorKey = GlobalKey<NavigatorState>();

const routeTransitionDuration = Duration(milliseconds: 260);
const routeTransitionReverseDuration = Duration(milliseconds: 180);

void openNotificationPayload(String payload) {
  final route = validatedNotificationRoute(payload);
  if (route == null) {
    return;
  }
  // WP-011 (F-019): remember the intended destination so the startup
  // finalization can honor it after authentication/hydration completes
  // instead of forcing every early tap back to home.
  PendingNotificationRoute.pending = route;
  WidgetsBinding.instance.addPostFrameCallback((_) {
    final context = rootNavigatorKey.currentContext;
    if (context == null || !context.mounted) {
      return;
    }
    context.push(route);
  });
}

/// Destination captured from a notification tapped before the startup gate
/// finished. Consumed exactly once by the startup finalization.
class PendingNotificationRoute {
  PendingNotificationRoute._();

  static String? pending;

  static String? take() {
    final route = pending;
    pending = null;
    return route;
  }
}
