import 'package:freezed_annotation/freezed_annotation.dart';

part 'websocket_packet.freezed.dart';
part 'websocket_packet.g.dart';

/// One frame of the Solar Network websocket gateway protocol.
///
/// The envelope is `{type, data, endpoint?, error_message?}`; the gateway may
/// add a delivery stamp as a *sibling* of `data` (see [ackIdForFrame]). The
/// generated model drops unknown keys, so the stamp is read from the raw JSON
/// before this model is built.
@freezed
sealed class WebSocketPacket with _$WebSocketPacket {
  const factory WebSocketPacket({
    required String type,
    required Map<String, dynamic>? data,
    String? endpoint,
    String? errorMessage,
  }) = _WebSocketPacket;

  factory WebSocketPacket.fromJson(Map<String, dynamic> json) =>
      _$WebSocketPacketFromJson(json);
}
