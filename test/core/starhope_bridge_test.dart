import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:island/core/api/api_session.dart';
import 'package:island/data/database.dart';
import 'package:island/starhope/starhope_bridge.dart';
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

  test('scope normalizes server and isolates deployments and accounts', () {
    expect(starHopeUserId(_token('one')), 'one');
    expect(starHopeUserId('invalid'), isNull);
    expect(
      starHopeScope('http://localhost:8000/', 'one'),
      starHopeScope('http://localhost:8000/api/v1', 'one'),
    );
    expect(
      starHopeScope('http://localhost:8000', 'one'),
      isNot(starHopeScope('http://localhost:8001', 'one')),
    );
    expect(
      starHopeScope('http://localhost:8000', 'one'),
      isNot(starHopeScope('http://localhost:8000', 'two')),
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
      final bridge = StarHopeBridge(
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
      await bridge.call('pull', ['questions', '2026-11-11T00:00:00Z']);
      await bridge.call('push', ['sessions', [], []]);
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
      for (final args in [
        ['agents'],
        ['../auth/me'],
        ['https://elsewhere.invalid'],
        ['questions', 'bad-time'],
      ]) {
        expect(jsonDecode(await bridge.call('pull', args))['error'], 'invalid');
      }
      expect(
        jsonDecode(await bridge.call('request', ['http://localhost']))['error'],
        'invalid',
      );
      expect(
        jsonDecode(
          await bridge.call('push', ['questions', List.filled(501, {}), []]),
        )['error'],
        'invalid',
      );
      expect(adapter.requests.length, 2);
      current = false;
      expect(jsonDecode(await bridge.call('load', []))['error'], 'session');
      expect(
        jsonDecode(await bridge.call('push', ['questions', [], []]))['error'],
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
      final bridge = StarHopeBridge(
        session: session,
        userId: 'one',
        isCurrent: () => true,
        read: () async => 'durable',
        save: (_) async {},
        locale: 'en-US',
        dark: false,
      );
      expect(
        jsonDecode(await bridge.call('pull', ['questions']))['error'],
        'offline',
      );
      expect(jsonDecode(await bridge.call('load', []))['data'], 'durable');
      expect(jsonDecode(await bridge.call('save', ['{}']))['error'], 'invalid');
      expect(jsonDecode(await bridge.call('save', [1]))['error'], 'invalid');
    },
  );

  test(
    'Drift reopens offline snapshots and chat snapshots do not erase them',
    () async {
      final directory = await Directory.systemTemp.createTemp('lkm-starhope-');
      final scope = starHopeScope('http://localhost:8000', 'one');
      var db = AppDatabase.native(Future.value(directory.path));
      try {
        await db.saveStarHope(scope, '{"offline":"question"}');
        expect(await db.readStarHope('different-scope'), isNull);
        // Normal chat cache writes still exercise the existing persistence path.
        await db.getDatabaseStats();
        await db.close();
        db = AppDatabase.native(Future.value(directory.path));
        expect(await db.readStarHope(scope), '{"offline":"question"}');
        await db.reset();
        db = AppDatabase.native(Future.value(directory.path));
        expect(await db.readStarHope(scope), isNull);
      } finally {
        await db.close();
        await directory.delete(recursive: true);
      }
    },
  );
}
