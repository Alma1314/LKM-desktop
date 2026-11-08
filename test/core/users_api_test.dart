import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:island/core/api/api_client.dart';
import 'package:island/core/api/users_api.dart';

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

UsersApi _api(_Adapter adapter) => UsersApi(
  ApiClient(
    serverUrl: 'https://lkm-ahz.ltd',
    dio: Dio()..httpClientAdapter = adapter,
  ),
);

const _profile = {
  'user_id': '11111111-1111-1111-1111-111111111111',
  'nickname': '阿尔玛',
  'avatar': 'https://lkm-ahz.ltd/a.png',
  'role': 'member',
  'contact_links': <Object>[],
};

void main() {
  test('reads a profile by id', () async {
    final adapter = _Adapter((_) => _ok(_profile));

    final profile = await _api(
      adapter,
    ).profile('11111111-1111-1111-1111-111111111111');

    expect(
      adapter.requests.single.uri.path,
      '/api/v1/auth/11111111-1111-1111-1111-111111111111',
    );
    expect(profile.displayName, '阿尔玛');
    expect(profile.role, 'member');
    expect(profile.avatar, 'https://lkm-ahz.ltd/a.png');
  });

  test('reads a profile by username', () async {
    final adapter = _Adapter((_) => _ok(_profile));

    await _api(adapter).profileByUsername('alma');

    expect(
      adapter.requests.single.uri.path,
      '/api/v1/auth/user/by-username/alma',
    );
  });

  test('reads and toggles the follow state', () async {
    final adapter = _Adapter((options) {
      if (options.method == 'GET') return _ok({'is_following': true});
      if (options.method == 'POST') return _ok({'following': true});
      return _ok({'following': false});
    });

    final api = _api(adapter);
    final id = '11111111-1111-1111-1111-111111111111';

    expect(await api.followStatus(id), isTrue);
    expect(await api.setFollow(id, follow: true), isTrue);
    expect(await api.setFollow(id, follow: false), isFalse);

    expect(adapter.requests[0].uri.path, '/api/v1/users/$id/follow/status');
    expect(adapter.requests[1].method, 'POST');
    expect(adapter.requests[1].uri.path, '/api/v1/users/$id/follow');
    expect(adapter.requests[2].method, 'DELETE');
  });

  test('maps the following list', () async {
    final adapter = _Adapter(
      (_) => _ok({
        'items': [
          {
            'user_id': '22222222-2222-2222-2222-222222222222',
            'display_name': 'bob',
            'avatar': null,
          },
        ],
      }),
    );

    final following = await _api(adapter).following();

    expect(adapter.requests.single.uri.path, '/api/v1/users/me/following');
    expect(following.single.userId, '22222222-2222-2222-2222-222222222222');
    expect(following.single.displayName, 'bob');
    expect(following.single.avatar, isNull);
  });
}
