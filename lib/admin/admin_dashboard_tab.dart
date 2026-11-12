import 'dart:math' as math;
import 'package:easy_localization/easy_localization.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:island/admin/admin_pod.dart';
import 'package:island/admin/admin_widgets.dart';
import 'package:island/core/api/admin_api.dart';

class AdminDashboardTab extends ConsumerWidget {
  const AdminDashboardTab({super.key, required this.onOpen});
  final ValueChanged<String> onOpen;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(adminMeProvider).value;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        AdminSection(
          title: 'adminMore.dashboard'.tr(),
          value: ref.watch(adminStatsProvider),
          onRetry: () => ref.invalidate(adminStatsProvider),
          builder: (stats) => Wrap(
            spacing: 16,
            runSpacing: 12,
            children: [
              for (final item in [
                ('users', stats.users),
                ('posts', stats.posts),
                ('files', stats.files),
                ('pendingFiles', stats.pendingFiles),
              ])
                SizedBox(
                  width: 160,
                  child: ListTile(
                    title: Text('${item.$2}'),
                    subtitle: Text('adminMore.${item.$1}'.tr()),
                  ),
                ),
            ],
          ),
        ),
        AdminSection(
          title: 'adminMore.trend'.tr(),
          value: ref.watch(adminTrendProvider),
          onRetry: () => ref.invalidate(adminTrendProvider),
          builder: (days) {
            if (days.isEmpty) return Text('adminMore.empty'.tr());
            final maxCount = days.fold<int>(
              1,
              (m, d) => math.max(m, math.max(d.users, d.posts)),
            );
            final color = Theme.of(context).colorScheme;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('adminMore.trendLegend'.tr()),
                for (final day in days)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(
                      children: [
                        SizedBox(width: 95, child: Text(day.date)),
                        Expanded(
                          child: Column(
                            children: [
                              LinearProgressIndicator(
                                value: day.users / maxCount,
                                color: color.primary,
                                minHeight: 6,
                              ),
                              const SizedBox(height: 3),
                              LinearProgressIndicator(
                                value: day.posts / maxCount,
                                color: color.tertiary,
                                minHeight: 6,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 90,
                          child: Text(
                            '${day.users} / ${day.posts}',
                            textAlign: TextAlign.end,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
        AdminSection(
          title: 'adminMore.reviewSummary'.tr(),
          value: ref.watch(adminReviewSummaryProvider),
          onRetry: () => ref.invalidate(adminReviewSummaryProvider),
          builder: (summary) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('adminMore.totalPending'.tr(args: ['${summary.total}'])),
              for (final queue in summary.queues)
                Builder(
                  builder: (context) {
                    final target = switch (queue.key) {
                      'files' when me?.can('files.review') == true =>
                        'adminPanel.tabFiles',
                      'reports' when me?.can('admin.reports_view') == true =>
                        'adminPanel.tabReports',
                      'admission_users'
                          when me?.can('admin.users_review') == true =>
                        'adminMore.admission',
                      _ => null,
                    };
                    const knownQueues = {
                      'files',
                      'reports',
                      'board_applications',
                      'column_applications',
                      'project_applications',
                      'admission_users',
                    };
                    return ListTile(
                      title: Text(
                        knownQueues.contains(queue.key)
                            ? 'adminMore.queue_${queue.key}'.tr()
                            : queue.key,
                      ),
                      subtitle: queue.waitingSeconds == null
                          ? null
                          : Text(
                              'adminMore.waiting'.tr(
                                args: ['${queue.waitingSeconds! ~/ 3600}'],
                              ),
                            ),
                      trailing: Text('${queue.count}'),
                      onTap: target == null ? null : () => onOpen(target),
                    );
                  },
                ),
            ],
          ),
        ),
        if (me?.can('admin.users_manage') == true)
          AdminSection(
            title: 'adminMore.latestUsers'.tr(),
            value: ref.watch(adminRecentUsersProvider),
            onRetry: () => ref.invalidate(adminRecentUsersProvider),
            onOpen: () => onOpen('adminMore.users'),
            builder: (data) => _recent(
              data.items.map((u) => (u.username, u.createdAt)).toList(),
              () => onOpen('adminMore.users'),
            ),
          ),
        if (me?.can('admin.content_review') == true)
          AdminSection(
            title: 'adminMore.latestPosts'.tr(),
            value: ref.watch(adminRecentContentProvider),
            onRetry: () => ref.invalidate(adminRecentContentProvider),
            onOpen: () => onOpen('adminPanel.tabContent'),
            builder: (data) => _recent(
              data.items.map((u) => (u.title, u.createdAt)).toList(),
              () => onOpen('adminPanel.tabContent'),
            ),
          ),
        if (me?.can('admin.reports_view') == true)
          AdminSection(
            title: 'adminMore.latestReports'.tr(),
            value: ref.watch(adminRecentReportsProvider),
            onRetry: () => ref.invalidate(adminRecentReportsProvider),
            onOpen: () => onOpen('adminPanel.tabReports'),
            builder: (data) => _recent(
              data.items.map((u) => (u.targetTitle, u.createdAt)).toList(),
              () => onOpen('adminPanel.tabReports'),
            ),
          ),
      ],
    );
  }

  Widget _recent(List<(String, DateTime)> items, VoidCallback open) =>
      items.isEmpty
      ? Text('adminMore.empty'.tr())
      : Column(
          children: [
            for (final item in items)
              ListTile(
                title: Text(item.$1),
                subtitle: Text(adminDate(item.$2)),
                onTap: open,
              ),
          ],
        );
}
