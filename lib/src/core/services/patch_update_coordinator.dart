import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shorebird_code_push/shorebird_code_push.dart';

import '../utils/redacting_logger.dart';

sealed class PatchUpdateState {
  const PatchUpdateState();
}

class PatchUpdateIdle extends PatchUpdateState {
  const PatchUpdateIdle({this.currentPatchNumber});
  final int? currentPatchNumber;
}

class PatchUpdateChecking extends PatchUpdateState {
  const PatchUpdateChecking({this.currentPatchNumber});
  final int? currentPatchNumber;
}

class PatchUpdateReady extends PatchUpdateState {
  const PatchUpdateReady({
    required this.nextPatchNumber,
    this.currentPatchNumber,
  });
  final int nextPatchNumber;
  final int? currentPatchNumber;
}

class PatchUpdateUpToDate extends PatchUpdateState {
  const PatchUpdateUpToDate({this.currentPatchNumber});
  final int? currentPatchNumber;
}

class PatchUpdateUnavailable extends PatchUpdateState {
  const PatchUpdateUnavailable();
}

class PatchUpdateCoordinator extends Notifier<PatchUpdateState> {
  PatchUpdateCoordinator({ShorebirdUpdater? updater, this.hasSufficientStorage})
    : _updaterOverride = updater;

  final ShorebirdUpdater? _updaterOverride;
  final Future<bool> Function()? hasSufficientStorage;
  late final ShorebirdUpdater _updater;
  DateTime? _lastCheckedAt;
  static const _checkCooldown = Duration(hours: 4);

  @override
  PatchUpdateState build() {
    _updater = _updaterOverride ?? ShorebirdUpdater();
    try {
      if (!_updater.isAvailable) {
        return const PatchUpdateUnavailable();
      }
    } on Object {
      return const PatchUpdateUnavailable();
    }
    unawaited(_init());
    return const PatchUpdateIdle();
  }

  Future<void> _init() async {
    try {
      if (!_updater.isAvailable) {
        AppLogger.info(
          'shorebird_runtime_status',
          fields: {
            'is_available': false,
            'current_patch_number': 'unavailable',
            'patch_active': false,
          },
        );
        state = const PatchUpdateUnavailable();
        return;
      }
      final currentPatch = await _updater.readCurrentPatch();
      final currentNumber = currentPatch?.number;
      final nextPatch = await _updater.readNextPatch();
      AppLogger.info(
        'shorebird_runtime_status',
        fields: {
          'is_available': true,
          'current_patch_number': currentNumber?.toString() ?? 'base',
          'next_patch_number': nextPatch?.number.toString() ?? 'none',
          'patch_active': currentNumber != null,
        },
      );
      if (currentNumber == null) {
        AppLogger.info('shorebird_base_running');
      } else {
        AppLogger.info(
          'shorebird_patch_active',
          fields: {'patch_number': currentNumber},
        );
      }
      if (nextPatch != null) {
        state = PatchUpdateReady(
          nextPatchNumber: nextPatch.number,
          currentPatchNumber: currentNumber,
        );
      } else {
        state = PatchUpdateIdle(currentPatchNumber: currentNumber);
      }
    } on Object catch (error) {
      AppLogger.warning('shorebird_patch_init_failed', error: error);
      state = const PatchUpdateUnavailable();
    }
  }

  Future<void> checkForUpdates({bool force = false}) async {
    final now = DateTime.now();
    if (!force &&
        _lastCheckedAt != null &&
        now.difference(_lastCheckedAt!) < _checkCooldown) {
      return;
    }
    _lastCheckedAt = now;

    try {
      if (!_updater.isAvailable) {
        state = const PatchUpdateUnavailable();
        return;
      }
      final currentPatch = await _updater.readCurrentPatch();
      final currentNumber = currentPatch?.number;
      state = PatchUpdateChecking(currentPatchNumber: currentNumber);

      final nextPatch = await _updater.readNextPatch();
      if (nextPatch != null) {
        AppLogger.info(
          'shorebird_patch_downloaded_restart_required',
          fields: {
            'current_patch_number': currentNumber?.toString() ?? 'base',
            'next_patch_number': nextPatch.number.toString(),
          },
        );
        state = PatchUpdateReady(
          nextPatchNumber: nextPatch.number,
          currentPatchNumber: currentNumber,
        );
        return;
      }

      final status = await _updater.checkForUpdate();
      if (status == UpdateStatus.outdated) {
        final storageCheck = hasSufficientStorage;
        if (storageCheck != null && !(await storageCheck())) {
          AppLogger.warning('patch_download_skipped_low_storage');
          state = PatchUpdateIdle(currentPatchNumber: currentNumber);
          return;
        }
        await _updater.update();
        final readyPatch = await _updater.readNextPatch();
        if (readyPatch != null) {
          AppLogger.info(
            'shorebird_patch_downloaded_restart_required',
            fields: {
              'current_patch_number': currentNumber?.toString() ?? 'base',
              'next_patch_number': readyPatch.number.toString(),
            },
          );
          state = PatchUpdateReady(
            nextPatchNumber: readyPatch.number,
            currentPatchNumber: currentNumber,
          );
          return;
        }
      } else if (status == UpdateStatus.restartRequired) {
        final readyPatch = await _updater.readNextPatch();
        final nextNumber = readyPatch?.number ?? (currentNumber ?? 0) + 1;
        AppLogger.info(
          'shorebird_patch_downloaded_restart_required',
          fields: {
            'current_patch_number': currentNumber?.toString() ?? 'base',
            'next_patch_number': nextNumber.toString(),
          },
        );
        state = PatchUpdateReady(
          nextPatchNumber: nextNumber,
          currentPatchNumber: currentNumber,
        );
        return;
      }

      AppLogger.info(
        'shorebird_patch_up_to_date',
        fields: {'current_patch_number': currentNumber?.toString() ?? 'base'},
      );
      state = PatchUpdateUpToDate(currentPatchNumber: currentNumber);
    } on Object catch (error) {
      AppLogger.warning('shorebird_patch_check_failed', error: error);
      final currentNumber = state is PatchUpdateIdle
          ? (state as PatchUpdateIdle).currentPatchNumber
          : null;
      state = PatchUpdateIdle(currentPatchNumber: currentNumber);
    }
  }
}

final patchUpdateCoordinatorProvider =
    NotifierProvider<PatchUpdateCoordinator, PatchUpdateState>(
      PatchUpdateCoordinator.new,
    );
