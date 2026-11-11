import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:island/core/api/api_client.dart';
import 'package:island/core/api/api_session.dart';
import 'package:island/core/api/files_api.dart';
import 'package:island/core/config.dart';
import 'package:island/core/services/udid.dart';

/// The LKM-service host the app talks to, as the user entered it (no `/api/v1`).
class LkmServerUrlNotifier extends Notifier<String> {
  @override
  String build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    return prefs.getString(kLkmServerStoreKey) ?? kLkmServerDefault;
  }

  /// Stores [value] after validating it. Returns an error message on failure,
  /// or null when the address was accepted.
  String? setServer(String value) {
    final candidate = _stripApiPrefix(value.trim());
    try {
      normalizeApiBase(candidate);
    } on ArgumentError {
      return '请输入完整的地址，例如 https://lkm-ahz.ltd';
    }
    final prefs = ref.read(sharedPreferencesProvider);
    prefs.setString(kLkmServerStoreKey, candidate);
    state = candidate;
    return null;
  }

  static String _stripApiPrefix(String value) {
    var host = value;
    while (host.endsWith('/')) {
      host = host.substring(0, host.length - 1);
    }
    if (host.endsWith(kApiPathPrefix)) {
      host = host.substring(0, host.length - kApiPathPrefix.length);
    }
    return host;
  }
}

final lkmServerUrlProvider = NotifierProvider<LkmServerUrlNotifier, String>(
  LkmServerUrlNotifier.new,
);

/// Stable device identifier used to bind challenges.
///
/// Overridable so tests (and any platform without the device-info plugin) can
/// supply a deterministic value instead of hitting a method channel.
final lkmDeviceIdProvider = FutureProvider<String>((ref) => getUdid());

/// The app's single LKM-service session: owns the token pair and the
/// authenticated HTTP client.
///
/// Rebuilt when the server address changes, so a stale token minted by another
/// deployment is never sent to the new host.
final lkmApiSessionProvider = Provider<ApiSession>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  final serverUrl = ref.watch(lkmServerUrlProvider);
  final session = ApiSession(prefs: prefs, serverUrl: serverUrl);
  ref.onDispose(session.client.close);
  return session;
});

/// File-library reads and the three-step upload, shared by the community
/// composer and the library screens.
final filesApiProvider = Provider<FilesApi>((ref) {
  return FilesApi(ref.watch(lkmApiSessionProvider).client);
});

/// Outcome of probing a candidate server before the user commits to it.
///
/// [reachable] and [isLkmService] are separate on purpose: a host that answers
/// HTTP but is not this backend (a plain web server, a wrong port, an old
/// Solian deployment) must read as "reached something that is not LKM-service"
/// rather than as "offline".
class LkmServerProbe {
  const LkmServerProbe({
    required this.reachable,
    this.isLkmService = false,
    this.status = 'unknown',
    this.dependencies = const {},
    this.message,
  });

  /// Whether the host answered at all (TCP/TLS/DNS succeeded).
  final bool reachable;

  /// Whether `/health` returned a parseable LKM-service envelope.
  final bool isLkmService;

  /// `ok` / `degraded`, straight from `/health`.
  final String status;

  /// Per-dependency status (`db`, `redis`, `auth`), when reported.
  final Map<String, String> dependencies;

  /// Human-readable reason when the probe failed.
  final String? message;

  bool get isHealthy => isLkmService && status == 'ok';

  static Future<LkmServerProbe> check(String serverUrl, {Dio? dio}) async {
    final client = ApiClient(serverUrl: serverUrl, dio: dio);
    try {
      final data = await client.getObject('/health');
      final status = data['status'];
      final dependencies = <String, String>{};
      for (final key in const ['db', 'redis', 'auth']) {
        final entry = data[key];
        if (entry is Map && entry['status'] is String) {
          dependencies[key] = entry['status'] as String;
        }
      }
      return LkmServerProbe(
        reachable: true,
        isLkmService: true,
        status: status is String ? status : 'unknown',
        dependencies: dependencies,
      );
    } on ApiException catch (error) {
      return LkmServerProbe(reachable: true, message: error.message);
    } on ApiTransportException catch (error) {
      return LkmServerProbe(reachable: false, message: error.message);
    } finally {
      client.close();
    }
  }
}

/// Whether the settings screen should show a probe result.
///
/// The probe is a real outbound request, so it stays off until the user asks
/// for it (test button or after saving an address) instead of firing every
/// time the settings tab is opened.
class LkmServerProbeRequested extends Notifier<bool> {
  @override
  bool build() => false;

  void request() => state = true;
}

final lkmServerProbeRequestedProvider =
    NotifierProvider<LkmServerProbeRequested, bool>(
      LkmServerProbeRequested.new,
    );

/// Probes the configured server. Invalidate to re-run.
final lkmServerProbeProvider = FutureProvider<LkmServerProbe>((ref) async {
  final serverUrl = ref.watch(lkmServerUrlProvider);
  return LkmServerProbe.check(serverUrl);
});
