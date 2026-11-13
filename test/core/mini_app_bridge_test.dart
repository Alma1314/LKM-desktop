import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:island/core/api/api_session.dart';
import 'package:island/data/database.dart';
import 'package:island/mini_apps/mini_app_bridge.dart';
import 'package:island/mini_apps/mini_app_manifest.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:island/starhope/starhope_screen.dart';

class _Adapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  bool offline = false;
  @override
  void close({bool force = false}) {}
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? stream,
    Future<void>? cancel,
  ) async {
    requests.add(options);
    if (offline) {
      throw DioException.connectionError(
        requestOptions: options,
        reason: 'offline',
      );
    }
    return ResponseBody.fromString(
      jsonEncode({
        'code': 0,
        'data': options.method == 'GET'
            ? {
                'items': [],
                'tombstones': [],
                'server_time': '2026-11-12T00:00:00Z',
              }
            : {'synced': 1, 'server_time': '2026-11-12T00:00:00Z'},
      }),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }
}

String _token(String user) =>
    'h.${base64Url.encode(utf8.encode(jsonEncode({'user_id': user})))}.s';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  final app = parseMiniAppCatalog(
    File('assets/webf/manifest.json').readAsStringSync(),
  ).singleWhere((app) => app.id == 'starhope');

  test('scope normalizes server and isolates deployments and accounts', () {
    expect(miniAppUserId(_token('one')), 'one');
    expect(miniAppUserId('invalid'), isNull);
    expect(
      miniAppAccountScope('http://localhost:8000/', 'one'),
      miniAppAccountScope('http://localhost:8000/api/v1', 'one'),
    );
    expect(
      miniAppAccountScope('http://localhost:8000', 'one'),
      isNot(miniAppAccountScope('http://localhost:8001', 'one')),
    );
    expect(
      miniAppAccountScope('http://localhost:8000', 'one'),
      isNot(miniAppAccountScope('http://localhost:8000', 'two')),
    );
    expect(const StarHopeScreen(), isNotNull);
  });

  test(
    'bridge exposes only scoped data and limited StarHope endpoints, never credentials',
    () async {
      final adapter = _Adapter();
      final session = ApiSession(
        prefs: await SharedPreferences.getInstance(),
        serverUrl: 'http://localhost:8000',
        dio: Dio()..httpClientAdapter = adapter,
      );
      await session.adopt(LkmTokenPair(accessToken: _token('one')));
      String? stored;
      var current = true;
      final bridge = MiniAppBridge(
        app: app,
        session: session,
        userId: 'one',
        isCurrent: () => current,
        read: () async => stored,
        save: (value) async {
          stored = value;
        },
        locale: 'zh-CN',
        dark: true,
      );
      final context = jsonDecode(await bridge.call('context', []));
      expect(context['data'], {
        'apiVersion': 1,
        'appId': 'starhope',
        'version': '1.0.0',
        'userId': 'one',
        'locale': 'zh-CN',
        'dark': true,
      });
      expect(jsonEncode(context), isNot(contains(session.cachedAccessToken!)));
      final uuid = jsonDecode(await bridge.call('newId', []))['data'] as String;
      expect(uuid.length, 36);
      final payload = jsonEncode({'version': 1, 'entries': {}, 'cursors': {}});
      expect(jsonDecode(await bridge.call('save', [payload]))['ok'], isTrue);
      expect(jsonDecode(await bridge.call('load', []))['data'], payload);
      await bridge.call('request', [
        'questions.pull',
        {
          'query': {'since': '2026-11-11T00:00:00Z'},
        },
      ]);
      await bridge.call('request', [
        'sessions.push',
        {
          'body': {'upserts': [], 'deletes': []},
        },
      ]);
      expect(adapter.requests[0].uri.path, '/api/v1/starhope/questions');
      expect(
        adapter.requests[0].queryParameters['since'],
        '2026-11-11T00:00:00Z',
      );
      expect(
        adapter.requests[0].headers['Authorization'],
        'Bearer ${session.cachedAccessToken}',
      );
      expect(adapter.requests[1].uri.path, '/api/v1/starhope/sessions/sync');
      expect(adapter.requests[1].data, {'upserts': [], 'deletes': []});
      for (final name in [
        'agents',
        '../auth/me',
        'https://elsewhere.invalid',
      ]) {
        expect(
          jsonDecode(await bridge.call('request', [name, {}]))['error'],
          'forbidden',
        );
      }
      expect(
        jsonDecode(
          await bridge.call('request', [
            'questions.pull',
            {'path': 'https://elsewhere.invalid'},
          ]),
        )['error'],
        'invalid',
      );
      expect(
        jsonDecode(
          await bridge.call('request', [
            'questions.pull',
            {
              'headers': {'Authorization': 'injected'},
            },
          ]),
        )['error'],
        'invalid',
      );
      expect(
        jsonDecode(await bridge.call('save', ['not json']))['error'],
        'invalid',
      );
      expect(
        jsonDecode(
          await bridge.call('save', [
            jsonEncode('x' * MiniAppBridge.maxSnapshotBytes),
          ]),
        )['error'],
        'invalid',
      );
      expect(adapter.requests.length, 2);
      current = false;
      expect(jsonDecode(await bridge.call('load', []))['error'], 'session');
      expect(
        jsonDecode(
          await bridge.call('request', ['questions.push', {}]),
        )['error'],
        'session',
      );
      bridge.dispose();
      expect(jsonDecode(await bridge.call('context', []))['error'], 'session');
    },
  );

  test(
    'network failure keeps the local snapshot usable and errors redact transport details',
    () async {
      final adapter = _Adapter()..offline = true;
      final session = ApiSession(
        prefs: await SharedPreferences.getInstance(),
        serverUrl: 'http://localhost:8000',
        dio: Dio()..httpClientAdapter = adapter,
      );
      final bridge = MiniAppBridge(
        app: app,
        session: session,
        userId: 'one',
        isCurrent: () => true,
        read: () async => 'durable',
        save: (_) async {},
        locale: 'en-US',
        dark: false,
      );
      expect(
        jsonDecode(
          await bridge.call('request', ['questions.pull', {}]),
        )['error'],
        'offline',
      );
      expect(jsonDecode(await bridge.call('load', []))['data'], 'durable');
      expect(
        jsonDecode(await bridge.call('save', ['not json']))['error'],
        'invalid',
      );
      expect(jsonDecode(await bridge.call('save', [1]))['error'], 'invalid');
    },
  );

  test(
    'Drift reopens offline snapshots and chat snapshots do not erase them',
    () async {
      final directory = await Directory.systemTemp.createTemp('lkm-starhope-');
      final scope = miniAppAccountScope('http://localhost:8000', 'one');
      var db = AppDatabase.native(Future.value(directory.path));
      try {
        await db.saveMiniApp('starhope', scope, '{"offline":"question"}');
        expect(await db.readMiniApp('starhope', 'different-scope'), isNull);
        expect(await db.readMiniApp('notes', scope), isNull);
        await db.saveMiniApp('notes', scope, '["offline note"]');
        expect(
          await db.readMiniApp('starhope', scope),
          '{"offline":"question"}',
        );
        // Normal chat cache writes still exercise the existing persistence path.
        await db.getDatabaseStats();
        await db.close();
        db = AppDatabase.native(Future.value(directory.path));
        expect(
          await db.readMiniApp('starhope', scope),
          '{"offline":"question"}',
        );
        expect(await db.readMiniApp('notes', scope), '["offline note"]');
        await db.reset();
        db = AppDatabase.native(Future.value(directory.path));
        expect(await db.readMiniApp('starhope', scope), isNull);
        expect(await db.readMiniApp('notes', scope), isNull);
      } finally {
        await db.close();
        await directory.delete(recursive: true);
      }
    },
  );
  test(
    'legacy StarHope offline data migrates without changing account scopes',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'lkm-mini-app-migrate-',
      );
      final scope = miniAppAccountScope('http://localhost:8000', 'one');
      sqfliteFfiInit();
      final old = await databaseFactoryFfi.openDatabase(
        '${directory.path}/island.sqlite',
      );
      await old.execute(
        'CREATE TABLE starhope_workspaces(scope TEXT PRIMARY KEY, payload TEXT NOT NULL)',
      );
      await old.execute('INSERT INTO starhope_workspaces VALUES (?, ?)', [
        scope,
        '{"legacy":true}',
      ]);
      await old.close();
      var db = AppDatabase.native(Future.value(directory.path));
      try {
        expect(await db.readMiniApp('starhope', scope), '{"legacy":true}');
        expect(await db.readMiniApp('notes', scope), isNull);
        await db.saveMiniApp('starhope', scope, '{"new":true}');
        await db.close();
        db = AppDatabase.native(Future.value(directory.path));
        expect(await db.readMiniApp('starhope', scope), '{"new":true}');
      } finally {
        await db.close();
        await directory.delete(recursive: true);
      }
    },
  );
}
