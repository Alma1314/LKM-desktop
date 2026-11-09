import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:http_parser/http_parser.dart';

import 'api_client.dart';

/// A row of the LKM file library. Every upload lands as `pending` and stays
/// invisible to anyone but its uploader until a reviewer approves it.
class LkmFile {
  const LkmFile({
    required this.id,
    required this.originalName,
    required this.mimeType,
    required this.size,
    required this.status,
  });

  final String id;
  final String originalName;
  final String mimeType;
  final int size;
  final String status;

  bool get isPending => status == 'pending';
  bool get isApproved => status == 'approved';
  bool get isRejected => status == 'rejected';

  factory LkmFile.fromJson(Map<String, dynamic> json) => LkmFile(
    id: '${json['id'] ?? ''}',
    originalName: '${json['original_name'] ?? ''}',
    mimeType: '${json['mime_type'] ?? ''}',
    size: json['size'] is num ? (json['size'] as num).toInt() : 0,
    status: '${json['status'] ?? ''}',
  );
}

enum LkmUploadMode { direct, sync }

class LkmUploadInit {
  const LkmUploadInit({
    required this.mode,
    this.uploadId,
    this.presignedUrl,
  });

  final LkmUploadMode mode;
  final String? uploadId;
  final String? presignedUrl;

  factory LkmUploadInit.fromJson(Map<String, dynamic> json) => LkmUploadInit(
    mode: json['mode'] == 'direct' ? LkmUploadMode.direct : LkmUploadMode.sync,
    uploadId: json['upload_id'] as String?,
    presignedUrl: json['presigned_url'] as String?,
  );
}

/// Three-step attachment upload (`upload-init` → presigned PUT → `confirm`)
/// with the multipart fallback the service asks for on non-S3 deployments.
class FilesApi {
  FilesApi(this._client, {Dio? putClient}) : _putClient = putClient ?? Dio();

  final ApiClient _client;

  /// Plain Dio for the presigned PUT: the URL is absolute, must not carry the
  /// service's bearer token, and its signature already authorises the write.
  final Dio _putClient;

  String get _origin {
    final base = _client.baseUrl;
    return base.endsWith(kApiPathPrefix)
        ? base.substring(0, base.length - kApiPathPrefix.length)
        : base;
  }

  /// Inline (image) URL for an approved file. Rendering it still needs the
  /// bearer header — the endpoint requires `files_download`.
  String previewUrl(String fileId) =>
      '$_origin$kApiPathPrefix/files/$fileId/preview';

  Future<LkmUploadInit> uploadInit({
    required String originalName,
    required String mimeType,
    String categoryId = '',
    String description = '',
    List<String> tags = const [],
  }) async {
    final body = await _client.post(
      '/files/upload-init',
      body: {
        'original_name': originalName,
        'mime_type': mimeType,
        'category_id': categoryId,
        'description': description,
        'tags': tags,
      },
    );
    if (body is! Map) {
      throw ApiException(
        code: ApiCode.internalError,
        message: '初始化上传响应格式错误',
        path: '/files/upload-init',
      );
    }
    return LkmUploadInit.fromJson(Map<String, dynamic>.from(body));
  }

  Future<LkmFile> confirm(String uploadId) async {
    final body = await _client.post('/files/$uploadId/confirm');
    if (body is! Map) {
      throw ApiException(
        code: ApiCode.internalError,
        message: '确认上传响应格式错误',
        path: '/files/$uploadId/confirm',
      );
    }
    return LkmFile.fromJson(Map<String, dynamic>.from(body));
  }

  Future<LkmFile> file(String fileId) async {
    return LkmFile.fromJson(await _client.getObject('/files/$fileId'));
  }

  /// Uploads [bytes] and returns the registered row (status `pending`).
  Future<LkmFile> upload({
    required Uint8List bytes,
    required String originalName,
    required String mimeType,
    String categoryId = '',
    String description = '',
    List<String> tags = const [],
    void Function(double? progress)? onProgress,
  }) async {
    final init = await uploadInit(
      originalName: originalName,
      mimeType: mimeType,
      categoryId: categoryId,
      description: description,
      tags: tags,
    );
    if (init.mode == LkmUploadMode.direct &&
        init.presignedUrl != null &&
        init.uploadId != null) {
      await _putClient.put<void>(
        init.presignedUrl!,
        data: Stream.fromIterable([bytes]),
        options: Options(
          headers: {
            'Content-Type': mimeType,
            'Content-Length': bytes.length,
          },
        ),
        onSendProgress: (sent, total) =>
            onProgress?.call(total > 0 ? sent / total : null),
      );
      return confirm(init.uploadId!);
    }
    // Local storage backend: no presigned URL, so send the bytes directly.
    final form = FormData.fromMap({
      'file': MultipartFile.fromBytes(
        bytes,
        filename: originalName,
        contentType: MediaType.parse(mimeType),
      ),
      'category_id': categoryId,
      'description': description,
      'tags': jsonEncode(tags),
    });
    final body = await _client.post('/files', body: form);
    if (body is! Map) {
      throw ApiException(
        code: ApiCode.internalError,
        message: '上传响应格式错误',
        path: '/files',
      );
    }
    return LkmFile.fromJson(Map<String, dynamic>.from(body));
  }
}
