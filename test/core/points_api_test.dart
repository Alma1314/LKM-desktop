import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:island/core/api/api_client.dart';
import 'package:island/core/api/points_api.dart';

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

PointsApi _api(_Adapter adapter) => PointsApi(
  ApiClient(
    serverUrl: 'https://lkm-ahz.ltd',
    dio: Dio()..httpClientAdapter = adapter,
  ),
);

void main() {
  test('balance decodes user id and amount', () async {
    final adapter = _Adapter(
      (_) => _envelope({'user_id': 'u1', 'balance': 42}),
    );
    final balance = await _api(adapter).balance();

    expect(balance.userId, 'u1');
    expect(balance.balance, 42);
    expect(adapter.requests.single.path, '/points/me');
    expect(adapter.requests.single.method, 'GET');
  });

  test('ledger sends pagination and decodes entries', () async {
    final adapter = _Adapter(
      (_) => _envelope({
        'items': [
          {
            'id': 'l1',
            'delta': -200,
            'balance_after': 800,
            'reason': 'transfer_out',
            'ref_type': 'qa_bounty',
            'ref_id': 'q1',
            'created_at': '2026-11-10T08:30:00Z',
          },
        ],
        'total': 21,
        'page': 2,
        'pages': 3,
      }),
    );
    final page = await _api(adapter).ledger(page: 2, limit: 20);

    final request = adapter.requests.single;
    expect(request.path, '/points/me/ledger');
    expect(request.queryParameters['page'], 2);
    expect(request.queryParameters['limit'], 20);
    expect(page.total, 21);
    expect(page.hasMore, isTrue);
    expect(page.items.single.delta, -200);
    expect(page.items.single.reason, 'transfer_out');
    expect(page.items.single.createdAt.isUtc, isFalse);
    expect(
      page.items.single.createdAt.toUtc(),
      DateTime.utc(2026, 11, 10, 8, 30),
    );
  });

  test('checkin posts and decodes streak', () async {
    final adapter = _Adapter(
      (_) => _envelope({
        'success': true,
        'earned': 5,
        'checkin_streak': 7,
        'today_checked': false,
      }),
    );
    final result = await _api(adapter).checkin();

    expect(adapter.requests.single.method, 'POST');
    expect(adapter.requests.single.path, '/points/checkin');
    expect(result.success, isTrue);
    expect(result.earned, 5);
    expect(result.checkinStreak, 7);
    expect(result.todayChecked, isFalse);
  });

  test('leaderboard passes period and decodes titles', () async {
    final adapter = _Adapter(
      (_) => _envelope({
        'items': [
          {
            'user_id': 'u1',
            'display_name': 'alma',
            'balance': 900,
            'title': 'hardcore',
          },
        ],
        'total': 1,
        'page': 1,
        'pages': 1,
      }),
    );
    final page = await _api(adapter).leaderboard(period: 'weekly');

    expect(adapter.requests.single.queryParameters['period'], 'weekly');
    expect(page.items.single.displayName, 'alma');
    expect(page.items.single.title, 'hardcore');
    expect(page.hasMore, isFalse);
  });

  test('achievements decode a bare list', () async {
    final adapter = _Adapter(
      (_) => _envelope([
        {
          'id': 'a9',
          'key': 'a9',
          'category': 'activity',
          'icon': 'tabler:calendar-check',
          'name_key': 'contributionData.achievements.a9.name',
          'desc_key': 'contributionData.achievements.a9.description',
          'type': 'checkin_streak',
          'threshold': 7,
          'reward_points': 0,
          'sort_order': 9,
          'progress': 3,
          'unlocked': false,
        },
      ]),
    );
    final items = await _api(adapter).achievements();

    expect(items.single.key, 'a9');
    expect(items.single.progressRatio, closeTo(3 / 7, 0.0001));
    expect(items.single.unlocked, isFalse);
  });

  test('tasks and exchange items decode bare lists', () async {
    final adapter = _Adapter((options) {
      if (options.path == '/points/tasks') {
        return _envelope([
          {
            'id': 't1',
            'key': 't1',
            'title_key': 'contributionData.tasks.t1.title',
            'desc_key': 'contributionData.tasks.t1.description',
            'category': 'checkin',
            'requirement_count': 1,
            'reward_points': 5,
            'sort_order': 1,
            'current_progress': 1,
            'completed': true,
          },
        ]);
      }
      return _envelope([
        {
          'id': 'e1',
          'key': 'e1',
          'name_key': 'contributionData.exchangeItems.e1.name',
          'desc_key': 'contributionData.exchangeItems.e1.description',
          'points_cost': 200,
          'stock': -1,
          'is_virtual': true,
          'sort_order': 1,
        },
      ]);
    });

    final api = _api(adapter);
    final tasks = await api.tasks();
    final items = await api.exchangeItems();

    expect(tasks.single.completed, isTrue);
    expect(tasks.single.progressRatio, 1.0);
    expect(items.single.pointsCost, 200);
    expect(items.single.stock, -1);
    expect(items.single.soldOut, isFalse);
    expect(items.single.lowStock, isFalse);
  });

  test('business errors surface as ApiException', () async {
    final adapter = _Adapter(
      (_) => _json(
        {'code': (2 << 16) | 1, 'message': '积分余额不足', 'data': null},
      ),
    );

    await expectLater(
      _api(adapter).balance(),
      throwsA(
        isA<ApiException>().having((e) => e.message, 'message', '积分余额不足'),
      ),
    );
  });
}
