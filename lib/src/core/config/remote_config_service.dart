// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/redacting_logger.dart';
import 'remote_config_models.dart';

typedef RemoteConfigFetcher = Future<Map<String, dynamic>?> Function();

class RemoteConfigService {
  RemoteConfigService({
    RemoteConfigFetcher? fetcher,
    SupabaseClient? supabaseClient,
  }) : _fetcher = fetcher,
       _supabaseClient = supabaseClient;

  final RemoteConfigFetcher? _fetcher;
  final SupabaseClient? _supabaseClient;
  RemoteConfig _current = const RemoteConfig.defaults();

  RemoteConfig get current => _current;

  Future<RemoteConfig> fetchLatest({
    Duration timeout = const Duration(seconds: 3),
  }) async {
    try {
      Map<String, dynamic>? data;
      if (_fetcher != null) {
        data = await _fetcher().timeout(timeout);
      } else if (_supabaseClient != null) {
        final res = await _supabaseClient
            .rpc<dynamic>('get_app_remote_config')
            .timeout(timeout);
        if (res is Map<String, dynamic>) {
          data = res;
        } else if (res is Map) {
          data = Map<String, dynamic>.from(res);
        }
      }

      if (data != null && data.isNotEmpty) {
        _current = RemoteConfig.fromJson(data);
      }
    } on TimeoutException {
      AppLogger.info('remote_config_fetch_timeout_fallback_to_cached');
    } on Object catch (error) {
      AppLogger.warning('remote_config_fetch_failed', error: error);
    }
    return _current;
  }
}

final remoteConfigServiceProvider = Provider<RemoteConfigService>((ref) {
  final supabase = Supabase.instance.client;
  final service = RemoteConfigService(supabaseClient: supabase);
  unawaited(service.fetchLatest());
  return service;
});

final remoteConfigProvider = Provider<RemoteConfig>((ref) {
  final service = ref.watch(remoteConfigServiceProvider);
  return service.current;
});
