import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:island/admin/admin_pod.dart';
import 'package:island/admin/admin_widgets.dart';
import 'package:island/core/api/admin_api.dart';
import 'package:island/core/api/api_providers.dart';

const _sections = [
  'overview',
  'platforms',
  'providers',
  'config',
  'plugins',
  'knowledge',
  'logs/history',
];
const _routes = [
  '/',
  '/platforms',
  '/providers',
  '/config',
  '/plugins',
  '/knowledge-base',
  '/data/logs',
];
const _overviewFields = [
  'version',
  'dashboard_version',
  'platform_count',
  'provider_count',
  'plugin_count',
  'message_count',
  'cpu_percent',
  'memory_process_mb',
  'memory_system_mb',
  'thread_count',
];

class AdminBotTab extends HookConsumerWidget {
  const AdminBotTab({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final index = useState(0);
    final busy = useState(false);
    final error = useState<Object?>(null);
    final search = useTextEditingController();
    useListenable(search);
    final section = _sections[index.value];
    final result = ref.watch(adminBotProvider(section));

    Future<void> open(String route) async {
      if (busy.value) return;
      // Capture deployment before the async ticket request; switching servers
      // must never send that ticket to the newly selected origin.
      final api = ref.read(adminApiProvider);
      final server = ref.read(lkmServerUrlProvider);
      busy.value = true;
      error.value = null;
      try {
        final ticket = await api.botTicket();
        if (!context.mounted) return;
        final uri = adminBotPanelUri(server, ticket, route);
        if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
          throw StateError('adminMore.openFailed'.tr());
        }
      } catch (_) {
        // A launcher exception can contain its URL; never expose the ticket.
        if (context.mounted) error.value = 'adminMore.openFailed'.tr();
      } finally {
        if (context.mounted) busy.value = false;
      }
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              DropdownButton<int>(
                value: index.value,
                items: [
                  for (var i = 0; i < _sections.length; i++)
                    DropdownMenuItem(
                      value: i,
                      child: Text(
                        'adminMore.bot_${_sections[i].replaceAll('/', '_')}'
                            .tr(),
                      ),
                    ),
                ],
                onChanged: (i) {
                  if (i != null) {
                    index.value = i;
                    search.clear();
                    error.value = null;
                  }
                },
              ),
              IconButton(
                onPressed: () => ref.invalidate(adminBotProvider(section)),
                tooltip: 'refresh'.tr(),
                icon: const Icon(Symbols.refresh),
              ),
              FilledButton.icon(
                onPressed: busy.value ? null : () => open(_routes[index.value]),
                icon: const Icon(Symbols.open_in_new),
                label: Text('adminMore.editInBrowser'.tr()),
              ),
              if (section == 'logs/history')
                TextButton(
                  onPressed: busy.value ? null : () => open('/data/logs'),
                  child: Text('adminMore.liveLogs'.tr()),
                ),
              TextButton(
                onPressed: busy.value ? null : () => open('/settings'),
                child: Text('adminMore.botSettings'.tr()),
              ),
            ],
          ),
        ),
        if (busy.value) const LinearProgressIndicator(),
        if (error.value != null) AdminErrorText(error: error.value!),
        Expanded(
          child: result.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => AdminErrorText(
              error: e,
              onRetry: () => ref.invalidate(adminBotProvider(section)),
            ),
            data: (data) {
              if (!data.configured || !data.available)
                return Center(
                  child: Text(
                    (data.configured
                            ? 'adminMore.botUnavailable'
                            : 'adminMore.botUnconfigured')
                        .tr(),
                  ),
                );
              if (section == 'overview')
                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    for (final field in _overviewFields)
                      ListTile(
                        title: Text('adminMore.metric_$field'.tr()),
                        trailing: Text('${data.values[field] ?? '—'}'),
                      ),
                  ],
                );
              if (section == 'logs/history') {
                final q = search.text.trim().toLowerCase();
                final logs = data.items
                    .where(
                      (e) =>
                          q.isEmpty ||
                          '${e['data'] ?? ''} ${e['level'] ?? ''}'
                              .toLowerCase()
                              .contains(q),
                    )
                    .toList();
                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: TextField(
                        controller: search,
                        decoration: InputDecoration(
                          labelText: 'adminMore.searchLogs'.tr(),
                        ),
                      ),
                    ),
                    Expanded(
                      child: logs.isEmpty
                          ? Center(child: Text('adminMore.empty'.tr()))
                          : ListView.builder(
                              padding: const EdgeInsets.all(16),
                              itemCount: logs.length,
                              itemBuilder: (_, i) {
                                final e = logs[i];
                                return SelectableText(
                                  '[${e['level'] ?? 'INFO'}] ${e['data'] ?? ''}',
                                  style: const TextStyle(
                                    fontFamily: 'monospace',
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                );
              }
              return data.items.isEmpty
                  ? Center(child: Text('adminMore.empty'.tr()))
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: data.items.length,
                      itemBuilder: (_, i) {
                        final item = data.items[i];
                        return Card(
                          child: ListTile(
                            title: Text(
                              '${item['display_name'] ?? item['name'] ?? item['id'] ?? ''}',
                            ),
                            subtitle: SelectableText(
                              [
                                    item['id'],
                                    item['type'],
                                    item['model'],
                                    item['subtitle'],
                                  ]
                                  .where((v) => v != null && '$v'.isNotEmpty)
                                  .join('\n'),
                            ),
                            trailing: item['enabled'] is bool
                                ? Chip(
                                    label: Text(
                                      (item['enabled'] == true
                                              ? 'adminMore.enabled'
                                              : 'adminMore.disabled')
                                          .tr(),
                                    ),
                                  )
                                : null,
                          ),
                        );
                      },
                    );
            },
          ),
        ),
      ],
    );
  }
}
