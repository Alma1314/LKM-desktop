import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';

import 'package:island/admin/admin_pod.dart';
import 'package:island/admin/admin_widgets.dart';
import 'package:island/core/api/admin_api.dart';
import 'package:island/core/api/api_client.dart';
import 'package:island/shared/widgets/alert.dart';

/// `/admin/content/items`: the website's admin posts page. Deleting an item is
/// the 2FA-gated backend path; the list itself is read-only.
class AdminContentTab extends HookConsumerWidget {
  const AdminContentTab({super.key});

  static const _types = <String?>[
    null,
    'discussion',
    'article',
    'column_post',
    'blog_post',
    'qa',
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final page = useState(1);
    final type = useState<String?>(null);
    final result = ref.watch(
      adminContentProvider((page: page.value, type: type.value)),
    );

    Future<void> remove(AdminContentItem item) async {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          content: Text('adminPanel.contentDeleteConfirm'.tr(args: [item.title])),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text('cancel'.tr()),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text('delete'.tr()),
            ),
          ],
        ),
      );
      if (confirmed != true || !context.mounted) return;
      try {
        await runAdminAction(
          context,
          ref,
          () => ref.read(adminApiProvider).deleteContentItem(item.id),
        );
        ref.invalidate(adminContentProvider);
      } on ApiException catch (error) {
        if (context.mounted) showSnackBar(error.message);
      }
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              DropdownButton<String?>(
                value: type.value,
                onChanged: (value) {
                  type.value = value;
                  page.value = 1;
                },
                items: [
                  for (final value in _types)
                    DropdownMenuItem(
                      value: value,
                      child: Text(
                        value == null
                            ? 'all'.tr()
                            : 'adminPanel.type_$value'.tr(),
                      ),
                    ),
                ],
              ),
              const Spacer(),
              IconButton(
                tooltip: 'refresh'.tr(),
                onPressed: () => ref.invalidate(adminContentProvider),
                icon: const Icon(Symbols.refresh_rounded),
              ),
            ],
          ),
        ),
        Expanded(
          child: result.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => Center(
              child: AdminErrorText(
                error: error,
                onRetry: () => ref.invalidate(adminContentProvider),
              ),
            ),
            data: (data) => data.items.isEmpty
                ? Center(child: Text('adminPanel.contentEmpty'.tr()))
                : Column(
                    children: [
                      Expanded(
                        child: ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                          itemCount: data.items.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final item = data.items[index];
                            return Card(
                              elevation: 0,
                              child: ListTile(
                                title: Text(
                                  item.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Wrap(
                                    spacing: 8,
                                    runSpacing: 4,
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    children: [
                                      Chip(
                                        label: Text(
                                          'adminPanel.type_${item.contentType}'.tr(),
                                        ),
                                        visualDensity: VisualDensity.compact,
                                      ),
                                      Text(item.authorName),
                                      Text(adminDate(item.createdAt)),
                                      Text(
                                        'adminPanel.contentCounts'.tr(
                                          args: [
                                            '${item.viewCount}',
                                            '${item.likeCount}',
                                            '${item.commentCount}',
                                          ],
                                        ),
                                      ),
                                      if (item.isPinned)
                                        Chip(
                                          label: Text('adminPanel.pinned'.tr()),
                                          visualDensity:
                                              VisualDensity.compact,
                                        ),
                                      if (item.isFeatured)
                                        Chip(
                                          label: Text('adminPanel.featured'.tr()),
                                          visualDensity:
                                              VisualDensity.compact,
                                        ),
                                    ],
                                  ),
                                ),
                                trailing: IconButton(
                                  tooltip: 'delete'.tr(),
                                  onPressed: () => remove(item),
                                  icon: const Icon(Symbols.delete),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: AdminPager(
                          page: data.page,
                          pages: data.pages,
                          onPage: (value) => page.value = value,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }
}
