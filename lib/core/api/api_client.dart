import 'package:dio/dio.dart';

/// The path prefix every LKM-service business endpoint lives under.
///
/// The settings screen asks the user for a host only (e.g.
/// `https://lkm-ahz.ltd` or `http://127.0.0.1:8000`); this suffix is appended
/// here so a mistyped/duplicated prefix on the user side is the only thing that
/// can go wrong, and [normalizeApiBase] already tolerates that.
const String kApiPathPrefix = '/api/v1';

const Duration kApiConnectTimeout = Duration(seconds: 10);
const Duration kApiReceiveTimeout = Duration(seconds: 20);

/// Error codes the client has to branch on.
///
/// The wire code is **not** an HTTP status: the service encodes it as
/// `namespace_id << 16 | local_code` (see `LKM-service/core/err.py`), so a
/// plain `code == 401` comparison silently never matches. Only the common
/// namespace (id 0) fits in a byte; auth failures start at 65536.
abstract final class ApiCode {
  // NS_COMMON (id 0).
  static const int ok = 0;
  static const int invalidInput = 1;
  static const int forbidden = 2;
  static const int internalError = 3;
  static const int mfaRequired = 4;
  static const int unavailable = 5;
  static const int timeout = 6;
  static const int versionConflict = 7;
  static const int unauthorized = 8;
  static const int notFound = 9;
  static const int badRequest = 10;
  static const int conflict = 11;

  // NS_AUTH (id 1): 1 << 16 | local.
  static const int authInvalidCredentials = (1 << 16) | 2;
  static const int authAccountLocked = (1 << 16) | 4;
  static const int authTokenExpired = (1 << 16) | 9;
  static const int authTokenInvalid = (1 << 16) | 10;
  static const int authRefreshTokenRevoked = (1 << 16) | 11;
  static const int authVerificationCodeInvalid = (1 << 16) | 6;
  static const int authVerificationCodeExpired = (1 << 16) | 7;

  // NS_AUTH 32–38: 挑战-因子轮转（LKM-service auth/challenge.py）。
  static const int authChallengeNotFound = (1 << 16) | 32;
  static const int authChallengeExpired = (1 << 16) | 33;
  static const int authChallengeConsumed = (1 << 16) | 34;
  static const int authChallengeDeviceMismatch = (1 << 16) | 35;
  static const int authChallengeStepInvalid = (1 << 16) | 36;

  /// Whether [code] means "the caller is not authenticated" in any spelling
  /// the service uses: the common code or one of the auth token codes.
  static bool isUnauthenticated(int code) =>
      code == unauthorized ||
      code == authTokenExpired ||
      code == authTokenInvalid ||
      code == authRefreshTokenRevoked;
}

/// Normalizes a user-entered server address into a Dio base URL.
///
/// Accepts `https://host`, `https://host/`, and the fully qualified
/// `https://host/api/v1` alike. Throws [ArgumentError] when the value is empty
/// or is not an absolute http(s) URL, so the settings screen can surface a
/// readable validation error instead of a failed first request.
String normalizeApiBase(String serverUrl) {
  final trimmed = serverUrl.trim();
  if (trimmed.isEmpty) {
    throw ArgumentError.value(serverUrl, 'serverUrl', '服务器地址不能为空');
  }
  if (!trimmed.startsWith('http://') && !trimmed.startsWith('https://')) {
    throw ArgumentError.value(serverUrl, 'serverUrl', '服务器地址必须以 http:// 或 https:// 开头');
  }

  var url = trimmed;
  while (url.endsWith('/')) {
    url = url.substring(0, url.length - 1);
  }
  if (url.endsWith(kApiPathPrefix)) return url;
  return '$url$kApiPathPrefix';
}

/// A business failure returned by the service: HTTP 200 with `code != 0`.
///
/// The service reports domain errors in the envelope rather than through the
/// HTTP status, so this is the exception almost every failed call raises.
class ApiException implements Exception {
  const ApiException({
    required this.code,
    required this.message,
    this.requestId = '',
    this.statusCode,
    this.method,
    this.path,
  });

  /// Wire error code, namespaced (see [ApiCode]).
  final int code;

  /// Server-provided message; already user-facing.
  final String message;

  /// Server correlation id, echoed from the envelope or `X-Request-ID`.
  final String requestId;

  /// HTTP status the envelope arrived with, when it was not 200.
  final int? statusCode;

  final String? method;
  final String? path;

  bool get isUnauthenticated => ApiCode.isUnauthenticated(code);
  bool get isForbidden => code == ApiCode.forbidden;
  bool get isNotFound => code == ApiCode.notFound;

  @override
  String toString() {
    final where = [method, path].whereType<String>().join(' ');
    final rid = requestId.isEmpty ? '' : ' [$requestId]';
    return 'ApiException($code)$rid${where.isEmpty ? '' : ' $where'}: $message';
  }
}

/// The request never produced a service envelope: DNS failure, timeout,
/// connection reset, or a body Dio itself refused to decode.
class ApiTransportException implements Exception {
  const ApiTransportException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => 'ApiTransportException: $message';
}

/// One page of a list endpoint.
///
/// The service returns `{items, total, page, pages}` inside the envelope and
/// repeats the total in the `X-Total` header; both are read, because the
/// header survives endpoints that stream a bare list.
class ApiPage<T> {
  const ApiPage({
    required this.items,
    required this.total,
    this.page = 1,
    this.pages = 1,
  });

  const ApiPage.empty()
    : items = const [],
      total = 0,
      page = 1,
      pages = 1;

  final List<T> items;
  final int total;
  final int page;
  final int pages;

  bool get hasMore => page < pages;
  bool get isEmpty => items.isEmpty;
}

/// HTTP client for one LKM-service deployment.
///
/// Responsibilities kept here, and nowhere else in the app:
///
/// * building the base URL ([normalizeApiBase]);
/// * attaching the bearer token, when a [tokenProvider] is supplied (the
///   session owns rotation; this client only reads the current value);
/// * unwrapping the `{code, message, data, request_id}` envelope and turning
///   `code != 0` into [ApiException] — Dio's default "only non-2xx throws"
///   rule is wrong for this service;
/// * mapping a bare non-envelope failure (5xx from a proxy, gateway timeout)
///   onto the closest common-namespace code;
/// * reading pagination from either the envelope or `X-Total`.
class ApiClient {
  ApiClient({
    required String serverUrl,
    Dio? dio,
    Future<String?> Function()? tokenProvider,
    String? userAgent,
  }) : baseUrl = normalizeApiBase(serverUrl),
       _ownsDio = dio == null,
       _dio = dio ?? Dio(),
       _tokenProvider = tokenProvider {
    _dio.options = _dio.options.copyWith(
      baseUrl: baseUrl,
      connectTimeout: kApiConnectTimeout,
      receiveTimeout: kApiReceiveTimeout,
      headers: {
        ..._dio.options.headers,
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        if (userAgent != null && userAgent.isNotEmpty) 'User-Agent': userAgent,
      },
    );
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final provider = _tokenProvider;
          if (provider != null) {
            final token = await provider();
            if (token != null && token.isNotEmpty) {
              options.headers['Authorization'] = 'Bearer $token';
            }
          }
          handler.next(options);
        },
      ),
    );
  }

  /// Fully qualified base URL, e.g. `https://lkm-ahz.ltd/api/v1`.
  final String baseUrl;

  final Dio _dio;
  final bool _ownsDio;
  final Future<String?> Function()? _tokenProvider;

  /// Escape hatch for the rare caller that needs Dio itself (raw download,
  /// upload progress, `ResponseType.stream`). Prefer the typed helpers.
  Dio get dio => _dio;

  Future<Object?> get(
    String path, {
    Map<String, dynamic>? query,
    Map<String, String>? headers,
    CancelToken? cancelToken,
  }) => _request(
    'GET',
    path,
    query: query,
    headers: headers,
    cancelToken: cancelToken,
  );

  Future<Object?> post(
    String path, {
    Object? body,
    Map<String, dynamic>? query,
    Map<String, String>? headers,
    CancelToken? cancelToken,
  }) => _request(
    'POST',
    path,
    body: body,
    query: query,
    headers: headers,
    cancelToken: cancelToken,
  );

  Future<Object?> put(
    String path, {
    Object? body,
    Map<String, dynamic>? query,
    Map<String, String>? headers,
    CancelToken? cancelToken,
  }) => _request(
    'PUT',
    path,
    body: body,
    query: query,
    headers: headers,
    cancelToken: cancelToken,
  );

  Future<Object?> patch(
    String path, {
    Object? body,
    Map<String, dynamic>? query,
    Map<String, String>? headers,
    CancelToken? cancelToken,
  }) => _request(
    'PATCH',
    path,
    body: body,
    query: query,
    headers: headers,
    cancelToken: cancelToken,
  );

  Future<Object?> delete(
    String path, {
    Object? body,
    Map<String, dynamic>? query,
    Map<String, String>? headers,
    CancelToken? cancelToken,
  }) => _request(
    'DELETE',
    path,
    body: body,
    query: query,
    headers: headers,
    cancelToken: cancelToken,
  );

  /// GET returning a JSON object, or an empty map when `data` is null.
  Future<Map<String, dynamic>> getObject(
    String path, {
    Map<String, dynamic>? query,
    Map<String, String>? headers,
    CancelToken? cancelToken,
  }) async {
    final data = await get(
      path,
      query: query,
      headers: headers,
      cancelToken: cancelToken,
    );
    if (data == null) return <String, dynamic>{};
    if (data is Map) return Map<String, dynamic>.from(data);
    throw _shapeError('GET', path, '期望对象，收到 ${data.runtimeType}');
  }

  /// GET returning a JSON list, or an empty list when `data` is null.
  Future<List<T>> getList<T>(
    String path, {
    Map<String, dynamic>? query,
    Map<String, String>? headers,
    required T Function(Map<String, dynamic>) parseItem,
    CancelToken? cancelToken,
  }) async {
    final page = await getPage(
      path,
      query: query,
      headers: headers,
      parseItem: parseItem,
      cancelToken: cancelToken,
    );
    return page.items;
  }

  /// GET returning one page, accepting both `{items, ...}` and a bare list.
  Future<ApiPage<T>> getPage<T>(
    String path, {
    Map<String, dynamic>? query,
    Map<String, String>? headers,
    required T Function(Map<String, dynamic>) parseItem,
    CancelToken? cancelToken,
  }) async {
    final response = await _send(
      'GET',
      path,
      query: query,
      headers: headers,
      cancelToken: cancelToken,
    );
    final data = _unwrap(response, 'GET', path);
    final headerTotal = int.tryParse(response.headers.value('x-total') ?? '');

    if (data is Map) {
      final rawItems = data['items'];
      if (rawItems is List) {
        final items = rawItems
            .whereType<Map>()
            .map((e) => parseItem(Map<String, dynamic>.from(e)))
            .toList(growable: false);
        return ApiPage(
          items: items,
          total: _asInt(data['total']) ?? headerTotal ?? items.length,
          page: _asInt(data['page']) ?? 1,
          pages: _asInt(data['pages']) ?? 1,
        );
      }
    }
    if (data is List) {
      final items = data
          .whereType<Map>()
          .map((e) => parseItem(Map<String, dynamic>.from(e)))
          .toList(growable: false);
      return ApiPage(items: items, total: headerTotal ?? items.length);
    }
    if (data == null) return const ApiPage.empty();
    throw _shapeError('GET', path, '期望分页结构，收到 ${data.runtimeType}');
  }

  /// Releases the underlying Dio when this client created it.
  void close() {
    if (_ownsDio) {
      _dio.close(force: true);
    }
  }

  Future<Object?> _request(
    String method,
    String path, {
    Object? body,
    Map<String, dynamic>? query,
    Map<String, String>? headers,
    CancelToken? cancelToken,
  }) async {
    final response = await _send(
      method,
      path,
      body: body,
      query: query,
      headers: headers,
      cancelToken: cancelToken,
    );
    return _unwrap(response, method, path);
  }

  Future<Response<dynamic>> _send(
    String method,
    String path, {
    Object? body,
    Map<String, dynamic>? query,
    Map<String, String>? headers,
    CancelToken? cancelToken,
  }) async {
    try {
      return await _dio.request<dynamic>(
        path,
        data: body,
        queryParameters: query,
        cancelToken: cancelToken,
        options: Options(
          method: method,
          validateStatus: (_) => true,
          headers: headers,
        ),
      );
    } on DioException catch (error) {
      if (error.type == DioExceptionType.cancel) rethrow;
      throw ApiTransportException(
        _describeTransportError(error),
        cause: error,
      );
    }
  }

  /// Turns a response into `data`, or throws [ApiException].
  Object? _unwrap(Response<dynamic> response, String method, String path) {
    final status = response.statusCode ?? 0;
    final ok = status >= 200 && status < 300;
    final body = response.data;

    if (body is Map) {
      final rawCode = body['code'];
      if (rawCode is int) {
        if (rawCode == ApiCode.ok) return body['data'];
        throw ApiException(
          code: rawCode,
          message: _messageOf(body) ?? '请求失败（$rawCode）',
          requestId: _requestIdOf(body, response),
          statusCode: status,
          method: method,
          path: path,
        );
      }
      // 非信封 JSON：服务端有几个端点用 msgspec 直出预编码响应。
      if (ok) return body;
    } else if (ok) {
      return body;
    }

    throw ApiException(
      code: _codeForStatus(status),
      message: 'HTTP $status ${_statusHint(status)}',
      requestId: response.headers.value('x-request-id') ?? '',
      statusCode: status,
      method: method,
      path: path,
    );
  }

  ApiException _shapeError(String method, String path, String detail) =>
      ApiException(
        code: ApiCode.invalidInput,
        message: detail,
        method: method,
        path: path,
      );

  static String? _messageOf(Map<dynamic, dynamic> body) {
    final message = body['message'];
    if (message is String && message.trim().isNotEmpty) return message.trim();
    return null;
  }

  static String _requestIdOf(
    Map<dynamic, dynamic> body,
    Response<dynamic> response,
  ) {
    final fromBody = body['request_id'];
    if (fromBody is String && fromBody.isNotEmpty) return fromBody;
    return response.headers.value('x-request-id') ?? '';
  }

  /// Closest common-namespace code for a response that carried no envelope.
  static int _codeForStatus(int status) {
    if (status == 401) return ApiCode.unauthorized;
    if (status == 403) return ApiCode.forbidden;
    if (status == 404) return ApiCode.notFound;
    if (status == 409) return ApiCode.conflict;
    if (status == 422 || status == 400) return ApiCode.invalidInput;
    if (status == 503) return ApiCode.unavailable;
    if (status == 504) return ApiCode.timeout;
    if (status >= 500) return ApiCode.internalError;
    return ApiCode.badRequest;
  }

  static String _statusHint(int status) {
    if (status == 0) return '（无响应）';
    if (status >= 500) return '服务端错误';
    if (status == 401) return '认证失败';
    if (status == 403) return '无权限';
    if (status == 404) return '资源不存在';
    return '请求被拒绝';
  }

  static String _describeTransportError(DioException error) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
        return '连接超时';
      case DioExceptionType.sendTimeout:
        return '发送超时';
      case DioExceptionType.receiveTimeout:
        return '接收超时';
      case DioExceptionType.connectionError:
        return '无法连接服务器';
      case DioExceptionType.badCertificate:
        return '证书校验失败';
      case DioExceptionType.badResponse:
        return '服务器返回异常响应';
      case DioExceptionType.transformTimeout:
        return '响应解析超时';
      case DioExceptionType.cancel:
        return '请求已取消';
      case DioExceptionType.unknown:
        return error.message ?? '网络错误';
    }
  }

  static int? _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }
}
