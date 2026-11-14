import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'OHOS picker keeps the current file API for cached provider files',
    () async {
      const channel = MethodChannel('miguelruivo.flutter.plugins.filepicker');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final directory = await Directory.systemTemp.createTemp('ohos-picker-');
      final file = await File(
        '${directory.path}/中文 file.txt',
      ).writeAsBytes([1, 2, 3]);
      final previous = FilePickerPlatform.instance;
      var cancelled = false;
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return switch (call.method) {
          'pickFiles' => cancelled ? <String>[] : [file.uri.toString()],
          'saveFile' => 'file://docs/export.txt',
          'clearTemporaryFiles' => null,
          _ => throw StateError(call.method),
        };
      });
      addTearDown(() async {
        messenger.setMockMethodCallHandler(channel, null);
        FilePickerPlatform.instance = previous;
        await directory.delete(recursive: true);
      });

      FilePickerOhos.registerWith();
      final statuses = <FilePickerStatus>[];
      final selected = (await FilePicker.pickFiles(
        onFileLoading: statuses.add,
      )).single;
      expect(selected.name, '中文 file.txt');
      expect(selected.path, file.path);
      expect(selected.lengthSync(), 3);
      expect(await selected.length(), 3);
      expect(await selected.readAsBytes(), [1, 2, 3]);
      expect(await selected.xFile.readAsBytes(), [1, 2, 3]);
      expect(
        await selected.readAsByteStream().expand((bytes) => bytes).toList(),
        [1, 2, 3],
      );
      expect(statuses, [FilePickerStatus.picking, FilePickerStatus.done]);
      cancelled = true;
      expect(await FilePicker.pickFiles(), isEmpty);
      expect(await FilePicker.pickFile(), isNull);
      expect(
        await FilePicker.saveFile(
          fileName: 'export.txt',
          bytes: Uint8List.fromList([4, 5]),
        ),
        Uri.parse('file://docs/export.txt'),
      );
      await FilePicker.clearTemporaryFiles();
      expect(calls.last.method, 'clearTemporaryFiles');
      await expectLater(FilePicker.getDirectoryPath(), throwsUnsupportedError);
    },
  );
}
