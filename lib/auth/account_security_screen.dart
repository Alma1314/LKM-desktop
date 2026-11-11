import 'package:auto_route/auto_route.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:passkeys/authenticator.dart';
import 'package:passkeys/types.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:island/auth/login_controller.dart';
import 'package:island/auth/oauth_desktop.dart';
import 'package:island/community/user_pod.dart';
import 'package:island/core/api/api_client.dart';
import 'package:island/core/api/auth_api.dart';
import 'package:island/shared/widgets/alert.dart';
import 'package:island/shared/widgets/app_scaffold.dart';

/// Account settings backed by `/auth/settings`, `/auth/2fa` and
/// `/auth/passkey`: profile, bound contacts, TOTP and passkeys.
@RoutePage()
class AccountSecurityScreen extends HookConsumerWidget {
  const AccountSecurityScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = useState<LkmAccountSettings?>(null);
    final credentials = useState<List<LkmPasskeyCredential>>(const []);
    final me = useState<LkmAccount?>(null);
    final busy = useState(false);
    final error = useState<String?>(null);

    final nickname = useTextEditingController();

    Future<void> load() async {
      busy.value = true;
      error.value = null;
      try {
        final api = ref.read(authApiProvider);
        final results = await Future.wait([
          api.accountSettings(),
          api.passkeyCredentials(),
          api.me(),
        ]);
        settings.value = results[0] as LkmAccountSettings;
        credentials.value = results[1] as List<LkmPasskeyCredential>;
        me.value = results[2] as LkmAccount;
        nickname.text = me.value?.nickname ?? '';
      } catch (failure) {
        error.value = _describe(failure);
      } finally {
        busy.value = false;
      }
    }

    useEffect(() {
      Future.microtask(load);
      return null;
    }, const []);

    Future<void> run(Future<void> Function() action) async {
      if (busy.value) return;
      busy.value = true;
      error.value = null;
      try {
        await action();
      } catch (failure) {
        error.value = _describe(failure);
      } finally {
        busy.value = false;
      }
    }

    Future<void> saveProfile() => run(() async {
      final account = me.value;
      if (account == null) return;
      await ref
          .read(authApiProvider)
          .updateProfile(userId: account.id, nickname: nickname.text.trim());
      ref.invalidate(lkmMeProvider);
      if (context.mounted) showSnackBar('authFlow.profileSaved'.tr());
    });

    Future<void> uploadAvatar() => run(() async {
      final account = me.value;
      if (account == null) return;
      final picked = await FilePicker.pickFiles(type: FileType.image);
      if (picked.isEmpty) return;
      final file = picked.first;
      final bytes = await file.xFile.readAsBytes();
      final api = ref.read(authApiProvider);
      final key = await api.uploadAvatar(bytes: bytes, filename: file.name);
      await api.updateProfile(userId: account.id, avatar: key);
      ref.invalidate(lkmMeProvider);
      if (context.mounted) showSnackBar('authFlow.avatarUpdated'.tr());
    });

    Future<void> bindContact({required bool email}) async {
      final contact = await _askText(
        context,
        title: (email ? 'authFlow.bindEmail' : 'authFlow.bindPhone').tr(),
        label: (email ? 'authFlow.email' : 'authFlow.phone').tr(),
      );
      if (contact == null || contact.trim().isEmpty) return;
      await run(() async {
        final api = ref.read(authApiProvider);
        email
            ? await api.requestBindEmail(contact)
            : await api.requestBindPhone(contact);
        if (!context.mounted) return;
        final code = await _askText(
          context,
          title: 'authFlow.verify'.tr(),
          label: 'authFlow.codeSentTo'.tr(args: [contact]),
          number: true,
        );
        if (code == null || code.trim().isEmpty) return;
        email
            ? await api.verifyBindEmail(email: contact, code: code)
            : await api.verifyBindPhone(phone: contact, code: code);
        await load();
      });
    }

    Future<void> bindGithub() => run(() async {
      final bound = await runGithubBind(ref.read(authApiProvider));
      if (!bound) {
        error.value = 'authFlow.bindFailed'.tr();
        return;
      }
      await load();
    });

    Future<void> unbind(String type) async {
      String? code;
      String? recovery;
      if (settings.value?.has2fa == true) {
        final values = await _askTwoFactor(context);
        if (values == null) return;
        code = values.$1;
        recovery = values.$2;
      }
      await run(() async {
        await ref
            .read(authApiProvider)
            .unbind(type, code: code, recoveryCode: recovery);
        await load();
      });
    }

    Future<void> toggleTotp(bool enable) => run(() async {
      final api = ref.read(authApiProvider);
      if (enable) {
        final result = await showDialog<bool>(
          context: context,
          builder: (_) => const _TotpSetupDialog(),
        );
        if (result == true) await load();
        return;
      }
      final values = await _askTwoFactor(context);
      if (values == null) return;
      await api.disableTotp(code: values.$1, recoveryCode: values.$2);
      await load();
    });

    Future<void> addPasskey() => run(() async {
      final authenticator = PasskeyAuthenticator(debugMode: kDebugMode);
      final options = await ref
          .read(authApiProvider)
          .beginPasskeyRegistration();
      final pk = options.publicKey;
      final rp = pk['rp'] is Map ? pk['rp'] as Map : const {};
      final user = pk['user'] is Map ? pk['user'] as Map : const {};
      final selection = pk['authenticatorSelection'] is Map
          ? pk['authenticatorSelection'] as Map
          : null;
      final params = (pk['pubKeyCredParams'] as List? ?? const [])
          .whereType<Map>();
      final request = RegisterRequestType(
        challenge: '${pk['challenge'] ?? ''}',
        relyingParty: RelyingPartyType(
          id: '${rp['id'] ?? ''}',
          name: '${rp['name'] ?? ''}',
        ),
        user: UserType(
          id: '${user['id'] ?? ''}',
          name: '${user['name'] ?? ''}',
          displayName: '${user['displayName'] ?? user['name'] ?? ''}',
        ),
        excludeCredentials: (pk['excludeCredentials'] as List? ?? const [])
            .whereType<Map>()
            .map(
              (e) => CredentialType(
                type: '${e['type'] ?? 'public-key'}',
                id: '${e['id'] ?? ''}',
                transports: const [],
              ),
            )
            .toList(growable: false),
        pubKeyCredParams: params
            .map(
              (e) => PubKeyCredParamType(
                type: '${e['type'] ?? 'public-key'}',
                alg: e['alg'] is int ? e['alg'] as int : -7,
              ),
            )
            .toList(growable: false),
        authSelectionType: selection == null
            ? null
            : AuthenticatorSelectionType(
                authenticatorAttachment:
                    selection['authenticatorAttachment'] as String?,
                residentKey: '${selection['residentKey'] ?? 'preferred'}',
                userVerification:
                    '${selection['userVerification'] ?? 'preferred'}',
                requireResidentKey: selection['requireResidentKey'] == true,
              ),
        timeout: pk['timeout'] is int ? pk['timeout'] as int : null,
        attestation: 'none',
      );
      final credential = await authenticator.register(request);
      await ref
          .read(authApiProvider)
          .completePasskeyRegistration(
            challengeId: options.challengeId,
            rawId: credential.id,
            response: {
              'attestationObject': credential.attestationObject,
              'clientDataJSON': credential.clientDataJSON,
            },
            deviceName: 'Desktop passkey',
          );
      await load();
    });

    Future<void> deletePasskey(LkmPasskeyCredential credential) =>
        run(() async {
          if (settings.value?.has2fa == true) {
            final values = await _askTwoFactor(context);
            if (values == null) return;
            final stepped = await ref
                .read(authApiProvider)
                .stepUpTotp(code: values.$1, recoveryCode: values.$2);
            if (stepped.hasTokens) {
              await ref
                  .read(loginControllerProvider.notifier)
                  .adoptTokens(
                    LkmAuthToken(
                      userId: stepped.userId,
                      accountLevel: stepped.accountLevel,
                      accessToken: stepped.accessToken!,
                      refreshToken: stepped.refreshToken ?? '',
                    ),
                  );
            }
          }
          await ref.read(authApiProvider).deletePasskey(credential.id);
          await load();
        });

    return AppScaffold(
      isNoBackground: false,
      appBar: AppBar(
        leading: const AutoLeadingButton(),
        title: Text('authFlow.accountSecurity'.tr()),
        actions: [
          IconButton(
            onPressed: busy.value ? null : load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: busy.value && settings.value == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                if (error.value != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      error.value!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                _Section(
                  title: 'authFlow.sectionProfile'.tr(),
                  children: [
                    TextField(
                      controller: nickname,
                      decoration: InputDecoration(
                        labelText: 'authFlow.nickname'.tr(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        FilledButton.tonal(
                          onPressed: busy.value ? null : saveProfile,
                          child: Text('authFlow.save'.tr()),
                        ),
                        OutlinedButton(
                          onPressed: busy.value ? null : uploadAvatar,
                          child: Text('authFlow.uploadAvatar'.tr()),
                        ),
                      ],
                    ),
                  ],
                ),
                _Section(
                  title: 'authFlow.sectionContacts'.tr(),
                  children: [
                    _BindingRow(
                      icon: Icons.alternate_email,
                      label: 'authFlow.email'.tr(),
                      value: settings.value?.email,
                      busy: busy.value,
                      onBind: () => bindContact(email: true),
                      onUnbind: () => unbind('email'),
                    ),
                    _BindingRow(
                      icon: Icons.phone_outlined,
                      label: 'authFlow.phone'.tr(),
                      value: settings.value?.phone,
                      busy: busy.value,
                      onBind: () => bindContact(email: false),
                      onUnbind: () => unbind('phone'),
                    ),
                    _BindingRow(
                      icon: Icons.code,
                      label: 'GitHub',
                      value: settings.value?.github,
                      busy: busy.value,
                      onBind: bindGithub,
                      onUnbind: () => unbind('github'),
                    ),
                  ],
                ),
                _Section(
                  title: 'authFlow.section2fa'.tr(),
                  children: [
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: settings.value?.has2fa ?? false,
                      onChanged: busy.value ? null : toggleTotp,
                      title: Text('authFlow.twoFactor'.tr()),
                      subtitle: Text(
                        (settings.value?.has2fa ?? false)
                            ? 'authFlow.enabled'.tr()
                            : 'authFlow.disabled'.tr(),
                      ),
                    ),
                  ],
                ),
                _Section(
                  title: 'authFlow.sectionPasskeys'.tr(),
                  children: [
                    if (credentials.value.isEmpty)
                      Text(
                        'authFlow.passkeyEmpty'.tr(),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    for (final credential in credentials.value)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.key),
                        title: Text(credential.deviceName),
                        subtitle: Text(
                          credential.createdAt == null
                              ? credential.credentialId
                              : '${credential.credentialId} · '
                                    '${_date(credential.createdAt!)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: IconButton(
                          tooltip: 'authFlow.delete'.tr(),
                          onPressed: busy.value
                              ? null
                              : () => deletePasskey(credential),
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: busy.value ? null : addPasskey,
                      icon: const Icon(Icons.add),
                      label: Text('authFlow.addPasskey'.tr()),
                    ),
                  ],
                ),
              ],
            ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _BindingRow extends StatelessWidget {
  const _BindingRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.busy,
    required this.onBind,
    required this.onUnbind,
  });

  final IconData icon;
  final String label;
  final String? value;
  final bool busy;
  final VoidCallback? onBind;
  final VoidCallback onUnbind;

  @override
  Widget build(BuildContext context) {
    final bound = value != null && value!.isNotEmpty;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon),
      title: Text(label),
      subtitle: Text(bound ? value! : 'authFlow.notBound'.tr()),
      trailing: bound
          ? TextButton(
              onPressed: busy ? null : onUnbind,
              child: Text('authFlow.unbind'.tr()),
            )
          : onBind == null
          ? null
          : TextButton(
              onPressed: busy ? null : onBind,
              child: Text('authFlow.bind'.tr()),
            ),
    );
  }
}

Future<String?> _askText(
  BuildContext context, {
  required String title,
  required String label,
  bool number = false,
}) {
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        keyboardType: number ? TextInputType.number : TextInputType.text,
        decoration: InputDecoration(labelText: label),
        onSubmitted: (value) => Navigator.pop(context, value.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('cancel'.tr()),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, controller.text.trim()),
          child: Text('confirm'.tr()),
        ),
      ],
    ),
  );
}

Future<(String?, String?)?> _askTwoFactor(BuildContext context) async {
  final controller = TextEditingController();
  final result = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('authFlow.twoFactorVerify'.tr()),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('authFlow.twoFactorHint'.tr()),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(
              labelText: 'authFlow.totpOrRecovery'.tr(),
            ),
            onSubmitted: (value) => Navigator.pop(context, value.trim()),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('cancel'.tr()),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, controller.text.trim()),
          child: Text('confirm'.tr()),
        ),
      ],
    ),
  );
  if (result == null || result.isEmpty) return null;
  final digits = RegExp(r'^\d{6}$').hasMatch(result);
  return digits ? (result, null) : (null, result);
}

class _TotpSetupDialog extends HookConsumerWidget {
  const _TotpSetupDialog();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final setup = useState<LkmTotpSetup?>(null);
    final completed = useState<LkmTotpSetupComplete?>(null);
    final code = useTextEditingController();
    final busy = useState(false);
    final error = useState<String?>(null);

    useEffect(() {
      Future.microtask(() async {
        try {
          setup.value = await ref.read(authApiProvider).beginTotpSetup();
        } catch (failure) {
          error.value = _describe(failure);
        }
      });
      return null;
    }, const []);

    Future<void> verify() async {
      if (busy.value) return;
      busy.value = true;
      error.value = null;
      try {
        final result = await ref
            .read(authApiProvider)
            .completeTotpSetup(code.text);
        completed.value = result;
      } catch (failure) {
        error.value = _describe(failure);
      } finally {
        busy.value = false;
      }
    }

    Future<void> confirm() async {
      busy.value = true;
      try {
        await ref.read(authApiProvider).confirmTotpRecoveryCodes();
        if (context.mounted) Navigator.pop(context, true);
      } catch (failure) {
        error.value = _describe(failure);
      } finally {
        busy.value = false;
      }
    }

    return AlertDialog(
      title: Text('authFlow.totpSetupTitle'.tr()),
      content: SingleChildScrollView(
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
      actions: [
        TextButton(
          onPressed: busy.value ? null : () => Navigator.pop(context),
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
    );
  }
}

String _describe(Object failure) {
  if (failure is ApiException) return failure.message;
  if (failure is ApiTransportException) return failure.message;
  return '$failure';
}

String _date(DateTime value) {
  final local = value.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)}';
}
