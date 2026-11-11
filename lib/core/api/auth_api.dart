import 'package:dio/dio.dart';

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

  String get displayName => (nickname != null && nickname!.trim().isNotEmpty)
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
      throw ApiException(code: ApiCode.unauthorized, message: '服务器未返回令牌');
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
                  (e) =>
                      LkmChallengeFactor.fromJson(Map<String, dynamic>.from(e)),
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

/// What a token-issuing auth call returned.
///
/// Registration endpoints share `AuthTokenData`, which may carry tokens, a 2FA
/// requirement, or an admission-pending envelope instead. Modelling all three
/// keeps the caller from mistaking "no token" for a malformed response.
class LkmAuthResult {
  const LkmAuthResult({
    required this.userId,
    required this.accountLevel,
    this.tokens,
    this.requires2fa = false,
    this.setupRequired = false,
    this.tempToken,
    this.admissionStatus,
  });

  final String userId;
  final String accountLevel;
  final LkmAuthToken? tokens;
  final bool requires2fa;
  final bool setupRequired;
  final String? tempToken;
  final String? admissionStatus;

  bool get isSignedIn => tokens != null;
  bool get isPendingAdmission =>
      admissionStatus == 'pending' || admissionStatus == 'rejected';

  factory LkmAuthResult.fromJson(Map<String, dynamic> json) {
    final access = json['access_token'];
    final hasTokens = access is String && access.isNotEmpty;
    return LkmAuthResult(
      userId: '${json['user_id'] ?? ''}',
      accountLevel: '${json['account_level'] ?? ''}',
      tokens: hasTokens ? LkmAuthToken.fromJson(json) : null,
      requires2fa: json['requires_2fa'] == true,
      setupRequired: json['setup_required'] == true,
      tempToken: json['temp_token'] as String?,
      admissionStatus: json['admission_status'] as String?,
    );
  }
}

/// First step of username/password registration: the server stashed the
/// pending account and sent the code(s) named here.
class LkmRegistrationPending {
  const LkmRegistrationPending({
    required this.txnId,
    required this.emailSent,
    required this.phoneSent,
    this.message,
  });

  final String txnId;
  final bool emailSent;
  final bool phoneSent;
  final String? message;

  factory LkmRegistrationPending.fromJson(Map<String, dynamic> json) =>
      LkmRegistrationPending(
        txnId: '${json['txn_id'] ?? ''}',
        emailSent: json['email_sent'] == true,
        phoneSent: json['phone_sent'] == true,
        message: json['message'] as String?,
      );
}

/// A recovery step that may require 2FA before the password is reset.
class LkmRecoveryOutcome {
  const LkmRecoveryOutcome({
    required this.message,
    this.requires2fa = false,
    this.txnId,
    this.tempToken,
  });

  final String message;
  final bool requires2fa;
  final String? txnId;
  final String? tempToken;

  factory LkmRecoveryOutcome.fromJson(Map<String, dynamic> json) =>
      LkmRecoveryOutcome(
        message: '${json['message'] ?? ''}',
        requires2fa: json['requires_2fa'] == true,
        txnId: json['txn_id'] as String?,
        tempToken: json['temp_token'] as String?,
      );
}

/// `GET/PUT /auth/onboarding` — registration wizard progress.
class LkmOnboardingState {
  const LkmOnboardingState({
    required this.step,
    required this.completed,
    this.data,
  });

  final int step;
  final bool completed;
  final Map<String, dynamic>? data;

  factory LkmOnboardingState.fromJson(Map<String, dynamic> json) {
    final raw = json['data'];
    return LkmOnboardingState(
      step: json['step'] is num ? (json['step'] as num).toInt() : 1,
      completed: json['completed'] == true,
      data: raw is Map ? Map<String, dynamic>.from(raw) : null,
    );
  }
}

/// `POST /auth/2fa/setup/begin` — secret plus the otpauth URI for a QR code.
class LkmTotpSetup {
  const LkmTotpSetup({required this.secret, required this.qrCodeUri});

  final String secret;
  final String qrCodeUri;

  factory LkmTotpSetup.fromJson(Map<String, dynamic> json) => LkmTotpSetup(
    secret: '${json['secret'] ?? ''}',
    qrCodeUri: '${json['qr_code_uri'] ?? ''}',
  );
}

/// `POST /auth/2fa/setup/complete` — recovery codes shown exactly once.
class LkmTotpSetupComplete {
  const LkmTotpSetupComplete({
    required this.recoveryCodes,
    required this.confirmedSavedRequired,
    this.accessToken,
    this.refreshToken,
  });

  final List<String> recoveryCodes;
  final bool confirmedSavedRequired;
  final String? accessToken;
  final String? refreshToken;

  factory LkmTotpSetupComplete.fromJson(Map<String, dynamic> json) {
    final codes = json['recovery_codes'];
    return LkmTotpSetupComplete(
      recoveryCodes: codes is List
          ? codes.whereType<String>().toList(growable: false)
          : const [],
      confirmedSavedRequired: json['confirmed_saved_required'] == true,
      accessToken: json['access_token'] as String?,
      refreshToken: json['refresh_token'] as String?,
    );
  }
}

/// `POST /auth/2fa/verify` and `/step-up` — new tokens once the second factor
/// is accepted.
class LkmTotpVerify {
  const LkmTotpVerify({
    required this.userId,
    required this.accountLevel,
    this.accessToken,
    this.refreshToken,
    this.trustDevice = false,
    this.mfaVerified,
  });

  final String userId;
  final String accountLevel;
  final String? accessToken;
  final String? refreshToken;
  final bool trustDevice;
  final bool? mfaVerified;

  bool get hasTokens => accessToken != null && accessToken!.isNotEmpty;

  factory LkmTotpVerify.fromJson(Map<String, dynamic> json) => LkmTotpVerify(
    userId: '${json['user_id'] ?? ''}',
    accountLevel: '${json['account_level'] ?? ''}',
    accessToken: json['access_token'] as String?,
    refreshToken: json['refresh_token'] as String?,
    trustDevice: json['trust_device'] == true,
    mfaVerified: json['mfa_verified'] as bool?,
  );
}

/// One registered passkey (`GET /auth/passkey/credentials`).
class LkmPasskeyCredential {
  const LkmPasskeyCredential({
    required this.id,
    required this.credentialId,
    required this.deviceName,
    this.createdAt,
  });

  final String id;
  final String credentialId;
  final String deviceName;
  final DateTime? createdAt;

  factory LkmPasskeyCredential.fromJson(Map<String, dynamic> json) =>
      LkmPasskeyCredential(
        id: '${json['id'] ?? ''}',
        credentialId: '${json['credential_id'] ?? ''}',
        deviceName: '${json['device_name'] ?? ''}',
        createdAt: DateTime.tryParse('${json['created_at'] ?? ''}')?.toLocal(),
      );
}

/// `PUT /auth/{id}/profile` — the public profile subset.
class LkmProfile {
  const LkmProfile({
    this.userId,
    this.nickname,
    this.avatar,
    this.role = 'member',
    this.contactLinks = const [],
  });

  final String? userId;
  final String? nickname;
  final String? avatar;
  final String role;
  final List<Map<String, dynamic>> contactLinks;

  factory LkmProfile.fromJson(Map<String, dynamic> json) {
    final links = json['contact_links'];
    return LkmProfile(
      userId: json['user_id'] as String?,
      nickname: json['nickname'] as String?,
      avatar: json['avatar'] as String?,
      role: '${json['role'] ?? 'member'}',
      contactLinks: links is List
          ? links
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList(growable: false)
          : const [],
    );
  }
}

/// `GET /auth/settings` — which contacts are bound, and whether 2FA is on.
class LkmAccountSettings {
  const LkmAccountSettings({
    this.email,
    this.phone,
    this.github,
    this.has2fa = false,
  });

  final String? email;
  final String? phone;
  final String? github;
  final bool has2fa;

  factory LkmAccountSettings.fromJson(Map<String, dynamic> json) =>
      LkmAccountSettings(
        email: json['email'] as String?,
        phone: json['phone'] as String?,
        github: json['github'] as String?,
        has2fa: json['has_2fa'] == true,
      );
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
  Future<void> requestFactorCode(String id, String deviceId) =>
      _client.post('/auth/challenge/$id/request', headers: _device(deviceId));

  /// `POST /auth/challenge/{id}/cancel?device_id=…`
  Future<void> cancelChallenge(String id, String deviceId) =>
      _client.post('/auth/challenge/$id/cancel', headers: _device(deviceId));

  /// `POST /auth/reg/email` — body `{email}`; not part of the challenge flow.
  Future<void> requestRegisterCode(String email) =>
      _client.post('/auth/reg/email', body: {'email': email});

  /// `POST /auth/reg/email/verify?email=…&code=…` — completes email-only
  /// registration. Apply-mode deployments answer with an admission envelope
  /// instead of tokens, hence [LkmAuthResult].
  Future<LkmAuthResult> registerWithEmail({
    required String email,
    required String code,
  }) async {
    final data = await _client.post(
      '/auth/reg/email/verify',
      query: {'email': email, 'code': code},
    );
    return LkmAuthResult.fromJson(_asMap(data));
  }

  /// `POST /auth/reg/normal` — username/password plus at least one contact;
  /// the server stores the pending account and sends the code(s).
  Future<LkmRegistrationPending> requestRegisterNormal({
    required String username,
    required String password,
    String? email,
    String? phone,
    String? applyReason,
  }) async {
    final data = await _client.post(
      '/auth/reg/normal',
      body: {
        'username': username.trim(),
        'password': password,
        'email': ?_nullIfEmpty(email),
        'phone': ?_nullIfEmpty(phone),
        'apply_reason': ?_nullIfEmpty(applyReason),
      },
    );
    return LkmRegistrationPending.fromJson(_asMap(data));
  }

  /// `POST /auth/reg/normal/verify?txn_id=&email_code=&phone_code=` — finishes
  /// normal registration.
  Future<LkmAuthResult> verifyRegisterNormal({
    required String txnId,
    String? emailCode,
    String? phoneCode,
  }) async {
    final data = await _client.post(
      '/auth/reg/normal/verify',
      query: {
        'txn_id': txnId,
        'email_code': ?_nullIfEmpty(emailCode),
        'phone_code': ?_nullIfEmpty(phoneCode),
      },
    );
    return LkmAuthResult.fromJson(_asMap(data));
  }

  /// `POST /auth/reg/local` — username/password only; apply-mode deployments
  /// may answer pending.
  Future<LkmAuthResult> registerLocal({
    required String username,
    required String password,
    String? applyReason,
  }) async {
    final data = await _client.post(
      '/auth/reg/local',
      body: {
        'username': username.trim(),
        'password': password,
        'apply_reason': ?_nullIfEmpty(applyReason),
      },
    );
    return LkmAuthResult.fromJson(_asMap(data));
  }

  /// `POST /auth/reg/phone` + `/reg/phone/verify` — phone-only registration.
  Future<void> requestRegisterPhone(String phone) =>
      _client.post('/auth/reg/phone', body: {'phone': phone.trim()});

  Future<LkmAuthResult> verifyRegisterPhone({
    required String phone,
    required String code,
    String? applyReason,
  }) async {
    final data = await _client.post(
      '/auth/reg/phone/verify',
      query: {
        'phone': phone.trim(),
        'code': code.trim(),
        'apply_reason': ?_nullIfEmpty(applyReason),
      },
    );
    return LkmAuthResult.fromJson(_asMap(data));
  }

  /// `GET /auth/onboarding` — current wizard progress.
  Future<LkmOnboardingState> onboarding() async {
    final data = await _client.getObject('/auth/onboarding');
    return LkmOnboardingState.fromJson(data);
  }

  /// `PUT /auth/onboarding/steps/{step}` — merge one step's answers.
  Future<LkmOnboardingState> setOnboardingStep(
    int step,
    Map<String, dynamic> data,
  ) async {
    final body = await _client.put(
      '/auth/onboarding/steps/$step',
      body: {'data': data},
    );
    return LkmOnboardingState.fromJson(_asMap(body));
  }

  /// `POST /auth/onboarding/skip` — mark the wizard finished.
  Future<LkmOnboardingState> skipOnboarding() async {
    final data = await _client.post('/auth/onboarding/skip');
    return LkmOnboardingState.fromJson(_asMap(data));
  }

  /// Desktop login start: the service 302s to GitHub and, after the callback,
  /// back to the loopback `redirectUri` with a one-time code.
  String githubLoginUrl({
    required String redirectUri,
    required String challenge,
  }) {
    return Uri.parse('${_client.baseUrl}/auth/oauth/github/login')
        .replace(
          queryParameters: {
            'redirect_uri': redirectUri,
            'challenge': challenge,
          },
        )
        .toString();
  }

  /// Desktop bind start; same loopback shape as [githubLoginUrl].
  Future<String> githubBindUrl({
    required String redirectUri,
    required String challenge,
  }) async {
    final data = await _client.post(
      '/auth/oauth/github/login/redirect',
      query: {'redirect_uri': redirectUri, 'challenge': challenge},
    );
    return '${_asMap(data)['url'] ?? ''}';
  }

  /// `POST /auth/oauth/desktop/exchange` — redeem the loopback code with the
  /// PKCE verifier.
  Future<LkmAuthResult> exchangeDesktopCode({
    required String code,
    required String verifier,
  }) async {
    final data = await _client.post(
      '/auth/oauth/desktop/exchange',
      body: {'code': code, 'verifier': verifier},
    );
    return LkmAuthResult.fromJson(_asMap(data));
  }

  /// `POST /auth/recover/email|phone` — send the reset code.
  Future<void> requestRecovery({
    required String contact,
    required bool byEmail,
  }) => _client.post(
    byEmail ? '/auth/recover/email' : '/auth/recover/phone',
    body: {byEmail ? 'email' : 'phone': contact.trim()},
  );

  /// `POST /auth/recover/email|phone/verify` — verify the code. Without MFA
  /// [newPassword] resets immediately; with MFA the outcome names the
  /// transaction to finish after 2FA.
  Future<LkmRecoveryOutcome> verifyRecovery({
    required String contact,
    required bool byEmail,
    required String code,
    String? newPassword,
  }) async {
    final data = await _client.post(
      byEmail ? '/auth/recover/email/verify' : '/auth/recover/phone/verify',
      body: {
        byEmail ? 'email' : 'phone': contact.trim(),
        'code': code.trim(),
        'new_password': ?newPassword,
      },
    );
    return LkmRecoveryOutcome.fromJson(_asMap(data));
  }

  /// `POST /auth/recover/magic-link` — mail a reset link.
  Future<void> requestRecoveryMagicLink(String email) =>
      _client.post('/auth/recover/magic-link', body: {'email': email.trim()});

  /// `POST /auth/recover/magic-link/verify` — consume the link token.
  Future<LkmRecoveryOutcome> verifyRecoveryMagicLink({
    required String token,
    String? newPassword,
  }) async {
    final data = await _client.post(
      '/auth/recover/magic-link/verify',
      body: {'token': token, 'new_password': ?newPassword},
    );
    return LkmRecoveryOutcome.fromJson(_asMap(data));
  }

  /// `POST /auth/recover/verify-totp` — confirm the second factor inside a
  /// recovery transaction.
  Future<void> verifyRecoveryTotp({
    required String txnId,
    required String tempToken,
  }) => _client.post(
    '/auth/recover/verify-totp',
    body: {'txn_id': txnId, 'temp_token': tempToken},
  );

  /// `POST /auth/recover/complete` — set the new password after 2FA.
  Future<void> completeRecovery({
    required String txnId,
    required String newPassword,
  }) => _client.post(
    '/auth/recover/complete',
    body: {'txn_id': txnId, 'new_password': newPassword},
  );

  /// `POST /auth/2fa/setup/begin` — secret and otpauth URI.
  Future<LkmTotpSetup> beginTotpSetup() async {
    final data = await _client.post('/auth/2fa/setup/begin');
    return LkmTotpSetup.fromJson(_asMap(data));
  }

  /// `POST /auth/2fa/setup/complete` — verify the first code; returns recovery
  /// codes exactly once.
  Future<LkmTotpSetupComplete> completeTotpSetup(String code) async {
    final data = await _client.post(
      '/auth/2fa/setup/complete',
      body: {'code': code.trim()},
    );
    return LkmTotpSetupComplete.fromJson(_asMap(data));
  }

  /// Admin-forced setup path: `POST /auth/2fa/setup/temp?temp_token=`.
  Future<LkmTotpSetup> beginTotpSetupWithTemp(String tempToken) async {
    final data = await _client.post(
      '/auth/2fa/setup/temp',
      query: {'temp_token': tempToken},
    );
    return LkmTotpSetup.fromJson(_asMap(data));
  }

  /// `POST /auth/2fa/setup/complete/temp?temp_token=&code=` — forced setup
  /// finishes signed in.
  Future<LkmTotpSetupComplete> completeTotpSetupWithTemp({
    required String tempToken,
    required String code,
  }) async {
    final data = await _client.post(
      '/auth/2fa/setup/complete/temp',
      query: {'temp_token': tempToken, 'code': code.trim()},
    );
    return LkmTotpSetupComplete.fromJson(_asMap(data));
  }

  /// `POST /auth/2fa/setup/confirm` — the user saved the recovery codes.
  Future<void> confirmTotpRecoveryCodes() =>
      _client.post('/auth/2fa/setup/confirm');

  /// `GET /auth/2fa/status`.
  Future<bool> totpEnabled() async {
    final data = await _client.getObject('/auth/2fa/status');
    return data['enabled'] == true;
  }

  /// `DELETE /auth/2fa` — needs a TOTP code or a recovery code.
  Future<void> disableTotp({String? code, String? recoveryCode}) =>
      _client.delete(
        '/auth/2fa',
        body: {'code': ?code, 'recovery_code': ?recoveryCode},
      );

  /// `POST /auth/2fa/verify` — public step that exchanges a login temp token
  /// for a session after the second factor.
  Future<LkmTotpVerify> verifyTotp({
    required String tempToken,
    String? code,
    String? recoveryCode,
    bool trustDevice = false,
  }) async {
    final data = await _client.post(
      '/auth/2fa/verify',
      body: {
        'temp_token': tempToken,
        'code': ?code,
        'recovery_code': ?recoveryCode,
        'trust_device': trustDevice,
      },
    );
    return LkmTotpVerify.fromJson(_asMap(data));
  }

  /// `POST /auth/2fa/step-up` — signed-in dangerous write; returns a pair with
  /// the 2FA trust window baked in.
  Future<LkmTotpVerify> stepUpTotp({String? code, String? recoveryCode}) async {
    final data = await _client.post(
      '/auth/2fa/step-up',
      body: {'code': ?code, 'recovery_code': ?recoveryCode},
    );
    return LkmTotpVerify.fromJson(_asMap(data));
  }

  /// `POST /auth/passkey/register/begin` — creation options.
  Future<LkmPasskeyOptions> beginPasskeyRegistration() async {
    final data = await _client.post('/auth/passkey/register/begin');
    final map = _asMap(data);
    final publicKey = map['public_key'];
    if (publicKey is! Map) {
      throw ApiException(code: ApiCode.internalError, message: '通行密钥注册选项格式异常');
    }
    return LkmPasskeyOptions(
      challengeId: '${map['challenge_id'] ?? ''}',
      publicKey: Map<String, dynamic>.from(publicKey),
    );
  }

  /// `POST /auth/passkey/register/complete` — a ceremony already produced a
  /// WebAuthn credential; this just records it.
  Future<void> completePasskeyRegistration({
    required String challengeId,
    required String rawId,
    required Map<String, dynamic> response,
    String? deviceName,
  }) => _client.post(
    '/auth/passkey/register/complete',
    body: {
      'challenge_id': challengeId,
      'rawId': rawId,
      'response': response,
      'device_name': ?_nullIfEmpty(deviceName),
    },
  );

  /// `GET /auth/passkey/credentials`.
  Future<List<LkmPasskeyCredential>> passkeyCredentials() async {
    final data = await _client.get('/auth/passkey/credentials');
    if (data is! List) return const [];
    return data
        .whereType<Map>()
        .map((e) => LkmPasskeyCredential.fromJson(Map<String, dynamic>.from(e)))
        .toList(growable: false);
  }

  /// `DELETE /auth/passkey/{id}` — requires 2FA on the service side.
  Future<void> deletePasskey(String id) => _client.delete('/auth/passkey/$id');

  /// `PUT /auth/{id}/profile` — nickname, avatar key and contact links.
  Future<LkmProfile> updateProfile({
    required String userId,
    String? nickname,
    String? avatar,
    List<Map<String, dynamic>>? contactLinks,
  }) async {
    final data = await _client.put(
      '/auth/$userId/profile',
      body: {
        'nickname': ?nickname,
        'avatar': ?avatar,
        'contact_links': ?contactLinks,
      },
    );
    return LkmProfile.fromJson(_asMap(data));
  }

  /// `POST /auth/avatar` — multipart `file`, <=2MB; returns the storage key.
  Future<String> uploadAvatar({
    required List<int> bytes,
    required String filename,
  }) async {
    final data = await _client.postForm(
      '/auth/avatar',
      form: FormData.fromMap({
        'file': MultipartFile.fromBytes(bytes, filename: filename),
      }),
    );
    final map = _asMap(data);
    return '${map['avatar'] ?? ''}';
  }

  /// `GET /auth/settings` — bound contacts and 2FA state.
  Future<LkmAccountSettings> accountSettings() async {
    final data = await _client.getObject('/auth/settings');
    return LkmAccountSettings.fromJson(data);
  }

  /// `POST /auth/settings/bind-email/request`.
  Future<void> requestBindEmail(String email) => _client.post(
    '/auth/settings/bind-email/request',
    body: {'email': email.trim()},
  );

  /// `POST /auth/settings/bind-email/verify`.
  Future<void> verifyBindEmail({required String email, required String code}) =>
      _client.post(
        '/auth/settings/bind-email/verify',
        body: {'email': email.trim(), 'code': code.trim()},
      );

  /// `POST /auth/settings/bind-phone/request`.
  Future<void> requestBindPhone(String phone) => _client.post(
    '/auth/settings/bind-phone/request',
    body: {'phone': phone.trim()},
  );

  /// `POST /auth/settings/bind-phone/verify`.
  Future<void> verifyBindPhone({required String phone, required String code}) =>
      _client.post(
        '/auth/settings/bind-phone/verify',
        body: {'phone': phone.trim(), 'code': code.trim()},
      );

  /// `DELETE /auth/settings/{type}` — `email` / `phone` / `github`; 2FA-enabled
  /// accounts must pass a TOTP or recovery code.
  Future<void> unbind(String type, {String? code, String? recoveryCode}) =>
      _client.delete(
        '/auth/settings/$type',
        body: {'code': ?code, 'recovery_code': ?recoveryCode},
      );

  /// `GET /auth/me`
  Future<LkmAccount> me() async {
    final data = await _client.getObject('/auth/me');
    return LkmAccount.fromJson(data);
  }

  static String? _nullIfEmpty(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
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
      throw ApiException(code: ApiCode.internalError, message: '通行密钥选项格式异常');
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
    throw ApiException(code: ApiCode.internalError, message: '认证响应格式异常');
  }
}
