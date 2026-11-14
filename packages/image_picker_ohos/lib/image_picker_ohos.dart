import 'package:flutter/services.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
// Reuse the pinned interface's existing transport instead of duplicating its Dart API.
// ignore: implementation_imports
import 'package:image_picker_platform_interface/src/method_channel/method_channel_image_picker.dart';

/// OHOS uses the shared interface's existing method-channel protocol.
class ImagePickerOhos extends MethodChannelImagePicker {
  static void registerWith() {
    ImagePickerPlatform.instance = ImagePickerOhos();
  }

  @override
  Future<List<XFile>> getMultiVideoWithOptions({
    MultiVideoPickerOptions options = const MultiVideoPickerOptions(),
  }) async {
    final paths = await const MethodChannel('plugins.flutter.io/image_picker')
        .invokeListMethod<String>('pickMultiVideo', {
          'limit': options.limit,
          'maxDuration': options.maxDuration?.inSeconds,
        });
    return (paths ?? <String>[]).map((path) => XFile(path)).toList();
  }
}
