import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:island/core/api/lkm_ws.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class _FakeSink implements WebSocketSink {
  final List<String> added = [];
  final Completer<void> _done = Completer<void>();

  @override
  void add(dynamic data) => added.add('$data');

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future<void> addStream(Stream stream) async {
    await for (final item in stream) {
      add(item);
    }
  }

  @override
  Future<void> close([int? closeCode, String? closeReason]) async {
    if (!_done.isCompleted) _done.complete();
  }

  @override
  Future<void> get done => _done.future;
}

class _FakeWsChannel extends StreamChannelMixin implements WebSocketChannel {
  final _incoming = StreamController<dynamic>.broadcast();
  final fakeSink = _FakeSink();

  @override
  Stream<dynamic> get stream => _incoming.stream;

  @override
  WebSocketSink get sink => fakeSink;

  @override
  String? get protocol => null;

  @override
  int? get closeCode => null;

  @override
  String? get closeReason => null;

  @override
  Future<void> get ready => Future<void>.value();

  void push(String frame) => _incoming.add(frame);

  Future<void> drop() => _incoming.close();
}

void main() {
  test('connects with the query token and channel list', () async {
    Uri? captured;
    final fake = _FakeWsChannel();
    final client = LkmWsClient(
      serverUrl: 'https://community.example/api/v1',
      tokenProvider: () => 'tok',
      connect: (uri) {
        captured = uri;
        return fake;
      },
    );
    addTearDown(client.close);

    client.connect();

    expect(captured!.scheme, 'wss');
    expect(captured!.host, 'community.example');
    expect(captured!.path, '/api/v1/ws/events');
    expect(captured!.queryParameters['token'], 'tok');
    expect(captured!.queryParameters['channels'], 'upload,notify');
  });

  test('signed out means no socket is opened', () async {
    var attempts = 0;
    final client = LkmWsClient(
      serverUrl: 'https://community.example',
      tokenProvider: () => null,
      connect: (_) {
        attempts += 1;
        return _FakeWsChannel();
      },
    );
    addTearDown(client.close);

    client.connect();

    expect(attempts, 0);
    expect(client.isConnected, isFalse);
  });

  test('answers a server ping with pong', () async {
    final fake = _FakeWsChannel();
    final client = LkmWsClient(
      serverUrl: 'https://community.example',
      tokenProvider: () => 'tok',
      connect: (_) => fake,
    );
    addTearDown(client.close);
    client.connect();

    fake.push('{"type":"ping"}');
    await Future<void>.delayed(Duration.zero);

    expect(fake.fakeSink.added.map(jsonDecode), [
      {'type': 'pong'},
    ]);
  });

  test('refreshes the token before pong when it rotated', () async {
    var token = 'tok-old';
    final fake = _FakeWsChannel();
    final client = LkmWsClient(
      serverUrl: 'https://community.example',
      tokenProvider: () => token,
      connect: (_) => fake,
    );
    addTearDown(client.close);
    client.connect();

    token = 'tok-new';
    fake.push('{"type":"ping"}');
    await Future<void>.delayed(Duration.zero);

    final frames = fake.fakeSink.added.map(
      (frame) => jsonDecode(frame) as Map<String, dynamic>,
    );
    expect(frames, [
      {'type': 'refresh', 'token': 'tok-new'},
      {'type': 'pong'},
    ]);
  });

  test('decodes push events and drops frames without an event name', () async {
    final fake = _FakeWsChannel();
    final client = LkmWsClient(
      serverUrl: 'https://community.example',
      tokenProvider: () => 'tok',
      connect: (_) => fake,
    );
    addTearDown(client.close);
    final received = <LkmWsEvent>[];
    final subscription = client.events.listen(received.add);
    addTearDown(subscription.cancel);

    client.connect();
    fake.push(
      '{"event":"notification_created","event_id":"e1","version":7,'
      '"notification_id":"n1"}',
    );
    fake.push('{"type":"whatever"}');
    fake.push('not json');
    await Future<void>.delayed(Duration.zero);

    expect(received.single.event, 'notification_created');
    expect(received.single.eventId, 'e1');
    expect(received.single.version, 7);
    expect(received.single.data['notification_id'], 'n1');
  });

  test('a dropped socket reconnects with backoff', () async {
    var attempts = 0;
    final channels = <_FakeWsChannel>[];
    final client = LkmWsClient(
      serverUrl: 'https://community.example',
      tokenProvider: () => 'tok',
      reconnectBaseDelay: const Duration(milliseconds: 10),
      connect: (_) {
        attempts += 1;
        final channel = _FakeWsChannel();
        channels.add(channel);
        return channel;
      },
    );
    addTearDown(client.close);

    client.connect();
    expect(attempts, 1);

    await channels.first.drop();
    await Future<void>.delayed(const Duration(milliseconds: 60));

    expect(attempts, 2);
    expect(client.isConnected, isTrue);
  });
}
