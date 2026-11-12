import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:island/community/user_pod.dart';
import 'package:island/core/api/api_providers.dart';
import 'package:island/core/api/api_session.dart';
import 'package:island/core/api/auth_api.dart';
import 'package:island/core/config.dart';
import 'package:island/hub/ask_question_dialog.dart';

class _Adapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  @override
  void close({bool force = false}) {}
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? stream,
    Future<void>? cancel,
  ) async {
    requests.add(options);
    return ResponseBody.fromString(
      jsonEncode({
        'code': 0,
        'data': {'user_id': 'u1', 'balance': 20},
      }),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }
}

void main() {
  testWidgets(
    'restored acknowledged question finishes without creating or charging again',
    (tester) async {
      const key = 'qa-draft:$kLkmServerDefault:u1';
      SharedPreferences.setMockInitialValues({
        key: jsonEncode({
          'title': 'Saved question',
          'situation': 'Context',
          'content': 'Body',
          'questionId': 'already-created',
          'images': [],
        }),
      });
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
                lkmMeProvider.overrideWith(
                  (ref) async => const LkmAccount(
                    id: 'u1',
                    username: 'user',
                    accountLevel: 'normal',
                    role: 'member',
                  ),
                ),
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
                          builder: (_) => const AskQuestionDialog(),
                        ),
                        child: const Text('Open'),
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
      await tester.tap(find.text('Open'));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(find.text('Saved question'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Submit'));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(adapter.requests.where((r) => r.method == 'POST'), isEmpty);
      expect(prefs.getString(key), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
