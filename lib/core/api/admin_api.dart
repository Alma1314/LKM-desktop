import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';

/// Keys holding the admin panel's cookie session.
///
/// The admin panel is a **separate** cookie session from the bearer session
/// (`/admin/auth/*` is served by the auth process, every `/admin/*` endpoint
/// reads `admin_session` only). The desktop has no cookie jar, so the two
/// cookie values are persisted here and replayed as an explicit `Cookie`
/// header — same approach as the treehole visitor token.
const String kAdminAccessTokenKey = 'lkm_admin_access_token';
const String kAdminRefreshTokenKey = 'lkm_admin_refresh_token';

const String _accessCookie = 'admin_session';
const String _refreshCookie = 'admin_refresh';

/// `GET /admin/auth/me`: the logged-in admin and the permission points their
/// active roles grant. The permission list only hides empty menus; every
/// endpoint still enforces its own check.
class AdminSessionInfo {
  const AdminSessionInfo({
    required this.id,
    required this.accountLevel,
    required this.role,
    required this.permissions,
  });

  final String id;
  final String accountLevel;
  final String role;
  final List<String> permissions;

  bool can(String permission) => permissions.contains(permission);

  factory AdminSessionInfo.fromJson(Map<String, dynamic> json) {
    final raw = json['permissions'];
    return AdminSessionInfo(
      id: '${json['id'] ?? ''}',
      accountLevel: '${json['account_level'] ?? ''}',
      role: '${json['role'] ?? ''}',
      permissions: raw is List
          ? raw.whereType<String>().toList(growable: false)
          : const [],
    );
  }
}

class AdminRule {
  const AdminRule({
    required this.id,
    required this.pattern,
    required this.isRegex,
    required this.action,
    required this.weight,
    required this.scope,
    required this.enabled,
  });

  final String id;
  final String pattern;
  final bool isRegex;

  /// `derank` or `hide`.
  final String action;
  final double weight;
  final String scope;
  final bool enabled;

  factory AdminRule.fromJson(Map<String, dynamic> json) => AdminRule(
    id: '${json['id'] ?? ''}',
    pattern: '${json['pattern'] ?? ''}',
    isRegex: json['is_regex'] == true,
    action: '${json['action'] ?? 'derank'}',
    weight: _asDouble(json['weight']),
    scope: '${json['scope'] ?? 'content'}',
    enabled: json['enabled'] != false,
  );
}

class AdminRuleHit {
  const AdminRuleHit({
    required this.pattern,
    required this.isRegex,
    required this.action,
    required this.weight,
    required this.scope,
  });

  final String pattern;
  final bool isRegex;
  final String action;
  final double weight;
  final String scope;

  factory AdminRuleHit.fromJson(Map<String, dynamic> json) => AdminRuleHit(
    pattern: '${json['pattern'] ?? ''}',
    isRegex: json['is_regex'] == true,
    action: '${json['action'] ?? ''}',
    weight: _asDouble(json['weight']),
    scope: '${json['scope'] ?? ''}',
  );
}

class AdminRuleTestResult {
  const AdminRuleTestResult({
    required this.matched,
    required this.penalty,
    required this.shouldHide,
    required this.hits,
    required this.totalRules,
  });

  final bool matched;
  final double penalty;
  final bool shouldHide;
  final List<AdminRuleHit> hits;
  final int totalRules;

  factory AdminRuleTestResult.fromJson(Map<String, dynamic> json) {
    final raw = json['hits'];
    return AdminRuleTestResult(
      matched: json['matched'] == true,
      penalty: _asDouble(json['penalty']),
      shouldHide: json['should_hide'] == true,
      hits: raw is List
          ? raw
                .whereType<Map>()
                .map((e) => AdminRuleHit.fromJson(Map<String, dynamic>.from(e)))
                .toList(growable: false)
          : const [],
      totalRules: _asInt(json['total_rules']),
    );
  }
}

/// One row of `/admin/content/items` (the website's admin posts page).
class AdminContentItem {
  const AdminContentItem({
    required this.id,
    required this.contentType,
    required this.title,
    required this.authorName,
    required this.status,
    required this.createdAt,
    required this.viewCount,
    required this.likeCount,
    required this.commentCount,
    required this.isPinned,
    required this.isFeatured,
  });

  final String id;

  /// `discussion` / `article` / `column_post` / `blog_post` / `qa`.
  final String contentType;
  final String title;
  final String authorName;
  final String status;
  final DateTime createdAt;
  final int viewCount;
  final int likeCount;
  final int commentCount;
  final bool isPinned;
  final bool isFeatured;

  factory AdminContentItem.fromJson(Map<String, dynamic> json) =>
      AdminContentItem(
        id: '${json['id'] ?? ''}',
        contentType: '${json['content_type'] ?? ''}',
        title: '${json['title'] ?? ''}',
        authorName: '${json['author_name'] ?? ''}',
        status: '${json['status'] ?? ''}',
        createdAt: _asLocal(json['created_at']) ?? DateTime(1970),
        viewCount: _asInt(json['view_count']),
        likeCount: _asInt(json['like_count']),
        commentCount: _asInt(json['comment_count']),
        isPinned: json['is_pinned'] == true,
        isFeatured: json['is_featured'] == true,
      );
}

class AdminReport {
  const AdminReport({
    required this.id,
    required this.type,
    required this.targetId,
    required this.targetTitle,
    required this.reporterName,
    required this.reason,
    required this.status,
    required this.createdAt,
    this.handledAt,
  });

  final String id;
  final String type;
  final String targetId;
  final String targetTitle;
  final String reporterName;
  final String reason;
  final String status;
  final DateTime createdAt;
  final DateTime? handledAt;

  factory AdminReport.fromJson(Map<String, dynamic> json) => AdminReport(
    id: '${json['id'] ?? ''}',
    type: '${json['type'] ?? ''}',
    targetId: '${json['target_id'] ?? ''}',
    targetTitle: '${json['target_title'] ?? ''}',
    reporterName: '${json['reporter_name'] ?? ''}',
    reason: '${json['reason'] ?? ''}',
    status: '${json['status'] ?? ''}',
    createdAt: _asLocal(json['created_at']) ?? DateTime(1970),
    handledAt: _asLocal(json['handled_at']),
  );
}

/// One row of the public `/files` listing filtered to the review queue.
class AdminFile {
  const AdminFile({
    required this.id,
    required this.originalName,
    required this.uploaderName,
    required this.mimeType,
    required this.size,
    required this.status,
    required this.classification,
    required this.createdAt,
    this.reviewComment,
  });

  final String id;
  final String originalName;
  final String uploaderName;
  final String mimeType;
  final int size;
  final String status;
  final String classification;
  final DateTime createdAt;
  final String? reviewComment;

  factory AdminFile.fromJson(Map<String, dynamic> json) => AdminFile(
    id: '${json['id'] ?? ''}',
    originalName: '${json['original_name'] ?? ''}',
    uploaderName: '${json['uploader_name'] ?? ''}',
    mimeType: '${json['mime_type'] ?? ''}',
    size: _asInt(json['size']),
    status: '${json['status'] ?? ''}',
    classification: '${json['classification'] ?? 'public'}',
    createdAt: _asLocal(json['created_at']) ?? DateTime(1970),
    reviewComment: json['review_comment'] as String?,
  );
}

class AdminBatchReviewItem {
  const AdminBatchReviewItem({
    required this.fileId,
    required this.ok,
    this.status,
    this.error,
  });

  final String fileId;
  final bool ok;
  final String? status;
  final String? error;

  factory AdminBatchReviewItem.fromJson(Map<String, dynamic> json) =>
      AdminBatchReviewItem(
        fileId: '${json['file_id'] ?? ''}',
        ok: json['ok'] == true,
        status: json['status'] as String?,
        error: json['error'] as String?,
      );
}

class AdminBatchReviewResult {
  const AdminBatchReviewResult({
    required this.results,
    required this.succeeded,
    required this.failed,
  });

  final List<AdminBatchReviewItem> results;
  final int succeeded;
  final int failed;

  factory AdminBatchReviewResult.fromJson(Map<String, dynamic> json) {
    final raw = json['results'];
    return AdminBatchReviewResult(
      results: raw is List
          ? raw
                .whereType<Map>()
                .map(
                  (e) =>
                      AdminBatchReviewItem.fromJson(Map<String, dynamic>.from(e)),
                )
                .toList(growable: false)
          : const [],
      succeeded: _asInt(json['succeeded']),
      failed: _asInt(json['failed']),
    );
  }
}

class AdminDlqItem {
  const AdminDlqItem({
    required this.id,
    required this.routingKey,
    required this.status,
    required this.attempts,
    this.reason,
    this.createdAt,
    this.payload,
  });

  final String id;
  final String routingKey;
  final String status;
  final int attempts;
  final String? reason;
  final String? createdAt;
  final Object? payload;

  factory AdminDlqItem.fromJson(Map<String, dynamic> json) => AdminDlqItem(
    id: '${json['id'] ?? ''}',
    routingKey: '${json['routing_key'] ?? ''}',
    status: '${json['status'] ?? ''}',
    attempts: _asInt(json['attempts']),
    reason: json['reason'] as String?,
    createdAt: json['created_at'] as String?,
    payload: json['payload'],
  );
}

/// Reads the admin panel's six content blocks and owns its cookie session.
///
/// Lifecycle: [login] stores the `admin_session`/`admin_refresh` pair; every
/// call then goes out with an explicit `Cookie` header. The access cookie is
/// short-lived (15 min) and refresh rotates **both** cookies, so refresh is
/// single-flight — a second concurrent rotation would present a stale refresh
/// token and revoke the live session.
class AdminApi {
  AdminApi({required ApiClient client, required SharedPreferences prefs})
    : _client = client,
      _prefs = prefs;

  final ApiClient _client;
  final SharedPreferences _prefs;

  String? _access;
  String? _refresh;
  Future<void>? _refreshInFlight;

  bool get isSignedIn => _access != null && _refresh != null;

  /// Loads a persisted pair, if one exists.
  void restore() {
    _access = _prefs.getString(kAdminAccessTokenKey);
    _refresh = _prefs.getString(kAdminRefreshTokenKey);
    if (_access == null || _refresh == null) _clearLocal();
  }

  /// Signs in with the admin panel's own username/password.
  Future<AdminSessionInfo> login(String username, String password) async {
    final response = await _client.dio.post<dynamic>(
      '/admin/auth/login',
      data: {'username': username, 'password': password},
      options: Options(validateStatus: (_) => true),
    );
    _unwrap(response, 'POST', '/admin/auth/login');
    _adoptCookies(response);
    if (!isSignedIn) {
      throw ApiException(
        code: ApiCode.forbidden,
        message: '后台登录未返回会话',
        method: 'POST',
        path: '/admin/auth/login',
      );
    }
    try {
      return await me();
    } catch (_) {
      await _clearRemote();
      rethrow;
    }
  }

  Future<AdminSessionInfo> me() async {
    return _authed(() async {
      final json = await _client.getObject(
        '/admin/auth/me',
        headers: _headers(),
      );
      return AdminSessionInfo.fromJson(json);
    });
  }

  /// TOTP step-up for dangerous writes (`ApiCode.mfaRequired`).
  Future<void> verify2fa(String code) async {
    await _ensureFresh();
    final response = await _client.dio.post<dynamic>(
      '/admin/auth/2fa',
      data: {'code': code},
      options: Options(
        validateStatus: (_) => true,
        headers: _headers(refresh: true),
      ),
    );
    _unwrap(response, 'POST', '/admin/auth/2fa');
    _adoptCookies(response);
  }

  Future<void> logout() async {
    if (isSignedIn) {
      try {
        await _client.dio.post<dynamic>(
          '/admin/auth/logout',
          options: Options(validateStatus: (_) => true, headers: _headers()),
        );
      } catch (_) {
        // Best effort: local state is cleared either way.
      }
    }
    await _clearRemote();
  }

  // --- content -------------------------------------------------------------

  Future<ApiPage<AdminContentItem>> contentItems({
    int page = 1,
    int limit = 20,
    String? contentType,
  }) {
    return _authed(
      () => _client.getPage(
        '/admin/content/items',
        query: {
          'page': page,
          'limit': limit,
          'content_type': ?contentType,
        },
        headers: _headers(),
        parseItem: AdminContentItem.fromJson,
      ),
    );
  }

  Future<void> deleteContentItem(String id) async {
    await _authed(
      () => _client.delete(
        '/admin/content/item/$id',
        headers: _headers(),
      ),
    );
  }

  // --- reports -------------------------------------------------------------

  Future<ApiPage<AdminReport>> reports({
    int page = 1,
    int limit = 20,
    String? status,
  }) {
    return _authed(
      () => _client.getPage(
        '/admin/reports',
        query: {
          'page': page,
          'limit': limit,
          'status': ?status,
        },
        headers: _headers(),
        parseItem: AdminReport.fromJson,
      ),
    );
  }

  // --- moderation rules ----------------------------------------------------

  Future<List<AdminRule>> rules() {
    return _authed(
      () => _client.getList(
        '/admin/moderation/rules',
        headers: _headers(),
        parseItem: AdminRule.fromJson,
      ),
    );
  }

  Future<AdminRule> createRule({
    required String pattern,
    required bool isRegex,
    required String action,
    required double weight,
    required bool enabled,
  }) async {
    final json = await _authed(
      () => _client.post(
        '/admin/moderation/rules',
        headers: _headers(),
        body: {
          'pattern': pattern,
          'is_regex': isRegex,
          'action': action,
          'weight': weight,
          'enabled': enabled,
        },
      ),
    );
    if (json is! Map) throw _shape('POST', '/admin/moderation/rules');
    return AdminRule.fromJson(Map<String, dynamic>.from(json));
  }

  Future<AdminRule> updateRule(
    String id, {
    String? pattern,
    bool? isRegex,
    String? action,
    double? weight,
    bool? enabled,
  }) async {
    final json = await _authed(
      () => _client.patch(
        '/admin/moderation/rules/$id',
        headers: _headers(),
        body: {
          'pattern': ?pattern,
          'is_regex': ?isRegex,
          'action': ?action,
          'weight': ?weight,
          'enabled': ?enabled,
        },
      ),
    );
    if (json is! Map) throw _shape('PATCH', '/admin/moderation/rules/$id');
    return AdminRule.fromJson(Map<String, dynamic>.from(json));
  }

  Future<void> deleteRule(String id) async {
    await _authed(
      () => _client.delete(
        '/admin/moderation/rules/$id',
        headers: _headers(),
      ),
    );
  }

  Future<AdminRuleTestResult> testRules(String text) async {
    final json = await _authed(
      () => _client.post(
        '/admin/moderation/rules/test',
        headers: _headers(),
        body: {'text': text},
      ),
    );
    if (json is! Map) throw _shape('POST', '/admin/moderation/rules/test');
    return AdminRuleTestResult.fromJson(Map<String, dynamic>.from(json));
  }

  // --- files ---------------------------------------------------------------

  /// The review queue is the public `/files` listing with a status filter; it
  /// is visibility-filtered by the caller's bearer session, so the admin must
  /// also be signed in to the desktop app (the panel's entry gate requires it).
  Future<ApiPage<AdminFile>> files({
    int page = 1,
    int limit = 50,
    String status = 'pending',
  }) {
    return _authed(
      () => _client.getPage(
        '/files',
        query: {'page': page, 'limit': limit, 'status': status},
        headers: _headers(),
        parseItem: AdminFile.fromJson,
      ),
    );
  }

  Future<AdminBatchReviewResult> reviewFiles({
    required List<String> fileIds,
    required String status,
    String? comment,
  }) async {
    final json = await _authed(
      () => _client.post(
        '/files/review-batch',
        headers: _headers(),
        body: {
          'file_ids': fileIds,
          'status': status,
          if (comment != null && comment.isNotEmpty)
            'review_comment': comment,
        },
      ),
    );
    if (json is! Map) throw _shape('POST', '/files/review-batch');
    return AdminBatchReviewResult.fromJson(Map<String, dynamic>.from(json));
  }

  // --- dlq -----------------------------------------------------------------

  Future<List<AdminDlqItem>> dlq({String status = 'pending', int limit = 100}) {
    return _authed(
      () => _client.getList(
        '/admin/dlq',
        query: {'status': status, 'limit': limit},
        headers: _headers(),
        parseItem: AdminDlqItem.fromJson,
      ),
    );
  }

  Future<void> requeueDlq(String id) async {
    await _authed(
      () => _client.post(
        '/admin/dlq/$id/requeue',
        headers: _headers(),
      ),
    );
  }

  Future<void> discardDlq(String id) async {
    await _authed(
      () => _client.post(
        '/admin/dlq/$id/discard',
        headers: _headers(),
      ),
    );
  }

  // --- session internals ---------------------------------------------------

  Map<String, String> _headers({bool refresh = false}) {
    final parts = <String>[
      if (_access != null) '$_accessCookie=$_access',
      if (refresh && _refresh != null) '$_refreshCookie=$_refresh',
    ];
    return {'Cookie': parts.join('; ')};
  }

  Future<T> _authed<T>(Future<T> Function() run) async {
    await _ensureFresh();
    try {
      return await run();
    } on ApiException catch (error) {
      // Admin session failures come back as FORBIDDEN (cookie guard), not
      // 401. Refresh once and replay; a genuine permission denial simply
      // fails again and is surfaced unchanged.
      if (error.code == ApiCode.forbidden || error.isUnauthenticated) {
        await _refreshOnce();
        return await run();
      }
      rethrow;
    }
  }

  Future<void> _ensureFresh() async {
    final access = _access;
    if (access == null) return;
    final expiry = _jwtExpiry(access);
    if (expiry == null ||
        expiry.difference(DateTime.now().toUtc()) < const Duration(minutes: 1)) {
      await _refreshOnce();
    }
  }

  Future<void> _refreshOnce() {
    final inFlight = _refreshInFlight;
    if (inFlight != null) return inFlight;
    final future = _doRefresh();
    _refreshInFlight = future;
    return future.whenComplete(() {
      if (identical(_refreshInFlight, future)) _refreshInFlight = null;
    });
  }

  Future<void> _doRefresh() async {
    final refreshToken = _refresh;
    if (refreshToken == null) {
      await _clearRemote();
      throw const ApiException(
        code: ApiCode.forbidden,
        message: '后台会话已失效',
        method: 'POST',
        path: '/admin/auth/refresh',
      );
    }
    final Response<dynamic> response;
    try {
      response = await _client.dio.post<dynamic>(
        '/admin/auth/refresh',
        options: Options(
          validateStatus: (_) => true,
          headers: {'Cookie': '$_refreshCookie=$refreshToken'},
        ),
      );
    } catch (_) {
      // Transport failure: keep the local pair so a later call can retry.
      rethrow;
    }
    try {
      _unwrap(response, 'POST', '/admin/auth/refresh');
    } on ApiException {
      await _clearRemote();
      rethrow;
    }
    _adoptCookies(response);
    if (!isSignedIn) {
      await _clearRemote();
      throw const ApiException(
        code: ApiCode.forbidden,
        message: '后台会话已失效',
        method: 'POST',
        path: '/admin/auth/refresh',
      );
    }
  }

  void _adoptCookies(Response<dynamic> response) {
    final raw = response.headers['set-cookie'];
    if (raw == null) return;
    var access = _access;
    var refresh = _refresh;
    for (final line in raw) {
      for (final match in _cookiePattern.allMatches(line)) {
        final name = match.group(1);
        final value = match.group(2);
        if (value == null || value.isEmpty) continue;
        if (name == _accessCookie) access = value;
        if (name == _refreshCookie) refresh = value;
      }
    }
    _access = access;
    _refresh = refresh;
    if (access != null) _prefs.setString(kAdminAccessTokenKey, access);
    if (refresh != null) _prefs.setString(kAdminRefreshTokenKey, refresh);
  }

  Future<void> _clearRemote() async {
    _clearLocal();
    await _prefs.remove(kAdminAccessTokenKey);
    await _prefs.remove(kAdminRefreshTokenKey);
  }

  void _clearLocal() {
    _access = null;
    _refresh = null;
  }

  /// Unwraps the `{code,message,data}` envelope without applying the bearer
  /// client's error mapping (the admin endpoints share the envelope, but these
  /// raw calls need the `set-cookie` headers that [ApiClient] hides).
  Object? _unwrap(Response<dynamic> response, String method, String path) {
    final body = response.data;
    final status = response.statusCode ?? 0;
    if (body is Map) {
      final code = body['code'];
      if (code is int) {
        if (code == ApiCode.ok) return body['data'];
        throw ApiException(
          code: code,
          message: '${body['message'] ?? '请求失败（$code）'}',
          statusCode: status,
          method: method,
          path: path,
        );
      }
    }
    if (status >= 200 && status < 300) return body;
    throw ApiException(
      code: status == 401
          ? ApiCode.unauthorized
          : status == 403
          ? ApiCode.forbidden
          : status >= 500
          ? ApiCode.internalError
          : ApiCode.badRequest,
      message: 'HTTP $status',
      statusCode: status,
      method: method,
      path: path,
    );
  }

  static ApiException _shape(String method, String path) => ApiException(
    code: ApiCode.internalError,
    message: '后台响应格式错误',
    method: method,
    path: path,
  );

  static DateTime? _jwtExpiry(String token) {
    final parts = token.split('.');
    if (parts.length != 3) return null;
    try {
      final decoded = utf8.decode(base64Url.decode(base64Url.normalize(parts[1])));
      final payload = jsonDecode(decoded);
      if (payload is! Map) return null;
      final exp = payload['exp'];
      if (exp is! num) return null;
      return DateTime.fromMillisecondsSinceEpoch(
        exp.toInt() * 1000,
        isUtc: true,
      );
    } catch (_) {
      return null;
    }
  }
}

final RegExp _cookiePattern = RegExp(
  r'(?:^|[,;]\s*)(admin_session|admin_refresh)=([^;,\s]+)',
);

int _asInt(Object? value, [int fallback = 0]) =>
    value is num ? value.toInt() : fallback;

double _asDouble(Object? value, [double fallback = 0]) =>
    value is num ? value.toDouble() : fallback;

DateTime? _asLocal(Object? value) {
  final raw = '${value ?? ''}';
  if (raw.isEmpty || raw == 'null') return null;
  return DateTime.tryParse(raw)?.toLocal();
}
