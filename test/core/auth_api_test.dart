import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:island/core/api/api_client.dart';
import 'package:island/core/api/auth_api.dart';

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

AuthApi _api(_Adapter adapter) => AuthApi(
  ApiClient(
    serverUrl: 'https://lkm-ahz.ltd',
    dio: Dio()..httpClientAdapter = adapter,
  ),
);

const _challengeJson = {
  'id': 'c-1',
  'status': 'pending',
  'purpose': 'login',
  'factors': [
    {'kind': 'password', 'hint': null},
  ],
  'expires_at': '2026-11-08T21:00:00+00:00',
};

void main() {
  test('create challenge posts account and device in the body', () async {
    final adapter = _Adapter((_) => _ok(_challengeJson));
    final challenge = await _api(adapter).createChallenge(
      account: 'alma',
      deviceId: 'device-a',
    );

    final request = adapter.requests.single;
    expect(request.method, 'POST');
    expect(request.uri.path, '/api/v1/auth/challenge');
    expect(request.data, {
      'account': 'alma',
      'device_id': 'device-a',
      'primary_factor': 'password',
    });
    expect(challenge.id, 'c-1');
    expect(challenge.current?.kind, 'password');
    expect(challenge.expiresAt, isNotNull);
  });

  test('a code challenge carries the masked hint', () async {
    final adapter = _Adapter(
      (_) => _ok({
        ..._challengeJson,
        'factors': [
          {'kind': 'code', 'hint': 'a***@example.com'},
        ],
      }),
    );
    final challenge = await _api(adapter).createChallenge(
      account: 'alma@example.com',
      deviceId: 'device-a',
      primaryFactor: 'code',
    );

    expect(challenge.current?.hint, 'a***@example.com');
    expect(
      adapter.requests.single.data['primary_factor'],
      'code',
    );
  });

  test('reading a challenge passes device_id as a query parameter', () async {
    final adapter = _Adapter((_) => _ok(_challengeJson));
    await _api(adapter).getChallenge('c-1', 'device-a');

    final request = adapter.requests.single;
    expect(request.method, 'GET');
    expect(request.uri.path, '/api/v1/auth/challenge/c-1');
    expect(request.uri.queryParameters['device_id'], 'device-a');
  });

  test('submitting a factor returns the completed tokens', () async {
    final adapter = _Adapter(
      (_) => _ok({
        'status': 'complete',
        'access_token': 'access-1',
        'refresh_token': 'refresh-1',
        'user_id': 'u-1',
        'account_level': 'normal',
      }),
    );
    final step = await _api(adapter).submitFactor(
      'c-1',
      deviceId: 'device-a',
      kind: 'password',
      password: 'secret',
    );

    final request = adapter.requests.single;
    expect(request.uri.path, '/api/v1/auth/challenge/c-1/factor');
    expect(request.data, {
      'device_id': 'device-a',
      'kind': 'password',
      'password': 'secret',
    });
    expect(step.isComplete, isTrue);
    expect(step.tokens?.accessToken, 'access-1');
  });

  test('a pending step returns the next factor', () async {
    final adapter = _Adapter(
      (_) => _ok({
        'id': 'c-1',
        'status': 'pending',
        'purpose': 'login',
        'factors': [
          {'kind': 'totp', 'hint': null},
        ],
        'expires_at': '2026-11-08T21:00:00+00:00',
      }),
    );
    final step = await _api(adapter).submitFactor(
      'c-1',
      deviceId: 'device-a',
      kind: 'password',
      password: 'secret',
    );

    expect(step.isComplete, isFalse);
    expect(step.challenge?.current?.kind, 'totp');
    // 没有 code 时不要把空 key 发上去。
    expect(adapter.requests.single.data.containsKey('code'), isFalse);
  });

  test('request and cancel keep device_id in the query', () async {
    final adapter = _Adapter((_) => _ok({'message': 'ok'}));
    final api = _api(adapter);

    await api.requestFactorCode('c-1', 'device-a');
    await api.cancelChallenge('c-1', 'device-a');

    expect(adapter.requests.first.uri.path, '/api/v1/auth/challenge/c-1/request');
    expect(adapter.requests.first.uri.queryParameters['device_id'], 'device-a');
    expect(adapter.requests.last.uri.path, '/api/v1/auth/challenge/c-1/cancel');
    expect(adapter.requests.last.uri.queryParameters['device_id'], 'device-a');
  });

  test('email registration stays outside the challenge flow', () async {
    final adapter = _Adapter((_) => _ok({'message': 'sent'}));
    await _api(adapter).requestRegisterCode('alma@example.com');

    expect(adapter.requests.single.uri.path, '/api/v1/auth/reg/email');
    expect(adapter.requests.single.data, {'email': 'alma@example.com'});
  });

  test('me parses the account and flags admins', () async {
    final adapter = _Adapter(
      (_) => _ok({
        'id': 'u-1',
        'username': 'alma',
        'nickname': 'Alma',
        'account_level': 'admin',
        'role': 'admin',
        'active_roles': ['admin', 'moderator'],
        'email': 'alma@example.com',
      }),
    );

    final account = await _api(adapter).me();

    expect(account.displayName, 'Alma');
    expect(account.isAdmin, isTrue);
  });

  test('passkey factor start parses the assertion options', () async {
    final adapter = _Adapter(
      (_) => _ok({
        'challenge_id': 'wac-1',
        'public_key': {
          'challenge': 'abc123',
          'rpId': 'lkm-ahz.ltd',
          'allowCredentials': [
            {
              'type': 'public-key',
              'id': 'cred-1',
              'transports': ['internal'],
            },
          ],
        },
      }),
    );
    final options = await _api(adapter).startPasskeyFactor('c-1', 'device-a');

    expect(
      adapter.requests.single.uri.path,
      '/api/v1/auth/challenge/c-1/passkey/start',
    );
    expect(adapter.requests.single.data, {'device_id': 'device-a'});
    expect(options.challengeId, 'wac-1');
    expect(options.challenge, 'abc123');
    expect(options.rpId, 'lkm-ahz.ltd');
    expect(options.allowCredentials.single['id'], 'cred-1');
  });

  test('passkey factor complete posts the browser-shaped assertion', () async {
    final adapter = _Adapter(
      (_) => _ok({
        'status': 'complete',
        'access_token': 'access-1',
        'refresh_token': 'refresh-1',
        'user_id': 'u-1',
        'account_level': 'normal',
      }),
    );
    final step = await _api(adapter).completePasskeyFactor(
      'c-1',
      deviceId: 'device-a',
      webauthnChallengeId: 'wac-1',
      assertion: const LkmPasskeyAssertion(
        rawId: 'cred-1',
        clientDataJson: 'cdj',
        authenticatorData: 'ad',
        signature: 'sig',
      ),
    );

    final body = adapter.requests.single.data as Map;
    expect(body['challenge_id'], 'wac-1');
    expect(body['rawId'], 'cred-1');
    expect((body['response'] as Map)['signature'], 'sig');
    // 没有 userHandle 时不要发空串。
    expect((body['response'] as Map).containsKey('userHandle'), isFalse);
    expect(step.isComplete, isTrue);
  });
}
