import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:island/auth/lkm/lkm_login_content.dart';
import 'package:island/core/api/api_providers.dart';
import 'package:island/core/api/api_session.dart';
import 'package:island/core/config.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Adapter implements HttpClientAdapter {
  _Adapter(this.handle);

  final ResponseBody Function(RequestOptions options) handle;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => handle(options);

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

const _me = {
  'id': 'u-1',
  'username': 'alma',
  'nickname': 'Alma',
  'account_level': 'normal',
  'role': 'user',
  'active_roles': null,
  'email': 'alma@example.com',
};

Future<void> _mount(
  WidgetTester tester,
  ResponseBody Function(RequestOptions options) handle,
) async {
  await tester.binding.setSurfaceSize(const Size(600, 1100));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final dio = Dio()..httpClientAdapter = _Adapter(handle);
  final session = ApiSession(
    prefs: prefs,
    serverUrl: 'https://lkm-ahz.ltd',
    dio: dio,
    refreshDio: dio,
  );
  addTearDown(session.client.close);

  final app = ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      lkmApiSessionProvider.overrideWithValue(session),
      lkmDeviceIdProvider.overrideWith((ref) async => 'device-test'),
    ],
    child: EasyLocalization(
      supportedLocales: const [Locale('en', 'US')],
      path: 'assets/i18n',
      saveLocale: false,
      child: Builder(
        builder: (context) => MaterialApp(
          locale: const Locale('en', 'US'),
          supportedLocales: const [Locale('en', 'US')],
          localizationsDelegates: context.localizationDelegates,
          home: const Scaffold(body: LkmLoginContent()),
        ),
      ),
    ),
  );

  await tester.runAsync(() async {
    await tester.pumpWidget(app);
    await Future<void>.delayed(const Duration(milliseconds: 300));
  });
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  testWidgets('starts with the method selector and an identifier field', (
    tester,
  ) async {
    await _mount(tester, (_) => _envelope(_challenge));

    expect(find.text('Sign in to Phientist'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
    expect(find.text('Email code'), findsOneWidget);
    expect(find.text('Register'), findsOneWidget);
    expect(find.text('Username or email'), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);
    // 还没建挑战：不该出现密码框。
    expect(find.text('Sign in'), findsNothing);
  });

  testWidgets('the password factor appears after the challenge is opened', (
    tester,
  ) async {
    await _mount(tester, (_) => _envelope(_challenge));

    await tester.enterText(
      find.widgetWithText(TextField, 'Username or email'),
      'alma',
    );
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.text('Password'), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
  });

  testWidgets('finishing the factors shows the account card', (tester) async {
    await _mount(tester, (options) {
      if (options.path.contains('/auth/me')) return _envelope(_me);
      if (options.path.contains('/factor')) return _envelope(_complete);
      return _envelope(_challenge);
    });

    await tester.enterText(
      find.widgetWithText(TextField, 'Username or email'),
      'alma',
    );
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Password'),
      'secret',
    );
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();

    expect(find.text('Signed in as Alma'), findsOneWidget);
    expect(find.text('Sign out'), findsOneWidget);
  });

  testWidgets('a second factor renders generically', (tester) async {
    await _mount(tester, (options) {
      if (options.path.contains('/factor')) {
        return _envelope({
          ..._challenge,
          'factors': [
            {'kind': 'totp', 'hint': null},
          ],
        });
      }
      return _envelope(_challenge);
    });

    await tester.enterText(
      find.widgetWithText(TextField, 'Username or email'),
      'alma',
    );
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Password'),
      'secret',
    );
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();

    expect(find.text('Authenticator code'), findsOneWidget);
    expect(find.text('Verify'), findsOneWidget);
    expect(find.text('Signed in as Alma'), findsNothing);
  });
}
