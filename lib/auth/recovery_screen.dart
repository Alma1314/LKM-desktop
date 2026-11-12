import 'package:auto_route/auto_route.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:island/auth/login_controller.dart';
import 'package:island/core/api/api_client.dart';
import 'package:island/core/api/auth_api.dart';
import 'package:island/shared/widgets/app_scaffold.dart';

enum _RecoveryMode { email, phone, magic }

/// Password recovery for LKM-service.
///
/// The service resets immediately when the account has no 2FA; with 2FA it
/// hands back a recovery transaction that must clear `/auth/2fa/verify` (which
/// records the temp-token usage) before `/recover/verify-totp` and
/// `/recover/complete` can finish. Magic-link users paste the mail link or its
/// token, because the desktop has no browser callback for that flow yet.
@RoutePage()
class RecoveryScreen extends HookConsumerWidget {
  const RecoveryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = useState(_RecoveryMode.email);
    final stage = useState(0);
    final busy = useState(false);
    final error = useState<String?>(null);
    final info = useState<String?>(null);

    final contact = useTextEditingController();
    final code = useTextEditingController();
    final link = useTextEditingController();
    final password = useTextEditingController();
    final confirm = useTextEditingController();
    final totp = useTextEditingController();

    final txnId = useState<String?>(null);
    final tempToken = useState<String?>(null);
    final totpVerified = useState(false);
    final recoveryVerified = useState(false);

    Future<void> run(Future<void> Function() action) async {
      if (busy.value) return;
      busy.value = true;
      error.value = null;
      try {
        await action();
      } on ApiException catch (failure) {
        if (context.mounted) error.value = failure.message;
      } on ApiTransportException catch (failure) {
        if (context.mounted) error.value = failure.message;
      } catch (failure) {
        if (context.mounted) error.value = '$failure';
      } finally {
        if (context.mounted) busy.value = false;
      }
    }

    bool validatePassword() {
      if (password.text.isEmpty) {
        error.value = 'authFlow.errorEmptyPassword'.tr();
        return false;
      }
      if (password.text != confirm.text) {
        error.value = 'authFlow.errorPasswordMismatch'.tr();
        return false;
      }
      return true;
    }

    void takeOutcome(LkmRecoveryOutcome outcome) {
      if (!context.mounted) return;
      if (outcome.requires2fa) {
        if (outcome.tempToken == null || outcome.txnId == null)
          throw StateError('Missing recovery transaction');
        txnId.value = outcome.txnId;
        tempToken.value = outcome.tempToken;
        stage.value = 2;
        return;
      }
      stage.value = 3;
    }

    Future<void> send() => run(() async {
      if (contact.text.trim().isEmpty) {
        error.value = 'authFlow.errorEmptyContact'.tr();
        return;
      }
      if (mode.value == _RecoveryMode.magic) {
        await ref.read(authApiProvider).requestRecoveryMagicLink(contact.text);
      } else {
        await ref
            .read(authApiProvider)
            .requestRecovery(
              contact: contact.text,
              byEmail: mode.value == _RecoveryMode.email,
            );
      }
      if (!context.mounted) return;
      stage.value = 1;
      info.value = 'authFlow.codeSentTo'.tr(args: [contact.text.trim()]);
    });

    Future<void> verifyCode() => run(() async {
      if (!validatePassword()) return;
      final outcome = await ref
          .read(authApiProvider)
          .verifyRecovery(
            contact: contact.text,
            byEmail: mode.value == _RecoveryMode.email,
            code: code.text,
            newPassword: password.text,
          );
      takeOutcome(outcome);
    });

    Future<void> verifyLink() => run(() async {
      if (!validatePassword()) return;
      final raw = link.text.trim();
      if (raw.isEmpty) {
        error.value = 'authFlow.errorEmptyCode'.tr();
        return;
      }
      final parsed = Uri.tryParse(raw);
      final token = parsed?.queryParameters['token'] ?? raw;
      final outcome = await ref
          .read(authApiProvider)
          .verifyRecoveryMagicLink(token: token, newPassword: password.text);
      takeOutcome(outcome);
    });

    Future<void> verifyTotp() => run(() async {
      final txn = txnId.value;
      final temp = tempToken.value;
      if (txn == null || temp == null) return;
      if (totp.text.trim().isEmpty) {
        error.value = 'authFlow.errorEmptyCode'.tr();
        return;
      }
      final api = ref.read(authApiProvider);
      if (!totpVerified.value) {
        final value = totp.text.trim();
        final isCode = RegExp(r'^\d{6}$').hasMatch(value);
        await api.verifyTotp(
          tempToken: temp,
          code: isCode ? value : null,
          recoveryCode: isCode ? null : value,
        );
        if (!context.mounted) return;
        totpVerified.value = true;
      }
      if (!recoveryVerified.value) {
        await api.verifyRecoveryTotp(txnId: txn, tempToken: temp);
        if (!context.mounted) return;
        recoveryVerified.value = true;
      }
      await ref
          .read(authApiProvider)
          .completeRecovery(txnId: txn, newPassword: password.text);
      if (context.mounted) stage.value = 3;
    });

    return AppScaffold(
      isNoBackground: false,
      appBar: AppBar(
        leading: const AutoLeadingButton(),
        title: Text('authFlow.recoveryTitle'.tr()),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Card(
              elevation: 0,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: stage.value == 3
                    ? _Done()
                    : stage.value == 2
                    ? _TotpStep(
                        totp: totp,
                        busy: busy.value,
                        error: error.value,
                        onSubmit: verifyTotp,
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'authFlow.recoverySubtitle'.tr(),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(height: 16),
                          if (stage.value == 0) ...[
                            SegmentedButton<_RecoveryMode>(
                              segments: [
                                ButtonSegment(
                                  value: _RecoveryMode.email,
                                  label: Text('authFlow.modeEmail'.tr()),
                                ),
                                ButtonSegment(
                                  value: _RecoveryMode.phone,
                                  label: Text('authFlow.modePhone'.tr()),
                                ),
                                ButtonSegment(
                                  value: _RecoveryMode.magic,
                                  label: Text('authFlow.modeMagic'.tr()),
                                ),
                              ],
                              selected: {mode.value},
                              showSelectedIcon: false,
                              onSelectionChanged: busy.value
                                  ? null
                                  : (selection) => mode.value = selection.first,
                            ),
                            const SizedBox(height: 16),
                            TextField(
                              controller: contact,
                              enabled: !busy.value,
                              decoration: _contactDecoration(mode.value),
                            ),
                          ] else if (mode.value == _RecoveryMode.magic) ...[
                            TextField(
                              controller: link,
                              enabled: !busy.value,
                              maxLines: 2,
                              decoration: InputDecoration(
                                labelText: 'authFlow.magicLinkLabel'.tr(),
                                helperText: 'authFlow.magicLinkHint'.tr(),
                              ),
                            ),
                            const SizedBox(height: 12),
                            _passwordFields(password, confirm, busy.value),
                          ] else ...[
                            TextField(
                              controller: code,
                              enabled: !busy.value,
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                labelText: 'authFlow.resetCode'.tr(),
                              ),
                            ),
                            const SizedBox(height: 12),
                            _passwordFields(password, confirm, busy.value),
                          ],
                          if (info.value != null) ...[
                            const SizedBox(height: 12),
                            Text(
                              info.value!,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                          ],
                          if (error.value != null) ...[
                            const SizedBox(height: 12),
                            Text(
                              error.value!,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ],
                          const SizedBox(height: 20),
                          FilledButton(
                            onPressed: busy.value
                                ? null
                                : stage.value == 0
                                ? send
                                : mode.value == _RecoveryMode.magic
                                ? verifyLink
                                : verifyCode,
                            child: busy.value
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Text(
                                    (stage.value == 0
                                            ? 'authFlow.sendCode'
                                            : 'authFlow.resetAction')
                                        .tr(),
                                  ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _passwordFields(
    TextEditingController password,
    TextEditingController confirm,
    bool busy,
  ) {
    return Column(
      children: [
        TextField(
          controller: password,
          enabled: !busy,
          obscureText: true,
          autocorrect: false,
          enableSuggestions: false,
          decoration: InputDecoration(labelText: 'authFlow.newPassword'.tr()),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: confirm,
          enabled: !busy,
          obscureText: true,
          autocorrect: false,
          enableSuggestions: false,
          decoration: InputDecoration(
            labelText: 'authFlow.confirmPassword'.tr(),
          ),
        ),
      ],
    );
  }

  InputDecoration _contactDecoration(_RecoveryMode mode) => InputDecoration(
    labelText: mode == _RecoveryMode.phone
        ? 'authFlow.phone'.tr()
        : 'authFlow.email'.tr(),
    prefixIcon: Icon(
      mode == _RecoveryMode.phone
          ? Icons.phone_outlined
          : Icons.alternate_email,
    ),
  );
}

class _TotpStep extends StatelessWidget {
  const _TotpStep({
    required this.totp,
    required this.busy,
    required this.error,
    required this.onSubmit,
  });

  final TextEditingController totp;
  final bool busy;
  final String? error;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'authFlow.totpTitle'.tr(),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Text(
          'authFlow.totpHint'.tr(),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 16),
        TextField(
          controller: totp,
          enabled: !busy,
          decoration: InputDecoration(
            labelText: 'authFlow.totpOrRecovery'.tr(),
          ),
        ),
        if (error != null) ...[
          const SizedBox(height: 12),
          Text(
            error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        const SizedBox(height: 20),
        FilledButton(
          onPressed: busy ? null : onSubmit,
          child: busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text('authFlow.verify'.tr()),
        ),
      ],
    );
  }
}

class _Done extends StatelessWidget {
  const _Done();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(
          Icons.check_circle_outline,
          size: 48,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(height: 12),
        Text(
          'authFlow.recoveryDone'.tr(),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 20),
        OutlinedButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('authFlow.backToLogin'.tr()),
        ),
      ],
    );
  }
}
