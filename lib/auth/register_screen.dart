import 'package:auto_route/auto_route.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:island/auth/login_controller.dart';
import 'package:island/auth/totp_setup_dialog.dart';
import 'package:island/community/user_pod.dart';
import 'package:island/core/api/api_client.dart';
import 'package:island/core/api/auth_api.dart';
import 'package:island/route.gr.dart';
import 'package:island/shared/widgets/app_scaffold.dart';

enum _RegisterMode { normal, local }

/// Username/password registration for LKM-service.
///
/// Two shapes exist server-side: `normal` (password plus a verified email or
/// phone) and `local` (password only, for admission-gated deployments). Both
/// answer with tokens or an admission-pending envelope, so the screen finishes
/// through the same session owner the login flow uses.
@RoutePage()
class RegisterScreen extends HookConsumerWidget {
  const RegisterScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = useState(_RegisterMode.normal);
    final busy = useState(false);
    final error = useState<String?>(null);
    final info = useState<String?>(null);
    final pending = useState<LkmRegistrationPending?>(null);
    final admission = useState<String?>(null);

    final username = useTextEditingController();
    final password = useTextEditingController();
    final email = useTextEditingController();
    final phone = useTextEditingController();
    final applyReason = useTextEditingController();
    final emailCode = useTextEditingController();
    final phoneCode = useTextEditingController();

    Future<void> finish(LkmAuthResult result) async {
      if (result.setupRequired && result.tempToken != null) {
        await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (_) => TotpSetupDialog(authResult: result),
        );
        if (!context.mounted) return;
        if (ref.read(loginControllerProvider).signedIn)
          Navigator.of(context).pop(true);
        return;
      }
      if (result.tokens != null) {
        await ref
            .read(loginControllerProvider.notifier)
            .adoptTokens(result.tokens!);
        ref.invalidate(lkmMeProvider);
        if (!context.mounted) return;
        await context.router.push(const OnboardingRoute());
        if (context.mounted) Navigator.of(context).pop(true);
        return;
      }
      if (result.isPendingAdmission) {
        admission.value = result.admissionStatus;
        return;
      }
      info.value = 'authFlow.registrationComplete'.tr();
    }

    Future<void> run(Future<void> Function() action) async {
      if (busy.value) return;
      busy.value = true;
      error.value = null;
      info.value = null;
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

    Future<void> requestNormal() => run(() async {
      if (username.text.trim().isEmpty) {
        error.value = 'authFlow.errorEmptyUsername'.tr();
        return;
      }
      if (password.text.isEmpty) {
        error.value = 'authFlow.errorEmptyPassword'.tr();
        return;
      }
      if (email.text.trim().isEmpty && phone.text.trim().isEmpty) {
        error.value = 'authFlow.errorEmptyContact'.tr();
        return;
      }
      final result = await ref
          .read(authApiProvider)
          .requestRegisterNormal(
            username: username.text,
            password: password.text,
            email: email.text,
            phone: phone.text,
            applyReason: applyReason.text,
          );
      pending.value = result;
      final sent = [
        if (result.emailSent) email.text.trim(),
        if (result.phoneSent) phone.text.trim(),
      ].join(' / ');
      info.value = 'authFlow.codeSentTo'.tr(args: [sent]);
    });

    Future<void> verifyNormal() => run(() async {
      final txn = pending.value;
      if (txn == null) return;
      final result = await ref
          .read(authApiProvider)
          .verifyRegisterNormal(
            txnId: txn.txnId,
            emailCode: emailCode.text,
            phoneCode: phoneCode.text,
          );
      await finish(result);
    });

    Future<void> registerLocal() => run(() async {
      if (username.text.trim().isEmpty) {
        error.value = 'authFlow.errorEmptyUsername'.tr();
        return;
      }
      if (password.text.isEmpty) {
        error.value = 'authFlow.errorEmptyPassword'.tr();
        return;
      }
      final result = await ref
          .read(authApiProvider)
          .registerLocal(
            username: username.text,
            password: password.text,
            applyReason: applyReason.text,
          );
      await finish(result);
    });

    return AppScaffold(
      isNoBackground: false,
      appBar: AppBar(
        leading: const AutoLeadingButton(),
        title: Text('authFlow.registerTitle'.tr()),
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
                child: admission.value != null
                    ? _AdmissionStatus(status: admission.value!)
                    : pending.value != null
                    ? _VerifyCodes(
                        pending: pending.value!,
                        emailCode: emailCode,
                        phoneCode: phoneCode,
                        busy: busy.value,
                        error: error.value,
                        onVerify: verifyNormal,
                        onResend: requestNormal,
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'authFlow.registerSubtitle'.tr(),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(height: 16),
                          SegmentedButton<_RegisterMode>(
                            segments: [
                              ButtonSegment(
                                value: _RegisterMode.normal,
                                label: Text('authFlow.modeNormal'.tr()),
                              ),
                              ButtonSegment(
                                value: _RegisterMode.local,
                                label: Text('authFlow.modeLocal'.tr()),
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
                            controller: username,
                            enabled: !busy.value,
                            autocorrect: false,
                            textInputAction: TextInputAction.next,
                            decoration: InputDecoration(
                              labelText: 'authFlow.username'.tr(),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: password,
                            enabled: !busy.value,
                            obscureText: true,
                            autocorrect: false,
                            enableSuggestions: false,
                            decoration: InputDecoration(
                              labelText: 'authFlow.password'.tr(),
                            ),
                          ),
                          if (mode.value == _RegisterMode.normal) ...[
                            const SizedBox(height: 12),
                            TextField(
                              controller: email,
                              enabled: !busy.value,
                              keyboardType: TextInputType.emailAddress,
                              autocorrect: false,
                              decoration: InputDecoration(
                                labelText: 'authFlow.email'.tr(),
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: phone,
                              enabled: !busy.value,
                              keyboardType: TextInputType.phone,
                              decoration: InputDecoration(
                                labelText: 'authFlow.phone'.tr(),
                              ),
                            ),
                          ],
                          const SizedBox(height: 12),
                          TextField(
                            controller: applyReason,
                            enabled: !busy.value,
                            maxLines: 2,
                            decoration: InputDecoration(
                              labelText: 'authFlow.applyReason'.tr(),
                              helperText: 'authFlow.applyReasonHint'.tr(),
                            ),
                          ),
                          if (error.value != null) ...[
                            const SizedBox(height: 12),
                            Text(
                              error.value!,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
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
                          const SizedBox(height: 20),
                          FilledButton(
                            onPressed: busy.value
                                ? null
                                : mode.value == _RegisterMode.normal
                                ? requestNormal
                                : registerLocal,
                            child: busy.value
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Text(
                                    (mode.value == _RegisterMode.normal
                                            ? 'authFlow.sendCode'
                                            : 'authFlow.createAccount')
                                        .tr(),
                                  ),
                          ),
                          const SizedBox(height: 8),
                          TextButton(
                            onPressed: busy.value
                                ? null
                                : () => context.router.pop(),
                            child: Text('authFlow.goLogin'.tr()),
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
}

class _VerifyCodes extends StatelessWidget {
  const _VerifyCodes({
    required this.pending,
    required this.emailCode,
    required this.phoneCode,
    required this.busy,
    required this.error,
    required this.onVerify,
    required this.onResend,
  });

  final LkmRegistrationPending pending;
  final TextEditingController emailCode;
  final TextEditingController phoneCode;
  final bool busy;
  final String? error;
  final VoidCallback onVerify;
  final VoidCallback onResend;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'authFlow.verifyTitle'.tr(),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        if (pending.emailSent) ...[
          const SizedBox(height: 12),
          TextField(
            controller: emailCode,
            enabled: !busy,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: 'authFlow.emailCode'.tr()),
          ),
        ],
        if (pending.phoneSent) ...[
          const SizedBox(height: 12),
          TextField(
            controller: phoneCode,
            enabled: !busy,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: 'authFlow.phoneCode'.tr()),
          ),
        ],
        if (error != null) ...[
          const SizedBox(height: 12),
          Text(
            error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        const SizedBox(height: 20),
        FilledButton(
          onPressed: busy ? null : onVerify,
          child: busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text('authFlow.verify'.tr()),
        ),
        TextButton(
          onPressed: busy ? null : onResend,
          child: Text('authFlow.resendCode'.tr()),
        ),
      ],
    );
  }
}

class _AdmissionStatus extends StatelessWidget {
  const _AdmissionStatus({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final rejected = status == 'rejected';
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(
          rejected ? Icons.block : Icons.hourglass_top,
          size: 48,
          color: rejected
              ? Theme.of(context).colorScheme.error
              : Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(height: 12),
        Text(
          (rejected ? 'authFlow.pendingRejected' : 'authFlow.pendingTitle')
              .tr(),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Text(
          'authFlow.pendingBody'.tr(),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
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
