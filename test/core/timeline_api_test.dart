import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:island/core/api/api_client.dart';
import 'package:island/core/api/timeline_api.dart';

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

TimelineApi _api(_Adapter adapter) => TimelineApi(
  ApiClient(
    serverUrl: 'https://community.example',
    dio: Dio()..httpClientAdapter = adapter,
  ),
);

const _itemJson = {
  'item_type': 'discussion',
  'id': '11111111-1111-1111-1111-111111111111',
  'author_id': '22222222-2222-2222-2222-222222222222',
  'author_name': 'alma',
  'title': '第一条讨论',
  'content_preview': '预览文本',
  'created_at': '2026-11-08T12:30:00+00:00',
  'sort_score': 3.5,
  'board_id': '33333333-3333-3333-3333-333333333333',
  'url': '/forum/post/11111111-1111-1111-1111-111111111111',
};

void main() {
  test('requests the timeline with mode and limit', () async {
    final adapter = _Adapter(
      (_) => _ok({
        'items': [_itemJson],
        'next_cursor': null,
      }),
    );

    final page = await _api(adapter).timeline(mode: 'hot', limit: 10);

    final request = adapter.requests.single;
    expect(request.uri.path, '/api/v1/timeline');
    expect(request.queryParameters, {'mode': 'hot', 'limit': '10'});
    expect(page.nextCursor, isNull);
    expect(page.items, hasLength(1));
  });

  test('sends the cursor only when it exists', () async {
    final adapter = _Adapter(
      (_) => _ok({'items': <Object>[], 'next_cursor': 'abc'}),
    );

    final page = await _api(
      adapter,
    ).timeline(mode: 'follow', cursor: 'abc', limit: 20);

    expect(adapter.requests.single.queryParameters, {
      'mode': 'follow',
      'limit': '20',
      'cursor': 'abc',
    });
    expect(page.nextCursor, 'abc');
  });

  test('maps a feed item and keeps nullable ids', () async {
    final adapter = _Adapter(
      (_) => _ok({
        'items': [
          _itemJson,
          {
            ..._itemJson,
            'item_type': 'article',
            'author_id': null,
            'board_id': null,
          },
        ],
        'next_cursor': null,
      }),
    );

    final page = await _api(adapter).timeline();
    final first = page.items.first;

    expect(first.itemType, 'discussion');
    expect(first.id, _itemJson['id']);
    expect(first.authorName, 'alma');
    expect(first.title, '第一条讨论');
    expect(first.contentPreview, '预览文本');
    expect(first.boardId, _itemJson['board_id']);
    expect(first.url, _itemJson['url']);
    expect(first.createdAt.isUtc, isFalse);
    expect(first.createdAt.toUtc(), DateTime.utc(2026, 11, 8, 12, 30));

    expect(page.items.last.authorId, isNull);
    expect(page.items.last.boardId, isNull);
  });

  test('an empty feed yields no items and no cursor', () async {
    final adapter = _Adapter((_) => _ok({'items': <Object>[]}));

    final page = await _api(adapter).timeline();

    expect(page.items, isEmpty);
    expect(page.nextCursor, isNull);
    expect(page.hasMore, isFalse);
  });

  test('a business error surfaces as ApiException', () async {
    final adapter = _Adapter(
      (_) => ResponseBody.fromString(
        jsonEncode({
          'code': (0 << 16) | 9,
          'message': 'not found',
          'request_id': 'rid',
        }),
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      ),
    );

    await expectLater(_api(adapter).timeline(), throwsA(isA<ApiException>()));
  });
}
