import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:island/core/api/api_client.dart';
import 'package:island/core/api/notification_api.dart';

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

NotificationApi _api(_Adapter adapter) => NotificationApi(
  ApiClient(
    serverUrl: 'https://community.example',
    dio: Dio()..httpClientAdapter = adapter,
  ),
);

const _notificationJson = {
  'id': '11111111-1111-1111-1111-111111111111',
  'type': 'comment_reply',
  'actor_id': '22222222-2222-2222-2222-222222222222',
  'target_id': '33333333-3333-3333-3333-333333333333',
  'payload': {'title': '有人回复了你'},
  'read_at': null,
  'created_at': '2026-11-08T12:30:00+00:00',
};

void main() {
  test('lists notifications with page and unread filter', () async {
    final adapter = _Adapter(
      (_) => _ok({
        'items': [_notificationJson],
        'total': 1,
        'page': 2,
        'pages': 3,
      }),
    );

    final page = await _api(adapter).list(page: 2, limit: 10, unreadOnly: true);

    final request = adapter.requests.single;
    expect(request.uri.path, '/api/v1/notification/me');
    expect(request.queryParameters, {
      'page': '2',
      'limit': '10',
      'unread': 'true',
    });
    expect(page.total, 1);
    expect(page.page, 2);
    expect(page.pages, 3);
    expect(page.hasMore, isTrue);

    final first = page.items.single;
    expect(first.type, 'comment_reply');
    expect(first.payload['title'], '有人回复了你');
    expect(first.readAt, isNull);
    expect(first.createdAt.isUtc, isFalse);
  });

  test('omits the unread filter when not requested', () async {
    final adapter = _Adapter(
      (_) => _ok({'items': <Object>[], 'total': 0, 'page': 1, 'pages': 1}),
    );

    await _api(adapter).list();

    expect(adapter.requests.single.queryParameters, {
      'page': '1',
      'limit': '20',
    });
  });

  test('reads the unread count', () async {
    final adapter = _Adapter((_) => _ok({'unread': 4}));

    expect(await _api(adapter).unreadCount(), 4);
    expect(
      adapter.requests.single.uri.path,
      '/api/v1/notification/me/unread-count',
    );
  });

  test('marks specific ids and everything read', () async {
    final adapter = _Adapter((_) => _ok({'updated': 2}));

    final updated = await _api(adapter).markRead(ids: ['a', 'b']);

    final request = adapter.requests.single;
    expect(request.uri.path, '/api/v1/notification/me/read');
    expect(request.data, {
      'ids': ['a', 'b'],
      'all': false,
    });
    expect(updated, 2);
  });
}
