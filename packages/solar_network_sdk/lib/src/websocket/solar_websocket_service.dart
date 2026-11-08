import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:logging/logging.dart';
import 'package:solar_network_sdk/src/websocket/network_monitor.dart';
import 'package:solar_network_sdk/src/websocket/websocket_packet.dart';
import 'package:solar_network_sdk/src/websocket/websocket_protocol.dart';
import 'package:solar_network_sdk/src/websocket/websocket_state.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Where the bearer token travels on the upgrade request.
enum WebSocketAuthTransport {
  /// `Authorization: Bearer …` header. Works on `dart:io` platforms.
  header,

  /// `tk` query parameter. Required on the web, where the browser owns the
  /// handshake and a custom header cannot be set.
  query,
}

/// Opens the channel for a dial.
///
/// A host overrides this to control the transport: the app dials with a fresh
/// `HttpClient` per connection so a changed route or IP override applies, and a
/// test can hand in a socket it owns.
typedef WebSocketChannelFactory =
    WebSocketChannel Function(Uri uri, Map<String, String>? headers);

/// Default dial: lets `web_socket_channel` pick the platform implementation.
WebSocketChannel defaultWebSocketChannelFactory(
  Uri uri,
  Map<String, String>? headers,
) => WebSocketChannel.connect(uri);

final _log = Logger('SolarNetworkSDK.WebSocket');

/// Client for the Solar Network websocket gateway.
///
/// Owns the connection lifecycle — dial, heartbeat, at-least-once ack and
/// buffer resume, backoff, connectivity-driven re-dial — and exposes two
/// broadcast streams: decoded [WebSocketPacket]s and [WebSocketState] changes.
///
/// The gateway delivers `messages.*` frames at least once: every frame carrying
/// an `_ack_id` envelope stamp is acked, and a repeat is acked again because a
/// repeat means the gateway never saw the previous ack. Each new connection
/// asks the gateway to resume the pending buffer, so a push that landed while
/// the client was offline is delivered on the next connect. Consumers must
/// therefore tolerate a repeated frame (dedupe by payload id) rather than
/// assume exactly-once delivery.
///
/// ```dart
/// final service = SolarWebSocketService(
///   uri: () => Uri.parse('wss://api.example.com/ws?namespace=dev.example'),
///   token: () async => await storage.readToken(),
/// );
/// service.dataStream.listen((packet) => print(packet.type));
/// await service.connect();
/// ```
class SolarWebSocketService {
  SolarWebSocketService({
    required Uri Function() uri,
    required Future<String?> Function() token,
    this.authTransport = WebSocketAuthTransport.header,
    WebSocketChannelFactory? channelFactory,
    NetworkMonitor? networkMonitor,
    this.heartbeatInterval = const Duration(seconds: 60),
    this.maxReconnectsPerMinute = 5,
    this.baseReconnectDelay = const Duration(milliseconds: 500),
    this.maxReconnectDelay = const Duration(seconds: 30),
    this.connectivityReconnectDelay = const Duration(milliseconds: 1200),
  }) : _uri = uri,
       _token = token,
       _channelFactory = channelFactory ?? defaultWebSocketChannelFactory,
       _networkMonitor = networkMonitor;

  final Uri Function() _uri;
  final Future<String?> Function() _token;
  final WebSocketAuthTransport authTransport;
  final WebSocketChannelFactory _channelFactory;
  final NetworkMonitor? _networkMonitor;
  final Duration heartbeatInterval;
  final int maxReconnectsPerMinute;
  final Duration baseReconnectDelay;
  final Duration maxReconnectDelay;
  final Duration connectivityReconnectDelay;

  WebSocketChannel? _channel;
  StreamSubscription? _channelSubscription;
  StreamSubscription<NetworkChange>? _networkSubscription;
  final StreamController<WebSocketPacket> _streamController =
      StreamController<WebSocketPacket>.broadcast();
  final StreamController<WebSocketState> _statusStreamController =
      StreamController<WebSocketState>.broadcast();
  Timer? _reconnectTimer;
  Timer? _heartbeatTimer;
  Timer? _connectivityReconnectTimer;
  int _connectionGeneration = 0;
  bool _isClosing = false;
  bool _isConnecting = false;

  NetworkChange? _lastNetworkChange;
  bool? _lastNetworkConnected;

  DateTime? _heartbeatAt;

  /// Round-trip time of the last answered heartbeat, for diagnostics.
  Duration? heartbeatDelay;

  int _reconnectCount = 0;
  DateTime? _reconnectWindowStart;

  /// Decoded frames from the gateway, including control frames such as `pong`.
  Stream<WebSocketPacket> get dataStream => _streamController.stream;

  /// Every connection-state change.
  Stream<WebSocketState> get statusStream => _statusStreamController.stream;

  /// Whether a channel is currently open.
  ///
  /// This is the transport truth; [statusStream] additionally reports why a
  /// dial failed.
  bool get isConnected => _channel != null;

  /// Connects, or returns immediately when a dial is already in flight.
  Future<void> connect() async {
    _ensureNetworkWatch();
    if (_isConnecting) {
      _log.fine('Connection attempt already in progress, skipping');
      return;
    }
    await _connectInternal();
  }

  /// Re-dials so a changed server address or route applies.
  ///
  /// A live socket keeps the route it was opened with, so switching routes has
  /// to drop it; the service reconnects with the same backoff rules.
  Future<void> reconnect() => connect();

  Future<void> _connectInternal() async {
    _isClosing = false;
    _isConnecting = true;
    final connectionGeneration = ++_connectionGeneration;
    await _disposeActiveChannel();

    if (_lastNetworkConnected == false) {
      _log.info('Refusing connect: no network connectivity');
      _isConnecting = false;
      _addStatus(const WebSocketState.disconnected());
      return;
    }

    _addStatus(const WebSocketState.connecting());

    final token = await _token();
    final hasToken = token != null && token.isNotEmpty;
    final base = _uri();
    final uri = authTransport == WebSocketAuthTransport.query && hasToken
        ? base.replace(queryParameters: {...base.queryParameters, 'tk': token})
        : base;
    final headers = authTransport == WebSocketAuthTransport.header && hasToken
        ? {'Authorization': 'Bearer $token'}
        : null;

    _log.info('Trying connecting to $uri');
    try {
      final channel = _channelFactory(uri, headers);
      _channel = channel;
      await channel.ready;
      if (connectionGeneration != _connectionGeneration) {
        await channel.sink.close();
        return;
      }
      _isConnecting = false;
      _reconnectCount = 0;
      _reconnectWindowStart = null;
      _addStatus(const WebSocketState.connected());
      _scheduleHeartbeat();
      _requestResume();
      _channelSubscription = channel.stream.listen(
        (data) => _handleFrame(connectionGeneration, data),
        onDone: () {
          if (connectionGeneration != _connectionGeneration || _isClosing) {
            return;
          }
          _log.info('Connection closed, attempting to reconnect...');
          _addStatus(const WebSocketState.disconnected());
          _scheduleReconnect();
        },
        onError: (Object error) {
          if (connectionGeneration != _connectionGeneration || _isClosing) {
            return;
          }
          _log.severe('Error occurred: $error, attempting to reconnect...');
          _addStatus(WebSocketState.error(error.toString()));
          _scheduleReconnect();
        },
      );
    } catch (err) {
      if (connectionGeneration != _connectionGeneration || _isClosing) return;
      _isConnecting = false;
      _log.severe('Failed to connect: $err');
      // Session logged out or expired (HTTP 401 handshake rejection): treat as
      // terminal — no automatic reconnect, no automatic logout. Retrying can
      // never succeed until the user signs in again.
      if (_isUnauthorizedConnectError(err)) {
        _isClosing = true;
        _cancelTimers();
        _addStatus(const WebSocketState.unauthorized());
        _channel?.sink.close();
        return;
      }
      _addStatus(WebSocketState.error(err.toString()));
      _scheduleReconnect();
    }
  }

  void _handleFrame(int connectionGeneration, Object? data) {
    if (connectionGeneration != _connectionGeneration) return;
    String dataStr;
    try {
      dataStr = data is List<int> ? utf8.decode(data) : data.toString();
    } catch (e) {
      _log.severe('Failed to decode data: $e');
      return;
    }
    try {
      final decoded = jsonDecode(dataStr);
      if (decoded is! Map<String, dynamic>) {
        _log.severe('Failed to parse packet: not an object');
        return;
      }
      final ackId = ackIdForFrame(decoded);
      final packet = WebSocketPacket.fromJson(decoded);
      _log.info('Received packet: ${packet.type}');

      if (packet.type == 'error.dupe') {
        _log.info('Duplicate device found: ${packet.errorMessage}');
        _isClosing = true;
        _cancelTimers();
        _addStatus(const WebSocketState.duplicateDevice());
        _channel?.sink.close();
        return;
      } else if (packet.type == 'error') {
        _log.info('Connect error: ${packet.errorMessage}');
        _isClosing = true;
        _cancelTimers();
        _addStatus(WebSocketState.error(packet.errorMessage ?? 'error'));
        _channel?.sink.close();
        return;
      }

      _streamController.sink.add(packet);
      if (ackId != null) {
        // Always ack, including a repeated _ack_id: a repeat means the gateway
        // never saw the previous ack, so de-duplicating here would strand the
        // frame in the retry buffer.
        _sendAck(ackId);
      }
      if (packet.type == 'pong' && _heartbeatAt != null) {
        final delay = DateTime.now().difference(_heartbeatAt!);
        heartbeatDelay = delay;
        _log.info(
          'Server respond last heartbeat for ${delay.inMilliseconds} ms',
        );
      }
    } catch (e) {
      _log.severe('Failed to parse packet: $e');
    }
  }

  /// Whether a connect failure is an auth rejection (HTTP 401 during the
  /// WebSocket upgrade handshake), i.e. the session is logged out or expired.
  bool _isUnauthorizedConnectError(Object error) {
    final message = error.toString();
    return message.contains('HTTP status code: 401') ||
        RegExp(r'status[^\d]*401').hasMatch(message);
  }

  void _addStatus(WebSocketState state) {
    if (!_statusStreamController.isClosed) {
      _statusStreamController.sink.add(state);
    }
  }

  void _cancelTimers() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _connectivityReconnectTimer?.cancel();
    _connectivityReconnectTimer = null;
    _heartbeatAt = null;
    heartbeatDelay = null;
  }

  void _scheduleReconnect() {
    _log.info('Scheduling reconnect...');
    if (_isClosing) {
      _log.fine('Not scheduling reconnect because connection is closing');
      return;
    }

    if (_lastNetworkConnected == false) {
      _log.info('Reconnect paused until network connectivity returns');
      _addStatus(const WebSocketState.disconnected());
      return;
    }

    final now = DateTime.now();
    if (_reconnectWindowStart == null ||
        now.difference(_reconnectWindowStart!).inMinutes >= 1) {
      _reconnectWindowStart = now;
      _reconnectCount = 0;
    }

    _reconnectCount++;

    if (_reconnectCount > maxReconnectsPerMinute) {
      _log.severe(
        'Reconnect limit exceeded: $maxReconnectsPerMinute reconnections in '
        'the last minute. Retrying in 30s.',
      );
      _addStatus(const WebSocketState.serverDown());
      _reconnectTimer?.cancel();
      _reconnectTimer = Timer(const Duration(seconds: 30), () {
        if (_isClosing) return;
        _reconnectWindowStart = null;
        _reconnectCount = 0;
        _addStatus(const WebSocketState.connecting());
        connect();
      });
      return;
    }

    _reconnectTimer?.cancel();
    final backoffMs =
        (baseReconnectDelay.inMilliseconds * (1 << (_reconnectCount - 1)))
            .clamp(
              baseReconnectDelay.inMilliseconds,
              maxReconnectDelay.inMilliseconds,
            );
    final jitter = Random().nextInt(200) - 100;
    final delayMs = (backoffMs + jitter).clamp(
      100,
      maxReconnectDelay.inMilliseconds,
    );
    _reconnectTimer = Timer(Duration(milliseconds: delayMs), () {
      if (_isClosing) return;
      _addStatus(const WebSocketState.connecting());
      connect();
    });
  }

  /// Drops the current socket and dials again immediately.
  void manualReconnect() {
    _log.info('Manual reconnect triggered by user');

    if (_lastNetworkConnected == false) {
      _log.info('Manual reconnect refused: offline');
      _reconnectTimer?.cancel();
      _reconnectTimer = null;
      _addStatus(const WebSocketState.disconnected());
      return;
    }

    _reconnectTimer?.cancel();
    _reconnectTimer = null;

    _isClosing = false;
    _reconnectCount = 0;
    _reconnectWindowStart = null;

    // Increment the generation first so the old socket's callbacks go inert.
    _connectionGeneration++;

    // Do not wait for the close: a broken socket can hang here, and the new
    // dial replaces it either way.
    _disposeActiveChannel()
        .timeout(const Duration(milliseconds: 1000))
        .then((_) {
          _addStatus(const WebSocketState.disconnected());
          Future.delayed(const Duration(milliseconds: 100), () {
            // The old attempt, if any, is abandoned with its generation.
            _isConnecting = false;
            _addStatus(const WebSocketState.connecting());
            connect();
          });
        })
        .catchError((Object err) {
          _log.warning('Dispose had error (this is normal): $err');
        });
  }

  void _scheduleHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(heartbeatInterval, (_) {
      _beatTheHeart();
    });
  }

  void _beatTheHeart() {
    if (_channel == null || _isClosing) return;
    _heartbeatAt = DateTime.now();
    _log.info('We\'re beating the heart! $_heartbeatAt');
    sendMessage(jsonEncode(const WebSocketPacket(type: 'ping', data: null)));
  }

  void _sendAck(String ackId) {
    final sent = sendMessage(encodeAckPacket(ackId));
    if (!sent) {
      // The reconnected socket re-requests the buffer, so nothing is lost.
      _log.fine('Failed to ack $ackId; will be replayed');
    }
  }

  /// Asks the gateway for every frame still pending for this account+device.
  ///
  /// Sent on every connection generation, not just reconnects: a push that
  /// landed while the client was offline is pending for the new connection too,
  /// which is the window a reconnect-only resume would leave uncovered.
  void _requestResume() {
    sendMessage(encodeResumePacket());
    // Do not make the client wait a whole heartbeat period for its first pong.
    _beatTheHeart();
  }

  /// Sends an already-encoded frame. Returns false when there is no socket.
  bool sendMessage(String message) {
    if (_channel == null || _isClosing) {
      _log.info('Cannot send message: channel is null or closing');
      return false;
    }
    try {
      _channel!.sink.add(message);
      return true;
    } catch (e) {
      _log.severe('Failed to send message: $e');
      return false;
    }
  }

  /// Sends [packet] as a JSON frame.
  bool sendPacket(WebSocketPacket packet) =>
      sendMessage(jsonEncode(packet.toJson()));

  void close() {
    _isClosing = true;
    _cancelTimers();
    _networkSubscription?.cancel();
    _networkSubscription = null;
    _lastNetworkChange = null;
    _lastNetworkConnected = null;
    _channelSubscription?.cancel();
    _channelSubscription = null;
    _channel?.sink.close();
    _channel = null;
    _streamController.close();
    _statusStreamController.close();
    _isClosing = false;
  }

  Future<void> _disposeActiveChannel() async {
    _cancelTimers();

    try {
      await _channelSubscription?.cancel().timeout(
        const Duration(milliseconds: 200),
      );
      _log.fine('Stream subscription cancelled successfully');
    } catch (_) {
      _log.warning('Stream subscription cancel timed out, forcing null');
    } finally {
      _channelSubscription = null;
    }

    try {
      await _channel?.sink.close().timeout(const Duration(milliseconds: 300));
      _log.fine('WebSocket sink closed successfully');
    } catch (_) {
      _log.warning('WebSocket close timed out, forcing null');
    } finally {
      _channel = null;
    }
  }

  void _ensureNetworkWatch() {
    final monitor = _networkMonitor;
    if (monitor == null || _networkSubscription != null) return;

    // The snapshot is only a starting point: a change that arrives while it is
    // being read is newer, and must not be overwritten by the stale value.
    monitor.current().then((change) {
      if (_lastNetworkChange != null) return;
      _lastNetworkChange = change;
      _lastNetworkConnected = change.connected;
    });
    _networkSubscription = monitor.changes.listen(
      _handleNetworkChange,
      onError: (Object error) {
        _log.warning('Connectivity watch failed: $error');
      },
    );
  }

  void _handleNetworkChange(NetworkChange change) {
    final previous = _lastNetworkChange;
    _lastNetworkChange = change;
    _lastNetworkConnected = change.connected;

    if (previous != null && previous.fingerprint == change.fingerprint) {
      return;
    }

    final hadNetwork = previous?.connected ?? false;
    _log.info(
      'Connectivity changed: ${previous?.fingerprint ?? 'unknown'} -> '
      '${change.fingerprint}',
    );

    if (!change.connected) {
      _connectivityReconnectTimer?.cancel();
      _connectivityReconnectTimer = null;
      _connectionGeneration++;
      unawaited(_disposeActiveChannel());
      _addStatus(const WebSocketState.disconnected());
      return;
    }

    if (previous == null) return;

    if (!hadNetwork || _channel != null || _isConnecting) {
      _scheduleConnectivityReconnect();
    }
  }

  void _scheduleConnectivityReconnect() {
    if (_isClosing) return;

    _connectivityReconnectTimer?.cancel();
    _connectivityReconnectTimer = Timer(connectivityReconnectDelay, () {
      if (_isClosing) return;
      if (_lastNetworkConnected == false) {
        _log.info('Skipping connectivity reconnect: offline again');
        _addStatus(const WebSocketState.disconnected());
        return;
      }

      _log.info('Reconnecting after connectivity change to refresh route');
      _addStatus(const WebSocketState.internetChanged());
      manualReconnect();
    });
  }
}
