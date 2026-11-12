import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:island/auth/login_controller.dart';
import 'package:island/auth/passkey.dart';
import 'package:island/core/api/api_providers.dart';
import 'package:island/core/api/auth_api.dart';
import 'package:island/core/api/api_session.dart';
import 'package:island/core/config.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

ResponseBody _envelope(Object? data, {int code = 0, String message = 'ok'}) =>
    ResponseBody.fromString(
      jsonEncode({'code': code, 'message': message, 'data': data}),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );

const _me = {
  'id': 'u-1',
  'username': 'alma',
  'nickname': 'Alma',
  'account_level': 'normal',
  'role': 'user',
  'active_roles': null,
};

const _challenge = {
  'id': 'c-1',
  'status': 'pending',
  'purpose': 'login',
  'factors': [
    {'kind': 'password', 'hint': null},
  ],
  'expires_at': '2026-11-08T21:00:00+00:00',
};

const _complete = {
  'status': 'complete',
  'access_token': 'access-1',
  'refresh_token': 'refresh-1',
  'user_id': 'u-1',
  'account_level': 'normal',
};

const _pendingTotp = {
  'id': 'c-1',
  'status': 'pending',
  'purpose': 'login',
  'factors': [
    {'kind': 'totp', 'hint': null},
  ],
  'expires_at': '2026-11-08T21:00:00+00:00',
};

Future<({ProviderContainer container, _Adapter adapter})> _setup(
  ResponseBody Function(RequestOptions options) handle, {
  PasskeyCeremony? ceremony,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final adapter = _Adapter(handle);
  final dio = Dio()..httpClientAdapter = adapter;
  final session = ApiSession(
    prefs: prefs,
    serverUrl: 'https://community.example',
    dio: dio,
    refreshDio: dio,
  );
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      lkmApiSessionProvider.overrideWithValue(session),
      lkmDeviceIdProvider.overrideWith((ref) async => 'device-test'),
      // Identity translator: assertions compare keys, not rendered copy.
      authTranslatorProvider.overrideWithValue((key, args) => key),
      if (ceremony != null) passkeyCeremonyProvider.overrideWithValue(ceremony),
    ],
  );
  addTearDown(container.dispose);
  addTearDown(session.client.close);
  return (container: container, adapter: adapter);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('mandatory setup is handed off without adopting a session', () async {
    final setup = await _setup(
      (options) => _envelope(
        options.path == '/auth/challenge'
            ? _challenge
            : {
                'status': 'setup_required',
                'setup_required': true,
                'requires_2fa': true,
                'temp_token': 'setup-only',
                'user_id': 'u-1',
                'account_level': 'admin',
              },
      ),
    );
    final controller = setup.container.read(loginControllerProvider.notifier);
    await controller.beginPassword('alma');
    await controller.submitPassword('secret');
    final state = setup.container.read(loginControllerProvider);
    expect(state.setup?.tempToken, 'setup-only');
    expect(state.oauthTempToken, isNull);
    expect(state.challenge, isNull);
    expect(setup.container.read(lkmApiSessionProvider).isSignedIn, isFalse);
  });

  test(
    'magic link uses query endpoints and adopts tokens without a 2FA prompt',
    () async {
      final setup = await _setup((options) {
        if (options.path == '/auth/login/magic-link/request') {
          expect(options.queryParameters, {'email': 'alma@example.com'});
          return _envelope(null);
        }
        if (options.path == '/auth/login/magic-link/verify') {
          expect(options.queryParameters, {'token': 'magic-token'});
          return _envelope(_complete);
        }
        return _envelope(_me);
      });
      final controller = setup.container.read(loginControllerProvider.notifier);
      await controller.requestMagicLink(' alma@example.com ');
      await controller.verifyMagicLink(
        'https://example.com/auth/login/magic-link/verify?token=magic-token',
      );
      final state = setup.container.read(loginControllerProvider);
      expect(state.signedIn, isTrue);
      expect(state.oauthTempToken, isNull);
      expect(state.setup, isNull);
    },
  );

  test('opening a password challenge shows the password factor', () async {
    final setup = await _setup((_) => _envelope(_challenge));
    final controller = setup.container.read(loginControllerProvider.notifier);

    await controller.beginPassword('alma');

    final state = setup.container.read(loginControllerProvider);
    expect(state.hasChallenge, isTrue);
    expect(state.currentFactor?.kind, 'password');
    final request = setup.adapter.requests.single;
    expect(request.uri.path, '/api/v1/auth/challenge');
    expect(request.data['primary_factor'], 'password');
    expect(request.headers['X-Device-Id'], 'device-test');
  });

  test('the last factor lands the session', () async {
    final setup = await _setup((options) {
      if (options.path.contains('/auth/me')) return _envelope(_me);
      if (options.path.contains('/factor')) return _envelope(_complete);
      return _envelope(_challenge);
    });
    final controller = setup.container.read(loginControllerProvider.notifier);

    await controller.beginPassword('alma');
    await controller.submitPassword('secret');

    final state = setup.container.read(loginControllerProvider);
    expect(state.account?.username, 'alma');
    expect(state.challenge, isNull);
    final session = setup.container.read(lkmApiSessionProvider);
    expect(session.isSignedIn, isTrue);
    expect(session.tokens?.accessToken, 'access-1');
  });

  test('a pending challenge rotates to the next factor', () async {
    final setup = await _setup((options) {
      if (options.path.contains('/factor')) return _envelope(_pendingTotp);
      return _envelope(_challenge);
    });
    final controller = setup.container.read(loginControllerProvider.notifier);

    await controller.beginPassword('alma');
    await controller.submitPassword('secret');

    final state = setup.container.read(loginControllerProvider);
    expect(state.account, isNull);
    expect(state.currentFactor?.kind, 'totp');
    // 未签入前不得落令牌。
    expect(setup.container.read(lkmApiSessionProvider).isSignedIn, isFalse);
  });

  test('the totp factor completes the challenge', () async {
    var factorCalls = 0;
    final setup = await _setup((options) {
      if (options.path.contains('/auth/me')) return _envelope(_me);
      if (options.path.contains('/factor')) {
        factorCalls += 1;
        return _envelope(factorCalls == 1 ? _pendingTotp : _complete);
      }
      return _envelope(_challenge);
    });
    final controller = setup.container.read(loginControllerProvider.notifier);

    await controller.beginPassword('alma');
    await controller.submitPassword('secret');
    await controller.submitTotp('123456');

    final state = setup.container.read(loginControllerProvider);
    expect(state.account?.username, 'alma');
    final factorBodies = setup.adapter.requests
        .where((r) => r.path.contains('/factor'))
        .map((r) => r.data as Map)
        .toList();
    expect(factorBodies.last['kind'], 'totp');
    expect(factorBodies.last['code'], '123456');
  });

  test('a wrong password keeps the challenge open', () async {
    final setup = await _setup((options) {
      if (options.path.contains('/factor')) {
        return _envelope(null, code: 65538, message: '用户名或密码错误');
      }
      return _envelope(_challenge);
    });
    final controller = setup.container.read(loginControllerProvider.notifier);

    await controller.beginPassword('alma');
    await controller.submitPassword('wrong');

    final state = setup.container.read(loginControllerProvider);
    expect(state.error, '用户名或密码错误');
    expect(state.hasChallenge, isTrue);
    expect(state.currentFactor?.kind, 'password');
  });

  test('a dead challenge sends the user back to the form', () async {
    final setup = await _setup((options) {
      if (options.path.contains('/factor')) {
        // 65569 = (1 << 16) | 33，挑战过期。
        return _envelope(null, code: 65569, message: 'challenge expired');
      }
      return _envelope(_challenge);
    });
    final controller = setup.container.read(loginControllerProvider.notifier);

    await controller.beginPassword('alma');
    await controller.submitPassword('secret');

    final state = setup.container.read(loginControllerProvider);
    expect(state.hasChallenge, isFalse);
    expect(state.error, 'lkmErrChallengeExpired');
  });

  test('the code path creates a code challenge and sends the code', () async {
    final setup = await _setup((options) {
      if (options.path.contains('/request')) {
        return _envelope({'message': 'sent'});
      }
      return _envelope({
        ..._challenge,
        'factors': [
          {'kind': 'code', 'hint': 'a***@example.com'},
        ],
      });
    });
    final controller = setup.container.read(loginControllerProvider.notifier);

    await controller.beginCode('alma@example.com');

    final state = setup.container.read(loginControllerProvider);
    expect(state.currentFactor?.kind, 'code');
    expect(state.codeSent, isTrue);
    expect(state.info, 'lkmCodeSentTo');
    final paths = setup.adapter.requests.map((r) => r.uri.path).toList();
    expect(paths, contains('/api/v1/auth/challenge/c-1/request'));
  });

  test('cancel closes the challenge locally and on the server', () async {
    final setup = await _setup((options) {
      if (options.path.contains('/cancel')) return _envelope({'message': 'ok'});
      return _envelope(_challenge);
    });
    final controller = setup.container.read(loginControllerProvider.notifier);

    await controller.beginPassword('alma');
    await controller.cancel();

    expect(setup.container.read(loginControllerProvider).hasChallenge, isFalse);
    expect(
      setup.adapter.requests.map((r) => r.uri.path),
      contains('/api/v1/auth/challenge/c-1/cancel'),
    );
  });

  test('email registration signs the account in', () async {
    final setup = await _setup((options) {
      if (options.path.contains('/auth/me')) return _envelope(_me);
      if (options.path.contains('/reg/email/verify'))
        return _envelope(_complete);
      return _envelope({'message': 'sent'});
    });
    final controller = setup.container.read(loginControllerProvider.notifier);

    await controller.requestRegisterCode('alma@example.com');
    expect(setup.container.read(loginControllerProvider).info, 'lkmCodeSentTo');

    await controller.verifyRegistration(
      email: 'alma@example.com',
      code: '654321',
    );

    expect(
      setup.container.read(loginControllerProvider).account?.username,
      'alma',
    );
  });

  test('sign-out clears the stored pair', () async {
    final setup = await _setup((options) {
      if (options.path.contains('/auth/me')) return _envelope(_me);
      if (options.path.contains('/factor')) return _envelope(_complete);
      return _envelope(_challenge);
    });
    final controller = setup.container.read(loginControllerProvider.notifier);
    await controller.beginPassword('alma');
    await controller.submitPassword('secret');

    await controller.signOut();

    expect(setup.container.read(loginControllerProvider).account, isNull);
    expect(
      setup.container
          .read(sharedPreferencesProvider)
          .getString(kLkmTokenPairStoreKey),
      isNull,
    );
  });
  test('the passkey path yields a passkey factor', () async {
    final setup = await _setup(
      (_) => _envelope({
        ..._challenge,
        'factors': [
          {'kind': 'passkey', 'hint': 'a***@example.com'},
        ],
      }),
    );
    final controller = setup.container.read(loginControllerProvider.notifier);

    await controller.beginPasskey('alma');

    final state = setup.container.read(loginControllerProvider);
    expect(state.method, LoginMethod.passkey);
    expect(state.currentFactor?.kind, 'passkey');
    expect(setup.adapter.requests.single.data['primary_factor'], 'passkey');
  });

  test('the passkey ceremony lands the session', () async {
    var ceremonyCalls = 0;
    final setup = await _setup(
      (options) {
        if (options.path.contains('/auth/me')) return _envelope(_me);
        if (options.path.contains('/passkey/start')) {
          return _envelope({
            'challenge_id': 'wac-1',
            'public_key': {
              'challenge': 'abc',
              'rpId': 'community.example',
              'allowCredentials': const [],
            },
          });
        }
        if (options.path.contains('/passkey/complete'))
          return _envelope(_complete);
        return _envelope({
          ..._challenge,
          'factors': [
            {'kind': 'passkey', 'hint': null},
          ],
        });
      },
      ceremony: (options) async {
        ceremonyCalls += 1;
        expect(options.challengeId, 'wac-1');
        return const LkmPasskeyAssertion(
          rawId: 'cred-1',
          clientDataJson: 'cdj',
          authenticatorData: 'ad',
          signature: 'sig',
        );
      },
    );
    final controller = setup.container.read(loginControllerProvider.notifier);

    await controller.beginPasskey('alma');
    await controller.authenticateWithPasskey();

    expect(ceremonyCalls, 1);
    final state = setup.container.read(loginControllerProvider);
    expect(state.account?.username, 'alma');
    expect(setup.container.read(lkmApiSessionProvider).isSignedIn, isTrue);
  });

  test('a cancelled ceremony keeps the challenge open', () async {
    final setup = await _setup((options) {
      if (options.path.contains('/passkey/start')) {
        return _envelope({
          'challenge_id': 'wac-1',
          'public_key': {'challenge': 'abc', 'rpId': 'community.example'},
        });
      }
      return _envelope({
        ..._challenge,
        'factors': [
          {'kind': 'passkey', 'hint': null},
        ],
      });
    }, ceremony: (_) async => throw Exception('user cancelled'));
    final controller = setup.container.read(loginControllerProvider.notifier);

    await controller.beginPasskey('alma');
    await controller.authenticateWithPasskey();

    final state = setup.container.read(loginControllerProvider);
    expect(state.error, 'lkmPasskeyFailed');
    expect(state.hasChallenge, isTrue);
    expect(state.busy, isFalse);
  });
}
