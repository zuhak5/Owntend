import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../utils/redacting_logger.dart';

class NativeCapabilitySnapshot {
  const NativeCapabilitySnapshot({
    required this.shellVersion,
    required this.capabilities,
  });

  const NativeCapabilitySnapshot.fallback()
    : shellVersion = 1,
      capabilities = const {'systemUi': 1, 'nativeAds': 1, 'platformEnv': 1};

  final int shellVersion;
  final Map<String, int> capabilities;

  bool supports(String capability, {int minVersion = 1}) {
    final version = capabilities[capability] ?? 0;
    return version >= minVersion;
  }

  factory NativeCapabilitySnapshot.fromMap(Map<dynamic, dynamic>? map) {
    if (map == null) return const NativeCapabilitySnapshot.fallback();
    final shellVersion = (map['shellVersion'] as num?)?.toInt() ?? 1;
    final rawCaps = map['capabilities'] as Map<dynamic, dynamic>? ?? const {};
    final capabilities = <String, int>{};
    for (final entry in rawCaps.entries) {
      if (entry.key is String && entry.value is num) {
        capabilities[entry.key as String] = (entry.value as num).toInt();
      }
    }
    return NativeCapabilitySnapshot(
      shellVersion: shellVersion,
      capabilities: capabilities,
    );
  }

  @override
  String toString() =>
      'NativeCapabilitySnapshot(shellVersion: $shellVersion, capabilities: $capabilities)';
}

class NativeCapabilities {
  NativeCapabilities({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('owntend/capabilities');

  final MethodChannel _channel;
  NativeCapabilitySnapshot? _cached;

  Future<NativeCapabilitySnapshot> getInfo() async {
    if (_cached != null) return _cached!;
    try {
      final raw = await _channel.invokeMapMethod<String, dynamic>(
        'getCapabilities',
      );
      _cached = NativeCapabilitySnapshot.fromMap(raw);
    } on MissingPluginException {
      _cached = const NativeCapabilitySnapshot.fallback();
    } on Object catch (error) {
      AppLogger.warning('native_capabilities_query_failed', error: error);
      _cached = const NativeCapabilitySnapshot.fallback();
    }
    return _cached!;
  }

  Future<String?> getTimeZoneId() async {
    try {
      final value = await _channel.invokeMethod<String>('getTimeZoneId');
      final trimmed = value?.trim();
      return trimmed?.isNotEmpty == true
          ? trimmed
          : DateTime.now().timeZoneName;
    } on MissingPluginException {
      return DateTime.now().timeZoneName;
    } on Object catch (error) {
      AppLogger.warning('native_timezone_query_failed', error: error);
      return DateTime.now().timeZoneName;
    }
  }
}

final nativeCapabilitiesProvider = Provider<NativeCapabilities>((ref) {
  return NativeCapabilities();
});
