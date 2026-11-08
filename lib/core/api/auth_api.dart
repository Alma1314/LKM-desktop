import 'package:island/core/api/api_client.dart';

/// The account a session belongs to (`GET /auth/me` → `MeInfo`).
class LkmAccount {
  const LkmAccount({
    required this.id,
    required this.username,
    required this.accountLevel,
    required this.role,
    this.nickname,
    this.avatar,
    this.email,
    this.phone,
    this.activeRoles = const [],
  });

  final String id;
  final String username;
  final String accountLevel;
  final String role;
  final List<String> activeRoles;
  final String? nickname;
  final String? avatar;
  final String? email;
  final String? phone;

  String get displayName =>
      (nickname != null && nickname!.trim().isNotEmpty)
      ? nickname!.trim()
      : username;

  /// Whether the admin surfaces may be offered (decision 4 in
  /// `docs/桌面端接入后端方案.md`). The server still enforces every endpoint.
  bool get isAdmin =>
      role == 'admin' ||
      accountLevel == 'admin' ||
      activeRoles.contains('admin');

  factory LkmAccount.fromJson(Map<String, dynamic> json) {
    final roles = json['active_roles'];
    return LkmAccount(
      id: '${json['id'] ?? ''}',
      username: '${json['username'] ?? ''}',
      accountLevel: '${json['account_level'] ?? ''}',
      role: '${json['role'] ?? ''}',
      activeRoles: roles is List
          ? roles.whereType<String>().toList(growable: false)
          : const [],
      nickname: json['nickname'] as String?,
      avatar: json['avatar'] as String?,
      email: json['email'] as String?,
      phone: json['phone'] as String?,
    );
  }
}

/// Tokens issued by the last factor of a challenge (or by registration).
class LkmAuthToken {
  const LkmAuthToken({
    required this.userId,
    required this.accountLevel,
    required this.accessToken,
    required this.refreshToken,
  });

  final String userId;
  final String accountLevel;
  final String accessToken;
  final String refreshToken;

  factory LkmAuthToken.fromJson(Map<String, dynamic> json) {
    final access = json['access_token'];
    final refresh = json['refresh_token'];
    if (access is! String || access.isEmpty || refresh is! String) {
      throw ApiException(
        code: ApiCode.unauthorized,
        message: '服务器未返回令牌',
      );
    }
    return LkmAuthToken(
      userId: '${json['user_id'] ?? ''}',
      accountLevel: '${json['account_level'] ?? ''}',
      accessToken: access,
      refreshToken: refresh,
    );
  }
}

/// One factor the server asks the client to collect.
///
/// `kind` is intentionally a plain string: the client renders what it knows
/// (`password`, `code`, `totp`) and reports anything else as unsupported,
/// which is what lets new factors ship server-side without a client release.
class LkmChallengeFactor {
  const LkmChallengeFactor({required this.kind, this.hint});

  final String kind;

  /// Where the code went (`a***@example.com`), when the server says so.
  final String? hint;

  factory LkmChallengeFactor.fromJson(Map<String, dynamic> json) =>
      LkmChallengeFactor(
        kind: '${json['kind'] ?? ''}',
        hint: json['hint'] as String?,
      );
}

/// The server-side challenge: which factors are next, and when it dies.
class LkmChallenge {
  const LkmChallenge({
    required this.id,
    required this.status,
    required this.factors,
    this.expiresAt,
  });

  final String id;
  final String status;
  final List<LkmChallengeFactor> factors;
  final DateTime? expiresAt;

  /// The factor to submit next, or null when the challenge has no further step.
  LkmChallengeFactor? get current => factors.isEmpty ? null : factors.first;

  factory LkmChallenge.fromJson(Map<String, dynamic> json) {
    final rawFactors = json['factors'];
    return LkmChallenge(
      id: '${json['id'] ?? ''}',
      status: '${json['status'] ?? 'pending'}',
      factors: rawFactors is List
          ? rawFactors
                .whereType<Map>()
                .map(
                  (e) => LkmChallengeFactor.fromJson(
                    Map<String, dynamic>.from(e),
                  ),
                )
                .toList(growable: false)
          : const [],
      expiresAt: DateTime.tryParse('${json['expires_at'] ?? ''}'),
    );
  }
}

/// Result of submitting one factor: either the last step (tokens) or the next
/// challenge state.
class LkmAuthStep {
  const LkmAuthStep.complete(LkmAuthToken this.tokens) : challenge = null;
  const LkmAuthStep.pending(LkmChallenge this.challenge) : tokens = null;

  final LkmAuthToken? tokens;
  final LkmChallenge? challenge;

  bool get isComplete => tokens != null;

  factory LkmAuthStep.fromJson(Map<String, dynamic> json) {
    if (json['status'] == 'complete') {
      return LkmAuthStep.complete(LkmAuthToken.fromJson(json));
    }
    return LkmAuthStep.pending(LkmChallenge.fromJson(json));
  }
}

/// WebAuthn request options for the passkey factor.
class LkmPasskeyOptions {
  const LkmPasskeyOptions({required this.challengeId, required this.publicKey});

  /// Server-side WebAuthn challenge row id (not the challenge-factor id).
  final String challengeId;

  /// `PublicKeyCredentialRequestOptions` as the server serialized it.
  final Map<String, dynamic> publicKey;

  String get challenge => '${publicKey['challenge'] ?? ''}';
  String get rpId => '${publicKey['rpId'] ?? ''}';

  List<Map<String, dynamic>> get allowCredentials {
    final raw = publicKey['allowCredentials'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList(growable: false);
  }
}

/// The assertion produced by the platform authenticator.
class LkmPasskeyAssertion {
  const LkmPasskeyAssertion({
    required this.rawId,
    required this.clientDataJson,
    required this.authenticatorData,
    required this.signature,
    this.userHandle,
  });

  final String rawId;
  final String clientDataJson;
  final String authenticatorData;
  final String signature;
  final String? userHandle;
}

/// Challenge-factor authentication endpoints, plus the few flows that are not
/// challenge-based (email registration).
///
/// The device identifier travels in the `X-Device-Id` header on every challenge
/// call: one place for all six of them, instead of a body/query split where a
/// wrong guess surfaces as "challenge not found" rather than as a bad request.
class AuthApi {
  const AuthApi(this._client);

  final ApiClient _client;

  static Map<String, String> _device(String deviceId) => {
    'X-Device-Id': deviceId,
  };

  /// `POST /auth/challenge` — body `{account, device_id, primary_factor}`.
  Future<LkmChallenge> createChallenge({
    required String account,
    required String deviceId,
    String primaryFactor = 'password',
  }) async {
    final data = await _client.post(
      '/auth/challenge',
      body: {'account': account, 'primary_factor': primaryFactor},
      headers: _device(deviceId),
    );
    return LkmChallenge.fromJson(_asMap(data));
  }

  /// `GET /auth/challenge/{id}?device_id=…` — restore an in-flight challenge.
  Future<LkmChallenge> getChallenge(String id, String deviceId) async {
    final data = await _client.get(
      '/auth/challenge/$id',
      headers: _device(deviceId),
    );
    return LkmChallenge.fromJson(_asMap(data));
  }

  /// `POST /auth/challenge/{id}/factor` — returns the next step or tokens.
  Future<LkmAuthStep> submitFactor(
    String id, {
    required String deviceId,
    required String kind,
    String? password,
    String? code,
    String? recoveryCode,
  }) async {
    final data = await _client.post(
      '/auth/challenge/$id/factor',
      body: {
        'kind': kind,
        'password': ?password,
        'code': ?code,
        'recovery_code': ?recoveryCode,
      },
      headers: _device(deviceId),
    );
    return LkmAuthStep.fromJson(_asMap(data));
  }

  /// `POST /auth/challenge/{id}/request?device_id=…` — sends the code factor.
  Future<void> requestFactorCode(String id, String deviceId) => _client.post(
    '/auth/challenge/$id/request',
    headers: _device(deviceId),
  );

  /// `POST /auth/challenge/{id}/cancel?device_id=…`
  Future<void> cancelChallenge(String id, String deviceId) => _client.post(
    '/auth/challenge/$id/cancel',
    headers: _device(deviceId),
  );

  /// `POST /auth/reg/email` — body `{email}`; not part of the challenge flow.
  Future<void> requestRegisterCode(String email) =>
      _client.post('/auth/reg/email', body: {'email': email});

  /// `POST /auth/reg/email/verify?email=…&code=…` — completes email-only
  /// registration and returns a signed-in token pair.
  Future<LkmAuthToken> registerWithEmail({
    required String email,
    required String code,
  }) async {
    final data = await _client.post(
      '/auth/reg/email/verify',
      query: {'email': email, 'code': code},
    );
    return LkmAuthToken.fromJson(_asMap(data));
  }

  /// `GET /auth/me`
  Future<LkmAccount> me() async {
    final data = await _client.getObject('/auth/me');
    return LkmAccount.fromJson(data);
  }

  /// `POST /auth/challenge/{id}/passkey/start` — assertion options.
  Future<LkmPasskeyOptions> startPasskeyFactor(
    String challengeId,
    String deviceId,
  ) async {
    final data = await _client.post(
      '/auth/challenge/$challengeId/passkey/start',
      headers: _device(deviceId),
    );
    final map = _asMap(data);
    final publicKey = map['public_key'];
    if (publicKey is! Map) {
      throw ApiException(
        code: ApiCode.internalError,
        message: '通行密钥选项格式异常',
      );
    }
    return LkmPasskeyOptions(
      challengeId: '${map['challenge_id'] ?? ''}',
      publicKey: Map<String, dynamic>.from(publicKey),
    );
  }

  /// `POST /auth/challenge/{id}/passkey/complete` — verifies the assertion.
  Future<LkmAuthStep> completePasskeyFactor(
    String challengeId, {
    required String deviceId,
    required String webauthnChallengeId,
    required LkmPasskeyAssertion assertion,
  }) async {
    final data = await _client.post(
      '/auth/challenge/$challengeId/passkey/complete',
      headers: _device(deviceId),
      body: {
        'challenge_id': webauthnChallengeId,
        'rawId': assertion.rawId,
        'type': 'public-key',
        'response': {
          'clientDataJSON': assertion.clientDataJson,
          'authenticatorData': assertion.authenticatorData,
          'signature': assertion.signature,
          'userHandle': ?assertion.userHandle,
        },
      },
    );
    return LkmAuthStep.fromJson(_asMap(data));
  }

  static Map<String, dynamic> _asMap(Object? data) {
    if (data is Map) return Map<String, dynamic>.from(data);
    throw ApiException(
      code: ApiCode.internalError,
      message: '认证响应格式异常',
    );
  }
}
