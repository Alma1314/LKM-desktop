import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:island/core/api/api_providers.dart';
import 'package:island/core/api/auth_api.dart';
import 'package:island/auth/lkm/lkm_auth_controller.dart';
import 'package:island/shared/widgets/alert.dart';

/// Entry mode of the login screen.
///
/// `register` is deliberately outside [LkmAuthMethod]: registration is not a
/// challenge (the server returns tokens straight from `/auth/reg/email/verify`),
/// and stargate kept it separate for the same reason.
enum _LoginMode { password, code, passkey, register }

/// Login for LKM-service, driven by the server's challenge: the screen renders
/// whatever factor the challenge names next, so a new factor (passkey, device
/// trust) needs no client change.
class LkmLoginContent extends ConsumerStatefulWidget {
  const LkmLoginContent({super.key});

  @override
  ConsumerState<LkmLoginContent> createState() => _LkmLoginContentState();
}

class _LkmLoginContentState extends ConsumerState<LkmLoginContent> {
  var _mode = _LoginMode.password;

  final _account = TextEditingController();
  final _password = TextEditingController();
  final _code = TextEditingController();
  final _email = TextEditingController();

  @override
  void dispose() {
    _account.dispose();
    _password.dispose();
    _code.dispose();
    _email.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(lkmAuthControllerProvider);
    final account = state.account;
    if (account != null) {
      return _SignedInCard(
        account: account,
        busy: state.busy,
        error: state.error,
        onSignOut: ref.read(lkmAuthControllerProvider.notifier).signOut,
      );
    }

    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'lkmLoginTitle'.tr(),
                style: theme.textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              Text(
                'lkmLoginSubtitle'.tr(),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              if (!state.hasChallenge) ...[
                _modeSelector(state.busy),
                const SizedBox(height: 20),
                ..._entryFields(state),
              ] else
                ..._factorFields(state),
              const SizedBox(height: 16),
              if (state.hasChallenge)
                TextButton(
                  onPressed: state.busy
                      ? null
                      : () => ref
                            .read(lkmAuthControllerProvider.notifier)
                            .cancel(),
                  child: Text('lkmCancel'.tr()),
                ),
              if (state.info != null) ...[
                const SizedBox(height: 8),
                Text(
                  state.info!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
              if (state.error != null) ...[
                const SizedBox(height: 8),
                Text(
                  state.error!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: 20),
              Text(
                'lkmServerHint'.tr(args: [ref.watch(lkmServerUrlProvider)]),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _modeSelector(bool busy) {
    return SegmentedButton<_LoginMode>(
      segments: [
        ButtonSegment(
          value: _LoginMode.password,
          label: Text('lkmMethodPassword'.tr()),
        ),
        ButtonSegment(
          value: _LoginMode.code,
          label: Text('lkmMethodCode'.tr()),
        ),
        ButtonSegment(
          value: _LoginMode.passkey,
          label: Text('lkmMethodPasskey'.tr()),
        ),
        ButtonSegment(
          value: _LoginMode.register,
          label: Text('lkmMethodRegister'.tr()),
        ),
      ],
      selected: {_mode},
      showSelectedIcon: false,
      onSelectionChanged: busy
          ? null
          : (selection) => setState(() => _mode = selection.first),
    );
  }

  /// Nothing has been sent to the server yet: collect the identifier.
  List<Widget> _entryFields(LkmAuthState state) {
    final controller = ref.read(lkmAuthControllerProvider.notifier);
    switch (_mode) {
      case _LoginMode.password:
        return [
          _field(
            controller: _account,
            label: 'lkmAccountLabel'.tr(),
            icon: Icons.person_outline,
            onSubmitted: () => controller.beginPassword(_account.text),
          ),
          const SizedBox(height: 16),
          _primaryButton(
            busy: state.busy,
            label: 'lkmContinue'.tr(),
            onPressed: () => controller.beginPassword(_account.text),
          ),
        ];
      case _LoginMode.code:
        return [
          _field(
            controller: _account,
            label: 'lkmContactLabel'.tr(),
            icon: Icons.alternate_email,
            onSubmitted: () => controller.beginCode(_account.text),
          ),
          const SizedBox(height: 16),
          _primaryButton(
            busy: state.busy,
            label: 'lkmContinue'.tr(),
            onPressed: () => controller.beginCode(_account.text),
          ),
        ];
      case _LoginMode.passkey:
        return [
          _field(
            controller: _account,
            label: 'lkmAccountLabel'.tr(),
            icon: Icons.person_outline,
            onSubmitted: () => controller.beginPasskey(_account.text),
          ),
          const SizedBox(height: 8),
          Text(
            'lkmPasskeyHint'.tr(),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          _primaryButton(
            busy: state.busy,
            label: 'lkmContinue'.tr(),
            onPressed: () => controller.beginPasskey(_account.text),
          ),
        ];
      case _LoginMode.register:
        return [
          _field(
            controller: _email,
            label: 'lkmEmailLabel'.tr(),
            icon: Icons.alternate_email,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _field(
                  controller: _code,
                  label: 'lkmCodeLabel'.tr(),
                  icon: Icons.pin_outlined,
                  onSubmitted: () => controller.verifyRegistration(
                    email: _email.text,
                    code: _code.text,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: state.busy
                    ? null
                    : () => controller.requestRegisterCode(_email.text),
                child: Text('lkmSendCode'.tr()),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'lkmRegisterHint'.tr(),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          _primaryButton(
            busy: state.busy,
            label: 'lkmRegisterAction'.tr(),
            onPressed: () => controller.verifyRegistration(
              email: _email.text,
              code: _code.text,
            ),
          ),
        ];
    }
  }

  /// A challenge is open: render whatever factor it names next.
  List<Widget> _factorFields(LkmAuthState state) {
    final controller = ref.read(lkmAuthControllerProvider.notifier);
    final factor = state.currentFactor;
    if (factor == null) {
      return [
        Text(
          'lkmErrChallengeExpired'.tr(),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.error,
          ),
          textAlign: TextAlign.center,
        ),
      ];
    }

    switch (factor.kind) {
      case 'password':
        return [
          _field(
            controller: _password,
            label: 'lkmPasswordLabel'.tr(),
            icon: Icons.lock_outline,
            obscure: true,
            onSubmitted: () => controller.submitPassword(_password.text),
          ),
          const SizedBox(height: 16),
          _primaryButton(
            busy: state.busy,
            label: 'lkmSignInAction'.tr(),
            onPressed: () => controller.submitPassword(_password.text),
          ),
        ];
      case 'code':
        return [
          Row(
            children: [
              Expanded(
                child: _field(
                  controller: _code,
                  label: 'lkmCodeLabel'.tr(),
                  icon: Icons.pin_outlined,
                  onSubmitted: () => controller.submitCode(_code.text),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: state.busy ? null : controller.resendCode,
                child: Text(
                  state.codeSent ? 'lkmResendCode'.tr() : 'lkmSendCode'.tr(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _primaryButton(
            busy: state.busy,
            label: 'lkmSignInAction'.tr(),
            onPressed: () => controller.submitCode(_code.text),
          ),
        ];
      case 'totp':
        final recovery = state.recoveryMode;
        return [
          _field(
            controller: _code,
            label: recovery ? 'lkmRecoveryCodeLabel'.tr() : 'lkmTotpLabel'.tr(),
            icon: Icons.shield_outlined,
            onSubmitted: () => controller.submitTotp(_code.text),
          ),
          const SizedBox(height: 16),
          _primaryButton(
            busy: state.busy,
            label: 'lkmVerifyAction'.tr(),
            onPressed: () => controller.submitTotp(_code.text),
          ),
          TextButton(
            onPressed: state.busy ? null : controller.toggleRecoveryMode,
            child: Text(
              recovery ? 'lkmTotpLabel'.tr() : 'lkmRecoveryCodeLabel'.tr(),
            ),
          ),
        ];
      case 'passkey':
        return [
          Text(
            factor.hint == null
                ? 'lkmPasskeyHint'.tr()
                : 'lkmCodeSentTo'.tr(args: [factor.hint!]),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          _primaryButton(
            busy: state.busy,
            label: 'lkmPasskeyAction'.tr(),
            onPressed: controller.authenticateWithPasskey,
          ),
        ];
      default:
        return [
          Text(
            'lkmErrUnsupportedFactor'.tr(args: [factor.kind]),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.error,
            ),
            textAlign: TextAlign.center,
          ),
        ];
    }
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool obscure = false,
    VoidCallback? onSubmitted,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      autocorrect: false,
      enableSuggestions: !obscure,
      textInputAction: onSubmitted == null
          ? TextInputAction.next
          : TextInputAction.done,
      onSubmitted: onSubmitted == null ? null : (_) => onSubmitted(),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        border: const OutlineInputBorder(),
        isDense: true,
      ),
    );
  }

  Widget _primaryButton({
    required bool busy,
    required String label,
    required VoidCallback onPressed,
  }) {
    return FilledButton(
      onPressed: busy ? null : onPressed,
      child: busy
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Text(label),
    );
  }
}

class _SignedInCard extends StatelessWidget {
  const _SignedInCard({
    required this.account,
    required this.busy,
    required this.error,
    required this.onSignOut,
  });

  final LkmAccount account;
  final bool busy;
  final String? error;
  final Future<void> Function() onSignOut;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final initial = account.displayName.isEmpty
        ? '?'
        : account.displayName.characters.first;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              CircleAvatar(
                radius: 32,
                child: Text(initial, style: theme.textTheme.headlineSmall),
              ),
              const SizedBox(height: 16),
              Text(
                'lkmSignedInAs'.tr(args: [account.displayName]),
                style: theme.textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              if (account.email != null) ...[
                const SizedBox(height: 4),
                Text(
                  account.email!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: 20),
              Text(
                'lkmHomePending'.tr(),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              if (error != null) ...[
                const SizedBox(height: 12),
                Text(
                  error!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: 20),
              OutlinedButton(
                onPressed: busy
                    ? null
                    : () async {
                        await onSignOut();
                        if (context.mounted) {
                          showSnackBar('lkmSignedOut'.tr());
                        }
                      },
                child: Text('lkmSignOutAction'.tr()),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
