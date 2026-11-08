# WebSocket Gateway Protocol

Client-side reference for the Solar Network wsgateway (`GET /ws`), as
implemented by `SolarWebSocketService` in `lib/src/websocket/`.

The gateway is multi-tenant. Dial with the product's namespace so presence and
pushes stay isolated from other first-party clients:

```text
wss://<server>/ws?namespace=<product-tenant-id>
```

Authentication is a bearer token on the upgrade request:

| Transport | How the token travels | Used by |
| --- | --- | --- |
| `WebSocketAuthTransport.header` | `Authorization: Bearer <token>` | `dart:io` platforms |
| `WebSocketAuthTransport.query` | `?tk=<token>` | web (the browser owns the handshake) |

A rejected session (HTTP 401 on the upgrade) is terminal: the client reports
`WebSocketState.unauthorized` and stops retrying until it is asked to connect
again.

## Frame envelope

```json
{ "type": "messages.new", "data": { "...": "..." }, "endpoint": null }
```

`endpoint` and `error_message` are optional. Frames with `type` `error` and
`error.dupe` terminate the connection; the latter means another session for the
same account+device replaced this one.

## Delivery is at-least-once

Some pushes (`messages.*`) are tracked by the gateway. A tracked frame carries a
delivery stamp as a sibling of `data`:

```json
{ "type": "messages.new", "data": { "id": "..." }, "_ack_id": "a1" }
```

Rules a client must follow:

1. **Ack every stamped frame** with `session.ack`:

   ```json
   { "type": "session.ack", "data": { "ack_id": "a1" } }
   ```

   Ack a repeated stamp again. A repeat means the gateway never saw the previous
   ack; de-duplicating the ack would strand the frame in the retry buffer.

2. **Resume the buffer on every connection**, not only on reconnects:

   ```json
   { "type": "session.resume", "data": null }
   ```

   A push that landed while the client was offline is pending for the new
   connection too. Sending it on every connection generation is what makes the
   offline window covered.

3. **Consumers must tolerate a repeated frame.** Dedupe side effects (unread
   counters, sounds, toasts, event bus) by payload id; state writes can be
   idempotent upserts. `BoundedIdSet` in the Solian app is one such guard.

The stamp lives on the envelope, not inside `data`, and the generated
`WebSocketPacket` model drops unknown keys — read it from the raw JSON before
`WebSocketPacket.fromJson` (`ackIdForFrame`).

## Heartbeat

The client sends `{"type":"ping","data":null}` every 60 seconds, and once
immediately after connecting so it does not wait a full period for the first
`pong`. The measured round trip is exposed as `heartbeatDelay`.

## Reconnect policy

- Exponential backoff from 500 ms to 30 s with jitter.
- More than 5 attempts in a minute reports `WebSocketState.serverDown` and
  backs off for 30 s.
- Connectivity loss drops the socket and pauses retries; a transport change
  (even wifi→mobile, both connected) re-dials so the new route applies, and
  reports `WebSocketState.internetChanged`.

## Wiring it in a host

```dart
final service = SolarWebSocketService(
  uri: () => Uri.parse('$server/ws'.replaceFirst('http', 'ws'))
      .replace(queryParameters: {'namespace': productTenantId}),
  token: () => getValidAuthToken(),
  authTransport: kIsWeb
      ? WebSocketAuthTransport.query
      : WebSocketAuthTransport.header,
  // Optional: control the dial (relay/IP routing, tests).
  channelFactory: (uri, headers) =>
      IOWebSocketChannel.connect(uri, headers: headers, customClient: HttpClient()),
  // Optional: supply connectivity without depending on a plugin.
  networkMonitor: myNetworkMonitor,
);

service.dataStream.listen((packet) { /* ... */ });
service.statusStream.listen((state) { /* ... */ });
await service.connect();
```

`isWebSocketReconnect(wasConnected: …, isConnected: …)` distinguishes a
reconnect from a first connect; resync logic should key on that transition.
