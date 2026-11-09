import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:island/core/api/api_client.dart';
import 'package:island/core/api/content_api.dart';

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

ContentApi _api(_Adapter adapter) => ContentApi(
  ApiClient(
    serverUrl: 'https://lkm-ahz.ltd',
    dio: Dio()..httpClientAdapter = adapter,
  ),
);

const _graphItem = {
  'id': '11111111-1111-1111-1111-111111111111',
  'contentType': 'discussion',
  'boardId': '22222222-2222-2222-2222-222222222222',
  'authorId': '33333333-3333-3333-3333-333333333333',
  'authorName': 'alma',
  'publisher': null,
  'department': null,
  'columnId': null,
  'columnTitle': '',
  'qaQuestionId': null,
  'slug': null,
  'title': '拉格朗日点',
  'excerpt': '五个特解',
  'summary': null,
  'cover': null,
  'keywords': <String>[],
  'content': '正文 **markdown**',
  'tags': ['物理'],
  'status': 'published',
  'isPinned': false,
  'isFeatured': true,
  'viewCount': 42,
  'likeCount': 3,
  'commentCount': 2,
  'bookmarkCount': 1,
  'forwardCount': 0,
  'readingTime': 3,
  'createdAt': '2026-11-08T12:30:00+00:00',
  'publishedAt': '2026-11-08T12:30:00+00:00',
  'version': 1,
};

void main() {
  test('queries contentItem over /graphql/v1 and maps camelCase', () async {
    final adapter = _Adapter(
      (_) => _json({
        'data': {'contentItem': _graphItem},
      }),
    );

    final item = await _api(adapter).item(_graphItem['id'] as String);

    final request = adapter.requests.single;
    expect(request.method, 'POST');
    expect(request.uri.toString(), 'https://lkm-ahz.ltd/graphql/v1');
    expect((request.data as Map)['variables'], {'id': _graphItem['id']});
    expect((request.data as Map)['query'], contains('contentItem'));

    expect(item, isNotNull);
    expect(item!.title, '拉格朗日点');
    expect(item.content, '正文 **markdown**');
    expect(item.authorName, 'alma');
    expect(item.viewCount, 42);
    expect(item.tags, ['物理']);
    expect(item.createdAt.isUtc, isFalse);
  });

  test('a missing content item reads as null', () async {
    final adapter = _Adapter(
      (_) => _json({
        'data': {'contentItem': null},
      }),
    );

    expect(await _api(adapter).item('missing'), isNull);
  });

  test('GraphQL errors become ApiException', () async {
    final adapter = _Adapter(
      (_) => _json({
        'data': null,
        'errors': [
          {'message': '权限不足'},
        ],
      }),
    );

    await expectLater(
      _api(adapter).item('x'),
      throwsA(isA<ApiException>().having((e) => e.message, 'message', '权限不足')),
    );
  });

  test('comments are requested with paging and mapped', () async {
    final adapter = _Adapter(
      (_) => _json({
        'data': {
          'contentComments': {
            'items': [
              {
                'id': 'c1',
                'contentId': _graphItem['id'],
                'authorId': 'u1',
                'authorName': 'bob',
                'content': '好问题',
                'floorNumber': 1,
                'parentId': null,
                'likeCount': 0,
                'liked': false,
                'createdAt': '2026-11-08T13:00:00+00:00',
              },
            ],
            'total': 1,
            'page': 2,
            'pages': 3,
          },
        },
      }),
    );

    final page = await _api(
      adapter,
    ).comments(_graphItem['id'] as String, page: 2, pageSize: 10);

    final request = adapter.requests.single;
    expect((request.data as Map)['variables'], {
      'itemId': _graphItem['id'],
      'page': 2,
      'pageSize': 10,
    });
    expect(page.total, 1);
    expect(page.page, 2);
    expect(page.pages, 3);
    expect(page.hasMore, isTrue);
    expect(page.items.single.authorName, 'bob');
    expect(page.items.single.floorNumber, 1);
  });

  test('posting a comment uses the REST write endpoint', () async {
    final adapter = _Adapter((_) => _envelope({'id': 'c1'}));

    await _api(adapter).addComment(_graphItem['id'] as String, '第一次回复');

    final request = adapter.requests.single;
    expect(request.method, 'POST');
    expect(
      request.uri.path,
      '/api/v1/content/items/${_graphItem['id']}/comments',
    );
    expect(request.data, {'content': '第一次回复'});
  });

  test('viewer state comes from GraphQL and maps camelCase', () async {
    final adapter = _Adapter(
      (_) => _json({
        'data': {
          'contentViewerState': {
            'liked': true,
            'favorited': false,
            'likeCount': 7,
            'bookmarkCount': 2,
          },
        },
      }),
    );

    final state = await _api(
      adapter,
    ).viewerState(_graphItem['id'] as String);

    final request = adapter.requests.single;
    expect(request.uri.toString(), 'https://lkm-ahz.ltd/graphql/v1');
    expect((request.data as Map)['variables'], {'contentId': _graphItem['id']});
    expect(state!.liked, isTrue);
    expect(state.favorited, isFalse);
    expect(state.likeCount, 7);
    expect(state.bookmarkCount, 2);
  });

  test('like and unlike are separate verbs returning the new count', () async {
    var likes = 0;
    final adapter = _Adapter((options) {
      likes += options.method == 'POST' ? 1 : -1;
      return _envelope({'like_count': likes});
    });
    final api = _api(adapter);
    final id = _graphItem['id'] as String;

    expect(await api.like(id), 1);
    expect(await api.unlike(id), 0);

    expect(adapter.requests[0].method, 'POST');
    expect(adapter.requests[1].method, 'DELETE');
    expect(
      adapter.requests.map((r) => r.uri.path).toSet(),
      {'/api/v1/content/items/$id/like'},
    );
  });

  test('favorite toggles over the interaction endpoint', () async {
    final adapter = _Adapter(
      (_) => _envelope({
        'content_id': 'x',
        'favorited': true,
        'bookmark_count': 9,
      }),
    );

    final count = await _api(
      adapter,
    ).favorite(_graphItem['id'] as String, favorited: true);

    expect(count, 9);
    expect(
      adapter.requests.single.uri.path,
      '/api/v1/interaction/favorites/${_graphItem['id']}',
    );
    expect(adapter.requests.single.method, 'POST');
  });

  test('forward returns the bumped count and reports the view', () async {
    final adapter = _Adapter((options) {
      return _envelope(
        options.uri.path.endsWith('/forward') ? {'forward_count': 5} : null,
      );
    });
    final api = _api(adapter);
    final id = _graphItem['id'] as String;

    expect(await api.forward(id), 5);
    await api.reportView(id);

    expect(adapter.requests.map((r) => r.uri.path), [
      '/api/v1/content/items/$id/forward',
      '/api/v1/interaction/views/$id',
    ]);
  });

  test('reports carry target type/id and a reason', () async {
    final adapter = _Adapter((_) => _envelope(null));

    await _api(adapter).report(
      targetType: 'post',
      targetId: _graphItem['id'] as String,
      reason: '垃圾内容',
    );

    final request = adapter.requests.single;
    expect(request.uri.path, '/api/v1/content/reports');
    expect(request.data, {
      'target_type': 'post',
      'target_id': _graphItem['id'],
      'reason': '垃圾内容',
    });
  });

  test('boards load over GraphQL and expose their status', () async {
    final adapter = _Adapter(
      (_) => _json({
        'data': {
          'boards': [
            {
              'id': 'b1',
              'slug': 'general',
              'title': '综合',
              'parentId': null,
              'status': 'active',
              'isPublic': true,
            },
            {
              'id': 'b2',
              'slug': 'locked',
              'title': '只读',
              'parentId': null,
              'status': 'frozen',
              'isPublic': true,
            },
          ],
        },
      }),
    );

    final boards = await _api(adapter).boards();

    expect(adapter.requests.single.uri.toString(), 'https://lkm-ahz.ltd/graphql/v1');
    expect(boards.map((b) => b.id), ['b1', 'b2']);
    expect(boards.first.isActive, isTrue);
    expect(boards.last.isActive, isFalse);
  });

  test('creating a discussion posts the REST write shape', () async {
    final adapter = _Adapter((_) => _envelope({'id': 'new-1'}));

    final id = await _api(adapter).createDiscussion(
      boardId: 'b1',
      title: '标题',
      content: '正文',
      tags: const ['物理'],
    );

    final request = adapter.requests.single;
    expect(id, 'new-1');
    expect(request.method, 'POST');
    expect(request.uri.path, '/api/v1/content/items');
    expect(request.data, {
      'content_type': 'discussion',
      'board_id': 'b1',
      'title': '标题',
      'content': '正文',
      'tags': ['物理'],
    });
  });

  test('deleting a post uses DELETE', () async {
    final adapter = _Adapter((_) => _envelope(null));

    await _api(adapter).deleteItem('item-9');

    expect(adapter.requests.single.method, 'DELETE');
    expect(adapter.requests.single.uri.path, '/api/v1/content/items/item-9');
  });

  test('comment like uses the nested endpoint', () async {
    final adapter = _Adapter((_) => _envelope({'like_count': 3}));

    final count = await _api(
      adapter,
    ).likeComment(_graphItem['id'] as String, 'c1');

    expect(count, 3);
    expect(adapter.requests.single.method, 'POST');
    expect(
      adapter.requests.single.uri.path,
      '/api/v1/content/items/${_graphItem['id']}/comments/c1/like',
    );
  });
}
