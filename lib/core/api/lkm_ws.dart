import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import 'api_client.dart';

/// One push frame from `/ws/events`, already decoded. The service adds
/// `event_id`/`version` for de-duplication; they are passed through untouched.
class LkmWsEvent {
  const LkmWsEvent({
    required this.event,
    required this.eventId,
    required this.version,
    required this.data,
  });

  final String event;
  final String eventId;
  final int version;

  /// The full decoded body (`event`, `file`/`payload`, `event_id`, `version`).
  final Map<String, dynamic> data;

  static LkmWsEvent? fromMap(Map<String, dynamic> map) {
    final event = '${map['event'] ?? ''}';
    if (event.isEmpty) return null;
    final version = map['version'];
    return LkmWsEvent(
      event: event,
      eventId: '${map['event_id'] ?? ''}',
      version: version is num ? version.toInt() : 0,
      data: map,
    );
  }
}

/// Real-time push channel for notification + upload events.
///
/// Not a delivery guarantee: the service publishes fire-and-forget over Redis
/// and the client falls back to refreshing when the socket lags or drops. What
/// this class does guarantee is the handshake (query token, `upload,notify`
/// channels), the control frames (`pong`, token `refresh`) and reconnect with
/// exponential backoff.
class LkmWsClient {
  LkmWsClient({
    required this.serverUrl,
    required this.tokenProvider,
    this.channels = const ['upload', 'notify'],
    this.reconnectBaseDelay = const Duration(seconds: 1),
    WebSocketChannel Function(Uri uri)? connect,
  }) : _connect = connect ?? WebSocketChannel.connect;

  final String serverUrl;

  /// Read on every (re)connect and on each server ping, so a rotated access
  /// token is handed to the service through a `refresh` frame.
  final String? Function() tokenProvider;

  final List<String> channels;
  final Duration reconnectBaseDelay;
  final WebSocketChannel Function(Uri uri) _connect;

  final StreamController<LkmWsEvent> _events =
      StreamController<LkmWsEvent>.broadcast();

  Stream<LkmWsEvent> get events => _events.stream;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Timer? _reconnectTimer;
  int _attempt = 0;
  bool _closed = false;
  String? _handshakeToken;

  bool get isConnected => _channel != null;

  void connect() {
    if (_closed || _channel != null) return;
    final token = tokenProvider();
    if (token == null || token.isEmpty) return;
    _handshakeToken = token;
    final uri = Uri.parse(
      '${_wsOrigin(serverUrl)}$kApiPathPrefix/ws/events',
    ).replace(
      queryParameters: {'token': token, 'channels': channels.join(',')},
    );
    try {
      final channel = _connect(uri);
      _channel = channel;
      _attempt = 0;
      _subscription = channel.stream.listen(
        _onFrame,
        onError: (Object _) => _onDisconnected(),
        onDone: _onDisconnected,
        cancelOnError: true,
      );
    } catch (_) {
      _channel = null;
      _scheduleReconnect();
    }
  }

  void _onFrame(dynamic raw) {
    if (raw is! String) return;
    final Map<String, dynamic>? map;
    try {
      final decoded = jsonDecode(raw);
      map = decoded is Map ? Map<String, dynamic>.from(decoded) : null;
    } catch (_) {
      return;
    }
    if (map == null) return;

    if (map['type'] == 'ping') {
      _answerPing();
      return;
    }
    final event = LkmWsEvent.fromMap(map);
    if (event != null) _events.add(event);
  }

  void _answerPing() {
    final channel = _channel;
    if (channel == null) return;
    final latest = tokenProvider();
    if (latest != null && latest.isNotEmpty && latest != _handshakeToken) {
      _handshakeToken = latest;
      channel.sink.add(jsonEncode({'type': 'refresh', 'token': latest}));
    }
    channel.sink.add(jsonEncode({'type': 'pong'}));
  }

  void _onDisconnected() {
    _subscription?.cancel();
    _subscription = null;
    _channel = null;
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_closed) return;
    _reconnectTimer?.cancel();
    final step = _attempt.clamp(0, 5);
    final delay = Duration(
      milliseconds: (reconnectBaseDelay.inMilliseconds * (1 << step)).clamp(
        reconnectBaseDelay.inMilliseconds,
        30000,
      ),
    );
    _attempt += 1;
    _reconnectTimer = Timer(delay, connect);
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _reconnectTimer?.cancel();
    await _subscription?.cancel();
    _channel = null;
    await _events.close();
  }

  static String _wsOrigin(String serverUrl) {
    final base = serverUrl.endsWith(kApiPathPrefix)
        ? serverUrl.substring(0, serverUrl.length - kApiPathPrefix.length)
        : serverUrl;
    if (base.startsWith('https://')) return 'wss://${base.substring(8)}';
    if (base.startsWith('http://')) return 'ws://${base.substring(7)}';
    return base;
  }
}
