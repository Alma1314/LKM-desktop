import 'dart:convert';

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

/// `/admin/dlq`: pending dead letters, with 2FA-gated requeue/discard.
class AdminDlqTab extends HookConsumerWidget {
  const AdminDlqTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = useState('pending');
    final items = ref.watch(adminDlqProvider(status.value));

    Future<void> act(AdminDlqItem item, {required bool requeue}) async {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          content: Text(
            (requeue ? 'adminPanel.dlqRequeueConfirm' : 'adminPanel.dlqDiscardConfirm')
                .tr(args: [item.routingKey]),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text('cancel'.tr()),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(requeue ? 'adminPanel.dlqRequeue'.tr() : 'delete'.tr()),
            ),
          ],
        ),
      );
      if (confirmed != true || !context.mounted) return;
      try {
        await runAdminAction(
          context,
          ref,
          () {
            final api = ref.read(adminApiProvider);
            return requeue
                ? api.requeueDlq(item.id)
                : api.discardDlq(item.id);
          },
        );
        ref.invalidate(adminDlqProvider);
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
              DropdownButton<String>(
                value: status.value,
                onChanged: (value) {
                  if (value != null) status.value = value;
                },
                items: [
                  DropdownMenuItem(
                    value: 'pending',
                    child: Text('adminPanel.report_pending'.tr()),
                  ),
                  DropdownMenuItem(
                    value: 'discarded',
                    child: Text('adminPanel.dlqDiscarded'.tr()),
                  ),
                ],
              ),
              const Spacer(),
              IconButton(
                tooltip: 'refresh'.tr(),
                onPressed: () => ref.invalidate(adminDlqProvider),
                icon: const Icon(Symbols.refresh_rounded),
              ),
            ],
          ),
        ),
        Expanded(
          child: items.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => Center(
              child: AdminErrorText(
                error: error,
                onRetry: () => ref.invalidate(adminDlqProvider),
              ),
            ),
            data: (rows) => rows.isEmpty
                ? Center(child: Text('adminPanel.dlqEmpty'.tr()))
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    itemCount: rows.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final item = rows[index];
                      final payload = item.payload == null
                          ? null
                          : jsonEncode(item.payload);
                      return Card(
                        elevation: 0,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      item.routingKey,
                                      style: const TextStyle(
                                        fontFamily: 'monospace',
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  Chip(
                                    label: Text(
                                      'adminPanel.dlqAttempts'.tr(
                                        args: ['${item.attempts}'],
                                      ),
                                    ),
                                    visualDensity: VisualDensity.compact,
                                  ),
                                  if (item.status == 'pending') ...[
                                    TextButton(
                                      onPressed: () =>
                                          act(item, requeue: true),
                                      child: Text('adminPanel.dlqRequeue'.tr()),
                                    ),
                                    TextButton(
                                      onPressed: () =>
                                          act(item, requeue: false),
                                      child: Text('adminPanel.dlqDiscard'.tr()),
                                    ),
                                  ],
                                ],
                              ),
                              if (item.reason != null &&
                                  item.reason!.isNotEmpty)
                                Text(
                                  item.reason!,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              if (item.createdAt != null)
                                Text(
                                  item.createdAt!,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              if (payload != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: Text(
                                    payload,
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(fontFamily: 'monospace'),
                                  ),
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
