library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../database/app_database.dart';
import '../domain/contracts.dart';
import '../domain/input_validation.dart';
import '../domain/models.dart' as domain;
import '../domain/render_fingerprints.dart';
import '../domain/task_selectors.dart';
import '../services/health_score_calculator.dart';
import '../services/photo_import_service.dart';
import '../services/recurrence_engine.dart';
import '../utils/date_utils.dart';
import '../utils/redacting_logger.dart';
import 'reactive_stream.dart';

part 'row_mappers.dart';
part 'asset_repository.dart';
part 'maintenance_repository.dart';
part 'statistics_repository.dart';
part 'notification_inbox_repository.dart';
part 'settings_repository.dart';
part 'search_repository.dart';
part 'streak_service.dart';

const _uuid = Uuid();

final maintenanceRepositoryProvider = Provider<MaintenanceRepository>(
  (ref) => DriftMaintenanceRepository(ref.watch(databaseProvider)),
);
