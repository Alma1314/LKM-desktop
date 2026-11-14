import 'dart:async';
import 'dart:io';

import 'package:cross_file/cross_file.dart';
import 'package:file_picker_platform_interface/file_picker_platform_interface.dart';
import 'package:flutter/services.dart';

const MethodChannel _channel = MethodChannel(
  'miguelruivo.flutter.plugins.filepicker',
  StandardMethodCodec(),
);

/// OHOS implementation of file_picker backed by DocumentViewPicker.
class FilePickerOhos extends FilePickerPlatform {
  static void registerWith() {
    FilePickerPlatform.instance = FilePickerOhos();
  }

  Future<List<OhosPlatformFile>> _pick({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    bool multiple = false,
    Function(FilePickerStatus)? onFileLoading,
  }) async {
    onFileLoading?.call(FilePickerStatus.picking);
    try {
    final List<Object?> uris = await _channel.invokeListMethod<String>(
          'pickFiles',
          <String, dynamic>{
            'dialogTitle': dialogTitle,
            'initialDirectory': initialDirectory,
            'type': type.index,
            'allowedExtensions': allowedExtensions,
            'multiple': multiple,
          },
        ) ??
        <Object?>[];
    return uris
        .whereType<String>()
        .map((String uri) => OhosPlatformFile(Uri.parse(uri)))
        .toList();
    } finally {
      onFileLoading?.call(FilePickerStatus.done);
    }
  }

  @override
  Future<PlatformFile?> pickFile({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    AndroidOptions androidOptions = const AndroidOptions(),
    DarwinOptions darwinOptions = const DarwinOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async {
    final files = await _pick(
      dialogTitle: dialogTitle,
      initialDirectory: initialDirectory,
      type: type,
      allowedExtensions: allowedExtensions,
      onFileLoading: onFileLoading,
    );
    return files.isEmpty ? null : files.first;
  }

  @override
  Future<List<PlatformFile>> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    AndroidOptions androidOptions = const AndroidOptions(),
    DarwinOptions darwinOptions = const DarwinOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async => _pick(
    dialogTitle: dialogTitle,
    initialDirectory: initialDirectory,
    type: type,
    allowedExtensions: allowedExtensions,
    multiple: true,
    onFileLoading: onFileLoading,
  );

  @override
  Future<List<String>> pickFileAndDirectoryPaths({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
  }) async {
    throw UnsupportedError('OHOS document providers do not expose absolute directory paths. Use pickFiles or saveFile.');
  }

  @override
  Future<String?> getDirectoryPath({
    String? dialogTitle,
    String? initialDirectory,
    AndroidOptions androidOptions = const AndroidOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async {
    throw UnsupportedError('OHOS document providers do not expose absolute directory paths. Use saveFile to export a file.');
  }

  @override
  Future<Uri?> saveFile({
    required String fileName,
    required Uint8List bytes,
    String mimeType = 'application/octet-stream',
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileSaving,
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async {
    onFileSaving?.call(FilePickerStatus.picking);
    try {
    final String? uri = await _channel.invokeMethod<String>('saveFile', <String, dynamic>{
      'fileName': fileName,
      'bytes': bytes,
      'mimeType': mimeType,
      'dialogTitle': dialogTitle,
      'initialDirectory': initialDirectory,
      'type': type.index,
      'allowedExtensions': allowedExtensions,
    });
    return uri == null ? null : Uri.parse(uri);
    } finally {
      onFileSaving?.call(FilePickerStatus.done);
    }
  }

  @override
  Future<void> clearTemporaryFiles() => _channel.invokeMethod<void>('clearTemporaryFiles');
}

base class OhosPlatformFile extends PlatformFile {
  OhosPlatformFile(this.uri, {int? size}) : _size = size;

  @override
  final Uri uri;
  final int? _size;

  @override
  String get name {
    final String last = uri.pathSegments.isEmpty ? uri.toString() : uri.pathSegments.last;
    return last.isEmpty ? uri.toString() : last;
  }

  String? get path => uri.scheme == 'file' && uri.authority.isEmpty ? uri.toFilePath() : null;

  @override
  XFile get xFile => XFile(path ?? uri.toString());

  @override
  int? lengthSync() => _size ?? (path == null ? null : File(path!).lengthSync());

  @override
  Future<int?> length() async => _size ?? File(path ?? uri.toString()).length();

  @override
  Future<Uint8List> readAsBytes() =>
      File(path ?? uri.toString()).readAsBytes();

  @override
  Stream<Uint8List> readAsByteStream() =>
      File(path ?? uri.toString())
          .openRead()
          .map((List<int> chunk) => Uint8List.fromList(chunk));
}
