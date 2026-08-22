import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../l10n/app_localizations_ext.dart';
import '../../core/config/app_config.dart';
import '../../core/sync/sync_providers.dart';
import '../../core/utils/redacting_logger.dart';
import '../../ui/app_theme.dart';
import '../auth/presentation/auth_providers.dart';
import 'ad_cache.dart';
import 'ad_retry_policy.dart';
import 'ad_runtime.dart';

part 'src/ad_presentation.dart';
part 'src/offline_creation_drafts.dart';
part 'src/wallet_contracts.dart';
part 'src/wallet_repository.dart';
part 'src/wallet_controller.dart';
part 'src/consent_bootstrap.dart';
part 'src/ads_service.dart';
part 'src/completion_ads.dart';
part 'src/native_ad_card.dart';
part 'src/points_ui.dart';
