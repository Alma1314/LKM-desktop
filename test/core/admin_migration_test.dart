import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:island/admin/admin_bot_tab.dart';
import 'package:island/admin/admin_dashboard_tab.dart';
import 'package:island/admin/admin_users_tab.dart';
import 'package:island/admin/admin_pod.dart';
import 'package:island/core/api/admin_api.dart';
import 'package:island/core/api/api_client.dart';
import 'package:island/core/config.dart';

class _Adapter implements HttpClientAdapter {
  _Adapter(this.handle);
  final ResponseBody Function(RequestOptions) handle;
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
    return handle(options);
  }
}

ResponseBody _json(
  Object? data, {
  int code = 0,
  Map<String, List<String>>? headers,
}) => ResponseBody.fromString(
  jsonEncode({'code': code, 'data': data, 'message': 'result'}),
  200,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
    ...?headers,
  },
);
String _token() =>
    'h.${base64Url.encode(utf8.encode(jsonEncode({'exp': DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/ 1000})))}.s';
const _user = {
  'id': 'u1',
  'username': 'alice',
  'account_level': 'normal',
  'is_locked': true,
  'created_at': '2026-11-12T00:00:00Z',
  'email': 'a@example.test',
};
const _admission = {
  'user_id': 'u1',
  'username': 'alice',
  'account_level': 'normal',
  'admission_status': 'pending',
  'apply_reason': 'Science',
  'applied_at': '2026-11-12T00:00:00Z',
};
Future<AdminApi> _api(
  _Adapter adapter, {
  String server = 'http://localhost:8000',
  bool login = true,
}) async {
  final prefs = await SharedPreferences.getInstance();
  final api = AdminApi(
    client: ApiClient(
      serverUrl: server,
      dio: Dio()..httpClientAdapter = adapter,
    ),
    prefs: prefs,
  );
  if (login) {
    await prefs.setString(api.accessStoreKey, _token());
    await prefs.setString(api.refreshStoreKey, 'refresh');
  }
  api.restore();
  return api;
}

Future<void> _pump(WidgetTester tester, AdminApi api, Widget child) async {
  await EasyLocalization.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  await tester.runAsync(() async {
    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('en', 'US')],
        path: 'assets/i18n',
        saveLocale: false,
        child: ProviderScope(
          overrides: [
            adminApiProvider.overrideWithValue(api),
            sharedPreferencesProvider.overrideWithValue(prefs),
          ],
          child: Builder(
            builder: (context) => MaterialApp(
              localizationsDelegates: context.localizationDelegates,
              supportedLocales: context.supportedLocales,
              locale: context.locale,
              home: Scaffold(body: child),
            ),
          ),
        ),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 200));
  });
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'admin projections use real stats/trend/queues and paginated user contract',
    () async {
      final adapter = _Adapter(
        (o) => switch (o.path) {
          '/admin/stats' => _json({
            'user_count': 4,
            'post_count': 3,
            'file_count': 2,
            'file_pending_count': 1,
          }),
          '/admin/stats/trend' => _json({
            'items': [
              {'date': '2026-11-12', 'user_delta': 2, 'post_delta': 1},
            ],
          }),
          '/admin/review-summary' => _json({
            'total_pending': 3,
            'queues': [
              {
                'key': 'files',
                'count': 3,
                'oldest_waiting_seconds': 7200,
                'href': '/admin/files',
              },
            ],
          }),
          '/admin/users' => _json({
            'items': [_user],
            'total': 21,
            'page': 2,
            'pages': 2,
          }),
          '/admin/admission/users' => _json([_admission]),
          _ => throw StateError(o.path),
        },
      );
      final api = await _api(adapter);
      expect((await api.stats()).pendingFiles, 1);
      expect((await api.trend()).single.users, 2);
      expect(adapter.requests.last.queryParameters, {'days': 14});
      expect((await api.reviewSummary()).queues.single.waitingSeconds, 7200);
      final users = await api.users(
        page: 2,
        keyword: ' alice ',
        includePii: true,
      );
      expect(users.pages, 2);
      expect(users.items.single.locked, isTrue);
      expect(users.items.single.email, 'a@example.test');
      expect(adapter.requests.last.queryParameters, {
        'page': 2,
        'limit': 20,
        'include_pii': true,
        'keyword': 'alice',
      });
      expect((await api.admissionUsers()).single.reason, 'Science');
      expect(adapter.requests.last.queryParameters, {'status': 'pending'});
      expect(
        adapter.requests.every(
          (o) => '${o.headers['Cookie']}'.startsWith('admin_session='),
        ),
        isTrue,
      );
    },
  );

  test(
    'admission validates rejection before sending and preserves MFA_REQUIRED',
    () async {
      final adapter = _Adapter((o) => _json(null, code: ApiCode.mfaRequired));
      final api = await _api(adapter);
      await expectLater(
        api.decideAdmission('u1', approve: false, reason: '  '),
        throwsArgumentError,
      );
      await expectLater(
        api.decideAdmission('u1', approve: false, reason: 'x' * 501),
        throwsArgumentError,
      );
      expect(adapter.requests, isEmpty);
      await expectLater(
        api.decideAdmission('u1', approve: false, reason: ' why '),
        throwsA(
          isA<ApiException>().having(
            (e) => e.code,
            'code',
            ApiCode.mfaRequired,
          ),
        ),
      );
      expect(adapter.requests.single.data, {
        'action': 'reject',
        'reason': 'why',
      });
      expect(
        adapter.requests.single.path,
        '/admin/admission/users/u1/decision',
      );
    },
  );

  test(
    'bot handles unavailable vs empty, and mints a fresh ticket per opening',
    () async {
      var tickets = 0;
      final adapter = _Adapter(
        (o) => o.path.endsWith('sso-ticket')
            ? _json({'ticket': 'one-use-${++tickets}', 'expires_in': 60})
            : o.path.endsWith('overview')
            ? _json({'configured': false, 'available': false})
            : o.path.endsWith('logs/history')
            ? _json({
                'configured': true,
                'available': false,
                'reason': 'unavailable',
                'logs': [],
              })
            : _json({'configured': true, 'available': true, 'items': []}),
      );
      final api = await _api(adapter);
      expect((await api.botData('overview')).configured, isFalse);
      expect((await api.botData('logs/history')).available, isFalse);
      for (final section in [
        'platforms',
        'providers',
        'config',
        'plugins',
        'knowledge',
      ]) {
        final data = await api.botData(section);
        expect(data.available, isTrue);
        expect(data.items, isEmpty);
      }
      expect(() => api.botData('../auth'), throwsArgumentError);
      expect(await api.botTicket(), 'one-use-1');
      expect(await api.botTicket(), 'one-use-2');
      final uri = adminBotPanelUri(
        'http://localhost:8123/api/v1',
        't+/?',
        '/data/logs',
      );
      expect(uri.origin, 'http://localhost:8123');
      expect(uri.path, '/bot/api/v1/auth/sso');
      expect(uri.queryParameters, {'ticket': 't+/?', 'next': '/data/logs'});
      expect(
        () => adminBotPanelUri('http://localhost', 't', '//external.test'),
        throwsArgumentError,
      );
      expect(
        () => adminBotPanelUri('file:///tmp', 't', '/'),
        throwsArgumentError,
      );
      expect(
        () => adminBotPanelUri('http://localhost', '', '/'),
        throwsArgumentError,
      );
    },
  );

  test(
    'admin cookies never cross deployments or restore unscoped legacy credentials',
    () async {
      final adapter = _Adapter((o) => _json(null));
      final first = await _api(adapter);
      final second = await _api(
        adapter,
        server: 'http://localhost:8001',
        login: false,
      );
      expect(first.isSignedIn, isTrue);
      expect(second.isSignedIn, isFalse);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(kAdminAccessTokenKey, _token());
      await prefs.setString(kAdminRefreshTokenKey, 'legacy');
      second.restore();
      expect(second.isSignedIn, isFalse);
      final restored = await _api(adapter, login: false);
      expect(restored.isSignedIn, isTrue);
    },
  );

  testWidgets(
    'admission confirms, steps up, and retries once with fresh cookies',
    (tester) async {
      var accepted = false;
      var verified = false;
      var writes = 0;
      final adapter = _Adapter((o) {
        if (o.path == '/admin/admission/users')
          return _json(accepted ? [] : [_admission]);
        if (o.path == '/admin/auth/2fa') {
          expect(o.data, {'code': '123456'});
          verified = true;
          return _json(
            {'ok': true},
            headers: {
              'set-cookie': ['admin_session=${_token()}; Path=/'],
            },
          );
        }
        writes++;
        expect(o.data, {'action': 'approve'});
        if (!verified) return _json(null, code: ApiCode.mfaRequired);
        accepted = true;
        return _json({..._admission, 'admission_status': 'approved'});
      });
      final api = await _api(adapter);
      await _pump(tester, api, const AdminAdmissionTab());
      expect(find.text('alice'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Approve'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(writes, 0);
      await tester.tap(find.widgetWithText(FilledButton, 'Approve').last);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Two-factor verification'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '123456');
      await tester.tap(find.widgetWithText(FilledButton, 'Verify'));
      await tester.pumpAndSettle();
      expect(writes, 2);
      expect(accepted, isTrue);
      expect(find.text('No records'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'bot unconfigured state is distinct from an empty resource list',
    (tester) async {
      final adapter = _Adapter(
        (o) => _json({'configured': false, 'available': false}),
      );
      final api = await _api(adapter);
      await _pump(tester, api, const AdminBotTab());
      expect(
        find.text('Bot is not connected to this deployment.'),
        findsOneWidget,
      );
      expect(find.text('No records'), findsNothing);
      expect(adapter.requests.single.path, '/admin/bot/overview');
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'users hide PII by default, reset search pagination and show locked state',
    (tester) async {
      final adapter = _Adapter(
        (o) => _json({
          'items': [_user],
          'total': 21,
          'page': o.queryParameters['page'],
          'pages': 2,
        }),
      );
      final api = await _api(adapter);
      await _pump(tester, api, const AdminUsersTab());
      expect(find.text('Locked'), findsOneWidget);
      expect(find.textContaining('a@example.test'), findsNothing);
      expect(adapter.requests.last.queryParameters['include_pii'], false);
      await tester.tap(find.byTooltip('adminPanel.next'.tr()));
      await tester.pumpAndSettle();
      expect(adapter.requests.last.queryParameters['page'], 2);
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      expect(adapter.requests.last.queryParameters['page'], 1);
      expect(adapter.requests.last.queryParameters['include_pii'], true);
      expect(find.textContaining('a@example.test'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'alice');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(adapter.requests.last.queryParameters['keyword'], 'alice');
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'dashboard sections fail independently and skip unauthorized activity feeds',
    (tester) async {
      final adapter = _Adapter(
        (o) => switch (o.path) {
          '/admin/auth/me' => _json({
            'id': 'a1',
            'permissions': ['admin.dashboard'],
          }),
          '/admin/stats' => _json({
            'user_count': 4,
            'post_count': 3,
            'file_count': 2,
            'file_pending_count': 1,
          }),
          '/admin/stats/trend' => _json(null, code: ApiCode.unavailable),
          '/admin/review-summary' => _json({'total_pending': 3, 'queues': []}),
          _ => throw StateError(o.path),
        },
      );
      final api = await _api(adapter);
      await _pump(tester, api, AdminDashboardTab(onOpen: (_) {}));
      expect(find.text('4'), findsOneWidget);
      expect(find.textContaining('result'), findsOneWidget);
      expect(find.text('Total pending: 3'), findsOneWidget);
      expect(
        adapter.requests.where(
          (o) => [
            '/admin/users',
            '/admin/content/items',
            '/admin/reports',
          ].contains(o.path),
        ),
        isEmpty,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
}
