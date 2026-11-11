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
    this.uploaderName = '',
    this.categoryId = '',
    this.categoryName = '',
    this.description = '',
    this.tags = const [],
    this.reviewComment,
    this.downloadCount = 0,
    this.viewCount = 0,
    this.version = 1,
    this.rootFileId,
    this.createdAt,
  });

  final String id;
  final String originalName;
  final String mimeType;
  final int size;
  final String status;
  final String uploaderName;
  final String categoryId;
  final String categoryName;
  final String description;
  final List<String> tags;
  final String? reviewComment;
  final int downloadCount;
  final int viewCount;
  final int version;
  final String? rootFileId;
  final DateTime? createdAt;

  bool get isPending => status == 'pending';
  bool get isApproved => status == 'approved';
  bool get isRejected => status == 'rejected';

  factory LkmFile.fromJson(Map<String, dynamic> json) {
    final tags = json['tags'];
    return LkmFile(
      id: '${json['id'] ?? ''}',
      originalName: '${json['original_name'] ?? ''}',
      mimeType: '${json['mime_type'] ?? ''}',
      size: json['size'] is num ? (json['size'] as num).toInt() : 0,
      status: '${json['status'] ?? ''}',
      uploaderName: '${json['uploader_name'] ?? ''}',
      categoryId: '${json['category_id'] ?? ''}',
      categoryName: '${json['category_name'] ?? ''}',
      description: '${json['description'] ?? ''}',
      tags: tags is List
          ? tags.whereType<String>().toList(growable: false)
          : const [],
      reviewComment: json['review_comment'] as String?,
      downloadCount: json['download_count'] is num
          ? (json['download_count'] as num).toInt()
          : 0,
      viewCount: json['view_count'] is num
          ? (json['view_count'] as num).toInt()
          : 0,
      version: json['version'] is num ? (json['version'] as num).toInt() : 1,
      rootFileId: json['root_file_id'] as String?,
      createdAt: DateTime.tryParse('${json['created_at'] ?? ''}')?.toLocal(),
    );
  }
}

/// `GET /files/{id}/download/url` — `backend` means the bytes must be fetched
/// through the authenticated `/content` endpoint, `presigned` is a direct link.
class LkmDownloadInfo {
  const LkmDownloadInfo({required this.kind, required this.url});

  final String kind;
  final String url;

  bool get isPresigned => kind == 'presigned';

  factory LkmDownloadInfo.fromJson(Map<String, dynamic> json) =>
      LkmDownloadInfo(
        kind: '${json['kind'] ?? ''}',
        url: '${json['url'] ?? ''}',
      );
}

enum LkmUploadMode { direct, sync }

class LkmUploadInit {
  const LkmUploadInit({required this.mode, this.uploadId, this.presignedUrl});

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

  /// `GET /files` — the library page, already visibility-filtered server-side.
  Future<ApiPage<LkmFile>> files({
    int page = 1,
    int limit = 20,
    String? categoryId,
    String? status,
    String sort = 'newest',
  }) => _client.getPage(
    '/files',
    query: {
      'page': page,
      'limit': limit,
      'category_id': ?categoryId,
      'status': ?status,
      'sort': sort,
    },
    parseItem: LkmFile.fromJson,
  );

  /// `GET /files/{id}/versions` — the uploader's previous revisions.
  Future<List<LkmFile>> versions(String fileId) =>
      _client.getList('/files/$fileId/versions', parseItem: LkmFile.fromJson);

  /// `GET /files/{id}/download/url` — presigned link or backend kind.
  Future<LkmDownloadInfo> downloadUrl(String fileId) async {
    final data = await _client.getObject('/files/$fileId/download/url');
    return LkmDownloadInfo.fromJson(data);
  }

  /// Streams the bytes through the authenticated `/content` endpoint.
  Future<Uint8List> downloadBytes(String fileId) async {
    try {
      final response = await _client.dio.get<dynamic>(
        '/files/$fileId/content',
        options: Options(responseType: ResponseType.bytes),
      );
      final data = response.data;
      if (data is List<int>) return Uint8List.fromList(data);
      if (data is Uint8List) return data;
      return Uint8List(0);
    } on DioException catch (error) {
      throw ApiTransportException('下载失败', cause: error);
    }
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
          headers: {'Content-Type': mimeType, 'Content-Length': bytes.length},
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
