import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:island/core/api/api_client.dart';

/// Preference key holding the LKM-service token pair.
///
/// Deliberately distinct from the Solian key (`dyn_user_tk`): both backends'
/// credentials live on the same device until the old domain is removed, and a
/// shared key would let one engine's rotation corrupt the other's session.
const String kLkmTokenPairStoreKey = 'lkm_api_token_pair';

/// Treat a token as expired this long before its real `exp`, so a request does
/// not race the boundary on a slow link.
const Duration kLkmTokenExpirySkew = Duration(seconds: 30);

/// Refresh early once the access token is this close to expiring, so a burst of
/// screen loads does not each discover the expiry separately.
const Duration kLkmTokenRefreshWindow = Duration(minutes: 5);

/// The stored credential. The service's `TokenPair` carries no `expires_in`;
/// both expiries are read from the JWT `exp` claim.
class LkmTokenPair {
  const LkmTokenPair({
    required this.accessToken,
    this.refreshToken,
    this.accessExpiresAt,
    this.refreshExpiresAt,
  });

  final String accessToken;
  final String? refreshToken;
  final DateTime? accessExpiresAt;
  final DateTime? refreshExpiresAt;

  bool get hasRefreshToken =>
      refreshToken != null && refreshToken!.isNotEmpty;

  bool accessIsUsable(DateTime now) => _usable(accessExpiresAt, now);

  bool refreshIsUsable(DateTime now) =>
      hasRefreshToken && _usable(refreshExpiresAt, now);

  LkmTokenPair copyWith({
    String? accessToken,
    String? refreshToken,
    DateTime? accessExpiresAt,
    DateTime? refreshExpiresAt,
  }) => LkmTokenPair(
    accessToken: accessToken ?? this.accessToken,
    refreshToken: refreshToken ?? this.refreshToken,
    accessExpiresAt: accessExpiresAt ?? this.accessExpiresAt,
    refreshExpiresAt: refreshExpiresAt ?? this.refreshExpiresAt,
  );

  Map<String, dynamic> toJson() => {
    'access_token': accessToken,
    if (refreshToken != null) 'refresh_token': refreshToken,
    if (accessExpiresAt != null)
      'access_expires_at': accessExpiresAt!.toUtc().toIso8601String(),
    if (refreshExpiresAt != null)
      'refresh_expires_at': refreshExpiresAt!.toUtc().toIso8601String(),
  };

  /// Builds a pair from the service payload, filling expiries from the JWTs.
  factory LkmTokenPair.fromResponse(Map<String, dynamic> json) {
    final access = json['access_token'];
    if (access is! String || access.isEmpty) {
      throw const FormatException('missing access_token');
    }
    final refresh = json['refresh_token'];
    return LkmTokenPair(
      accessToken: access,
      refreshToken: refresh is String && refresh.isNotEmpty ? refresh : null,
      accessExpiresAt: decodeJwtExpiry(access),
      refreshExpiresAt: refresh is String && refresh.isNotEmpty
          ? decodeJwtExpiry(refresh)
          : null,
    );
  }

  static LkmTokenPair? tryFromPrefs(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      return null;
    }
    if (decoded is! Map) return null;
    final access = decoded['access_token'];
    if (access is! String || access.isEmpty) return null;
    return LkmTokenPair(
      accessToken: access,
      refreshToken: decoded['refresh_token'] as String?,
      accessExpiresAt: _parseDate(decoded['access_expires_at']),
      refreshExpiresAt: _parseDate(decoded['refresh_expires_at']),
    );
  }

  static bool _usable(DateTime? expiresAt, DateTime now) =>
      expiresAt == null || expiresAt.isAfter(now.add(kLkmTokenExpirySkew));

  static DateTime? _parseDate(Object? value) {
    if (value is! String || value.isEmpty) return null;
    return DateTime.tryParse(value)?.toLocal();
  }
}

/// Reads the `exp` claim of a JWT without verifying it.
///
/// Verification is the server's job; the client only needs the deadline to
/// refresh ahead of it.
DateTime? decodeJwtExpiry(String token) {
  final parts = token.split('.');
  if (parts.length < 2) return null;
  try {
    final payload = utf8.decode(base64Url.decode(base64Url.normalize(parts[1])));
    final map = jsonDecode(payload);
    if (map is! Map) return null;
    final exp = map['exp'];
    if (exp is int) {
      return DateTime.fromMillisecondsSinceEpoch(
        exp * 1000,
        isUtc: true,
      ).toLocal();
    }
  } catch (_) {
    return null;
  }
  return null;
}

/// The stored session could not be renewed: the refresh token is gone, expired
/// or revoked. The caller must send the user back to the login screen.
class SessionExpiredException implements Exception {
  const SessionExpiredException([this.message = '登录状态已失效，请重新登录']);

  final String message;

  @override
  String toString() => 'SessionExpiredException: $message';
}

/// The single owner of the LKM-service credential.
///
/// Two properties matter more than the API surface:
///
/// 1. **Nobody else reads or writes the token preference.** The old Solian
///    code has four separate readers of its own key and the service rotates
///    refresh tokens on every use (`consume_once` in `auth/service_auth.py`),
///    so a second reader that replays a stale refresh token revokes the live
///    one and signs the user out. Everything goes through this class.
/// 2. **Refresh is single-flight and re-reads the disk first.** Several screens
///    can hit 401 in the same second; only one rotation may happen, and if
///    another engine (second window, web tab) already rotated, the disk copy
///    wins over this instance's memory.
class ApiSession {
  ApiSession({
    required SharedPreferences prefs,
    required String serverUrl,
    Dio? dio,
    Dio? refreshDio,
    String? userAgent,
  }) : _prefs = prefs,
       serverUrl = normalizeApiBase(serverUrl),
       _tokens = LkmTokenPair.tryFromPrefs(
         prefs.getString(kLkmTokenPairStoreKey),
       ) {
    _refreshDio = refreshDio ?? Dio();
    _configure(_refreshDio);
    _dio = dio ?? Dio();
    _configure(_dio);
    _client = ApiClient(
      serverUrl: this.serverUrl,
      dio: _dio,
      tokenProvider: currentAccessToken,
      userAgent: userAgent,
    );
  }

  final SharedPreferences _prefs;

  /// Normalized base URL, e.g. `https://lkm-ahz.ltd/api/v1`.
  final String serverUrl;

  late final Dio _dio;
  late final Dio _refreshDio;
  late final ApiClient _client;

  LkmTokenPair? _tokens;
  Future<bool>? _refreshInFlight;

  /// HTTP client for authenticated business calls.
  ApiClient get client => _client;

  /// The pair currently held, or null when signed out.
  LkmTokenPair? get tokens => _tokens;

  bool get isSignedIn => _tokens != null;

  /// The access token if one is on disk. Does not refresh; used by transports
  /// that cannot await (websocket handshake query building).
  String? get cachedAccessToken => _tokens?.accessToken;

  void _configure(Dio dio) {
    dio.options = dio.options.copyWith(
      baseUrl: serverUrl,
      connectTimeout: kApiConnectTimeout,
      receiveTimeout: kApiReceiveTimeout,
      headers: {
        ...dio.options.headers,
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
    );
  }

  /// Adopts a freshly issued pair (login / registration).
  Future<void> adopt(LkmTokenPair pair) async {
    _tokens = pair;
    await _persist(pair);
  }

  /// Forgets the credential locally. Pass [revoke] to also tell the server (the
  /// logout endpoint revokes every refresh token for the user, so this is not
  /// a per-device logout).
  Future<void> signOut({bool revoke = true}) async {
    final access = _tokens?.accessToken;
    _tokens = null;
    await _prefs.remove(kLkmTokenPairStoreKey);
    if (!revoke || access == null || access.isEmpty) return;
    try {
      await _client.post('/auth/logout');
    } catch (_) {
      // Local sign-out must succeed even when the server is unreachable.
    }
  }

  /// Returns a usable access token, refreshing when the current one is inside
  /// [kLkmTokenRefreshWindow] of expiring.
  Future<String?> currentAccessToken() async {
    final tokens = _tokens;
    if (tokens == null) return null;
    if (_isFresh(tokens.accessExpiresAt)) return tokens.accessToken;

    final refreshed = await _refreshTokenPair();
    return refreshed ? _tokens?.accessToken : null;
  }

  /// Runs [action], and if it fails as unauthenticated (expired or revoked
  /// access token), refreshes once and retries it once.
  Future<T> run<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on ApiException catch (error) {
      if (!error.isUnauthenticated) rethrow;
      final refreshed = await _refreshTokenPair(force: true);
      if (!refreshed) throw const SessionExpiredException();
      return await action();
    }
  }

  /// Rotates the pair. Returns false when there is nothing usable to rotate.
  ///
  /// Force skips the "still fresh" short-circuit; both paths share the same
  /// in-flight future, so concurrent callers observe one rotation.
  Future<bool> _refreshTokenPair({bool force = false}) {
    final inflight = _refreshInFlight;
    if (inflight != null) return inflight;

    final future = _performRefresh(force: force);
    _refreshInFlight = future;
    future.whenComplete(() {
      if (identical(_refreshInFlight, future)) _refreshInFlight = null;
    });
    return future;
  }

  Future<bool> _performRefresh({required bool force}) async {
    // Another engine may have rotated while this instance was idle; its copy is
    // the one the server still honours.
    await _prefs.reload();
    final onDisk = LkmTokenPair.tryFromPrefs(
      _prefs.getString(kLkmTokenPairStoreKey),
    );
    if (onDisk != null) _tokens = onDisk;

    final current = _tokens;
    if (current == null) return false;
    if (!force && _isFresh(current.accessExpiresAt)) return true;

    final now = DateTime.now();
    if (!current.refreshIsUsable(now)) {
      await _clear();
      return false;
    }

    try {
      final response = await _refreshDio.post<dynamic>(
        '/auth/refresh',
        data: {'refresh_token': current.refreshToken},
        options: Options(validateStatus: (_) => true),
      );
      final pair = _pairFromEnvelope(response);
      await adopt(pair);
      return true;
    } on ApiException catch (error) {
      if (ApiCode.isUnauthenticated(error.code) ||
          error.code == ApiCode.authRefreshTokenRevoked ||
          error.code == ApiCode.authTokenInvalid) {
        await _clear();
        return false;
      }
      rethrow;
    }
  }

  /// Unwraps `{code, message, data}` for the two token endpoints. Kept local
  /// because the refresh Dio has no token interceptor to route through
  /// [ApiClient].
  LkmTokenPair _pairFromEnvelope(Response<dynamic> response) {
    final status = response.statusCode ?? 0;
    final body = response.data;
    if (body is Map) {
      final code = body['code'];
      if (code is int) {
        if (code == ApiCode.ok) {
          final data = body['data'];
          if (data is Map) {
            return LkmTokenPair.fromResponse(Map<String, dynamic>.from(data));
          }
          throw ApiException(
            code: ApiCode.internalError,
            message: '令牌响应缺少 data',
            statusCode: status,
          );
        }
        throw ApiException(
          code: code,
          message: (body['message'] as String?) ?? '令牌刷新失败（$code）',
          requestId: (body['request_id'] as String?) ?? '',
          statusCode: status,
        );
      }
    }
    throw ApiException(
      code: status == 401 ? ApiCode.unauthorized : ApiCode.internalError,
      message: 'HTTP $status 令牌刷新失败',
      statusCode: status,
    );
  }

  bool _isFresh(DateTime? expiresAt) {
    if (expiresAt == null) return true;
    return expiresAt.isAfter(
      DateTime.now().add(kLkmTokenRefreshWindow),
    );
  }

  Future<void> _persist(LkmTokenPair pair) =>
      _prefs.setString(kLkmTokenPairStoreKey, jsonEncode(pair.toJson()));

  Future<void> _clear() async {
    _tokens = null;
    await _prefs.remove(kLkmTokenPairStoreKey);
  }
}
