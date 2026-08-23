// ignore_for_file: prefer_initializing_formals

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';

import 'remote_asset_service.dart';

class HkActionFeedbackService {
  HkActionFeedbackService({
    AudioPlayer? completionPlayer,
    AudioPlayer? deletePlayer,
    RemoteAssetService? remoteAssetService,
  }) : _completionPlayer =
           completionPlayer ?? AudioPlayer(playerId: 'owntend-completion'),
       _deletePlayer = deletePlayer ?? AudioPlayer(playerId: 'owntend-delete'),
       _remoteAssetService = remoteAssetService;

  final AudioPlayer _completionPlayer;
  final AudioPlayer _deletePlayer;
  final RemoteAssetService? _remoteAssetService;

  Future<void> playCreated() async {
    await _bestEffortHaptic(HapticFeedback.lightImpact);
    await _bestEffortSystemSound(SystemSoundType.click);
  }

  Future<void> playCompleted() async {
    await _bestEffortHaptic(HapticFeedback.mediumImpact);
    await _playAsset(
      player: _completionPlayer,
      asset: 'audio/task_done.wav',
      volume: 0.38,
      fallback: SystemSoundType.click,
    );
  }

  Future<void> playDeleted() async {
    await _bestEffortHaptic(HapticFeedback.heavyImpact);
    await _playAsset(
      player: _deletePlayer,
      asset: 'audio/task_delete.wav',
      volume: 0.32,
      fallback: SystemSoundType.alert,
    );
  }

  Future<void> _playAsset({
    required AudioPlayer player,
    required String asset,
    required double volume,
    required SystemSoundType fallback,
  }) async {
    try {
      await player.stop();
      Source source = AssetSource(asset);
      if (_remoteAssetService != null) {
        final cachedPath = await _remoteAssetService.getCachedAssetPath(asset);
        if (cachedPath != null && cachedPath.isNotEmpty) {
          source = DeviceFileSource(cachedPath);
        }
      }
      await player.play(source, volume: volume, mode: PlayerMode.lowLatency);
    } catch (_) {
      await _bestEffortSystemSound(fallback);
    }
  }

  Future<void> _bestEffortHaptic(Future<void> Function() feedback) async {
    try {
      await feedback();
    } catch (_) {
      // Haptics are unavailable on some platforms and test hosts.
    }
  }

  Future<void> _bestEffortSystemSound(SystemSoundType type) async {
    try {
      await SystemSound.play(type);
    } catch (_) {
      // Native system sounds are only a fallback.
    }
  }

  Future<void> dispose() async {
    await _completionPlayer.dispose();
    await _deletePlayer.dispose();
  }
}

final hkActionFeedbackService = HkActionFeedbackService();
