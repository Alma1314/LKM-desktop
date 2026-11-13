import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:island/core/api/api_client.dart';
import 'package:island/core/api/api_session.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Router implements HttpClientAdapter {
  _Router(this.handle);

  final FutureOr<ResponseBody> Function(RequestOptions options) handle;
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

  test(
    'credentials are scoped to the normalized deployment, ignoring legacy pairs',
    () async {
      final prefs = await _prefs();
      await prefs.setString(
        kLkmTokenPairStoreKey,
        jsonEncode({'access_token': 'legacy'}),
      );
      final a = ApiSession(prefs: prefs, serverUrl: 'https://a.example');
      expect(a.isSignedIn, isFalse);
      await a.adopt(
        const LkmTokenPair(accessToken: 'A', refreshToken: 'refresh-A'),
      );
      final requests = _Router((o) {
        expect(o.uri.host, 'b.example');
        expect(o.headers['Authorization'], isNull);
        return _envelope({});
      });
      final b = ApiSession(
        prefs: prefs,
        serverUrl: 'https://b.example',
        dio: Dio()..httpClientAdapter = requests,
      );
      await b.client.get('/auth/me');
      expect(b.isSignedIn, isFalse);
      final restored = ApiSession(
        prefs: prefs,
        serverUrl: 'https://a.example/api/v1/',
      );
      expect(restored.cachedAccessToken, 'A');
      a.dispose();
      b.dispose();
      restored.dispose();
    },
  );

  for (final replacement in [false, true]) {
    test(
      'stale refresh cannot overwrite ${replacement ? 'a new login' : 'sign-out'}',
      () async {
        final prefs = await _prefs();
        final started = Completer<void>();
        final response = Completer<ResponseBody>();
        final session = ApiSession(
          prefs: prefs,
          serverUrl: 'https://community.example',
          refreshDio: Dio()
            ..httpClientAdapter = _Router((_) {
              started.complete();
              return response.future;
            }),
        );
        await session.adopt(
          LkmTokenPair(
            accessToken: 'old',
            refreshToken: 'old-refresh',
            accessExpiresAt: DateTime.now().subtract(
              const Duration(minutes: 1),
            ),
          ),
        );
        final pending = session.currentAccessToken();
        await started.future;
        if (replacement) {
          await session.adopt(const LkmTokenPair(accessToken: 'replacement'));
        } else {
          await session.signOut(revoke: false);
        }
        response.complete(
          _envelope({
            'access_token': 'stale',
            'refresh_token': 'stale-refresh',
          }),
        );
        await pending;
        expect(session.cachedAccessToken, replacement ? 'replacement' : null);
        expect(
          prefs.getString(session.storeKey),
          replacement ? contains('replacement') : isNull,
        );
        session.dispose();
      },
    );
  }

  test(
    'logout carries the captured bearer after clearing local credentials',
    () async {
      final prefs = await _prefs();
      final router = _Router((options) {
        expect(options.path, '/auth/logout');
        expect(options.headers['Authorization'], 'Bearer access-1');
        expect(
          prefs.getString(apiTokenStoreKey('https://example.com')),
          isNull,
        );
        return _envelope(null);
      });
      final session = ApiSession(
        prefs: prefs,
        serverUrl: 'https://example.com',
        dio: Dio()..httpClientAdapter = router,
      );
      await session.adopt(
        const LkmTokenPair(accessToken: 'access-1', refreshToken: 'refresh-1'),
      );
      await session.signOut();
      expect(router.requests.length, 1);
      expect(session.isSignedIn, isFalse);
    },
  );

  test('adopt persists the pair and serves a fresh access token', () async {
    final prefs = await _prefs();
    final calls = _Router((_) => _envelope({'access_token': 'x'}));
    final session = ApiSession(
      prefs: prefs,
      serverUrl: 'https://community.example',
      dio: Dio()..httpClientAdapter = calls,
      refreshDio: Dio()..httpClientAdapter = calls,
    );

    await session.adopt(
      LkmTokenPair(
        accessToken: 'access-1',
        accessExpiresAt: DateTime.now().add(const Duration(hours: 1)),
      ),
    );

    expect(session.isSignedIn, isTrue);
    expect(await session.currentAccessToken(), 'access-1');
    expect(
      prefs.getString(apiTokenStoreKey('https://community.example')),
      contains('access-1'),
    );
    expect(
      calls.requests.where((r) => r.path.contains('/auth/refresh')),
      isEmpty,
    );
    session.client.close();
  });

  test(
    'an expired access token rotates the pair once and persists it',
    () async {
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
        serverUrl: 'https://community.example',
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
      expect(
        prefs.getString(apiTokenStoreKey('https://community.example')),
        contains(token!),
      );
      session.client.close();
    },
  );

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
      serverUrl: 'https://community.example',
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
      serverUrl: 'https://community.example',
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
    expect(
      prefs.getString(apiTokenStoreKey('https://community.example')),
      isNull,
    );
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
      serverUrl: 'https://community.example',
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
      serverUrl: 'https://community.example',
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
