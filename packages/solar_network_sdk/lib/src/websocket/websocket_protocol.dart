import 'dart:convert';

import 'package:solar_network_sdk/src/websocket/websocket_packet.dart';

/// The gateway's at-least-once delivery stamp on a frame envelope.
///
/// It is a sibling of `data`, not a field inside it, and the generated
/// [WebSocketPacket] model drops unknown keys, so it has to be read from the
/// raw JSON before `WebSocketPacket.fromJson`.
String? ackIdForFrame(Map<String, dynamic> decoded) {
  // Sibling of `data` on the envelope, mirroring wsgateway.Packet.AckID.
  final ackId = decoded['_ack_id'];
  if (ackId is! String) return null;
  final trimmed = ackId.trim();
  return trimmed.isEmpty ? null : trimmed;
}

/// Control packets the gateway understands for at-least-once delivery.
const String kAckPacketType = 'session.ack';
const String kResumePacketType = 'session.resume';

/// Whether a socket-state change is a reconnect: previously connected, now
/// connected again. A first observation is not a reconnect.
bool isWebSocketReconnect({
  required bool? wasConnected,
  required bool isConnected,
}) {
  return wasConnected == false && isConnected;
}

/// Encodes the ack for a delivered [ackId].
String encodeAckPacket(String ackId) =>
    jsonEncode(WebSocketPacket(type: kAckPacketType, data: {'ack_id': ackId}));

/// Encodes the buffer-resume request sent on every new connection.
String encodeResumePacket() =>
    jsonEncode(const WebSocketPacket(type: kResumePacketType, data: null));
