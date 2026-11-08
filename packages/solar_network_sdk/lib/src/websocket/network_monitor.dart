/// The transport state a client reports to the gateway client.
///
/// A host supplies this so the SDK does not depend on a connectivity plugin:
/// the app already watches `connectivity_plus`, and a CLI or a test can supply
/// a fixed status.
class NetworkChange {
  const NetworkChange({required this.connected, required this.fingerprint});

  /// Whether any usable transport exists.
  final bool connected;

  /// Identifies the transport, not just its usability: a wifi→mobile switch is
  /// a change even though both are connected, and the gateway client re-dials
  /// so the new route applies. Any stable string works.
  final String fingerprint;
}

/// Source of network availability for [SolarWebSocketService].
abstract interface class NetworkMonitor {
  /// Best-effort current state, used before the first change arrives.
  Future<NetworkChange> current();

  /// Emits on every transport change, including connected→connected switches.
  Stream<NetworkChange> get changes;
}
