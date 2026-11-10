import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:island/core/api/api_client.dart';
import 'package:island/core/api/treehole_api.dart';

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

const String _token = 'abcdefghijklmnopqrstuvwxyz0123456789ABCDEFG';

ResponseBody _json(
  Object? body, {
  int status = 200,
  Map<String, List<String>>? headers,
}) => ResponseBody.fromString(
  jsonEncode(body),
  status,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
    ...?headers,
  },
);

ResponseBody _envelope(Object? data) =>
    _json({'code': 0, 'message': 'ok', 'data': data});

ResponseBody _session() => _json(
  {
    'code': 0,
    'message': 'OK',
    'data': {'ready': true},
  },
  headers: {
    'set-cookie': [
      'lkm-treehole-session=$_token; Path=/api/v1/treehole; HttpOnly',
    ],
  },
);

Future<TreeholeApi> _api(_Adapter adapter) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  return TreeholeApi(
    ApiClient(
      serverUrl: 'https://lkm-ahz.ltd',
      dio: Dio()..httpClientAdapter = adapter,
    ),
    prefs,
  );
}

const _letterJson = {
  'id': 'l1',
  'content': '今天也没有人回我',
  'category': 'confess',
  'privacy': 'public',
  'codename': 'LostWhale123',
  'moods': ['孤独'],
  'tags': ['campus'],
  'sticker': '',
  'paper': 'paper',
  'status': 'published',
  'createdAt': 1762531200000,
  'likes': 3,
  'favorites': 1,
  'liked': true,
  'favorited': false,
  'isMine': false,
};

void main() {
  test('bootstraps the anonymous session once and reuses the cookie', () async {
    final adapter = _Adapter(
      (options) => options.path.endsWith('/session')
          ? _session()
          : _envelope([_letterJson]),
    );
    final api = await _api(adapter);

    await api.letters();
    await api.letters();

    expect(adapter.requests.map((r) => r.path), [
      '/treehole/session',
      '/treehole/letters',
      '/treehole/letters',
    ]);
    expect(
      adapter.requests[1].headers['Cookie'],
      'lkm-treehole-session=$_token',
    );
    expect(adapter.requests[1].queryParameters, {
      'scope': 'public',
      'page': 1,
      'limit': 100,
    });
  });

  test('parses letters, epoch millis included', () async {
    final adapter = _Adapter(
      (options) => options.path.endsWith('/session')
          ? _session()
          : _envelope([_letterJson]),
    );

    final letters = await (await _api(adapter)).letters();

    final letter = letters.single;
    expect(letter.id, 'l1');
    expect(letter.codename, 'LostWhale123');
    expect(letter.moods, ['孤独']);
    expect(letter.liked, isTrue);
    expect(letter.isMine, isFalse);
    expect(
      letter.createdAt,
      DateTime.fromMillisecondsSinceEpoch(1762531200000).toLocal(),
    );
  });

  test('toggleReaction returns the updated letter and kind', () async {
    final adapter = _Adapter(
      (options) => options.path.endsWith('/session')
          ? _session()
          : _envelope({
              'active': true,
              'letter': {..._letterJson, 'likes': 4, 'liked': true},
            }),
    );

    final letter = await (await _api(adapter)).toggleReaction('l1', 'like');

    expect(letter.likes, 4);
    expect(letter.liked, isTrue);
    expect(adapter.requests.last.path, '/treehole/letters/l1/reactions/like');
  });

  test('reply and report send the expected bodies', () async {
    final adapter = _Adapter(
      (options) => options.path.endsWith('/session')
          ? _session()
          : _envelope({'conversationId': 'c1'}),
    );
    final api = await _api(adapter);

    expect(await api.replyLetter('l1', '抱抱你'), 'c1');
    expect((adapter.requests.last.data as Map)['text'], '抱抱你');

    await api.report(
      targetType: 'letter',
      targetId: 'l1',
      reason: '不合适的内容',
    );
    final report = adapter.requests.last;
    expect(report.path, '/treehole/reports');
    expect(report.data, {
      'targetType': 'letter',
      'targetId': 'l1',
      'reason': '不合适的内容',
      'detail': '',
    });
  });

  test('wishes parse and light returns the new total', () async {
    final adapter = _Adapter((options) {
      if (options.path.endsWith('/session')) return _session();
      if (options.path.endsWith('/light')) return _envelope({'lights': 7});
      return _envelope([
        {
          'id': 'w1',
          'text': '希望明天会更好',
          'lights': 6,
          'createdAt': 1762531200000,
          'ownerId': 'me_local',
        },
      ]);
    });
    final api = await _api(adapter);

    final wish = (await api.wishes()).single;
    expect(wish.text, '希望明天会更好');
    expect(wish.lights, 6);
    expect(wish.isMine, isTrue);

    expect(await api.lightWish('w1'), 7);
    expect(adapter.requests.last.path, '/treehole/wishes/w1/light');
  });

  test('conversations expose messages and the peer codename', () async {
    final adapter = _Adapter((options) {
      if (options.path.endsWith('/session')) return _session();
      return _envelope([
        {
          'id': 'c1',
          'myLetterId': 'l1',
          'peerLetterId': 'l2',
          'peerCodename': '访客abc123',
          'myCodename': 'LostWhale123',
          'blocked': false,
          'updatedAt': 1762531200000,
          'messages': [
            {
              'id': 'm1',
              'text': '你好',
              'recalled': false,
              'from': 'me',
              'at': 1762531200000,
            },
          ],
        },
      ]);
    });

    final conv = (await (await _api(adapter)).conversations()).single;

    expect(conv.peerCodename, '访客abc123');
    expect(conv.messages.single.isMine, isTrue);
  });

  test('create and edit letters send the camelCase write payload', () async {
    final adapter = _Adapter(
      (options) => options.path.endsWith('/session')
          ? _session()
          : _envelope(_letterJson),
    );
    final api = await _api(adapter);
    final input = LkmLetterInput(
      content: '致未来的我',
      category: 'heal',
      privacy: 'self',
      codename: 'GentleMoon321',
      moods: ['期待'],
      tags: ['growth'],
      scheduledAt: DateTime.fromMillisecondsSinceEpoch(1763000000000),
    );

    await api.createLetter(input);
    expect(adapter.requests.last.method, 'POST');
    expect(adapter.requests.last.path, '/treehole/letters');
    expect(adapter.requests.last.data, {
      'content': '致未来的我',
      'category': 'heal',
      'privacy': 'self',
      'codename': 'GentleMoon321',
      'moods': ['期待'],
      'tags': ['growth'],
      'sticker': '',
      'paper': 'paper',
      'scheduledAt': 1763000000000,
    });

    await api.editLetter('l1', input);
    expect(adapter.requests.last.method, 'PUT');
    expect(adapter.requests.last.path, '/treehole/letters/l1');
  });

  test('a session reply without a cookie is a transport failure', () async {
    final adapter = _Adapter(
      (options) => _json({'code': 0, 'message': 'OK', 'data': {'ready': true}}),
    );

    await expectLater(
      (await _api(adapter)).letters(),
      throwsA(isA<ApiTransportException>()),
    );
  });
}
