import 'package:flutter/widgets.dart';

const themeTransitionDuration = Duration(milliseconds: 620);
const themeTransitionCurve = Curves.easeInOutCubic;

bool prefersReducedMotion(BuildContext context) {
  final media = MediaQuery.maybeOf(context);
  return media?.disableAnimations == true ||
      media?.accessibleNavigation == true;
}
