import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:island/core/services/timezone/native.dart' as timezone;
import 'package:wakelock_plus/wakelock_plus.dart';

void main() {
  testWidgets('OHOS timezone identifiers keep the current TimezoneInfo API', (
    tester,
  ) async {
    const channel = MethodChannel('flutter_timezone');
    final messenger = tester.binding.defaultBinaryMessenger;
    var fail = false;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (fail) throw PlatformException(code: 'timezone_error');
      return switch (call.method) {
        'getLocalTimezone' => 'Asia/Shanghai',
        'getAvailableTimezones' => ['Asia/Shanghai', 'Etc/UTC'],
        _ => throw MissingPluginException(),
      };
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    final local = await FlutterTimezone.getLocalTimezone('zh-CN');
    expect(local.identifier, 'Asia/Shanghai');
    expect(local.localizedName, isNull);
    expect(
      (await FlutterTimezone.getAvailableTimezones()).map((t) => t.identifier),
      ['Asia/Shanghai', 'Etc/UTC'],
    );
    expect(await timezone.getMachineTz(), 'Asia/Shanghai');
    fail = true;
    await expectLater(
      timezone.getMachineTz(),
      throwsA(isA<PlatformException>()),
    );
  }, variant: TargetPlatformVariant({TargetPlatform.ohos}));

  testWidgets('OHOS wakelock wire format matches the current Pigeon API', (
    tester,
  ) async {
    final messenger = tester.binding.defaultBinaryMessenger;
    const prefix =
        'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi';
    var enabled = false;
    var fail = false;
    messenger.setMockMessageHandler('$prefix.toggle', (data) async {
      // [ToggleMessage([bool])] with custom tag 129, shared with the ArkTS codec.
      final bytes = data!.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
      expect(bytes.take(5), [12, 1, 129, 12, 1]);
      expect(bytes.length, 6);
      if (fail) {
        return const StandardMessageCodec().encodeMessage([
          'window_error_1300002',
          'Window unavailable',
          null,
        ]);
      }
      enabled = bytes.last == 1;
      return const StandardMessageCodec().encodeMessage([null]);
    });
    messenger.setMockMessageHandler('$prefix.isEnabled', (_) async {
      // [IsEnabledMessage([bool])] with custom tag 130.
      return ByteData.sublistView(
        Uint8List.fromList([12, 1, 130, 12, 1, enabled ? 1 : 2]),
      );
    });
    addTearDown(() {
      messenger.setMockMessageHandler('$prefix.toggle', null);
      messenger.setMockMessageHandler('$prefix.isEnabled', null);
    });

    expect(await WakelockPlus.enabled, isFalse);
    await WakelockPlus.enable();
    expect(await WakelockPlus.enabled, isTrue);
    await WakelockPlus.disable();
    expect(await WakelockPlus.enabled, isFalse);
    fail = true;
    await expectLater(
      WakelockPlus.enable(),
      throwsA(
        isA<PlatformException>().having(
          (e) => e.code,
          'code',
          'window_error_1300002',
        ),
      ),
    );
  }, variant: TargetPlatformVariant({TargetPlatform.ohos}));
}
