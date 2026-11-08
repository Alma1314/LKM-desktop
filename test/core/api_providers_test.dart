import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:island/core/api/api_providers.dart';
import 'package:island/core/config.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

ResponseBody _health(Object? data, {int code = 0}) => ResponseBody.fromString(
  jsonEncode({'code': code, 'message': 'ok', 'data': data}),
  200,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

Dio _dio(_Adapter adapter) => Dio()..httpClientAdapter = adapter;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LkmServerUrlNotifier', () {
    test('defaults to the LKM host and stores the bare domain', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(container.dispose);

      expect(container.read(lkmServerUrlProvider), kLkmServerDefault);

      final error = container
          .read(lkmServerUrlProvider.notifier)
          .setServer('http://127.0.0.1:8000/api/v1/');

      expect(error, isNull);
      expect(container.read(lkmServerUrlProvider), 'http://127.0.0.1:8000');
      expect(prefs.getString(kLkmServerStoreKey), 'http://127.0.0.1:8000');
    });

    test('rejects a scheme-less address without touching storage', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(container.dispose);

      final error = container
          .read(lkmServerUrlProvider.notifier)
          .setServer('lkm-ahz.ltd');

      expect(error, isNotNull);
      expect(container.read(lkmServerUrlProvider), kLkmServerDefault);
      expect(prefs.getString(kLkmServerStoreKey), isNull);
    });
  });

  group('LkmServerProbe', () {
    test('reads a healthy envelope', () async {
      final adapter = _Adapter(
        (_) => _health({
          'status': 'ok',
          'db': {'status': 'up'},
          'redis': {'status': 'up'},
          'auth': {'status': 'disabled'},
        }),
      );

      final probe = await LkmServerProbe.check(
        'https://lkm-ahz.ltd',
        dio: _dio(adapter),
      );

      expect(probe.reachable, isTrue);
      expect(probe.isLkmService, isTrue);
      expect(probe.isHealthy, isTrue);
      expect(probe.dependencies['db'], 'up');
      expect(
        adapter.requests.single.uri.toString(),
        'https://lkm-ahz.ltd/api/v1/health',
      );
    });

    test('reports degraded without failing', () async {
      final adapter = _Adapter(
        (_) => _health({
          'status': 'degraded',
          'db': {'status': 'up'},
          'redis': {'status': 'error'},
          'auth': {'status': 'disabled'},
        }),
      );

      final probe = await LkmServerProbe.check(
        'https://lkm-ahz.ltd',
        dio: _dio(adapter),
      );

      expect(probe.isLkmService, isTrue);
      expect(probe.isHealthy, isFalse);
      expect(probe.dependencies['redis'], 'error');
    });

    test('separates "answered but not LKM" from "offline"', () async {
      final foreign = _Adapter(
        (_) => ResponseBody.fromString('<html>hi</html>', 200),
      );
      final foreignProbe = await LkmServerProbe.check(
        'https://example.com',
        dio: _dio(foreign),
      );
      expect(foreignProbe.reachable, isTrue);
      expect(foreignProbe.isLkmService, isFalse);

      final offline = _Adapter((options) {
        throw DioException(
          requestOptions: options,
          type: DioExceptionType.connectionError,
        );
      });
      final offlineProbe = await LkmServerProbe.check(
        'http://127.0.0.1:8000',
        dio: _dio(offline),
      );
      expect(offlineProbe.reachable, isFalse);
      expect(offlineProbe.message, '无法连接服务器');
    });
  });
}
