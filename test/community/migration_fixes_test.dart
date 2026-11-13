import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:island/core/api/api_client.dart';
import 'package:island/core/api/api_providers.dart';
import 'package:island/core/api/api_session.dart';
import 'package:island/core/api/users_api.dart';
import 'package:island/core/config.dart';
import 'package:island/community/my_content_screen.dart';
import 'package:island/hub/hub_pod.dart';
import 'package:island/shared/widgets/api_page_list.dart';
import 'package:island/treehole/letters_view.dart';
import 'package:island/treehole/treehole_pod.dart';

class _Adapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  @override
  void close({bool force = false}) {}
  @override
  Future<ResponseBody> fetch(
    RequestOptions o,
    Stream<Uint8List>? s,
    Future<void>? c,
  ) async {
    requests.add(o);
    Object? data;
    if (o.path == '/treehole/letters') {
      data = [
        {
          'id': o.queryParameters['scope'],
          'content': '${o.queryParameters['scope']} letter',
          'privacy': o.queryParameters['scope'],
          'status': 'published',
          'codename': 'Reader',
        },
        {
          'id': 'mine',
          'content': 'Private own letter',
          'status': 'published',
          'isMine': true,
        },
      ];
    } else if (o.path.endsWith('/reply')) {
      data = {'conversationId': 'conversation'};
    } else if (o.uri.path == '/graphql/v1') {
      final page = (o.data as Map)['variables']['page'] as int;
      return ResponseBody.fromString(
        jsonEncode({
          'data': {
            'contentItems': {
              'items': [
                {'id': 'post-$page', 'title': 'Post'},
              ],
              'total': 21,
              'page': page,
              'pages': 2,
            },
          },
        }),
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    } else {
      final page = int.parse('${o.queryParameters['page'] ?? 1}');
      data = {
        'items': [
          {'id': 'q-$page', 'title': 'Question'},
        ],
        'total': 21,
        'page': page,
        'pages': 2,
      };
    }
    return ResponseBody.fromString(
      jsonEncode({'code': 0, 'data': data}),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }
}

Future<({ProviderContainer container, ApiSession session, _Adapter adapter})>
_setup() async {
  SharedPreferences.setMockInitialValues({'lkm_treehole_session': 'visitor'});
  final prefs = await SharedPreferences.getInstance();
  final adapter = _Adapter();
  final session = ApiSession(
    prefs: prefs,
    serverUrl: kLkmServerDefault,
    dio: Dio()..httpClientAdapter = adapter,
  );
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      lkmApiSessionProvider.overrideWithValue(session),
    ],
  );
  addTearDown(container.dispose);
  addTearDown(session.dispose);
  return (container: container, session: session, adapter: adapter);
}

Future<void> _pump(
  WidgetTester tester,
  ProviderContainer container,
  Widget child,
) async {
  await EasyLocalization.ensureInitialized();
  await tester.runAsync(() async {
    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('en', 'US')],
        path: 'assets/i18n',
        saveLocale: false,
        child: UncontrolledProviderScope(
          container: container,
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
    await Future<void>.delayed(const Duration(milliseconds: 30));
  });
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'avatar keys resolve against the current deployment with versioned cache URLs',
    () {
      final first = Uri.parse(
        userAvatarUrl('https://a.example', 'u1', 'avatars/u1/v1.webp')!,
      );
      expect(first.host, 'a.example');
      expect(first.path, '/api/v1/auth/avatar/u1');
      expect(first.queryParameters['v'], 'avatars/u1/v1.webp');
      expect(
        userAvatarUrl('https://a.example', 'u1', 'avatars/u1/v2.webp'),
        isNot(first.toString()),
      );
      expect(
        Uri.parse(
          userAvatarUrl('https://b.example', 'u1', 'avatars/u1/v1.webp')!,
        ).host,
        'b.example',
      );
      expect(userAvatarUrl('https://a.example', 'u1', null), isNull);
    },
  );

  test(
    'my content and the QA hall request subsequent pages instead of truncating',
    () async {
      final setup = await _setup();
      final q = await setup.container.read(
        myQuestionsProvider((authorId: 'u1', page: 2)).future,
      );
      expect(q.items.single.id, 'q-2');
      final hall = await setup.container.read(
        qaQuestionsProvider((category: null, sort: 'newest', page: 2)).future,
      );
      expect(hall.page, 2);
      final posts = await setup.container.read(
        myPostsProvider((authorId: 'u1', page: 2)).future,
      );
      expect(posts.items.single.id, 'post-2');
      expect(
        setup.adapter.requests
            .where((r) => r.queryParameters['page'] == 2)
            .length,
        2,
      );
    },
  );

  testWidgets(
    'page two failure can retry and previous page remains accessible',
    (tester) async {
      final setup = await _setup();
      var fail = true;
      final pages = FutureProvider.autoDispose.family<ApiPage<String>, int>((
        ref,
        page,
      ) async {
        if (page == 2 && fail)
          throw const ApiException(code: 5, message: 'Offline page');
        return ApiPage(
          items: [page == 1 ? 'First page' : 'Older content'],
          total: 2,
          page: page,
          pages: 2,
        );
      });
      await _pump(
        tester,
        setup.container,
        ApiPageList<String>(
          provider: pages.call,
          itemBuilder: (_, item) => Text(item),
        ),
      );
      await tester.tap(find.byTooltip('Next page'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Offline page'), findsOneWidget);
      fail = false;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('Older content'), findsOneWidget);
      await tester.tap(find.byTooltip('Previous page'));
      await tester.pumpAndSettle();
      expect(find.text('First page'), findsOneWidget);
    },
  );

  testWidgets(
    'random reading mixes scopes, excludes own letters and switches one at a time',
    (tester) async {
      final setup = await _setup();
      final pool = (await tester.runAsync(
        () => setup.container.read(treeholeRandomLettersProvider.future),
      ))!;
      expect(pool.map((l) => l.id).toSet(), {'public', 'random'});
      await _pump(
        tester,
        setup.container,
        const TreeholeLettersView(scope: 'random'),
      );
      expect(find.text('Private own letter'), findsNothing);
      expect(find.text('public letter'), findsNothing);
      await tester.runAsync(() async {
        await tester.tap(find.text('Draw a letter'));
        await setup.container.read(treeholeRandomLettersProvider.future);
      });
      await tester.pumpAndSettle();
      final publicFirst = find.text('public letter').evaluate().isNotEmpty;
      expect(
        find.text(publicFirst ? 'public letter' : 'random letter'),
        findsOneWidget,
      );
      await tester.runAsync(() async {
        await tester.tap(find.text('Another letter'));
        await setup.container.read(treeholeRandomLettersProvider.future);
      });
      await tester.pumpAndSettle();
      expect(
        find.text(publicFirst ? 'random letter' : 'public letter'),
        findsOneWidget,
      );
      expect(
        find.text(publicFirst ? 'public letter' : 'random letter'),
        findsNothing,
      );
      expect(find.text('Private own letter'), findsNothing);
      expect(find.text('Reply'), findsOneWidget);
    },
  );
}
