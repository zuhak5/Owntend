/// Public dependencies shared by feature-presentation libraries.
///
/// This barrel deliberately excludes feature screens and the application
/// composition root so presentation features cannot acquire a circular
/// dependency on `owntend_app.dart`.
library;

export 'dart:async' hide AsyncError;
export 'dart:convert';
export 'dart:io';
export 'dart:typed_data';
export 'dart:ui' show ImageFilter;

export 'package:crypto/crypto.dart';
export 'package:file_picker/file_picker.dart'
    hide AndroidOptions, LinuxOptions, WebOptions, WindowsOptions;
export 'package:flutter/foundation.dart';
export 'package:flutter/material.dart';
export 'package:flutter/services.dart';
export 'package:flutter_riverpod/flutter_riverpod.dart';
export 'package:flutter_secure_storage/flutter_secure_storage.dart';
export 'package:go_router/go_router.dart';
export 'package:image_picker/image_picker.dart';
export 'package:intl/intl.dart' hide TextDirection;
export 'package:material_symbols_icons/symbols.dart';
export 'package:path_provider/path_provider.dart';
export 'package:share_plus/share_plus.dart';
export 'package:sentry_flutter/sentry_flutter.dart';
export 'package:supabase_flutter/supabase_flutter.dart';
export 'package:uuid/uuid.dart';

export 'package:owntend/l10n/app_localizations.dart';
export 'package:owntend/l10n/app_localizations_ext.dart';

export '../app/app_dependencies.dart';
export '../core/config/app_config.dart';
export '../core/data/repositories.dart';
export '../core/database/app_database.dart';
export '../core/domain/contracts.dart';
export '../core/domain/models.dart';
export '../core/domain/task_selectors.dart';
export '../core/observability/sentry_navigation.dart';
export '../core/services/action_feedback_service.dart';
export '../core/services/app_permission_coordinator.dart';
export '../core/services/automatic_backup_coordinator.dart';
export '../core/services/backup_service.dart';
export '../core/services/diagnostic_export_service.dart';
export '../core/services/feedback_messenger.dart';
export '../core/services/notification_localization.dart';
export '../core/services/notification_service.dart';
export '../core/services/reminder_schedule_reconciler.dart';
export '../core/services/restore_journal.dart';
export '../core/supabase/supabase_bootstrap.dart';
export '../core/sync/background_sync_scheduler.dart';
export '../core/sync/local_sync_store.dart';
export '../core/sync/restore_foreground_service.dart';
export '../core/sync/sync_bootstrap.dart';
export '../core/sync/sync_contracts.dart';
export '../core/sync/sync_coordinator.dart';
export '../core/utils/app_failure.dart';
export '../core/utils/redacting_logger.dart';
export '../features/auth/data/local_account_data_cleaner.dart';
export '../features/auth/domain/auth_repository.dart';
export '../features/maintenance/application/task_creation_controller.dart';
export '../features/maintenance/domain/task_creation.dart';
export '../features/maintenance/presentation/task_completion_controller.dart';
export '../features/monetization/monetization.dart';
export '../features/monetization/presentation/earn_points_flow.dart';
export '../features/navigation/app_navigation.dart';
export '../features/permissions/domain/capability_snapshots.dart';
export '../features/permissions/domain/permission_capability.dart';
export '../features/permissions/presentation/permission_education_overlay.dart';
export '../features/permissions/presentation/permission_setup_screen.dart';
export '../features/startup/domain/initial_home_snapshot.dart';
export '../i18n/dynamic_text.dart';
export 'app_theme.dart';
export 'domain_localization.dart';
export 'domain_formatters.dart';
export 'editor_modal.dart';
export 'editor_sheet_frame.dart';
export 'full_bleed_illustration_background.dart';
export 'full_canvas_system_ui.dart';
export 'local_media_file.dart';
export 'motion.dart';
export 'presentation_formatters.dart';
