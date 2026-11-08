import 'package:freezed_annotation/freezed_annotation.dart';

part 'websocket_state.freezed.dart';

/// Lifecycle of a gateway connection.
///
/// [connecting] is emitted both for a first dial and for every retry, so a UI
/// that only needs "is the socket usable right now" should ask
/// [WebSocketState.connected] rather than compare states.
@freezed
sealed class WebSocketState with _$WebSocketState {
  const factory WebSocketState.connected() = _Connected;
  const factory WebSocketState.connecting() = _Connecting;
  const factory WebSocketState.disconnected() = _Disconnected;

  /// The transport changed (network switch, route change) and the socket is
  /// being re-established so it applies the new path.
  const factory WebSocketState.internetChanged() = _InternetChanged;

  /// Too many failed attempts in a row: the client is backing off for longer
  /// than its normal retry window.
  const factory WebSocketState.serverDown() = _ServerDown;

  /// Another session for the same account+device replaced this one. Terminal
  /// until the client explicitly connects again.
  const factory WebSocketState.duplicateDevice() = _DuplicateDevice;

  /// Session logged out or expired: the gateway rejected the handshake with
  /// HTTP 401. Terminal — no automatic reconnect until the user signs in again.
  const factory WebSocketState.unauthorized() = _Unauthorized;
  const factory WebSocketState.error(String message) = _Error;
}
