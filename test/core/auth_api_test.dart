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
    serverUrl: 'https://community.example',
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
    final challenge = await _api(
      adapter,
    ).createChallenge(account: 'alma', deviceId: 'device-a');

    final request = adapter.requests.single;
    expect(request.method, 'POST');
    expect(request.uri.path, '/api/v1/auth/challenge');
    expect(request.headers['X-Device-Id'], 'device-a');
    expect(request.data, {'account': 'alma', 'primary_factor': 'password'});
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
    expect(adapter.requests.single.data['primary_factor'], 'code');
  });

  test('reading a challenge passes device_id as a query parameter', () async {
    final adapter = _Adapter((_) => _ok(_challengeJson));
    await _api(adapter).getChallenge('c-1', 'device-a');

    final request = adapter.requests.single;
    expect(request.method, 'GET');
    expect(request.uri.path, '/api/v1/auth/challenge/c-1');
    expect(request.headers['X-Device-Id'], 'device-a');
    expect(request.uri.queryParameters.containsKey('device_id'), isFalse);
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
    expect(request.headers['X-Device-Id'], 'device-a');
    expect(request.data, {'kind': 'password', 'password': 'secret'});
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

  test('request and cancel carry the device header', () async {
    final adapter = _Adapter((_) => _ok({'message': 'ok'}));
    final api = _api(adapter);

    await api.requestFactorCode('c-1', 'device-a');
    await api.cancelChallenge('c-1', 'device-a');

    expect(
      adapter.requests.first.uri.path,
      '/api/v1/auth/challenge/c-1/request',
    );
    expect(adapter.requests.first.headers['X-Device-Id'], 'device-a');
    expect(adapter.requests.last.uri.path, '/api/v1/auth/challenge/c-1/cancel');
    expect(adapter.requests.last.headers['X-Device-Id'], 'device-a');
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
          'rpId': 'community.example',
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
    expect(adapter.requests.single.headers['X-Device-Id'], 'device-a');
    expect(adapter.requests.single.data, isNull);
    expect(options.challengeId, 'wac-1');
    expect(options.challenge, 'abc123');
    expect(options.rpId, 'community.example');
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

  test('normal registration sends one contact and keeps the txn id', () async {
    final adapter = _Adapter(
      (_) => _ok({
        'message': 'Verification code(s) sent',
        'txn_id': 'txn-1',
        'email_sent': true,
        'phone_sent': false,
      }),
    );
    final pending = await _api(adapter).requestRegisterNormal(
      username: ' alma ',
      password: 'secret',
      email: 'alma@example.com',
      applyReason: ' ',
    );

    final body = adapter.requests.single.data as Map;
    expect(adapter.requests.single.uri.path, '/api/v1/auth/reg/normal');
    expect(body['username'], 'alma');
    expect(body['email'], 'alma@example.com');
    expect(body.containsKey('phone'), isFalse);
    expect(body.containsKey('apply_reason'), isFalse);
    expect(pending.txnId, 'txn-1');
    expect(pending.emailSent, isTrue);
  });

  test(
    'normal registration verify passes codes as query and parses pending',
    () async {
      final adapter = _Adapter(
        (_) => _ok({
          'user_id': 'u-2',
          'account_level': 'local',
          'admission_status': 'pending',
          'access_token': null,
          'refresh_token': null,
        }),
      );
      final result = await _api(
        adapter,
      ).verifyRegisterNormal(txnId: 'txn-1', emailCode: '123456');

      final request = adapter.requests.single;
      expect(request.uri.path, '/api/v1/auth/reg/normal/verify');
      expect(request.uri.queryParameters['txn_id'], 'txn-1');
      expect(request.uri.queryParameters['email_code'], '123456');
      expect(request.uri.queryParameters.containsKey('phone_code'), isFalse);
      expect(result.isSignedIn, isFalse);
      expect(result.isPendingAdmission, isTrue);
      expect(result.admissionStatus, 'pending');
    },
  );

  test('local registration parses a token pair', () async {
    final adapter = _Adapter(
      (_) => _ok({
        'user_id': 'u-2',
        'account_level': 'local',
        'access_token': 'access-2',
        'refresh_token': 'refresh-2',
      }),
    );
    final result = await _api(
      adapter,
    ).registerLocal(username: 'alma', password: 'secret');

    expect(adapter.requests.single.uri.path, '/api/v1/auth/reg/local');
    expect(
      (adapter.requests.single.data as Map).containsKey('apply_reason'),
      isFalse,
    );
    expect(result.isSignedIn, isTrue);
    expect(result.tokens?.accessToken, 'access-2');
  });

  test('onboarding reads, merges a step and skips', () async {
    final adapter = _Adapter(
      (options) => _ok({
        'step': options.method == 'GET'
            ? 1
            : options.uri.path.endsWith('/skip')
            ? 4
            : 2,
        'completed': options.uri.path.endsWith('/skip'),
        'data': {
          'tags': ['dev'],
        },
      }),
    );
    final api = _api(adapter);

    final state = await api.onboarding();
    expect(state.step, 1);
    expect(adapter.requests.last.uri.path, '/api/v1/auth/onboarding');
    expect(state.data?['tags'], ['dev']);

    await api.setOnboardingStep(2, {
      'tags': ['dev'],
    });
    final put = adapter.requests.last;
    expect(put.method, 'PUT');
    expect(put.uri.path, '/api/v1/auth/onboarding/steps/2');
    expect(put.data, {
      'data': {
        'tags': ['dev'],
      },
    });

    final skipped = await api.skipOnboarding();
    expect(adapter.requests.last.uri.path, '/api/v1/auth/onboarding/skip');
    expect(skipped.completed, isTrue);
  });

  test('recovery verify returns the 2FA transaction to finish', () async {
    final adapter = _Adapter((options) {
      if (options.uri.path.endsWith('/magic-link/verify')) {
        return _ok({'message': 'Password reset successful'});
      }
      return _ok({
        'message': 'MFA required',
        'requires_2fa': true,
        'txn_id': 'txn-9',
        'temp_token': 'temp-9',
      });
    });
    final api = _api(adapter);

    final outcome = await api.verifyRecovery(
      contact: 'alma@example.com',
      byEmail: true,
      code: '123456',
    );
    final request = adapter.requests.last;
    expect(request.uri.path, '/api/v1/auth/recover/email/verify');
    expect((request.data as Map)['email'], 'alma@example.com');
    expect((request.data as Map).containsKey('new_password'), isFalse);
    expect(outcome.requires2fa, isTrue);
    expect(outcome.txnId, 'txn-9');
    expect(outcome.tempToken, 'temp-9');

    await api.verifyRecoveryTotp(txnId: 'txn-9', tempToken: 'temp-9');
    expect(adapter.requests.last.uri.path, '/api/v1/auth/recover/verify-totp');

    await api.completeRecovery(txnId: 'txn-9', newPassword: 'new-secret');
    expect(adapter.requests.last.uri.path, '/api/v1/auth/recover/complete');

    final magic = await api.verifyRecoveryMagicLink(token: 'link-1');
    expect(magic.requires2fa, isFalse);
  });

  test('2FA setup, status, disable and step-up hit their endpoints', () async {
    final adapter = _Adapter((options) {
      if (options.uri.path.endsWith('/status')) {
        return _ok({'enabled': true});
      }
      if (options.uri.path.endsWith('/setup/begin')) {
        return _ok({'secret': 'S3CR3T', 'qr_code_uri': 'otpauth://x'});
      }
      if (options.uri.path.endsWith('/setup/complete')) {
        return _ok({
          'recovery_codes': ['a', 'b'],
          'confirmed_saved_required': true,
        });
      }
      return _ok({
        'user_id': 'u-1',
        'account_level': 'normal',
        'access_token': 'access-3',
        'refresh_token': 'refresh-3',
        'mfa_verified': true,
      });
    });
    final api = _api(adapter);

    final setup = await api.beginTotpSetup();
    expect(setup.secret, 'S3CR3T');
    final complete = await api.completeTotpSetup('123456');
    expect(complete.recoveryCodes, ['a', 'b']);
    expect(complete.confirmedSavedRequired, isTrue);
    expect(await api.totpEnabled(), isTrue);

    await api.disableTotp(recoveryCode: 'rec-1');
    expect(adapter.requests.last.method, 'DELETE');
    expect(adapter.requests.last.uri.path, '/api/v1/auth/2fa');

    final stepped = await api.stepUpTotp(code: '123456');
    expect(stepped.hasTokens, isTrue);
    expect(adapter.requests.last.uri.path, '/api/v1/auth/2fa/step-up');
  });

  test('passkey credentials list and delete', () async {
    final adapter = _Adapter((options) {
      if (options.method == 'DELETE') {
        return _ok({'message': 'deleted'});
      }
      return _ok([
        {
          'id': 'pk-1',
          'credential_id': 'cred-1',
          'device_name': 'MacBook',
          'created_at': '2026-11-11T10:00:00+00:00',
        },
      ]);
    });
    final api = _api(adapter);

    final credentials = await api.passkeyCredentials();
    expect(credentials.single.deviceName, 'MacBook');
    expect(credentials.single.credentialId, 'cred-1');

    await api.deletePasskey('pk-1');
    expect(adapter.requests.last.method, 'DELETE');
    expect(adapter.requests.last.uri.path, '/api/v1/auth/passkey/pk-1');
  });

  test(
    'account settings parse bindings and unbind sends step-up codes',
    () async {
      final adapter = _Adapter((options) {
        if (options.method == 'GET') {
          return _ok({
            'email': 'alma@example.com',
            'phone': null,
            'github': 'alma',
            'has_2fa': true,
          });
        }
        return _ok({'message': 'ok'});
      });
      final api = _api(adapter);

      final settings = await api.accountSettings();
      expect(settings.email, 'alma@example.com');
      expect(settings.github, 'alma');
      expect(settings.has2fa, isTrue);

      await api.unbind('email', code: '123456');
      expect(adapter.requests.last.method, 'DELETE');
      expect(adapter.requests.last.uri.path, '/api/v1/auth/settings/email');
      expect(adapter.requests.last.data, {'code': '123456'});
    },
  );

  test('GitHub desktop login builds the loopback authorization URL', () {
    final api = _api(_Adapter((_) => _ok({})));
    final url = Uri.parse(
      api.githubLoginUrl(
        redirectUri: 'http://127.0.0.1:4567/callback',
        challenge: 'a' * 64,
      ),
    );

    expect(url.path, '/api/v1/auth/oauth/github/login');
    expect(
      url.queryParameters['redirect_uri'],
      'http://127.0.0.1:4567/callback',
    );
    expect(url.queryParameters['challenge'], 'a' * 64);
  });

  test('desktop code exchange posts the verifier and parses tokens', () async {
    final adapter = _Adapter(
      (_) => _ok({
        'user_id': 'u-1',
        'account_level': 'normal',
        'access_token': 'access-9',
        'refresh_token': 'refresh-9',
      }),
    );
    final result = await _api(
      adapter,
    ).exchangeDesktopCode(code: 'code-1', verifier: 'verifier-1');

    expect(
      adapter.requests.single.uri.path,
      '/api/v1/auth/oauth/desktop/exchange',
    );
    expect(adapter.requests.single.data, {
      'code': 'code-1',
      'verifier': 'verifier-1',
    });
    expect(result.tokens?.accessToken, 'access-9');
  });

  test('GitHub bind URL is requested with the loopback parameters', () async {
    final adapter = _Adapter(
      (_) => _ok({'url': 'https://github.com/login/oauth/authorize?x=1'}),
    );
    final url = await _api(adapter).githubBindUrl(
      redirectUri: 'http://127.0.0.1:4567/callback',
      challenge: 'b' * 64,
    );

    final request = adapter.requests.single;
    expect(request.uri.path, '/api/v1/auth/oauth/github/login/redirect');
    expect(
      request.uri.queryParameters['redirect_uri'],
      'http://127.0.0.1:4567/callback',
    );
    expect(request.uri.queryParameters['challenge'], 'b' * 64);
    expect(url, 'https://github.com/login/oauth/authorize?x=1');
  });

  test('avatar upload is multipart and returns the storage key', () async {
    final adapter = _Adapter(
      (_) => _ok({'message': 'ok', 'avatar': 'u/1.png'}),
    );
    final key = await _api(
      adapter,
    ).uploadAvatar(bytes: const [1, 2, 3], filename: 'avatar.png');

    final request = adapter.requests.single;
    expect(request.uri.path, '/api/v1/auth/avatar');
    expect(
      request.headers[Headers.contentTypeHeader],
      startsWith('multipart/form-data'),
    );
    expect(request.data, isA<FormData>());
    expect(key, 'u/1.png');
  });
}
