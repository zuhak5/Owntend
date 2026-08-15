import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_config.dart';
import 'secure_supabase_storage.dart';

class SupabaseBootstrap {
  SupabaseBootstrap._();

  static bool _initialized = false;

  static Future<SupabaseClient> initialize(AppConfig config) async {
    if (_initialized) {
      return Supabase.instance.client;
    }

    final secureStorage = SecureSupabaseStorage(
      namespace: config.storageNamespace,
    );
    await Supabase.initialize(
      url: config.supabaseUrl.toString(),
      publishableKey: config.supabasePublishableKey,
      authOptions: FlutterAuthClientOptions(localStorage: secureStorage),
    );
    _initialized = true;
    return Supabase.instance.client;
  }
}
