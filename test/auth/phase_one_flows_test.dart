import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:island/auth/account_security_screen.dart';
import 'package:island/auth/login_content.dart';
import 'package:island/auth/onboarding_screen.dart';
import 'package:island/auth/recovery_screen.dart';
import 'package:island/auth/register_screen.dart';
import 'package:island/auth/totp_setup_dialog.dart';
import 'package:island/core/api/api_providers.dart';
import 'package:island/core/api/api_session.dart';
import 'package:island/core/api/auth_api.dart';
import 'package:island/core/config.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Adapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  @override
  void close({bool force = false}) {}
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? stream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final data = switch (options.path) {
      '/auth/2fa/setup/temp' => {
        'secret': 'secret',
        'qr_code_uri': 'otpauth://test',
      },
      '/auth/2fa/setup/complete/temp' => {
        'recovery_codes': ['recovery-one'],
        'confirmed_saved_required': true,
        'access_token': 'access',
        'refresh_token': 'refresh',
      },
      '/auth/me' => {
        'id': 'u1',
        'username': 'admin',
        'account_level': 'admin',
        'role': 'admin',
      },
      _ => null,
    };
    return ResponseBody.fromString(
      jsonEncode({'code': 0, 'message': 'ok', 'data': data}),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }
}

void main() {
  testWidgets(
    'mandatory setup shows recovery codes before adopting a session and confirming',
    (tester) async {
      // Keep all W1 pages in the persistent compile check.
      expect(const AccountSecurityScreen(), isNotNull);
      expect(const RegisterScreen(), isNotNull);
      expect(const RecoveryScreen(), isNotNull);
      expect(const OnboardingScreen(), isNotNull);
      expect(const LoginContent(), isNotNull);
      SharedPreferences.setMockInitialValues({});
      await EasyLocalization.ensureInitialized();
      final prefs = await SharedPreferences.getInstance();
      final adapter = _Adapter();
      final session = ApiSession(
        prefs: prefs,
        serverUrl: kLkmServerDefault,
        dio: Dio()..httpClientAdapter = adapter,
      );
      await tester.runAsync(() async {
        await tester.pumpWidget(
          EasyLocalization(
            supportedLocales: const [Locale('en', 'US')],
            path: 'assets/i18n',
            saveLocale: false,
            child: ProviderScope(
              overrides: [
                sharedPreferencesProvider.overrideWithValue(prefs),
                lkmApiSessionProvider.overrideWithValue(session),
              ],
              child: Builder(
                builder: (context) => MaterialApp(
                  localizationsDelegates: context.localizationDelegates,
                  supportedLocales: context.supportedLocales,
                  locale: context.locale,
                  home: Scaffold(
                    body: Builder(
                      builder: (context) => TextButton(
                        onPressed: () => showDialog<bool>(
                          context: context,
                          barrierDismissible: false,
                          builder: (_) => const TotpSetupDialog(
                            authResult: LkmAuthResult(
                              userId: 'u1',
                              accountLevel: 'admin',
                              setupRequired: true,
                              tempToken: 'temp',
                            ),
                          ),
                        ),
                        child: const Text('start'),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pumpAndSettle();
      await tester.tap(find.text('start'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '123456');
      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();
      expect(find.text('recovery-one'), findsOneWidget);
      expect(session.isSignedIn, isFalse);
      expect(adapter.requests.map((r) => r.path), [
        '/auth/2fa/setup/temp',
        '/auth/2fa/setup/complete/temp',
      ]);
      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();
      expect(session.isSignedIn, isTrue);
      expect(find.byType(TotpSetupDialog), findsNothing);
      expect(adapter.requests.last.path, '/auth/2fa/setup/confirm');
      expect(adapter.requests.last.headers['Authorization'], 'Bearer access');
      await tester.pumpWidget(const SizedBox());
    },
  );
}
