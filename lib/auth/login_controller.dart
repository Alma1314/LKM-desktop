import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:island/core/api/api_client.dart';
import 'package:island/core/api/api_providers.dart';
import 'package:island/core/api/api_session.dart';
import 'package:island/auth/oauth_desktop.dart';
import 'package:island/auth/passkey.dart';
import 'package:island/community/user_pod.dart';
import 'package:island/core/api/auth_api.dart';

/// Resolves an i18n key for the controller.
///
/// The controller runs outside the widget tree, so it cannot call `.tr()`
/// directly; tests override this with an identity function instead of booting
/// EasyLocalization.
typedef AuthTranslator = String Function(String key, List<String>? args);

final authTranslatorProvider = Provider<AuthTranslator>((ref) {
  return (key, args) => args == null ? key.tr() : key.tr(args: args);
});

/// How the user chose to prove identity for the first factor.
enum LoginMethod { password, code, passkey }

/// Snapshot of the login screen.
///
/// [challenge] is the server's state: whatever is in `factors` is what the UI
/// renders next. The client never decides on its own which factor comes after
/// which — that is the whole point of rotating factors server-side.
class LoginState {
  const LoginState({
    this.account,
    this.challenge,
    this.busy = false,
    this.error,
    this.info,
    this.codeSent = false,
    this.method = LoginMethod.password,
    this.recoveryMode = false,
    this.oauthTempToken,
    this.setup,
  });

  /// The signed-in account, or null when nobody is signed in.
  final LkmAccount? account;

  /// In-flight challenge, or null before the first call / after completion.
  final LkmChallenge? challenge;

  final bool busy;
  final String? error;
  final String? info;

  /// Whether the current code factor has already been requested.
  final bool codeSent;

  /// Which primary factor the *next* "continue" should create a challenge with.
  final LoginMethod method;

  /// Whether the TOTP step is being answered with a recovery code instead.
  final bool recoveryMode;

  /// GitHub OAuth answered `requires_2fa`: the temp token to pass to
  /// `/auth/2fa/verify` once the user enters a code.
  final String? oauthTempToken;
  final LkmAuthResult? setup;

  bool get signedIn => account != null;
  bool get hasChallenge => challenge != null;
  LkmChallengeFactor? get currentFactor => challenge?.current;

  LoginState copyWith({
    LkmAccount? account,
    LkmChallenge? challenge,
    bool? busy,
    String? error,
    String? info,
    bool? codeSent,
    LoginMethod? method,
    bool? recoveryMode,
    String? oauthTempToken,
    bool clearOauthTempToken = false,
    bool clearAccount = false,
    bool clearChallenge = false,
    bool clearMessages = false,
    LkmAuthResult? setup,
  }) => LoginState(
    account: clearAccount ? null : (account ?? this.account),
    challenge: clearChallenge ? null : (challenge ?? this.challenge),
    busy: busy ?? this.busy,
    error: clearMessages ? null : error,
    info: clearMessages ? null : (info ?? this.info),
    codeSent: codeSent ?? this.codeSent,
    method: method ?? this.method,
    recoveryMode: recoveryMode ?? this.recoveryMode,
    oauthTempToken: clearOauthTempToken
        ? null
        : (oauthTempToken ?? this.oauthTempToken),
    setup: setup ?? this.setup,
  );
}

/// Drives the challenge-factor login: create a challenge, render its factors,
/// submit them one by one, land the tokens.
///
/// The token pair is adopted in exactly one place ([_finish]), and only for a
/// step the server marked complete — so a half-finished challenge can never
/// leave a partial session behind.
class LoginController extends Notifier<LoginState> {
  @override
  LoginState build() {
    // Identity mutations notify data providers; this controller owns those
    // transitions itself and only restores when the deployment changes.
    ref.watch(lkmApiSessionProvider.select((session) => session.serverUrl));
    final session = ref.read(lkmApiSessionProvider);
    if (session.isSignedIn) {
      Future.microtask(_restore);
    }
    return const LoginState();
  }

  AuthApi get _api => AuthApi(ref.read(lkmApiSessionProvider).client);

  String _t(String key, [List<String>? args]) =>
      ref.read(authTranslatorProvider)(key, args);

  Future<String> _deviceId() => ref.read(lkmDeviceIdProvider.future);

  Future<void> _restore() async {
    final session = ref.read(lkmApiSessionProvider);
    final revision = session.identityRevision;
    if (!session.isSignedIn) return;
    state = state.copyWith(busy: true, clearMessages: true);
    try {
      final account = await session.run(() => AuthApi(session.client).me());
      if (!ref.mounted ||
          !identical(ref.read(lkmApiSessionProvider), session) ||
          session.identityRevision != revision)
        return;
      state = state.copyWith(account: account, busy: false);
    } catch (error) {
      if (!ref.mounted ||
          !identical(ref.read(lkmApiSessionProvider), session) ||
          session.identityRevision != revision)
        return;
      if (error is SessionExpiredException ||
          (error is ApiException && error.isUnauthenticated)) {
        await session.signOut(revoke: false);
      }
      state = state.copyWith(
        busy: false,
        clearAccount: true,
        error: _describe(error),
      );
    }
  }

  void selectMethod(LoginMethod method) {
    if (state.hasChallenge || state.busy) return;
    state = state.copyWith(method: method, clearMessages: true);
  }

  /// Step 1 of the password path: open a challenge whose first factor is the
  /// password. No credential is sent yet, so nothing leaks about the account.
  Future<void> beginPassword(String account) async {
    if (account.trim().isEmpty) {
      state = state.copyWith(error: _t('lkmErrEmptyAccount'));
      return;
    }
    await _createChallenge(
      account: account.trim(),
      primaryFactor: 'password',
      method: LoginMethod.password,
    );
  }

  /// Step 1 of the code path: open a challenge whose first factor is a code and
  /// immediately ask the server to send it.
  Future<void> beginCode(String contact) async {
    if (contact.trim().isEmpty) {
      state = state.copyWith(error: _t('lkmErrEmptyAccount'));
      return;
    }
    final created = await _createChallenge(
      account: contact.trim(),
      primaryFactor: 'code',
      method: LoginMethod.code,
    );
    if (!created) return;
    await resendCode();
  }

  /// Step 1 of the passkey path: open a challenge whose first factor is a
  /// passkey. The account is only used to scope `allowCredentials`.
  Future<void> beginPasskey(String account) async {
    if (account.trim().isEmpty) {
      state = state.copyWith(error: _t('lkmErrEmptyAccount'));
      return;
    }
    await _createChallenge(
      account: account.trim(),
      primaryFactor: 'passkey',
      method: LoginMethod.passkey,
    );
  }

  /// Runs the platform ceremony for the current passkey factor and submits the
  /// assertion.
  Future<void> authenticateWithPasskey() async {
    final session = ref.read(lkmApiSessionProvider);
    final api = AuthApi(session.client);
    final challenge = state.challenge;
    if (challenge == null) return;
    state = state.copyWith(busy: true, clearMessages: true);
    try {
      final deviceId = await _deviceId();
      final options = await api.startPasskeyFactor(challenge.id, deviceId);
      final assertion = await ref.read(passkeyCeremonyProvider)(options);
      final step = await api.completePasskeyFactor(
        challenge.id,
        deviceId: deviceId,
        webauthnChallengeId: options.challengeId,
        assertion: assertion,
      );
      _checkSession(session);
      if (step.isComplete) {
        await _finish(step.tokens!, session);
        return;
      }
      if (step.setup != null) {
        await _applyOauthResult(step.setup!, session);
        return;
      }
      state = state.copyWith(
        challenge: step.challenge,
        busy: false,
        codeSent: false,
        recoveryMode: false,
      );
    } on ApiException catch (error) {
      final dead =
          error.code == ApiCode.authChallengeExpired ||
          error.code == ApiCode.authChallengeConsumed ||
          error.code == ApiCode.authChallengeNotFound;
      state = state.copyWith(
        busy: false,
        clearChallenge: dead,
        error: dead ? _t('lkmErrChallengeExpired') : _describe(error),
      );
    } catch (error) {
      // 用户取消系统弹窗、设备不支持、凭据不匹配都落到这里：不该清挑战，
      // 让他还能改用密码登录。
      state = state.copyWith(busy: false, error: _t('lkmPasskeyFailed'));
    }
  }

  Future<void> submitPassword(String password) async {
    if (password.isEmpty) {
      state = state.copyWith(error: _t('lkmErrEmptyCredentials'));
      return;
    }
    await _submit('password', password: password);
  }

  Future<void> submitCode(String code) async {
    if (code.trim().isEmpty) {
      state = state.copyWith(error: _t('lkmErrEmptyCode'));
      return;
    }
    await _submit('code', code: code.trim());
  }

  Future<void> submitTotp(String code) async {
    if (code.trim().isEmpty) {
      state = state.copyWith(error: _t('lkmErrEmptyCode'));
      return;
    }
    if (state.recoveryMode) {
      await _submit('totp', recoveryCode: code.trim());
      return;
    }
    await _submit('totp', code: code.trim());
  }

  void toggleRecoveryMode() {
    state = state.copyWith(
      recoveryMode: !state.recoveryMode,
      clearMessages: true,
    );
  }

  /// Re-sends the code for the current code factor.
  Future<void> resendCode() async {
    final challenge = state.challenge;
    if (challenge == null) return;
    state = state.copyWith(busy: true, clearMessages: true);
    try {
      final deviceId = await _deviceId();
      await _api.requestFactorCode(challenge.id, deviceId);
      final hint = challenge.current?.hint;
      state = state.copyWith(
        busy: false,
        codeSent: true,
        info: hint == null ? _t('lkmSendCode') : _t('lkmCodeSentTo', [hint]),
      );
    } catch (error) {
      state = state.copyWith(busy: false, error: _describe(error));
    }
  }

  /// Abandons the current challenge (server-side too) and returns to the form.
  Future<void> cancel() async {
    final challenge = state.challenge;
    state = state.copyWith(busy: true, clearMessages: true);
    try {
      if (challenge != null) {
        await _api.cancelChallenge(challenge.id, await _deviceId());
      }
    } catch (_) {
      // Local reset must not depend on the server being reachable.
    }
    state = LoginState(method: state.method);
  }

  Future<void> requestRegisterCode(String email) async {
    if (email.trim().isEmpty) {
      state = state.copyWith(error: _t('lkmErrEmptyEmail'));
      return;
    }
    state = state.copyWith(busy: true, clearMessages: true);
    try {
      await _api.requestRegisterCode(email.trim());
      state = state.copyWith(
        busy: false,
        codeSent: true,
        info: _t('lkmCodeSentTo', [email.trim()]),
      );
    } catch (error) {
      state = state.copyWith(busy: false, error: _describe(error));
    }
  }

  Future<void> verifyRegistration({
    required String email,
    required String code,
  }) async {
    final session = ref.read(lkmApiSessionProvider);
    final api = AuthApi(session.client);
    if (email.trim().isEmpty || code.trim().isEmpty) {
      state = state.copyWith(error: _t('lkmErrEmptyCode'));
      return;
    }
    state = state.copyWith(busy: true, clearMessages: true);
    try {
      final result = await api.registerWithEmail(
        email: email.trim(),
        code: code.trim(),
      );
      if (result.tokens != null) {
        await _finish(result.tokens!, session);
      } else if (result.isPendingAdmission) {
        state = state.copyWith(busy: false, info: _t('lkmAdmissionPending'));
      } else {
        state = state.copyWith(
          busy: false,
          info: _t('lkmRegistrationComplete'),
        );
      }
    } catch (error) {
      state = state.copyWith(busy: false, error: _describe(error));
    }
  }

  /// Browser-based GitHub login: opens the system browser, waits on the
  /// loopback callback, then exchanges the one-time code.
  Future<void> signInWithGithub() async {
    final session = ref.read(lkmApiSessionProvider);
    final api = AuthApi(session.client);
    state = state.copyWith(busy: true, clearMessages: true);
    try {
      final result = await runGithubLogin(api);
      await _applyOauthResult(result, session);
    } catch (error) {
      state = state.copyWith(busy: false, error: _describe(error));
    }
  }

  Future<void> requestMagicLink(String email) async {
    if (state.busy) return;
    if (email.trim().isEmpty) {
      state = state.copyWith(error: _t('lkmErrEmptyEmail'));
      return;
    }
    state = state.copyWith(busy: true, clearMessages: true);
    try {
      await _api.requestMagicLink(email);
      state = state.copyWith(
        busy: false,
        info: _t('lkmCodeSentTo', [email.trim()]),
      );
    } catch (error) {
      state = state.copyWith(busy: false, error: _describe(error));
    }
  }

  Future<void> verifyMagicLink(String link) async {
    final session = ref.read(lkmApiSessionProvider);
    final api = AuthApi(session.client);
    if (state.busy) return;
    final raw = link.trim();
    if (raw.isEmpty) {
      state = state.copyWith(error: _t('lkmErrEmptyCode'));
      return;
    }
    state = state.copyWith(busy: true, clearMessages: true);
    try {
      final uri = Uri.tryParse(raw);
      final token = uri?.queryParameters['token'] ?? raw;
      await _applyOauthResult(await api.verifyMagicLink(token), session);
    } catch (error) {
      state = state.copyWith(busy: false, error: _describe(error));
    }
  }

  Future<void> _applyOauthResult(
    LkmAuthResult result,
    ApiSession session,
  ) async {
    _checkSession(session);
    if (result.setupRequired && result.tempToken != null) {
      state = LoginState(setup: result);
      return;
    }
    if (result.tokens != null) {
      await _finish(result.tokens!, session);
      return;
    }
    if (result.requires2fa && result.tempToken != null) {
      state = state.copyWith(
        busy: false,
        oauthTempToken: result.tempToken,
        info: _t('lkmTotpLabel'),
      );
      return;
    }
    state = state.copyWith(
      busy: false,
      info: result.isPendingAdmission
          ? _t('lkmAdmissionPending')
          : _t('lkmRegistrationComplete'),
      clearOauthTempToken: true,
    );
  }

  /// Second factor for the OAuth path (the challenge flow does not apply).
  Future<void> submitOauthTotp(String code) async {
    final session = ref.read(lkmApiSessionProvider);
    final api = AuthApi(session.client);
    final temp = state.oauthTempToken;
    if (temp == null) return;
    if (code.trim().isEmpty) {
      state = state.copyWith(error: _t('lkmErrEmptyCode'));
      return;
    }
    state = state.copyWith(busy: true, clearMessages: true);
    try {
      final verified = await api.verifyTotp(
        tempToken: temp,
        code: state.recoveryMode ? null : code.trim(),
        recoveryCode: state.recoveryMode ? code.trim() : null,
        trustDevice: true,
      );
      if (!verified.hasTokens) {
        state = state.copyWith(
          busy: false,
          error: _t('lkmErrGeneric', ['2FA']),
        );
        return;
      }
      await _finish(
        LkmAuthToken(
          userId: verified.userId,
          accountLevel: verified.accountLevel,
          accessToken: verified.accessToken!,
          refreshToken: verified.refreshToken ?? '',
        ),
        session,
      );
    } catch (error) {
      state = state.copyWith(busy: false, error: _describe(error));
    }
  }

  Future<void> signOut() async {
    state = state.copyWith(busy: true, clearMessages: true);
    await ref.read(lkmApiSessionProvider).signOut();
    ref.invalidate(lkmMeProvider);
    state = const LoginState();
  }

  /// Adopts a pair minted outside the challenge flow (registration, passkey
  /// management), through the same single adoption path as login.
  Future<LkmAccount?> adoptTokens(
    LkmAuthToken token, {
    ApiSession? session,
  }) async {
    await _finish(token, session ?? ref.read(lkmApiSessionProvider));
    return state.account;
  }

  Future<bool> _createChallenge({
    required String account,
    required String primaryFactor,
    required LoginMethod method,
  }) async {
    final session = ref.read(lkmApiSessionProvider);
    final api = AuthApi(session.client);
    state = state.copyWith(busy: true, clearMessages: true, method: method);
    try {
      final challenge = await api.createChallenge(
        account: account,
        deviceId: await _deviceId(),
        primaryFactor: primaryFactor,
      );
      _checkSession(session);
      state = state.copyWith(
        challenge: challenge,
        busy: false,
        codeSent: false,
      );
      return true;
    } catch (error) {
      state = state.copyWith(busy: false, error: _describe(error));
      return false;
    }
  }

  Future<void> _submit(
    String kind, {
    String? password,
    String? code,
    String? recoveryCode,
  }) async {
    final session = ref.read(lkmApiSessionProvider);
    final api = AuthApi(session.client);
    final challenge = state.challenge;
    if (challenge == null) return;
    state = state.copyWith(busy: true, clearMessages: true);
    try {
      final step = await api.submitFactor(
        challenge.id,
        deviceId: await _deviceId(),
        kind: kind,
        password: password,
        code: code,
        recoveryCode: recoveryCode,
      );
      _checkSession(session);
      if (step.setup != null) {
        await _applyOauthResult(step.setup!, session);
        return;
      }
      if (step.isComplete) {
        await _finish(step.tokens!, session);
        return;
      }
      final next = step.challenge!;
      state = state.copyWith(
        challenge: next,
        busy: false,
        codeSent: false,
        recoveryMode: false,
      );
      // A code factor can appear after the first step too; fetch its code so
      // the user is not left staring at an empty input.
      if (next.current?.kind == 'code') {
        await resendCode();
      }
    } on ApiException catch (error) {
      // A dead challenge (expired, consumed, unknown id) can never be resumed;
      // send the user back to the form instead of letting them retry into 404s.
      final dead =
          error.code == ApiCode.authChallengeExpired ||
          error.code == ApiCode.authChallengeConsumed ||
          error.code == ApiCode.authChallengeNotFound;
      state = state.copyWith(
        busy: false,
        clearChallenge: dead,
        error: dead ? _t('lkmErrChallengeExpired') : _describe(error),
      );
    } catch (error) {
      state = state.copyWith(busy: false, error: _describe(error));
    }
  }

  void _checkSession(ApiSession session) {
    if (!ref.mounted || !identical(ref.read(lkmApiSessionProvider), session)) {
      throw const SessionExpiredException();
    }
  }

  Future<void> _finish(LkmAuthToken token, ApiSession session) async {
    _checkSession(session);
    await session.adopt(
      LkmTokenPair(
        accessToken: token.accessToken,
        refreshToken: token.refreshToken,
        accessExpiresAt: decodeJwtExpiry(token.accessToken),
        refreshExpiresAt: decodeJwtExpiry(token.refreshToken),
      ),
    );
    _checkSession(session);
    final revision = session.identityRevision;
    final account = await AuthApi(session.client).me();
    _checkSession(session);
    if (session.identityRevision != revision)
      throw const SessionExpiredException();
    ref.invalidate(lkmMeProvider);
    state = LoginState(account: account);
  }

  String _describe(Object error) {
    if (error is ApiException) {
      if (error.code == ApiCode.authChallengeExpired ||
          error.code == ApiCode.authChallengeConsumed) {
        return _t('lkmErrChallengeExpired');
      }
      return error.message;
    }
    if (error is ApiTransportException) return error.message;
    if (error is SessionExpiredException) return error.message;
    return _t('lkmErrGeneric', [error.toString()]);
  }
}

final loginControllerProvider = NotifierProvider<LoginController, LoginState>(
  LoginController.new,
);

/// Shared [AuthApi] for flows outside the login controller (registration,
/// recovery, account settings).
final authApiProvider = Provider<AuthApi>((ref) {
  return AuthApi(ref.watch(lkmApiSessionProvider).client);
});
