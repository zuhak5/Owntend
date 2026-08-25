import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:owntend/src/core/services/action_feedback_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
    service = HkActionFeedbackService();
  });

  tearDown(() async {
    await service.dispose();
  });

  group('HkActionFeedbackService', () {
    test('executes bundled-audio feedback flows without throwing on desktop/test hosts', () async {
      await expectLater(service.playCreated(), completes);
      await expectLater(service.playCompleted(), completes);
      await expectLater(service.playDeleted(), completes);
    });
  });
}
