import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:island/core/api/api_client.dart';
import 'package:island/core/api/api_session.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Router implements HttpClientAdapter {
  _Router(this.handle);

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

ResponseBody _envelope(Object? data, {int code = 0, String message = 'ok'}) =>
    ResponseBody.fromString(
      jsonEncode({'code': code, 'message': message, 'data': data}),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );

String _jwt(Duration offset) {
  final exp = DateTime.now().add(offset).millisecondsSinceEpoch ~/ 1000;
  final payload = base64Url
      .encode(utf8.encode(jsonEncode({'exp': exp})))
      .replaceAll('=', '');
  return 'eyJhbGciOiJIUzI1NiJ9.$payload.signature';
}

Future<SharedPreferences> _prefs() async {
  SharedPreferences.setMockInitialValues({});
  return SharedPreferences.getInstance();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('adopt persists the pair and serves a fresh access token', () async {
    final prefs = await _prefs();
    final calls = _Router((_) => _envelope({'access_token': 'x'}));
    final session = ApiSession(
      prefs: prefs,
      serverUrl: 'https://lkm-ahz.ltd',
      dio: Dio()..httpClientAdapter = calls,
      refreshDio: Dio()..httpClientAdapter = calls,
    );

    await session.adopt(
      LkmTokenPair(accessToken: 'access-1', accessExpiresAt: DateTime.now().add(const Duration(hours: 1))),
    );

    expect(session.isSignedIn, isTrue);
    expect(await session.currentAccessToken(), 'access-1');
    expect(prefs.getString(kLkmTokenPairStoreKey), contains('access-1'));
    expect(
      calls.requests.where((r) => r.path.contains('/auth/refresh')),
      isEmpty,
    );
    session.client.close();
  });

  test('an expired access token rotates the pair once and persists it', () async {
    final prefs = await _prefs();
    final router = _Router((options) {
      expect(options.path, contains('/auth/refresh'));
      expect(options.data, {'refresh_token': 'refresh-1'});
      return _envelope({
        'access_token': _jwt(const Duration(hours: 1)),
        'refresh_token': _jwt(const Duration(days: 7)),
      });
    });
    final session = ApiSession(
      prefs: prefs,
      serverUrl: 'https://lkm-ahz.ltd',
      dio: Dio()..httpClientAdapter = router,
      refreshDio: Dio()..httpClientAdapter = router,
    );

    await session.adopt(
      LkmTokenPair(
        accessToken: 'access-old',
        refreshToken: 'refresh-1',
        accessExpiresAt: DateTime.now().subtract(const Duration(minutes: 1)),
        refreshExpiresAt: DateTime.now().add(const Duration(days: 7)),
      ),
    );

    final token = await session.currentAccessToken();

    expect(token, isNotNull);
    expect(token, isNot('access-old'));
    expect(router.requests, hasLength(1));
    expect(prefs.getString(kLkmTokenPairStoreKey), contains(token!));
    session.client.close();
  });

  test('concurrent expiries share one rotation', () async {
    final prefs = await _prefs();
    final router = _Router(
      (_) => _envelope({
        'access_token': _jwt(const Duration(hours: 1)),
        'refresh_token': _jwt(const Duration(days: 7)),
      }),
    );
    final session = ApiSession(
      prefs: prefs,
      serverUrl: 'https://lkm-ahz.ltd',
      dio: Dio()..httpClientAdapter = router,
      refreshDio: Dio()..httpClientAdapter = router,
    );
    await session.adopt(
      LkmTokenPair(
        accessToken: 'access-old',
        refreshToken: 'refresh-1',
        accessExpiresAt: DateTime.now().subtract(const Duration(minutes: 1)),
        refreshExpiresAt: DateTime.now().add(const Duration(days: 7)),
      ),
    );

    final results = await Future.wait([
      session.currentAccessToken(),
      session.currentAccessToken(),
      session.currentAccessToken(),
    ]);

    expect(results.toSet(), hasLength(1));
    expect(results.first, isNotNull);
    expect(router.requests, hasLength(1));
    session.client.close();
  });

  test('a revoked refresh token clears the session', () async {
    final prefs = await _prefs();
    final router = _Router(
      (_) => _envelope(
        null,
        code: ApiCode.authRefreshTokenRevoked,
        message: '刷新令牌已撤销',
      ),
    );
    final session = ApiSession(
      prefs: prefs,
      serverUrl: 'https://lkm-ahz.ltd',
      dio: Dio()..httpClientAdapter = router,
      refreshDio: Dio()..httpClientAdapter = router,
    );
    await session.adopt(
      LkmTokenPair(
        accessToken: 'access-old',
        refreshToken: 'refresh-1',
        accessExpiresAt: DateTime.now().subtract(const Duration(minutes: 1)),
        refreshExpiresAt: DateTime.now().add(const Duration(days: 7)),
      ),
    );

    expect(await session.currentAccessToken(), isNull);
    expect(session.isSignedIn, isFalse);
    expect(prefs.getString(kLkmTokenPairStoreKey), isNull);
    session.client.close();
  });

  test('run refreshes once and retries the failed call', () async {
    final prefs = await _prefs();
    var businessCalls = 0;
    final router = _Router((options) {
      if (options.path.contains('/auth/refresh')) {
        return _envelope({
          'access_token': _jwt(const Duration(hours: 1)),
          'refresh_token': _jwt(const Duration(days: 7)),
        });
      }
      businessCalls++;
      return _envelope({'id': 1});
    });
    final session = ApiSession(
      prefs: prefs,
      serverUrl: 'https://lkm-ahz.ltd',
      dio: Dio()..httpClientAdapter = router,
      refreshDio: Dio()..httpClientAdapter = router,
    );
    await session.adopt(
      LkmTokenPair(
        accessToken: 'access-old',
        refreshToken: 'refresh-1',
        accessExpiresAt: DateTime.now().subtract(const Duration(minutes: 1)),
        refreshExpiresAt: DateTime.now().add(const Duration(days: 7)),
      ),
    );

    var attempts = 0;
    final value = await session.run(() async {
      attempts++;
      if (attempts == 1) {
        throw const ApiException(
          code: ApiCode.authTokenExpired,
          message: 'expired',
        );
      }
      return {'id': 1};
    });

    expect(value['id'], 1);
    expect(attempts, 2);
    expect(businessCalls, 0);
    session.client.close();
  });

  test('run surfaces SessionExpiredException when rotation fails', () async {
    final prefs = await _prefs();
    final router = _Router(
      (_) => _envelope(
        null,
        code: ApiCode.authRefreshTokenRevoked,
        message: '刷新令牌已撤销',
      ),
    );
    final session = ApiSession(
      prefs: prefs,
      serverUrl: 'https://lkm-ahz.ltd',
      dio: Dio()..httpClientAdapter = router,
      refreshDio: Dio()..httpClientAdapter = router,
    );
    await session.adopt(
      LkmTokenPair(
        accessToken: 'access-old',
        refreshToken: 'refresh-1',
        accessExpiresAt: DateTime.now().subtract(const Duration(minutes: 1)),
        refreshExpiresAt: DateTime.now().add(const Duration(days: 7)),
      ),
    );

    await expectLater(
      session.run(() async {
        throw const ApiException(
          code: ApiCode.unauthorized,
          message: 'unauthorized',
        );
      }),
      throwsA(isA<SessionExpiredException>()),
    );
    session.client.close();
  });
}
