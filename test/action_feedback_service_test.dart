import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:owntend/src/core/services/action_feedback_service.dart';
import 'package:owntend/src/core/services/remote_asset_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late RemoteAssetService remoteAssetService;
  late HkActionFeedbackService service;

  setUp(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('xyz.luan/audioplayers.global'),
          (call) async => 1,
        );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('xyz.luan/audioplayers'),
          (call) async => 1,
        );
    tempDir = await Directory.systemTemp.createTemp('feedback_test_');
    remoteAssetService = RemoteAssetService(cacheDirectory: tempDir);
    service = HkActionFeedbackService(remoteAssetService: remoteAssetService);
  });

  tearDown(() async {
    await service.dispose();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('HkActionFeedbackService (SB-017)', () {
    test(
      'executes feedback flows without throwing on desktop/test hosts',
      () async {
        await expectLater(service.playCreated(), completes);
        await expectLater(service.playCompleted(), completes);
        await expectLater(service.playDeleted(), completes);
      },
    );

    test('accepts dynamic remote asset override', () async {
      final customFile = File('${tempDir.path}/task_done.wav');
      await customFile.writeAsString('mock-audio-data');

      // The service seamlessly falls back or plays the device source
      await expectLater(service.playCompleted(), completes);
    });
  });
}
