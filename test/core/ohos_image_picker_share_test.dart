import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_picker_ohos/image_picker_ohos.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:share_plus/share_plus.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.ohos);
  tearDown(() => debugDefaultTargetPlatformOverride = null);
  test(
    'OHOS picker keeps the current image/video API and readable XFiles',
    () async {
      final directory = await Directory.systemTemp.createTemp('ohos-picker-');
      addTearDown(() => directory.delete(recursive: true));
      final image = await File(
        '${directory.path}/图片.jpg',
      ).writeAsBytes([1, 2, 3]);
      final video = await File(
        '${directory.path}/video.mp4',
      ).writeAsBytes([4, 5]);
      const channel = MethodChannel('plugins.flutter.io/image_picker');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final calls = <MethodCall>[];
      var cancel = false;
      var fail = false;
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        if (fail) throw PlatformException(code: 'picker_error');
        return switch (call.method) {
          'pickImage' => cancel ? null : image.path,
          'pickVideo' => cancel ? null : video.path,
          'pickMultiImage' => cancel ? <String>[] : [image.path, image.path],
          'pickMultiVideo' => cancel ? <String>[] : [video.path, video.path],
          'pickMedia' => cancel ? <String>[] : [image.path, video.path],
          'retrieve' => null,
          _ => throw MissingPluginException(),
        };
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final previous = ImagePicker.platform;
      ImagePickerOhos.registerWith();
      addTearDown(() => ImagePickerPlatform.instance = previous);
      final picker = ImagePicker();
      final selected = await picker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.front,
        maxWidth: 200,
        imageQuality: 80,
      );
      expect(await selected!.readAsBytes(), [1, 2, 3]);
      expect(calls.last.arguments, containsPair('cameraDevice', 1));
      expect(calls.last.arguments, containsPair('source', 0));
      expect(calls.last.arguments, containsPair('maxWidth', 200.0));
      expect((await picker.pickMultiImage(limit: 3)).length, 2);
      expect(calls.last.arguments, containsPair('limit', 3));
      expect((await picker.pickMultiVideo(limit: 3)).length, 2);
      expect((await picker.pickMultipleMedia(limit: 3)).map((f) => f.path), [
        image.path,
        video.path,
      ]);
      expect((await picker.retrieveLostData()).isEmpty, isTrue);
      cancel = true;
      expect(await picker.pickImage(source: ImageSource.gallery), isNull);
      expect(await picker.pickMultiImage(), isEmpty);
      expect(await picker.pickMultiVideo(), isEmpty);
      fail = true;
      await expectLater(
        picker.pickImage(source: ImageSource.gallery),
        throwsA(isA<PlatformException>()),
      );
    },
  );

  test('OHOS share keeps current text, URI, file and legacy calls', () async {
    final directory = await Directory.systemTemp.createTemp('ohos-share-');
    addTearDown(() => directory.delete(recursive: true));
    final file = await File('${directory.path}/图片.png').writeAsBytes([1, 2, 3]);
    const channel = MethodChannel('dev.fluttercommunity.plus/share');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final calls = <MethodCall>[];
    var fail = false;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (fail) throw PlatformException(code: 'share_error');
      return 'dev.fluttercommunity.plus/share/unavailable';
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    expect(
      (await SharePlus.instance.share(ShareParams(text: 'hello'))).status,
      ShareResultStatus.unavailable,
    );
    await SharePlus.instance.share(
      ShareParams(uri: Uri.parse('https://example.com'), title: 'link'),
    );
    expect(calls.last.arguments, containsPair('uri', 'https://example.com'));
    await SharePlus.instance.share(
      ShareParams(files: [XFile(file.path)], text: 'image', subject: 'subject'),
    );
    expect(calls.last.method, 'share');
    expect(calls.last.arguments, containsPair('paths', [file.path]));
    expect(calls.last.arguments, containsPair('mimeTypes', ['image/png']));
    // ignore: deprecated_member_use
    await Share.shareXFiles([XFile(file.path)]);
    expect(calls.last.method, 'share');
    expect(calls.last.arguments, containsPair('paths', [file.path]));
    fail = true;
    await expectLater(
      SharePlus.instance.share(ShareParams(text: 'hello')),
      throwsA(isA<PlatformException>()),
    );
  });
}
