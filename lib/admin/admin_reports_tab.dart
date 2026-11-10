import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';

import 'package:island/admin/admin_pod.dart';
import 'package:island/admin/admin_widgets.dart';

/// `/admin/reports`: the read-only report queue. The backend exposes no
/// resolve/dismiss write endpoint, so this page intentionally has no actions.
class AdminReportsTab extends HookConsumerWidget {
  const AdminReportsTab({super.key});

  static const _statuses = <String?>[null, 'pending', 'resolved', 'dismissed'];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final page = useState(1);
    final status = useState<String?>('pending');
    final result = ref.watch(
      adminReportsProvider((page: page.value, status: status.value)),
    );
    final theme = Theme.of(context);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              DropdownButton<String?>(
                value: status.value,
                onChanged: (value) {
                  status.value = value;
                  page.value = 1;
                },
                items: [
                  for (final value in _statuses)
                    DropdownMenuItem(
                      value: value,
                      child: Text(
                        value == null
                            ? 'all'.tr()
                            : 'adminPanel.report_$value'.tr(),
                      ),
                    ),
                ],
              ),
              const Spacer(),
              IconButton(
                tooltip: 'refresh'.tr(),
                onPressed: () => ref.invalidate(adminReportsProvider),
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
                onRetry: () => ref.invalidate(adminReportsProvider),
              ),
            ),
            data: (data) => data.items.isEmpty
                ? Center(child: Text('adminPanel.reportEmpty'.tr()))
                : Column(
                    children: [
                      Expanded(
                        child: ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                          itemCount: data.items.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final report = data.items[index];
                            return Card(
                              elevation: 0,
                              child: ListTile(
                                leading: Icon(
                                  report.status == 'pending'
                                      ? Symbols.flag
                                      : Symbols.flag_check,
                                  color: report.status == 'pending'
                                      ? theme.colorScheme.error
                                      : theme.colorScheme.onSurfaceVariant,
                                ),
                                title: Text(
                                  report.targetTitle.isEmpty
                                      ? report.targetId
                                      : report.targetTitle,
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
                                          'adminPanel.report_${report.status}'.tr(),
                                        ),
                                        visualDensity: VisualDensity.compact,
                                      ),
                                      Text(report.type),
                                      Text(
                                        'adminPanel.reportBy'.tr(
                                          args: [report.reporterName],
                                        ),
                                      ),
                                      Text(adminDate(report.createdAt)),
                                    ],
                                  ),
                                ),
                                isThreeLine: true,
                                trailing: SizedBox(
                                  width: 220,
                                  child: Text(
                                    report.reason,
                                    textAlign: TextAlign.end,
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodySmall,
                                  ),
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
