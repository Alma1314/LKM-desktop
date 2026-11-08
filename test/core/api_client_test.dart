import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:island/core/api/api_client.dart';

/// Serves canned responses without touching the network.
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.handler);

  final ResponseBody Function(RequestOptions options) handler;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _jsonBody(
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

ApiClient _clientWith(
  ResponseBody Function(RequestOptions options) handler, {
  String serverUrl = 'https://lkm-ahz.ltd',
  Future<String?> Function()? tokenProvider,
  List<RequestOptions>? recorded,
}) {
  final adapter = _FakeAdapter(handler);
  final dio = Dio()..httpClientAdapter = adapter;
  recorded?.addAll(adapter.requests);
  return ApiClient(
    serverUrl: serverUrl,
    dio: dio,
    tokenProvider: tokenProvider,
  );
}

void main() {
  group('normalizeApiBase', () {
    test('appends the API prefix to a bare host', () {
      expect(
        normalizeApiBase('https://lkm-ahz.ltd'),
        'https://lkm-ahz.ltd/api/v1',
      );
    });

    test('tolerates a trailing slash', () {
      expect(
        normalizeApiBase('http://127.0.0.1:8000/'),
        'http://127.0.0.1:8000/api/v1',
      );
    });

    test('does not duplicate an already qualified base', () {
      expect(
        normalizeApiBase('https://lkm-ahz.ltd/api/v1/'),
        'https://lkm-ahz.ltd/api/v1',
      );
    });

    test('rejects empty and scheme-less input', () {
      expect(() => normalizeApiBase('  '), throwsArgumentError);
      expect(() => normalizeApiBase('lkm-ahz.ltd'), throwsArgumentError);
    });
  });

  group('ApiClient envelope', () {
    test('returns data when code is 0', () async {
      final client = _clientWith(
        (_) => _jsonBody({
          'code': 0,
          'message': 'ok',
          'data': {'id': 7, 'username': 'alma'},
          'request_id': 'rid-1',
        }),
      );

      final me = await client.getObject('/auth/me');
      expect(me['id'], 7);
      expect(me['username'], 'alma');
      client.close();
    });

    test('raises a namespaced ApiException on HTTP 200 + code != 0', () async {
      final client = _clientWith(
        (_) => _jsonBody({
          'code': ApiCode.authInvalidCredentials,
          'message': '用户名或密码错误',
          'request_id': 'rid-2',
        }),
      );

      await expectLater(
        client.post('/auth/login/password', body: {'username': 'a'}),
        throwsA(
          isA<ApiException>()
              .having((e) => e.code, 'code', 65538)
              .having((e) => e.message, 'message', '用户名或密码错误')
              .having((e) => e.requestId, 'requestId', 'rid-2')
              .having((e) => e.isUnauthenticated, 'isUnauthenticated', isFalse),
        ),
      );
      client.close();
    });

    test('maps an envelope-less 500 onto the internal-error code', () async {
      final client = _clientWith(
        (_) => ResponseBody.fromString('upstream exploded', 500),
      );

      await expectLater(
        client.get('/timeline'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.code, 'code', ApiCode.internalError)
              .having((e) => e.statusCode, 'statusCode', 500),
        ),
      );
      client.close();
    });

    test('wraps transport failures', () async {
      final client = _clientWith((options) {
        throw DioException(
          requestOptions: options,
          type: DioExceptionType.connectionError,
          message: 'refused',
        );
      });

      await expectLater(
        client.get('/timeline'),
        throwsA(
          isA<ApiTransportException>().having(
            (e) => e.message,
            'message',
            '无法连接服务器',
          ),
        ),
      );
      client.close();
    });

    test('attaches the bearer token from the provider', () async {
      final seen = <RequestOptions>[];
      final adapter = _FakeAdapter(
        (_) => _jsonBody({'code': 0, 'message': 'ok', 'data': null}),
      );
      final dio = Dio()..httpClientAdapter = adapter;
      final client = ApiClient(
        serverUrl: 'https://lkm-ahz.ltd',
        dio: dio,
        tokenProvider: () async => 'token-abc',
      );

      await client.get('/auth/me');
      seen.addAll(adapter.requests);
      expect(seen.single.headers['Authorization'], 'Bearer token-abc');
      expect(
        seen.single.uri.toString(),
        'https://lkm-ahz.ltd/api/v1/auth/me',
      );
      client.close();
    });
  });

  group('ApiClient pagination', () {
    test('reads items and totals from the envelope', () async {
      final client = _clientWith(
        (_) => _jsonBody({
          'code': 0,
          'message': 'ok',
          'data': {
            'items': [
              {'id': 1},
              {'id': 2},
            ],
            'total': 42,
            'page': 2,
            'pages': 5,
          },
        }),
      );

      final page = await client.getPage<int>(
        '/content/items',
        parseItem: (json) => json['id'] as int,
      );

      expect(page.items, [1, 2]);
      expect(page.total, 42);
      expect(page.page, 2);
      expect(page.hasMore, isTrue);
      client.close();
    });

    test('reads a bare list and falls back to the X-Total header', () async {
      final client = _clientWith(
        (_) => _jsonBody(
          {
            'code': 0,
            'message': 'ok',
            'data': [
              {'id': 5},
            ],
          },
          headers: {
            'x-total': ['9'],
          },
        ),
      );

      final page = await client.getPage<int>(
        '/search',
        parseItem: (json) => json['id'] as int,
      );

      expect(page.items, [5]);
      expect(page.total, 9);
      client.close();
    });

    test('returns an empty page for a null payload', () async {
      final client = _clientWith(
        (_) => _jsonBody({'code': 0, 'message': 'ok', 'data': null}),
      );

      final page = await client.getPage<int>(
        '/notification/me',
        parseItem: (json) => json['id'] as int,
      );

      expect(page.isEmpty, isTrue);
      expect(page.total, 0);
      client.close();
    });
  });

  group('ApiCode', () {
    test('recognises both spellings of an unauthenticated caller', () {
      expect(ApiCode.isUnauthenticated(ApiCode.unauthorized), isTrue);
      expect(ApiCode.isUnauthenticated(ApiCode.authTokenExpired), isTrue);
      expect(ApiCode.isUnauthenticated(ApiCode.authTokenInvalid), isTrue);
      expect(
        ApiCode.isUnauthenticated(ApiCode.authInvalidCredentials),
        isFalse,
      );
    });
  });
}
