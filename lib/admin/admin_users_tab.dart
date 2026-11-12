import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';
import 'package:island/admin/admin_pod.dart';
import 'package:island/admin/admin_widgets.dart';
import 'package:island/core/api/admin_api.dart';

class AdminUsersTab extends HookConsumerWidget {
  const AdminUsersTab({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final search = useTextEditingController();
    final keyword = useState('');
    final pii = useState(false);
    final page = useState(1);
    final query = (page: page.value, keyword: keyword.value, pii: pii.value);
    final result = ref.watch(adminUsersProvider(query));
    void submit() {
      page.value = 1;
      keyword.value = search.text.trim();
      ref.invalidate(adminUsersProvider);
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              TextField(
                controller: search,
                onSubmitted: (_) => submit(),
                decoration: InputDecoration(
                  labelText: 'adminMore.searchUsers'.tr(),
                  suffixIcon: IconButton(
                    onPressed: submit,
                    icon: const Icon(Symbols.search),
                  ),
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('adminMore.pii'.tr()),
                value: pii.value,
                onChanged: (v) {
                  page.value = 1;
                  pii.value = v;
                },
              ),
            ],
          ),
        ),
        Expanded(
          child: result.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => AdminErrorText(
              error: e,
              onRetry: () => ref.invalidate(adminUsersProvider(query)),
            ),
            data: (data) => Column(
              children: [
                Expanded(
                  child: data.items.isEmpty
                      ? Center(child: Text('adminMore.empty'.tr()))
                      : ListView.builder(
                          itemCount: data.items.length,
                          itemBuilder: (_, i) {
                            final user = data.items[i];
                            return ListTile(
                              title: Text(user.username),
                              subtitle: Text(
                                [
                                  user.id,
                                  user.level,
                                  adminDate(user.createdAt),
                                  if (pii.value && user.email != null)
                                    user.email!,
                                  if (pii.value && user.phone != null)
                                    user.phone!,
                                ].join('\n'),
                              ),
                              trailing: Chip(
                                label: Text(
                                  (user.locked
                                          ? 'adminMore.locked'
                                          : 'adminMore.unlocked')
                                      .tr(),
                                ),
                              ),
                            );
                          },
                        ),
                ),
                AdminPager(
                  page: data.page,
                  pages: data.pages,
                  onPage: (p) => page.value = p,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class AdminAdmissionTab extends HookConsumerWidget {
  const AdminAdmissionTab({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final busy = useState(false);
    final error = useState<Object?>(null);
    final result = ref.watch(adminAdmissionProvider);

    Future<void> decide(AdmissionUser user, bool approve) async {
      if (busy.value) return;
      final api = ref.read(adminApiProvider);
      busy.value = true;
      error.value = null;
      try {
        final reason = await showDialog<String>(
          context: context,
          builder: (_) =>
              _AdmissionDecisionDialog(user: user, approve: approve),
        );
        if (reason == null || !context.mounted) return;
        final saved = await runAdminAction(
          context,
          ref,
          () => api.decideAdmission(user.id, approve: approve, reason: reason),
        );
        if (saved == null || !context.mounted) return;
        ref.invalidate(adminAdmissionProvider);
        ref.invalidate(adminUsersProvider);
        ref.invalidate(adminRecentUsersProvider);
        ref.invalidate(adminReviewSummaryProvider);
      } catch (e) {
        if (context.mounted) error.value = e;
      } finally {
        if (context.mounted) busy.value = false;
      }
    }

    return Column(
      children: [
        ListTile(
          title: Text('adminMore.admission'.tr()),
          trailing: IconButton(
            onPressed: busy.value
                ? null
                : () => ref.invalidate(adminAdmissionProvider),
            icon: const Icon(Symbols.refresh),
          ),
        ),
        if (busy.value) const LinearProgressIndicator(),
        if (error.value != null) AdminErrorText(error: error.value!),
        Expanded(
          child: result.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => AdminErrorText(
              error: e,
              onRetry: () => ref.invalidate(adminAdmissionProvider),
            ),
            data: (items) => items.isEmpty
                ? Center(child: Text('adminMore.empty'.tr()))
                : ListView.builder(
                    itemCount: items.length,
                    itemBuilder: (_, i) {
                      final user = items[i];
                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                user.username,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              SelectableText(
                                [
                                  user.id,
                                  if (user.email != null) user.email!,
                                  if (user.appliedAt != null)
                                    adminDate(user.appliedAt!),
                                  if (user.reason != null) user.reason!,
                                ].join('\n'),
                              ),
                              Wrap(
                                spacing: 8,
                                children: [
                                  FilledButton(
                                    onPressed: busy.value
                                        ? null
                                        : () => decide(user, true),
                                    child: Text('adminMore.approve'.tr()),
                                  ),
                                  TextButton(
                                    onPressed: busy.value
                                        ? null
                                        : () => decide(user, false),
                                    child: Text('adminMore.reject'.tr()),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }
}

class _AdmissionDecisionDialog extends HookWidget {
  const _AdmissionDecisionDialog({required this.user, required this.approve});
  final AdmissionUser user;
  final bool approve;
  @override
  Widget build(BuildContext context) {
    final reason = useTextEditingController();
    useListenable(reason);
    return AlertDialog(
      title: Text((approve ? 'adminMore.approve' : 'adminMore.reject').tr()),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(user.username),
            if (!approve)
              TextField(
                controller: reason,
                maxLength: 500,
                maxLines: 3,
                decoration: InputDecoration(labelText: 'adminMore.reason'.tr()),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('cancel'.tr()),
        ),
        FilledButton(
          onPressed: !approve && reason.text.trim().isEmpty
              ? null
              : () => Navigator.pop(context, reason.text.trim()),
          child: Text(
            (approve ? 'adminMore.approve' : 'adminMore.reject').tr(),
          ),
        ),
      ],
    );
  }
}
