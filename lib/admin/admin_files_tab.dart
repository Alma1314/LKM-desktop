import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';

import 'package:island/admin/admin_pod.dart';
import 'package:island/admin/admin_widgets.dart';
import 'package:island/core/api/api_client.dart';
import 'package:island/shared/widgets/alert.dart';

/// The website's admin files page: the `/files` review queue plus the
/// 2FA-gated `POST /files/review-batch` action (approved/rejected, max 50).
class AdminFilesTab extends HookConsumerWidget {
  const AdminFilesTab({super.key});

  static const _statuses = ['pending', 'approved', 'rejected'];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final page = useState(1);
    final status = useState('pending');
    final selected = useState<Set<String>>(<String>{});
    final result = ref.watch(
      adminFilesProvider((page: page.value, status: status.value)),
    );

    void clearSelection() => selected.value = <String>{};

    void toggle(String id) {
      final next = Set<String>.from(selected.value);
      if (!next.remove(id)) next.add(id);
      selected.value = next;
    }

    Future<void> review(String target) async {
      final ids = selected.value.toList(growable: false);
      if (ids.isEmpty) return;
      String? comment;
      if (target == 'rejected') {
        comment = await showDialog<String>(
          context: context,
          builder: (_) => const _RejectReasonDialog(),
        );
        if (comment == null || comment.trim().isEmpty) return;
      }
      if (!context.mounted) return;
      try {
        final batch = await runAdminAction(
          context,
          ref,
          () => ref
              .read(adminApiProvider)
              .reviewFiles(fileIds: ids, status: target, comment: comment),
        );
        if (batch == null) return;
        if (context.mounted) {
          showSnackBar(
            'adminPanel.fileReviewResult'.tr(
              args: ['${batch.succeeded}', '${batch.failed}'],
            ),
          );
        }
        clearSelection();
        ref.invalidate(adminFilesProvider);
      } on ApiException catch (error) {
        if (context.mounted) showSnackBar(error.message);
      }
    }

    return result.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(
        child: AdminErrorText(
          error: error,
          onRetry: () => ref.invalidate(adminFilesProvider),
        ),
      ),
      data: (data) {
        final items = data.items;
        final currentIds = items.map((e) => e.id).toSet();
        final visibleSelection = selected.value.intersection(currentIds);
        final allSelected =
            items.isNotEmpty && visibleSelection.length == items.length;
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(
                children: [
                  DropdownButton<String>(
                    value: status.value,
                    onChanged: (value) {
                      if (value == null) return;
                      status.value = value;
                      page.value = 1;
                      clearSelection();
                    },
                    items: [
                      for (final value in _statuses)
                        DropdownMenuItem(
                          value: value,
                          child: Text('adminPanel.file_$value'.tr()),
                        ),
                    ],
                  ),
                  const SizedBox(width: 12),
                  Checkbox(
                    value: allSelected,
                    onChanged: items.isEmpty
                        ? null
                        : (value) {
                            selected.value = value == true
                                ? Set<String>.from(currentIds)
                                : <String>{};
                          },
                  ),
                  Text('adminPanel.fileSelectAll'.tr()),
                  const Spacer(),
                  Text(
                    'adminPanel.fileSelected'.tr(
                      args: ['${visibleSelection.length}'],
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: visibleSelection.isEmpty
                        ? null
                        : () => review('rejected'),
                    icon: const Icon(Symbols.block),
                    label: Text('adminPanel.fileReject'.tr()),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: visibleSelection.isEmpty
                        ? null
                        : () => review('approved'),
                    icon: const Icon(Symbols.check),
                    label: Text('adminPanel.fileApprove'.tr()),
                  ),
                  IconButton(
                    tooltip: 'refresh'.tr(),
                    onPressed: () {
                      clearSelection();
                      ref.invalidate(adminFilesProvider);
                    },
                    icon: const Icon(Symbols.refresh_rounded),
                  ),
                ],
              ),
            ),
            Expanded(
              child: items.isEmpty
                  ? Center(child: Text('adminPanel.fileEmpty'.tr()))
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
                      itemCount: items.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final file = items[index];
                        return CheckboxListTile(
                          value: selected.value.contains(file.id),
                          onChanged: (_) => toggle(file.id),
                          title: Text(
                            file.originalName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Wrap(
                            spacing: 12,
                            runSpacing: 4,
                            children: [
                              Text(file.uploaderName),
                              Text(adminFileSize(file.size)),
                              Text(adminDate(file.createdAt)),
                              Chip(
                                label: Text('adminPanel.file_${file.status}'.tr()),
                                visualDensity: VisualDensity.compact,
                              ),
                              if (file.reviewComment != null &&
                                  file.reviewComment!.isNotEmpty)
                                Text(file.reviewComment!),
                            ],
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
                onPage: (value) {
                  page.value = value;
                  clearSelection();
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

class _RejectReasonDialog extends HookWidget {
  const _RejectReasonDialog();

  @override
  Widget build(BuildContext context) {
    final reason = useTextEditingController();
    final error = useState<String?>(null);
    return AlertDialog(
      title: Text('adminPanel.fileReject'.tr()),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: reason,
            autofocus: true,
            maxLength: 500,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: 'adminPanel.fileRejectReason'.tr(),
            ),
          ),
          if (error.value != null)
            Text(
              error.value!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('cancel'.tr()),
        ),
        FilledButton(
          onPressed: () {
            if (reason.text.trim().isEmpty) {
              error.value = 'adminPanel.fileRejectReason'.tr();
              return;
            }
            Navigator.of(context).pop(reason.text.trim());
          },
          child: Text('confirm'.tr()),
        ),
      ],
    );
  }
}
