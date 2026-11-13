import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:island/auth/login_controller.dart';
import 'package:island/core/api/auth_api.dart';
import 'package:island/core/api/api_providers.dart';
import 'package:island/core/api/api_client.dart';

class TotpSetupDialog extends HookConsumerWidget {
  const TotpSetupDialog({super.key, this.authResult});

  final LkmAuthResult? authResult;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = useMemoized(() => ref.read(lkmApiSessionProvider));
    final setup = useState<LkmTotpSetup?>(null);
    final completed = useState<LkmTotpSetupComplete?>(null);
    final code = useTextEditingController();
    final busy = useState(false);
    final error = useState<String?>(null);

    useEffect(() {
      Future.microtask(() async {
        try {
          final api = AuthApi(session.client);
          final value = authResult == null
              ? await api.beginTotpSetup()
              : await api.beginTotpSetupWithTemp(authResult!.tempToken!);
          if (context.mounted) setup.value = value;
        } catch (failure) {
          if (context.mounted) error.value = _describe(failure);
        }
      });
      return null;
    }, const []);

    Future<void> verify() async {
      if (busy.value) return;
      busy.value = true;
      error.value = null;
      try {
        final api = AuthApi(session.client);
        final result = authResult == null
            ? await api.completeTotpSetup(code.text)
            : await api.completeTotpSetupWithTemp(
                tempToken: authResult!.tempToken!,
                code: code.text,
              );
        if (context.mounted) completed.value = result;
      } catch (failure) {
        if (context.mounted) error.value = _describe(failure);
      } finally {
        if (context.mounted) busy.value = false;
      }
    }

    Future<void> confirm() async {
      busy.value = true;
      try {
        if (authResult != null) {
          final tokens = completed.value!;
          if (tokens.accessToken == null || tokens.refreshToken == null) {
            throw StateError('Missing setup session');
          }
          await ref
              .read(loginControllerProvider.notifier)
              .adoptTokens(
                LkmAuthToken(
                  userId: authResult!.userId,
                  accountLevel: authResult!.accountLevel,
                  accessToken: tokens.accessToken!,
                  refreshToken: tokens.refreshToken!,
                ),
                session: session,
              );
        }
        await AuthApi(session.client).confirmTotpRecoveryCodes();
        if (context.mounted) Navigator.pop(context, true);
      } catch (failure) {
        if (context.mounted) error.value = _describe(failure);
      } finally {
        if (context.mounted) busy.value = false;
      }
    }

    return PopScope(
      canPop: !busy.value && completed.value == null,
      child: AlertDialog(
        title: Text('authFlow.totpSetupTitle'.tr()),
        content: SizedBox(
          width: 320,
          child: SingleChildScrollView(
            child: completed.value != null
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('authFlow.recoveryCodesHint'.tr()),
                      const SizedBox(height: 8),
                      for (final item in completed.value!.recoveryCodes)
                        SelectableText(item),
                      if (error.value != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          error.value!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ],
                    ],
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (setup.value != null) ...[
                        Center(
                          child: QrImageView(
                            data: setup.value!.qrCodeUri,
                            size: 180,
                          ),
                        ),
                        const SizedBox(height: 8),
                        SelectableText(
                          setup.value!.secret,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                      ],
                      TextField(
                        controller: code,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: 'authFlow.totpCode'.tr(),
                        ),
                      ),
                      if (error.value != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          error.value!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ],
                    ],
                  ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: busy.value || completed.value != null
                ? null
                : () => Navigator.pop(context),
            child: Text('cancel'.tr()),
          ),
          if (completed.value == null)
            FilledButton(
              onPressed: busy.value || setup.value == null ? null : verify,
              child: Text('authFlow.verify'.tr()),
            )
          else
            FilledButton(
              onPressed: busy.value ? null : confirm,
              child: Text('authFlow.saved'.tr()),
            ),
        ],
      ),
    );
  }
}

String _describe(Object failure) {
  if (failure is ApiException) return failure.message;
  if (failure is ApiTransportException) return failure.message;
  return '$failure';
}
