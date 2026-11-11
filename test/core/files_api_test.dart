import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:island/core/api/api_client.dart';
import 'package:island/core/api/files_api.dart';

class _Adapter implements HttpClientAdapter {
  _Adapter(this.handle);

  final ResponseBody Function(RequestOptions options) handle;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return handle(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(Object? body) => ResponseBody.fromString(
  jsonEncode(body),
  200,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

ResponseBody _envelope(Object? data) =>
    _json({'code': 0, 'message': 'ok', 'data': data});

const _fileRow = {
  'id': 'f1',
  'original_name': 'photo.png',
  'mime_type': 'image/png',
  'size': 3,
  'status': 'pending',
};

void main() {
  test('MIME filtering scans later pages before paginating matches', () async {
    final adapter = _Adapter((options) {
      final page = options.queryParameters['page'] as int;
      return _envelope({
        'items': page == 1
            ? [
                {..._fileRow, 'mime_type': 'application/pdf'},
              ]
            : [_fileRow],
        'total': 2,
        'page': page,
        'pages': 2,
      });
    });
    final api = FilesApi(
      ApiClient(
        serverUrl: 'https://example.com',
        dio: Dio()..httpClientAdapter = adapter,
      ),
    );
    final result = await api.files(mimePrefix: 'image/', limit: 1);
    expect(adapter.requests.length, 2);
    expect(result.items.single.mimeType, 'image/png');
    expect(result.total, 1);
    expect(result.hasMore, isFalse);
  });

  test('upload version uses multipart and correct endpoint', () async {
    final adapter = _Adapter((options) {
      expect(options.path, '/files/f1/versions');
      expect(options.contentType, startsWith('multipart/form-data'));
      expect(options.data, isA<FormData>());
      return _envelope({..._fileRow, 'version': 2});
    });
    final api = FilesApi(
      ApiClient(
        serverUrl: 'https://example.com',
        dio: Dio()..httpClientAdapter = adapter,
      ),
    );
    final file = await api.uploadVersion(
      'f1',
      bytes: Uint8List.fromList([1]),
      originalName: 'photo.png',
      mimeType: 'image/png',
    );
    expect(file.version, 2);
  });

  test('direct upload runs init → presigned PUT → confirm', () async {
    final put = _Adapter((_) => ResponseBody.fromString('', 200));
    var step = 0;
    final api = _Adapter((options) {
      step += 1;
      if (options.uri.path.endsWith('/upload-init')) {
        return _envelope({
          'mode': 'direct',
          'upload_id': 'u1',
          'presigned_url': 'https://s3.example/up/u1?X-Amz-Signature=x',
        });
      }
      return _envelope(_fileRow);
    });
    final files = FilesApi(
      ApiClient(
        serverUrl: 'https://lkm-ahz.ltd',
        dio: Dio()..httpClientAdapter = api,
      ),
      putClient: Dio()..httpClientAdapter = put,
    );

    final file = await files.upload(
      bytes: Uint8List.fromList([1, 2, 3]),
      originalName: 'photo.png',
      mimeType: 'image/png',
    );

    expect(file.id, 'f1');
    expect(file.isPending, isTrue);
    expect(
      step,
      2,
      reason: 'init + confirm reach the service; the PUT does not',
    );

    final init = api.requests.first;
    expect(init.uri.path, '/api/v1/files/upload-init');
    expect(init.data, {
      'original_name': 'photo.png',
      'mime_type': 'image/png',
      'category_id': '',
      'description': '',
      'tags': <String>[],
    });
    expect(api.requests.last.uri.path, '/api/v1/files/u1/confirm');

    final upload = put.requests.single;
    expect(upload.method, 'PUT');
    expect(upload.uri.toString(), 'https://s3.example/up/u1?X-Amz-Signature=x');
    expect(upload.headers['Content-Type'], 'image/png');
    expect(upload.headers['Content-Length'], 3);
    expect(upload.headers.containsKey('Authorization'), isFalse);
  });

  test('a sync-mode server falls back to multipart POST /files', () async {
    final api = _Adapter((options) {
      if (options.uri.path.endsWith('/upload-init')) {
        return _envelope({'mode': 'sync'});
      }
      return _envelope(_fileRow);
    });
    final files = FilesApi(
      ApiClient(
        serverUrl: 'https://lkm-ahz.ltd',
        dio: Dio()..httpClientAdapter = api,
      ),
      putClient: Dio()..httpClientAdapter = _Adapter((_) => _json({})),
    );

    final file = await files.upload(
      bytes: Uint8List.fromList([1, 2, 3]),
      originalName: 'photo.png',
      mimeType: 'image/png',
      categoryId: 'cat',
      description: '图',
      tags: const ['a'],
    );

    expect(file.id, 'f1');
    final request = api.requests.last;
    expect(request.uri.path, '/api/v1/files');
    expect(request.method, 'POST');
    final form = request.data as FormData;
    final fields = Map.fromEntries(form.fields);
    expect(fields['category_id'], 'cat');
    expect(fields['description'], '图');
    expect(fields['tags'], '["a"]');
    expect(form.files.single.key, 'file');
    expect(form.files.single.value.filename, 'photo.png');
  });

  test('previewUrl strips the API prefix and points at the preview route', () {
    final files = FilesApi(
      ApiClient(
        serverUrl: 'https://lkm-ahz.ltd/api/v1',
        dio: Dio()..httpClientAdapter = _Adapter((_) => _json({})),
      ),
    );

    expect(
      files.previewUrl('f1'),
      'https://lkm-ahz.ltd/api/v1/files/f1/preview',
    );
  });

  test('library list forwards filters and parses the full row', () async {
    final api = _Adapter(
      (_) => _json({
        'code': 0,
        'message': 'ok',
        'data': {
          'items': [
            {
              ..._fileRow,
              'status': 'approved',
              'uploader_name': 'alma',
              'category_name': '物理',
              'download_count': 7,
              'view_count': 9,
              'version': 2,
              'tags': ['力学'],
              'created_at': '2026-11-10T10:00:00+00:00',
            },
          ],
          'total': 1,
          'page': 1,
          'pages': 1,
        },
      }),
    );
    final files = FilesApi(
      ApiClient(
        serverUrl: 'https://lkm-ahz.ltd',
        dio: Dio()..httpClientAdapter = api,
      ),
    );

    final page = await files.files(status: 'approved', sort: 'downloads');

    final request = api.requests.single;
    expect(request.uri.path, '/api/v1/files');
    expect(request.uri.queryParameters['status'], 'approved');
    expect(request.uri.queryParameters['sort'], 'downloads');
    expect(page.items.single.categoryName, '物理');
    expect(page.items.single.downloadCount, 7);
    expect(page.items.single.tags, ['力学']);
  });

  test('download url and bytes use their own endpoints', () async {
    var call = 0;
    final api = _Adapter((options) {
      call += 1;
      if (options.uri.path.endsWith('/download/url')) {
        return _envelope({
          'kind': 'presigned',
          'url': 'https://s3.example/dl/f1',
        });
      }
      return ResponseBody.fromBytes([1, 2, 3], 200);
    });
    final files = FilesApi(
      ApiClient(
        serverUrl: 'https://lkm-ahz.ltd',
        dio: Dio()..httpClientAdapter = api,
      ),
    );

    final info = await files.downloadUrl('f1');
    expect(info.isPresigned, isTrue);
    expect(info.url, 'https://s3.example/dl/f1');

    final bytes = await files.downloadBytes('f1');
    expect(bytes, [1, 2, 3]);
    expect(api.requests.last.uri.path, '/api/v1/files/f1/content');
    expect(call, 2);
  });
}
