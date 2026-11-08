import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:island/core/api/api_client.dart';
import 'package:island/core/api/search_api.dart';

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

ResponseBody _ok(Object? data) => ResponseBody.fromString(
  jsonEncode({'code': 0, 'message': 'ok', 'data': data}),
  200,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

SearchApi _api(_Adapter adapter) => SearchApi(
  ApiClient(
    serverUrl: 'https://lkm-ahz.ltd',
    dio: Dio()..httpClientAdapter = adapter,
  ),
);

const _hitJson = {
  'id': '11111111-1111-1111-1111-111111111111',
  'content_type': 'discussion',
  'board_id': null,
  'title': '拉格朗日点',
  'excerpt': '五个特解',
  'slug': null,
  'author_id': '22222222-2222-2222-2222-222222222222',
  'author_name': 'alma',
  'like_count': 3,
  'comment_count': 1,
  'view_count': 42,
  'published_at': null,
  'created_at': '2026-11-08T12:30:00+00:00',
  'document_code': null,
  'version': null,
  'project_id': null,
};

void main() {
  test('searches with q and pagination', () async {
    final adapter = _Adapter(
      (_) => _ok({
        'items': [_hitJson],
        'total': 1,
        'page': 1,
        'pages': 1,
      }),
    );

    final page = await _api(
      adapter,
    ).search('拉格朗日', contentType: 'discussion', page: 1, limit: 10);

    final request = adapter.requests.single;
    expect(request.uri.path, '/api/v1/search');
    expect(request.queryParameters, {
      'q': '拉格朗日',
      'content_type': 'discussion',
      'page': '1',
      'limit': '10',
    });
    expect(page.total, 1);

    final hit = page.items.single;
    expect(hit.title, '拉格朗日点');
    expect(hit.excerpt, '五个特解');
    expect(hit.authorName, 'alma');
    expect(hit.likeCount, 3);
    expect(hit.createdAt.isUtc, isFalse);
  });

  test('omits the content type filter when absent', () async {
    final adapter = _Adapter(
      (_) => _ok({'items': <Object>[], 'total': 0, 'page': 1, 'pages': 1}),
    );

    await _api(adapter).search('x');

    expect(adapter.requests.single.queryParameters, {
      'q': 'x',
      'page': '1',
      'limit': '20',
    });
  });
}
