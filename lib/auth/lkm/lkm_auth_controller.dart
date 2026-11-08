import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:island/core/api/api_client.dart';
import 'package:island/core/api/api_providers.dart';
import 'package:island/core/api/api_session.dart';
import 'package:island/core/api/auth_api.dart';

/// Resolves an i18n key for the controller.
///
/// The controller runs outside the widget tree, so it cannot call `.tr()`
/// directly; tests override this with an identity function instead of booting
/// EasyLocalization.
typedef LkmTranslator = String Function(String key, List<String>? args);

final lkmTranslatorProvider = Provider<LkmTranslator>((ref) {
  return (key, args) => args == null ? key.tr() : key.tr(args: args);
});

/// How the user chose to prove identity for the first factor.
enum LkmAuthMethod { password, code }

/// Snapshot of the login screen.
///
/// [challenge] is the server's state: whatever is in `factors` is what the UI
/// renders next. The client never decides on its own which factor comes after
/// which — that is the whole point of rotating factors server-side.
class LkmAuthState {
  const LkmAuthState({
    this.account,
    this.challenge,
    this.busy = false,
    this.error,
    this.info,
    this.codeSent = false,
    this.method = LkmAuthMethod.password,
    this.recoveryMode = false,
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
  final LkmAuthMethod method;

  /// Whether the TOTP step is being answered with a recovery code instead.
  final bool recoveryMode;

  bool get signedIn => account != null;
  bool get hasChallenge => challenge != null;
  LkmChallengeFactor? get currentFactor => challenge?.current;

  LkmAuthState copyWith({
    LkmAccount? account,
    LkmChallenge? challenge,
    bool? busy,
    String? error,
    String? info,
    bool? codeSent,
    LkmAuthMethod? method,
    bool? recoveryMode,
    bool clearAccount = false,
    bool clearChallenge = false,
    bool clearMessages = false,
  }) => LkmAuthState(
    account: clearAccount ? null : (account ?? this.account),
    challenge: clearChallenge ? null : (challenge ?? this.challenge),
    busy: busy ?? this.busy,
    error: clearMessages ? null : error,
    info: clearMessages ? null : (info ?? this.info),
    codeSent: codeSent ?? this.codeSent,
    method: method ?? this.method,
    recoveryMode: recoveryMode ?? this.recoveryMode,
  );
}

/// Drives the challenge-factor login: create a challenge, render its factors,
/// submit them one by one, land the tokens.
///
/// The token pair is adopted in exactly one place ([_finish]), and only for a
/// step the server marked complete — so a half-finished challenge can never
/// leave a partial session behind.
class LkmAuthController extends Notifier<LkmAuthState> {
  @override
  LkmAuthState build() {
    final session = ref.watch(lkmApiSessionProvider);
    if (session.isSignedIn) {
      Future.microtask(_restore);
    }
    return const LkmAuthState();
  }

  AuthApi get _api => AuthApi(ref.read(lkmApiSessionProvider).client);

  String _t(String key, [List<String>? args]) =>
      ref.read(lkmTranslatorProvider)(key, args);

  Future<String> _deviceId() => ref.read(lkmDeviceIdProvider.future);

  Future<void> _restore() async {
    if (!ref.read(lkmApiSessionProvider).isSignedIn) return;
    state = state.copyWith(busy: true, clearMessages: true);
    try {
      final account = await _api.me();
      state = state.copyWith(account: account, busy: false);
    } catch (error) {
      await ref.read(lkmApiSessionProvider).signOut(revoke: false);
      state = state.copyWith(
        busy: false,
        clearAccount: true,
        error: _describe(error),
      );
    }
  }

  void selectMethod(LkmAuthMethod method) {
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
      method: LkmAuthMethod.password,
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
      method: LkmAuthMethod.code,
    );
    if (!created) return;
    await resendCode();
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
    state = LkmAuthState(method: state.method);
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
    if (email.trim().isEmpty || code.trim().isEmpty) {
      state = state.copyWith(error: _t('lkmErrEmptyCode'));
      return;
    }
    state = state.copyWith(busy: true, clearMessages: true);
    try {
      final token = await _api.registerWithEmail(
        email: email.trim(),
        code: code.trim(),
      );
      await _finish(token);
    } catch (error) {
      state = state.copyWith(busy: false, error: _describe(error));
    }
  }

  Future<void> signOut() async {
    state = state.copyWith(busy: true, clearMessages: true);
    await ref.read(lkmApiSessionProvider).signOut();
    state = const LkmAuthState();
  }

  Future<bool> _createChallenge({
    required String account,
    required String primaryFactor,
    required LkmAuthMethod method,
  }) async {
    state = state.copyWith(busy: true, clearMessages: true, method: method);
    try {
      final challenge = await _api.createChallenge(
        account: account,
        deviceId: await _deviceId(),
        primaryFactor: primaryFactor,
      );
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
    final challenge = state.challenge;
    if (challenge == null) return;
    state = state.copyWith(busy: true, clearMessages: true);
    try {
      final step = await _api.submitFactor(
        challenge.id,
        deviceId: await _deviceId(),
        kind: kind,
        password: password,
        code: code,
        recoveryCode: recoveryCode,
      );
      if (step.isComplete) {
        await _finish(step.tokens!);
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

  Future<void> _finish(LkmAuthToken token) async {
    final session = ref.read(lkmApiSessionProvider);
    await session.adopt(
      LkmTokenPair(
        accessToken: token.accessToken,
        refreshToken: token.refreshToken,
        accessExpiresAt: decodeJwtExpiry(token.accessToken),
        refreshExpiresAt: decodeJwtExpiry(token.refreshToken),
      ),
    );
    final account = await _api.me();
    state = LkmAuthState(account: account);
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

final lkmAuthControllerProvider =
    NotifierProvider<LkmAuthController, LkmAuthState>(LkmAuthController.new);
