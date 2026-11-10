import 'package:auto_route/auto_route.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';

import 'package:island/admin/admin_content_tab.dart';
import 'package:island/admin/admin_dlq_tab.dart';
import 'package:island/admin/admin_files_tab.dart';
import 'package:island/admin/admin_pod.dart';
import 'package:island/admin/admin_reports_tab.dart';
import 'package:island/admin/admin_rules_tab.dart';
import 'package:island/admin/admin_widgets.dart';
import 'package:island/core/api/admin_api.dart';
import 'package:island/core/api/api_client.dart';
import 'package:island/shared/hooks/material_hooks.dart';
import 'package:island/shared/widgets/app_scaffold.dart';

/// The website's `/admin` panel, rebuilt against the cookie-session admin API.
///
/// Entry is offered from the account page only for `account.isAdmin`, but the
/// panel has its own sign-in: every `/admin/*` endpoint authenticates from the
/// `admin_session` cookie, which a bearer session cannot stand in for. The
/// permission list from `/admin/auth/me` hides tabs whose endpoints the active
/// roles cannot use; the server still enforces each call.
@RoutePage()
class AdminScreen extends HookConsumerWidget {
  const AdminScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final signedIn = ref.watch(adminSignedInProvider);
    if (!signedIn) return const _AdminLoginView();

    final me = ref.watch(adminMeProvider);
    return AppScaffold(
      isNoBackground: false,
      appBar: AppBar(
        leading: const AutoLeadingButton(),
        title: Text('adminPanel.title'.tr()),
        actions: [
          if (me.hasValue)
            IconButton(
              tooltip: 'adminPanel.signOut'.tr(),
              onPressed: () async {
                await ref.read(adminApiProvider).logout();
                if (!context.mounted) return;
                ref.read(adminSignedInProvider.notifier).set(false);
                ref.invalidate(adminMeProvider);
              },
              icon: const Icon(Symbols.logout),
            ),
        ],
      ),
      body: me.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AdminErrorText(
                error: error,
                onRetry: () => ref.invalidate(adminMeProvider),
              ),
              TextButton(
                onPressed: () async {
                  await ref.read(adminApiProvider).logout();
                  ref.read(adminSignedInProvider.notifier).set(false);
                  ref.invalidate(adminMeProvider);
                },
                child: Text('adminPanel.signOut'.tr()),
              ),
            ],
          ),
        ),
        data: (info) {
          if (info == null) return const SizedBox.shrink();
          final tabs = _tabsFor(info);
          if (tabs.isEmpty) {
            return Center(child: Text('adminPanel.noPermission'.tr()));
          }
          return _AdminBody(tabs: tabs);
        },
      ),
    );
  }
}

class _AdminTab {
  const _AdminTab(this.labelKey, this.icon, this.builder);

  final String labelKey;
  final IconData icon;
  final Widget Function() builder;
}

List<_AdminTab> _tabsFor(AdminSessionInfo info) => [
  if (info.can('admin.moderation_manage'))
    _AdminTab(
      'adminPanel.tabModeration',
      Symbols.gavel,
      AdminRulesTab.new,
    ),
  if (info.can('admin.content_review'))
    _AdminTab(
      'adminPanel.tabContent',
      Symbols.article,
      AdminContentTab.new,
    ),
  if (info.can('admin.reports_view'))
    _AdminTab(
      'adminPanel.tabReports',
      Symbols.flag,
      AdminReportsTab.new,
    ),
  if (info.can('files.review'))
    _AdminTab(
      'adminPanel.tabFiles',
      Symbols.folder,
      AdminFilesTab.new,
    ),
  if (info.can('admin.events_manage'))
    _AdminTab(
      'adminPanel.tabDlq',
      Symbols.inbox,
      AdminDlqTab.new,
    ),
];

class _AdminBody extends HookConsumerWidget {
  const _AdminBody({required this.tabs});

  final List<_AdminTab> tabs;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = useMaterialTabController(initialLength: tabs.length);
    return Column(
      children: [
        TabBar(
          controller: controller,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: [
            for (final tab in tabs)
              Tab(icon: Icon(tab.icon), text: tab.labelKey.tr()),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: controller,
            children: [for (final tab in tabs) tab.builder()],
          ),
        ),
      ],
    );
  }
}

class _AdminLoginView extends HookConsumerWidget {
  const _AdminLoginView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final username = useTextEditingController();
    final password = useTextEditingController();
    final busy = useState(false);
    final error = useState<String?>(null);

    Future<void> submit() async {
      if (busy.value) return;
      if (username.text.trim().isEmpty || password.text.isEmpty) {
        error.value = 'adminPanel.credentialsRequired'.tr();
        return;
      }
      busy.value = true;
      error.value = null;
      try {
        await ref
            .read(adminApiProvider)
            .login(username.text.trim(), password.text);
        if (!context.mounted) return;
        ref.read(adminSignedInProvider.notifier).set(true);
        ref.invalidate(adminMeProvider);
      } on ApiException catch (e) {
        error.value = e.message;
      } catch (e) {
        error.value = '$e';
      } finally {
        busy.value = false;
      }
    }

    return AppScaffold(
      isNoBackground: false,
      appBar: AppBar(
        leading: const AutoLeadingButton(),
        title: Text('adminPanel.title'.tr()),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Card(
              elevation: 0,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(
                      Symbols.admin_panel_settings,
                      size: 48,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'adminPanel.loginTitle'.tr(),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'adminPanel.loginHint'.tr(),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: username,
                      enabled: !busy.value,
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(
                        labelText: 'adminPanel.username'.tr(),
                        prefixIcon: const Icon(Symbols.person),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: password,
                      enabled: !busy.value,
                      obscureText: true,
                      onSubmitted: (_) => submit(),
                      decoration: InputDecoration(
                        labelText: 'adminPanel.password'.tr(),
                        prefixIcon: const Icon(Symbols.lock),
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
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: busy.value ? null : submit,
                      child: busy.value
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text('adminPanel.signIn'.tr()),
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
