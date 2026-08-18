import '../domain/contracts.dart';
import '../utils/redacting_logger.dart';

class AutomaticBackupCoordinator {
  AutomaticBackupCoordinator({
    required this.backupRepositoryFactory,
    bool Function()? automaticStartEnabled,
    DateTime Function()? now,
    this.foregroundThrottle = const Duration(minutes: 15),
  }) : _automaticStartEnabled = automaticStartEnabled ?? _enabledByDefault,
       _now = now ?? DateTime.now;

  final BackupRepository Function() backupRepositoryFactory;
  final bool Function() _automaticStartEnabled;
  final DateTime Function() _now;
  final Duration foregroundThrottle;

  bool _postReady = false;
  DateTime? _lastSuccessfulDueCheckAt;
  Future<void>? _inFlight;

  Future<void> onPostReady() {
    final firstPostReadyTrigger = !_postReady;
    _postReady = true;
    return _runDueCheck(ignoreThrottle: firstPostReadyTrigger);
  }

  Future<void> onAppResumed() {
    return _runDueCheck(ignoreThrottle: false);
  }

  void reset() {
    _postReady = false;
    _lastSuccessfulDueCheckAt = null;
  }

  Future<void> _runDueCheck({required bool ignoreThrottle}) {
    if (!_postReady || !_automaticStartEnabled()) {
      return Future<void>.value();
    }

    final active = _inFlight;
    if (active != null) {
      return active;
    }

    final now = _now().toUtc();
    final lastSuccessfulDueCheckAt = _lastSuccessfulDueCheckAt;
    if (!ignoreThrottle &&
        lastSuccessfulDueCheckAt != null &&
        now.difference(lastSuccessfulDueCheckAt) < foregroundThrottle) {
      return Future<void>.value();
    }

    final work = _performDueCheck();
    _inFlight = work;
    work.whenComplete(() {
      if (identical(_inFlight, work)) {
        _inFlight = null;
      }
    });
    return work;
  }

  Future<void> _performDueCheck() async {
    try {
      await backupRepositoryFactory().exportAutomaticBackupIfDue();
      _lastSuccessfulDueCheckAt = _now().toUtc();
    } on Object catch (error, stackTrace) {
      AppLogger.warning(
        'automatic_backup_due_check_failed',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  static bool _enabledByDefault() => true;
}
