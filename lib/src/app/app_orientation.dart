import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const _preferredOrientations = <DeviceOrientation>[
  DeviceOrientation.portraitUp,
];

@visibleForTesting
List<DeviceOrientation> preferredAppOrientations() => _preferredOrientations;

Future<void> configurePreferredOrientations() {
  return SystemChrome.setPreferredOrientations(_preferredOrientations);
}
