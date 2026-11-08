import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:solar_network_sdk/solar_network_sdk.dart';
import 'package:test/test.dart';

/// A minimal gateway: upgrades one websocket per path and records every frame
/// the client puts on the wire.
class _FakeGateway {
  _FakeGateway._(this._server);

  final HttpServer _server;
  final List<Map<String, dynamic>> received = [];
  final _frames = StreamController<Map<String, dynamic>>.broadcast();
  WebSocket? _socket;

  static Future<_FakeGateway> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final gateway = _FakeGateway._(server);
    server.listen(gateway._handle);
    return gateway;
  }

  String get baseUrl => 'http://${_server.address.host}:${_server.port}';

  Future<void> _handle(HttpRequest request) async {
    final socket = await WebSocketTransformer.upgrade(request);
    _socket = socket;
    socket.listen((data) {
      final decoded = jsonDecode(data as String);
      if (decoded is! Map<String, dynamic>) return;
      received.add(decoded);
      _frames.add(decoded);
    }, onDone: () => _socket = null);
  }

  Future<void> push(Map<String, dynamic> frame) async {
    final socket = _socket;
    if (socket == null) throw StateError('no client connected');
    socket.add(jsonEncode(frame));
  }

  /// Waits until [predicate] holds for the frames received so far.
  Future<void> waitFor(
    bool Function(List<Map<String, dynamic>>) predicate, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    if (predicate(received)) return;
    final completer = Completer<void>();
    late StreamSubscription<Map<String, dynamic>> sub;
    sub = _frames.stream.listen((_) {
      if (!completer.isCompleted && predicate(received)) completer.complete();
    });
    try {
      await completer.future.timeout(timeout);
    } finally {
      await sub.cancel();
    }
  }

  Iterable<Map<String, dynamic>> acks() =>
      received.where((frame) => frame['type'] == kAckPacketType);

  Future<void> close() async {
    await _socket?.close();
    await _frames.close();
    await _server.close(force: true);
  }
}

/// A network the test drives: no platform channels, so it also proves the
/// service works with a caller-supplied monitor.
class _FakeNetworkMonitor implements NetworkMonitor {
  bool connected = true;
  String fingerprint = 'wifi';
  final _changes = StreamController<NetworkChange>.broadcast();

  void emit({bool? connected, String? fingerprint}) {
    this.connected = connected ?? this.connected;
    this.fingerprint = fingerprint ?? this.fingerprint;
    _changes.add(
      NetworkChange(connected: this.connected, fingerprint: this.fingerprint),
    );
  }

  @override
  Future<NetworkChange> current() async =>
      NetworkChange(connected: connected, fingerprint: fingerprint);

  @override
  Stream<NetworkChange> get changes => _changes.stream;
}

void main() {
  group('ackIdForFrame', () {
    test('reads the envelope stamp, not the payload', () {
      expect(
        ackIdForFrame({'type': 'messages.new', 'data': {}, '_ack_id': 'a1'}),
        'a1',
      );
      // An untracked family carries no stamp.
      expect(ackIdForFrame({'type': 'notifications.new', 'data': {}}), isNull);
      // The payload's own id is not a delivery stamp.
      expect(
        ackIdForFrame({
          'type': 'messages.new',
          'data': {'id': 'message-id'},
        }),
        isNull,
      );
      expect(ackIdForFrame({'type': 'ping', 'data': null}), isNull);
      expect(
        ackIdForFrame({'type': 'messages.new', 'data': {}, '_ack_id': '  '}),
        isNull,
      );
    });
  });

  group('control packets', () {
    test('encode the documented envelope', () {
      final ack = jsonDecode(encodeAckPacket('a1')) as Map<String, dynamic>;
      expect(ack['type'], kAckPacketType);
      expect(ack['data'], {'ack_id': 'a1'});

      final resume = jsonDecode(encodeResumePacket()) as Map<String, dynamic>;
      expect(resume['type'], kResumePacketType);
      expect(
        resume['data'],
        isNull,
        reason: 'resume carries no payload: the session identifies the buffer',
      );
    });
  });

  group('isWebSocketReconnect', () {
    test('only a false -> true transition is a reconnect', () {
      expect(
        isWebSocketReconnect(wasConnected: false, isConnected: true),
        isTrue,
      );
      expect(
        isWebSocketReconnect(wasConnected: true, isConnected: true),
        isFalse,
      );
      expect(
        isWebSocketReconnect(wasConnected: true, isConnected: false),
        isFalse,
      );
      expect(
        isWebSocketReconnect(wasConnected: null, isConnected: true),
        isFalse,
        reason: 'the first observation is the initial connect, not a reconnect',
      );
    });
  });

  group('SolarWebSocketService', () {
    late _FakeGateway gateway;
    late SolarWebSocketService service;

    setUp(() async {
      gateway = await _FakeGateway.start();
      service = SolarWebSocketService(
        uri: () => Uri.parse(
          '${gateway.baseUrl}/ws'.replaceFirst('http', 'ws'),
        ).replace(queryParameters: {'namespace': 'dev.solsynth.solian'}),
        token: () async => _jwtExpiringIn(const Duration(hours: 1)),
      );
      await service.connect();
      // Every connection generation asks for its pending buffer.
      await gateway.waitFor(
        (frames) => frames.any((f) => f['type'] == kResumePacketType),
      );
    });

    tearDown(() async {
      service.close();
      await gateway.close();
    });

    test('resumes exactly once per connection', () async {
      final resumes = gateway.received.where(
        (f) => f['type'] == kResumePacketType,
      );
      expect(resumes, hasLength(1));
      expect(resumes.single['data'], isNull);
      // The heartbeat is kicked immediately so the client does not wait a full
      // period for its first pong.
      await gateway.waitFor((frames) => frames.any((f) => f['type'] == 'ping'));
    });

    test('acks a stamped frame, and acks a repeat again', () async {
      await gateway.push({
        'type': 'messages.new',
        'data': {'id': 'm1'},
        '_ack_id': 'ack-1',
      });
      await gateway.waitFor((frames) => gateway.acks().isNotEmpty);
      expect((gateway.acks().single['data'] as Map)['ack_id'], 'ack-1');

      // A re-delivery means the gateway never saw the previous ack, so the
      // client must answer again rather than deduplicating the ack.
      await gateway.push({
        'type': 'messages.new',
        'data': {'id': 'm1'},
        '_ack_id': 'ack-1',
      });
      await gateway.waitFor((_) => gateway.acks().length >= 2);
      expect(gateway.acks().map((f) => (f['data'] as Map)['ack_id']), [
        'ack-1',
        'ack-1',
      ]);
    });

    test('does not ack an untracked frame', () async {
      await gateway.push({
        'type': 'notifications.new',
        'data': {'id': 'n1'},
      });
      // Give the socket a chance to deliver and answer; a frame without a
      // stamp must produce no ack at all.
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(gateway.acks(), isEmpty);
    });

    test('carries the token as a header on the io transport', () async {
      final tokenGateway = await _FakeGateway.start();
      // A factory that records the dial and then delegates to the real dial,
      // so the assertion is about what the service asked for.
      Uri? dialed;
      Map<String, String>? headers;
      final recording = SolarWebSocketService(
        uri: () =>
            Uri.parse('${tokenGateway.baseUrl}/ws'.replaceFirst('http', 'ws')),
        token: () async => 'token-1',
        channelFactory: (uri, h) {
          dialed = uri;
          headers = h;
          return defaultWebSocketChannelFactory(uri, h);
        },
      );
      addTearDown(() async {
        recording.close();
        await tokenGateway.close();
      });

      await recording.connect();
      await tokenGateway.waitFor(
        (frames) => frames.any((f) => f['type'] == kResumePacketType),
      );
      expect(headers, {'Authorization': 'Bearer token-1'});
      expect(
        dialed!.queryParameters.containsKey('tk'),
        isFalse,
        reason: 'the token must not be duplicated into the URL',
      );
    });

    test('carries the token as tk on the web transport', () async {
      final tokenGateway = await _FakeGateway.start();
      Uri? dialed;
      Map<String, String>? headers;
      final recording = SolarWebSocketService(
        uri: () =>
            Uri.parse('${tokenGateway.baseUrl}/ws'.replaceFirst('http', 'ws')),
        token: () async => 'token-1',
        authTransport: WebSocketAuthTransport.query,
        channelFactory: (uri, h) {
          dialed = uri;
          headers = h;
          return defaultWebSocketChannelFactory(uri, h);
        },
      );
      addTearDown(() async {
        recording.close();
        await tokenGateway.close();
      });

      await recording.connect();
      await tokenGateway.waitFor(
        (frames) => frames.any((f) => f['type'] == kResumePacketType),
      );
      expect(dialed!.queryParameters['tk'], 'token-1');
      expect(
        headers,
        isNull,
        reason: 'the browser cannot set an Authorization header',
      );
    });

    test('re-dials when the network transport changes', () async {
      final monitor = _FakeNetworkMonitor();
      final networkGateway = await _FakeGateway.start();
      final networkService = SolarWebSocketService(
        uri: () => Uri.parse(
          '${networkGateway.baseUrl}/ws'.replaceFirst('http', 'ws'),
        ),
        token: () async => null,
        networkMonitor: monitor,
        connectivityReconnectDelay: const Duration(milliseconds: 20),
      );
      addTearDown(() async {
        networkService.close();
        await networkGateway.close();
      });

      await networkService.connect();
      await networkGateway.waitFor(
        (frames) => frames.any((f) => f['type'] == kResumePacketType),
      );
      final states = <WebSocketState>[];
      networkService.statusStream.listen(states.add);

      monitor.emit(connected: true, fingerprint: 'mobile');
      await Future<void>.delayed(const Duration(milliseconds: 400));

      expect(
        states.any(
          (s) => s.maybeWhen(internetChanged: () => true, orElse: () => false),
        ),
        isTrue,
      );
      // The replacement connection resumes its own buffer.
      expect(
        networkGateway.received
            .where((f) => f['type'] == kResumePacketType)
            .length,
        2,
      );
    });
  });
}

/// An unsigned JWT whose `exp` is [duration] from now.
String _jwtExpiringIn(Duration duration) {
  final expiresAt = DateTime.now().add(duration).millisecondsSinceEpoch ~/ 1000;
  final header = base64Url.encode(utf8.encode('{"alg":"none","typ":"JWT"}'));
  final payload = base64Url.encode(utf8.encode(jsonEncode({'exp': expiresAt})));
  return '$header.$payload.';
}
