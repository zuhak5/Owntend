import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

// WP-012 (D3): both portrait orientations are accepted so the UI survives
// the device being held upside down (e.g., camera grip, car mount) without
// forcing a system rotation prompt; landscape remains out of product scope.
const _preferredOrientations = <DeviceOrientation>[
  DeviceOrientation.portraitUp,
  DeviceOrientation.portraitDown,
];

@visibleForTesting
List<DeviceOrientation> preferredAppOrientations() => _preferredOrientations;

Future<void> configurePreferredOrientations() {
  return SystemChrome.setPreferredOrientations(_preferredOrientations);
}
