import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:auto_route/auto_route.dart';
import 'package:island/route.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:island/community/user_pod.dart';
import 'package:island/core/api/api_providers.dart';
import 'package:island/core/api/api_session.dart';
import 'package:island/core/config.dart';
import 'package:island/exam/exam_pod.dart';
import 'package:island/misc/dashboard/community_cards.dart';
import 'package:island/misc/dashboard/dash.dart';
import 'package:island/misc/dashboard/dashboard_layout.dart';
import 'package:island/misc/legal_document.dart';
import 'package:island/points/points_pod.dart';
import 'package:island/route.gr.dart';

class _Adapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  final fail = <String>{};
  @override
  void close({bool force = false}) {}
  @override
  Future<ResponseBody> fetch(
    RequestOptions o,
    Stream<Uint8List>? stream,
    Future<void>? cancel,
  ) async {
    requests.add(o);
    if (fail.contains(o.path)) {
      throw DioException.connectionError(requestOptions: o, reason: 'offline');
    }
    final future = DateTime.now()
        .add(const Duration(days: 30))
        .toUtc()
        .toIso8601String();
    final past = DateTime.now()
        .subtract(const Duration(days: 30))
        .toUtc()
        .toIso8601String();
    Map<String, dynamic> question(
      String id, {
      String status = 'open',
      int bounty = 50,
      String? expires,
    }) => {
      'id': id,
      'title': id,
      'status': status,
      'bounty_total': bounty,
      'bounty_distributed': 0,
      'bounty_expires_at': expires ?? future,
      'author_name': 'Ada',
    };
    Map<String, dynamic> page(List<Object?> items) => {
      'items': items,
      'page': 1,
      'pages': 1,
      'total': items.length,
    };
    final path = o.path.startsWith('http') ? o.uri.path : o.path;
    final data = switch (path) {
      '/auth/me' => {'id': 'one', 'username': 'Ada'},
      '/content/qa/questions' => page([
        question('Closed', status: 'closed'),
        question('Free', bounty: 0),
        question('Expired', expires: past),
        question('Bounty optics'),
      ]),
      '/projects' => [
        {'id': 'p0', 'title': 'Archived project', 'is_recruiting': false},
        {'id': 'p1', 'title': 'Recruiting telescope', 'is_recruiting': true},
        {
          'id': 'p2',
          'title': 'Pinned science',
          'is_recruiting': true,
          'is_pinned': true,
        },
      ],
      '/graphql/v1' => {
        'contentItems': page([
          {'id': 'c0', 'title': 'Ordinary column', 'isFeatured': false},
          {'id': 'c1', 'title': 'Featured gravity', 'isFeatured': true},
        ]),
      },
      '/exam' => page([
        {'id': 'e0', 'title': 'Finished exam', 'ends_at': past},
        {
          'id': 'e1',
          'title': 'Future math cup',
          'type': 'competition',
          'starts_at': future,
        },
      ]),
      '/points/me' => {'user_id': 'one', 'balance': 1729},
      '/points/leaderboard' => page([
        {'user_id': 'one', 'display_name': 'Ada', 'balance': 42},
      ]),
      '/exam/certificates/mine' => [
        {'id': 'cert', 'passed': true},
      ],
      _ => throw StateError('Unexpected request: ${o.path}'),
    };
    return ResponseBody.fromString(
      jsonEncode(
        path == '/graphql/v1' ? {'data': data} : {'code': 0, 'data': data},
      ),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }
}

Future<(ProviderContainer, ApiSession, _Adapter)> _container() async {
  final prefs = await SharedPreferences.getInstance();
  final adapter = _Adapter();
  final session = ApiSession(
    prefs: prefs,
    serverUrl: 'http://localhost:8000',
    dio: Dio()..httpClientAdapter = adapter,
  );
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      lkmApiSessionProvider.overrideWithValue(session),
    ],
  );
  addTearDown(container.dispose);
  addTearDown(session.client.close);
  return (container, session, adapter);
}

Future<void> _pump(
  WidgetTester tester,
  ProviderContainer container,
  Widget child, {
  Size size = const Size(1200, 1000),
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.runAsync(() async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: EasyLocalization(
          supportedLocales: const [Locale('en', 'US')],
          path: 'assets/i18n',
          saveLocale: false,
          child: Builder(
            builder: (context) => child is LegalDocumentScreen
                ? MaterialApp.router(
                    theme: ThemeData(fontFamily: 'Nunito'),
                    routerConfig: container
                        .read(routerProvider)
                        .config(
                          deepLinkBuilder: (_) =>
                              DeepLink.path('/${child.document}'),
                        ),
                    localizationsDelegates: context.localizationDelegates,
                    locale: context.locale,
                    supportedLocales: context.supportedLocales,
                  )
                : MaterialApp(
                    theme: ThemeData(fontFamily: 'Nunito'),
                    localizationsDelegates: context.localizationDelegates,
                    locale: context.locale,
                    supportedLocales: context.supportedLocales,
                    home: StackRouterScope(
                      controller: container.read(routerProvider),
                      stateHash: 0,
                      child: Scaffold(body: child),
                    ),
                  ),
          ),
        ),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 100));
  });
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final font = FontLoader('Nunito')
      ..addFont(rootBundle.load('assets/fonts/Nunito-Regular.ttf'));
    await font.load();
    final symbols =
        FontLoader(
      'packages/material_symbols_icons/MaterialSymbolsOutlined',
        )..addFont(
          rootBundle.load(
        'packages/material_symbols_icons/lib/fonts/MaterialSymbolsOutlined.ttf',
          ),
        );
    await symbols.load();
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues({
      kAppDashboardConfig: jsonEncode({
        'vertical_layouts': [],
        'horizontal_layouts': [],
        'show_clock_and_countdown': false,
        'show_search_bar': true,
      }),
    });
    await EasyLocalization.ensureInitialized();
  });

  test(
    'home reads real public contracts and excludes ineligible records',
    () async {
      final (c, _, a) = await _container();
      final questions = await c.read(
        dashboardEntriesProvider('questions').future,
      );
      final projects = await c.read(
        dashboardEntriesProvider('projects').future,
      );
      final columns = await c.read(dashboardEntriesProvider('columns').future);
      final exams = await c.read(
        dashboardEntriesProvider('competitions').future,
      );
      expect(questions.map((e) => e.title), ['Bounty optics']);
      expect(questions.single.route, isA<QaDetailRoute>());
      expect(projects.map((e) => e.title), [
        'Pinned science',
        'Recruiting telescope',
      ]);
      expect(projects.first.route, isA<ProjectDetailRoute>());
      expect(columns.single.title, 'Featured gravity');
      expect(columns.single.route, isA<ContentDetailRoute>());
      expect(exams.single.title, 'Future math cup');
      expect(exams.single.route, isA<ExamDetailRoute>());
      expect(a.requests.first.queryParameters, containsPair('sort', 'bounty'));
      expect(a.requests.first.queryParameters, containsPair('limit', 50));
      final graphql = a.requests.singleWhere(
        (o) => o.uri.path == '/graphql/v1',
      );
      expect(graphql.data['variables']['contentType'], 'column_post');
      expect(
        a.requests.any((o) => o.headers.containsKey('Authorization')),
        isFalse,
      );
    },
  );

  test('personal data clears and reloads on account invalidation', () async {
    final (c, session, a) = await _container();
    final balance = c.listen(lkmPointsBalanceProvider, (_, _) {});
    final certs = c.listen(myCertificatesProvider, (_, _) {});
    addTearDown(balance.close);
    addTearDown(certs.close);
    expect(await c.read(lkmPointsBalanceProvider.future), isNull);
    expect(await c.read(myCertificatesProvider.future), isEmpty);
    expect(a.requests, isEmpty);
    await session.adopt(
      LkmTokenPair(
        accessToken: 'access',
        accessExpiresAt: DateTime.now().add(const Duration(hours: 1)),
      ),
    );
    c.invalidate(lkmMeProvider);
    expect((await c.read(lkmPointsBalanceProvider.future))!.balance, 1729);
    expect((await c.read(myCertificatesProvider.future)).single.passed, isTrue);
    await session.signOut(revoke: false);
    c.invalidate(lkmMeProvider);
    expect(await c.read(lkmPointsBalanceProvider.future), isNull);
    expect(await c.read(myCertificatesProvider.future), isEmpty);
  });

  test(
    'default and saved upstream layouts migrate without duplicate cards',
    () {
      expect(
        DashboardLayout.resolveCardLayouts(null),
        DashboardLayout.defaultCardLayouts,
      );
      expect(
        DashboardLayout.resolveCardLayouts([
          'checkIn',
          'weather',
          'fortuneCard',
          'postFeatured',
          'friendsOverview',
          'notifications',
          'chatList',
          'fortuneGraph',
        ]),
        DashboardLayout.defaultCardLayouts,
      );
      expect(
        DashboardLayout.resolveCardLayouts([
          'chatList',
          'postsColumn',
          'postFeatured',
          'weather',
          'accountUnactivated',
        ]),
        ['chatList', 'columns', 'weather'],
      );
    },
  );

  testWidgets(
    'a failed section offers retry while other real sections render',
    (tester) async {
      final (c, _, a) = await _container();
      a.fail.add('/content/qa/questions');
      await _pump(
        tester,
        c,
        const Column(
          children: [
            CommunityDashboardCard(kind: 'questions'),
            CommunityDashboardCard(kind: 'projects'),
          ],
        ),
      );
      expect(find.text('Could not load this section'), findsOneWidget);
      expect(find.text('Recruiting telescope'), findsOneWidget);
      a.fail.clear();
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('Bounty optics'), findsOneWidget);
      expect(find.text('Could not load this section'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  for (final width in [400.0, 1400.0]) {
    testWidgets('upstream home layout supports guests at width $width', (
      tester,
    ) async {
      final (c, _, _) = await _container();
      final key = GlobalKey();
      await _pump(
        tester,
        c,
        RepaintBoundary(
          key: key,
          child: const Scaffold(body: DashboardGrid()),
        ),
        size: Size(width, 1100),
      );
      expect(find.text('Welcome to LKM'), findsOneWidget);
      if (width == 400) {
        await tester.drag(
          find.byType(CustomScrollView).first,
          const Offset(0, -600),
        );
        await tester.pumpAndSettle();
      }
      expect(find.text('Bounty optics'), findsOneWidget);
      expect(tester.takeException(), isNull);
      final output = Platform.environment['W7_SCREENSHOT'];
      if (output != null && width == 1400) {
        await tester.runAsync(() async {
          final image =
              await (key.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary)
                  .toImage(pixelRatio: 1);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          File(output).writeAsBytesSync(bytes!.buffer.asUint8List());
        });
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
    });
  }

  for (final name in ['privacy', 'terms']) {
    testWidgets('packaged $name document loads offline', (tester) async {
      final (c, _, a) = await _container();
      await _pump(tester, c, LegalDocumentScreen(document: name));
      expect(
        find.text('This document is provided in Simplified Chinese.'),
        findsOneWidget,
      );
      expect(
        find.textContaining('2026年11月13日', findRichText: true),
        findsOneWidget,
      );
      expect(a.requests, isEmpty);
      expect(c.read(routerProvider).currentPath, '/legal/$name');
      expect(tester.takeException(), isNull);
    });
  }
}
