import 'package:audio_session/audio_session.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'OHOS audio focus denial and interruptions preserve the shared API',
    (tester) async {
      const channel = MethodChannel('com.ryanheise.ohos_audio_manager');
      const configurationChannel = MethodChannel('com.ryanheise.audio_session');
      final messenger = tester.binding.defaultBinaryMessenger;
      final calls = <MethodCall>[];
      var grantFocus = false;
      messenger.setMockMethodCallHandler(
        configurationChannel,
        (_) async => null,
      );
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return call.method == 'setActive' ? grantFocus : true;
      });
      addTearDown(() {
        messenger.setMockMethodCallHandler(channel, null);
        messenger.setMockMethodCallHandler(configurationChannel, null);
      });

      const config = AudioSessionConfiguration.music();
      final decoded = AudioSessionConfiguration.fromJson(config.toJson());
      expect(decoded.ohosAudioAttributes?.streamUsage, StreamUsage.music);
      expect(decoded.androidAudioAttributes, config.androidAudioAttributes);

      final session = await AudioSession.instance;
      await session.configure(config);
      expect(await session.setActive(true), isFalse);
      expect(calls.map((c) => c.method), ['setActive']);

      grantFocus = true;
      expect(await session.setActive(true), isTrue);
      expect(calls.last.method, 'setInterruptionEventListener');
      final interruption = session.interruptionEventStream.first;
      await messenger.handlePlatformMessage(
        channel.name,
        const StandardMethodCodec().encodeMethodCall(
          const MethodCall('onAudioInterrupt', [0]),
        ),
        (_) {},
      );
      final event = await interruption;
      expect(event.begin, isTrue);
      expect(event.type, AudioInterruptionType.pause);
    },
    variant: TargetPlatformVariant({TargetPlatform.ohos}),
  );
}
