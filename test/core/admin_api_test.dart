import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:island/core/api/admin_api.dart';
import 'package:island/core/api/api_client.dart';

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

ResponseBody _json(
  Object? body, {
  int status = 200,
  Map<String, List<String>>? headers,
}) => ResponseBody.fromString(
  jsonEncode(body),
  status,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
    ...?headers,
  },
);

ResponseBody _envelope(
  Object? data, {
  Map<String, List<String>>? headers,
}) => _json({'code': 0, 'message': 'ok', 'data': data}, headers: headers);

ResponseBody _failure(int code, String message) =>
    _json({'code': code, 'message': message, 'data': null}, status: 403);

/// A syntactically valid JWT whose `exp` is far enough in the future that
/// `_ensureFresh` does not rotate it before the call under test.
String _token({Duration ttl = const Duration(hours: 1), String id = ''}) {
  final payload = base64Url
      .encode(
        utf8.encode(
          jsonEncode({
            'exp':
                DateTime.now().add(ttl).millisecondsSinceEpoch ~/ 1000,
            'jti': id,
          }),
        ),
      )
      .replaceAll('=', '');
  return 'header.$payload.signature';
}

ApiClient _client(_Adapter adapter) => ApiClient(
  serverUrl: 'https://community.example',
  dio: Dio()..httpClientAdapter = adapter,
);

Future<AdminApi> _api(_Adapter adapter) async {
  final prefs = await SharedPreferences.getInstance();
  return AdminApi(client: _client(adapter), prefs: prefs);
}

Map<String, List<String>> _cookies(String access, String refresh) => {
  'set-cookie': [
    'admin_session=$access; Path=/; Max-Age=900',
    'admin_refresh=$refresh; Path=/; Max-Age=86400',
  ],
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('login stores both cookies and reads /admin/auth/me', () async {
    final access = _token();
    final adapter = _Adapter((options) {
      if (options.path == '/admin/auth/login') {
        expect(options.data, {'username': 'root', 'password': 'pw'});
        return _envelope(
          {'id': 'u1'},
          headers: _cookies(access, 'refresh-1'),
        );
      }
      expect(options.path, '/admin/auth/me');
      expect(options.headers['Cookie'], 'admin_session=$access');
      return _envelope({
        'id': 'u1',
        'account_level': 'admin',
        'role': 'super_admin',
        'permissions': ['admin.dashboard', 'admin.content_review'],
      });
    });
    final api = await _api(adapter);

    final me = await api.login('root', 'pw');

    expect(api.isSignedIn, isTrue);
    expect(me.role, 'super_admin');
    expect(me.can('admin.content_review'), isTrue);
    expect(me.can('admin.bot_panel'), isFalse);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(kAdminAccessTokenKey), access);
    expect(prefs.getString(kAdminRefreshTokenKey), 'refresh-1');
  });

  test('a failed login surfaces the server message and keeps no session', () async {
    final adapter = _Adapter(
      (options) => _failure(ApiCode.forbidden, '用户名或密码错误'),
    );
    final api = await _api(adapter);

    await expectLater(
      api.login('root', 'wrong'),
      throwsA(
        isA<ApiException>().having(
          (e) => e.message,
          'message',
          '用户名或密码错误',
        ),
      ),
    );
    expect(api.isSignedIn, isFalse);
  });

  test('expired admin session refreshes once and replays the call', () async {
    // Both carry a future `exp`, so the local pre-check does not rotate; the
    // server is the one rejecting the stale cookie.
    final expired = _token(id: 'old');
    final fresh = _token(id: 'new');
    final adapter = _Adapter((options) {
      if (options.path == '/admin/auth/refresh') {
        expect(options.headers['Cookie'], 'admin_refresh=refresh-old');
        return _envelope(
          {'ok': true},
          headers: _cookies(fresh, 'refresh-new'),
        );
      }
      if (options.headers['Cookie'] == 'admin_session=$expired') {
        return _failure(ApiCode.forbidden, 'Admin session invalid or expired');
      }
      expect(options.headers['Cookie'], 'admin_session=$fresh');
      return _envelope({
        'items': [
          {
            'id': 'r1',
            'pattern': 'spam',
            'is_regex': false,
            'action': 'hide',
            'weight': 0.7,
            'scope': 'content',
            'enabled': true,
          },
        ],
      });
    });
    final api = await _api(adapter);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(kAdminAccessTokenKey, expired);
    await prefs.setString(kAdminRefreshTokenKey, 'refresh-old');
    api.restore();

    final rules = await api.rules();

    expect(rules.single.pattern, 'spam');
    expect(rules.single.weight, 0.7);
    expect(adapter.requests.map((r) => r.path), [
      '/admin/moderation/rules',
      '/admin/auth/refresh',
      '/admin/moderation/rules',
    ]);
    expect(prefs.getString(kAdminRefreshTokenKey), 'refresh-new');
  });

  test('content list filters by type and delete hits the item path', () async {
    final access = _token();
    final adapter = _Adapter((options) {
      if (options.method == 'DELETE') {
        expect(options.path, '/admin/content/item/c1');
        return _envelope({'ok': true});
      }
      expect(options.queryParameters['content_type'], 'discussion');
      return _envelope({
        'items': [
          {
            'id': 'c1',
            'content_type': 'discussion',
            'title': 'Hello',
            'author_name': 'alice',
            'status': 'published',
            'created_at': '2026-11-01T00:00:00Z',
            'view_count': 3,
            'like_count': 2,
            'comment_count': 1,
            'is_pinned': false,
            'is_featured': true,
          },
        ],
        'total': 1,
        'page': 1,
        'pages': 1,
      });
    });
    final api = await _api(adapter);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(kAdminAccessTokenKey, access);
    await prefs.setString(kAdminRefreshTokenKey, 'r');
    api.restore();

    final page = await api.contentItems(contentType: 'discussion');
    await api.deleteContentItem('c1');

    expect(page.items.single.title, 'Hello');
    expect(page.items.single.isFeatured, isTrue);
    expect(adapter.requests.last.path, '/admin/content/item/c1');
  });

  test('reports and files decode pagination and batch review payload', () async {
    final access = _token();
    final adapter = _Adapter((options) {
      if (options.path == '/files/review-batch') {
        expect(options.data, {
          'file_ids': ['f1', 'f2'],
          'status': 'rejected',
          'review_comment': 'bad',
        });
        return _envelope({
          'results': [
            {'file_id': 'f1', 'ok': true, 'status': 'rejected'},
            {'file_id': 'f2', 'ok': false, 'error': 'gone'},
          ],
          'succeeded': 1,
          'failed': 1,
        });
      }
      if (options.path == '/admin/reports') {
        expect(options.queryParameters['status'], 'pending');
        return _envelope({
          'items': [
            {
              'id': 'rep1',
              'type': 'post',
              'target_id': 'c1',
              'target_title': 'Hello',
              'reporter_name': 'bob',
              'reason': 'spam',
              'status': 'pending',
              'created_at': '2026-11-02T00:00:00Z',
              'handled_at': null,
            },
          ],
          'total': 1,
          'page': 1,
          'pages': 1,
        });
      }
      expect(options.path, '/files');
      expect(options.queryParameters['status'], 'pending');
      return _envelope({
        'items': [
          {
            'id': 'f1',
            'original_name': 'a.pdf',
            'uploader_name': 'alice',
            'mime_type': 'application/pdf',
            'size': 120,
            'status': 'pending',
            'classification': 'public',
            'created_at': '2026-11-03T00:00:00Z',
          },
        ],
        'total': 1,
        'page': 1,
        'pages': 1,
      });
    });
    final api = await _api(adapter);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(kAdminAccessTokenKey, access);
    await prefs.setString(kAdminRefreshTokenKey, 'r');
    api.restore();

    final reports = await api.reports(status: 'pending');
    final files = await api.files();
    final result = await api.reviewFiles(
      fileIds: ['f1', 'f2'],
      status: 'rejected',
      comment: 'bad',
    );

    expect(reports.items.single.reporterName, 'bob');
    expect(files.items.single.uploaderName, 'alice');
    expect(result.succeeded, 1);
    expect(result.results.last.error, 'gone');
  });

  test('dlq list, requeue and discard use the admin paths', () async {
    final access = _token();
    final adapter = _Adapter((options) {
      if (options.method == 'GET') {
        expect(options.queryParameters['status'], 'discarded');
        return _envelope({
          'items': [
            {
              'id': 'd1',
              'routing_key': 'content.liked',
              'status': 'discarded',
              'attempts': 3,
              'reason': 'boom',
              'created_at': '2026-11-04T00:00:00Z',
              'payload': {'x': 1},
            },
          ],
        });
      }
      return _envelope({'ok': true});
    });
    final api = await _api(adapter);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(kAdminAccessTokenKey, access);
    await prefs.setString(kAdminRefreshTokenKey, 'r');
    api.restore();

    final items = await api.dlq(status: 'discarded');
    await api.requeueDlq('d1');
    await api.discardDlq('d1');

    expect(items.single.routingKey, 'content.liked');
    expect(adapter.requests.map((r) => r.path), [
      '/admin/dlq',
      '/admin/dlq/d1/requeue',
      '/admin/dlq/d1/discard',
    ]);
  });

  test('MFA_REQUIRED is passed through so the UI can step up', () async {
    final access = _token();
    final adapter = _Adapter(
      (options) => _failure(ApiCode.mfaRequired, 'MFA required'),
    );
    final api = await _api(adapter);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(kAdminAccessTokenKey, access);
    await prefs.setString(kAdminRefreshTokenKey, 'r');
    api.restore();

    await expectLater(
      api.deleteRule('rule1'),
      throwsA(isA<ApiException>().having((e) => e.code, 'code', ApiCode.mfaRequired)),
    );
    expect(adapter.requests, hasLength(1));
  });
}
