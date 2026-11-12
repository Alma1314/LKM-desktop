import 'package:auto_route/auto_route.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';

import 'package:island/community/content_detail_pod.dart';
import 'package:island/core/api/api_providers.dart';
import 'package:island/core/theme.dart';
import 'package:island/exam/exam_pod.dart';
import 'package:island/hub/hub_pod.dart';
import 'package:island/points/points_pod.dart';
import 'package:island/route.gr.dart';

class DashboardEntry {
  const DashboardEntry(this.title, this.subtitleKey, this.args, this.route);
  final String title;
  final String subtitleKey;
  final List<String> args;
  final PageRouteInfo route;
}

/// Each section owns its request/error/retry; a failure never hides the rest.
final dashboardEntriesProvider = FutureProvider.autoDispose
    .family<List<DashboardEntry>, String>((ref, kind) async {
      final session = ref.watch(lkmApiSessionProvider);
      final now = DateTime.now();
      switch (kind) {
        case 'questions':
          // ponytail: rank/filter one 50-row page; use server-side eligibility
          // filters if the service later exposes them.
          final page = await session.run(
            () => ref.watch(qaApiProvider).questions(sort: 'bounty', limit: 50),
          );
          return page.items
              .where(
                (q) =>
                    q.isOpen &&
                    q.bountyTotal > q.bountyDistributed &&
                    (q.bountyExpiresAt == null ||
                        q.bountyExpiresAt!.isAfter(now)),
              )
              .take(5)
              .map(
                (q) => DashboardEntry(q.title, 'home.bounty', [
                  '${q.bountyTotal - q.bountyDistributed}',
                  q.authorName,
                ], QaDetailRoute(id: q.id)),
              )
              .toList();
        case 'projects':
          final projects = await ref.watch(projectsProvider.future);
          final recruiting = projects.where((p) => p.isRecruiting).toList()
            ..sort(
              (a, b) => (b.isPinned ? 1 : 0).compareTo(a.isPinned ? 1 : 0),
            );
          return recruiting
              .take(5)
              .map(
                (p) => DashboardEntry(p.title, 'home.projectDetail', [
                  p.summary,
                  p.recruitingRoles.join(' / '),
                ], ProjectDetailRoute(id: p.id)),
              )
              .toList();
        case 'columns':
          final page = await session.run(
            () => ref
                .watch(contentApiProvider)
                .items(contentType: 'column_post', pageSize: 50),
          );
          final featured = page.items.where((p) => p.isFeatured).toList()
            ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
          return featured
              .take(5)
              .map(
                (p) => DashboardEntry(p.title, 'home.columnDetail', [
                  p.columnTitle,
                  p.authorName,
                ], ContentDetailRoute(id: p.id)),
              )
              .toList();
        case 'competitions':
          final page = await ref.watch(examsProvider('competition').future);
          return page.items
              .where(
                (e) =>
                    e.isPublished &&
                    (e.endsAt == null || e.endsAt!.isAfter(now)),
              )
              .take(5)
              .map(
                (e) => DashboardEntry(
                  e.title,
                  e.startsAt != null && e.startsAt!.isAfter(now)
                      ? 'home.competitionUpcoming'
                      : 'home.competitionOpen',
                  [e.subject, '${e.timeLimitMin}'],
                  ExamDetailRoute(id: e.id),
                ),
              )
              .toList();
        default:
          throw ArgumentError.value(kind, 'kind');
      }
    });

class CommunityDashboardCard extends ConsumerWidget {
  const CommunityDashboardCard({super.key, required this.kind});
  final String kind;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (IconData icon, PageRouteInfo route) = switch (kind) {
      'questions' => (Symbols.help_center, HubRoute()),
      'projects' => (Symbols.rocket_launch, HubRoute(initialTab: 2)),
      'columns' => (Symbols.article, HubRoute(initialTab: 1)),
      _ => (Symbols.trophy, const ExamHallRoute()),
    };
    void refresh() {
      ref.invalidate(dashboardEntriesProvider(kind));
      if (kind == 'projects') ref.invalidate(projectsProvider);
      if (kind == 'competitions') ref.invalidate(examsProvider('competition'));
    }

    return _DashboardSection(
      title: 'home.$kind'.tr(),
      icon: icon,
      onRefresh: refresh,
      onOpen: () => context.router.push(route),
      child: _DashboardValue(
        value: ref.watch(dashboardEntriesProvider(kind)),
        onRetry: refresh,
        builder: (entries) => entries.isEmpty
            ? _Hint('home.empty'.tr())
            : Column(
                children: [
                  for (final entry in entries)
                    ListTile(
                      title: Text(
                        entry.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        entry.subtitleKey.tr(args: entry.args),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: const Icon(Symbols.chevron_right, size: 18),
                      onTap: () => context.router.push(entry.route),
                    ),
                ],
              ),
      ),
    );
  }
}

class PersonalDashboardCard extends ConsumerWidget {
  const PersonalDashboardCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final balance = ref.watch(lkmPointsBalanceProvider);
    final certificates = ref.watch(myCertificatesProvider);
    return _DashboardSection(
      title: 'home.personal'.tr(),
      icon: Symbols.account_circle,
      onRefresh: () {
        ref.invalidate(lkmPointsBalanceProvider);
        ref.invalidate(myCertificatesProvider);
      },
      onOpen: () => context.router.push(const MyContentRoute()),
      child: Column(
        children: [
          _DashboardValue(
            value: balance,
            onRetry: () => ref.invalidate(lkmPointsBalanceProvider),
            builder: (data) => ListTile(
              leading: const Icon(Symbols.paid),
              title: Text(data == null ? '—' : '${data.balance}'),
              subtitle: Text('contribution.currentPoints'.tr()),
              onTap: () => context.router.push(const PointsRoute()),
            ),
          ),
          _DashboardValue(
            value: certificates,
            onRetry: () => ref.invalidate(myCertificatesProvider),
            builder: (data) => ListTile(
              leading: const Icon(Symbols.workspace_premium),
              title: Text('${data.where((c) => c.passed).length}'),
              subtitle: Text('home.certificates'.tr()),
              onTap: () => context.router.push(const ExamHallRoute()),
            ),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              TextButton(
                onPressed: () => context.router.push(const StarHopeRoute()),
                child: const Text('StarHope'),
              ),
              TextButton(
                onPressed: () => context.router.push(const LibraryRoute()),
                child: Text('home.files'.tr()),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class DashboardLeaderboardCard extends ConsumerWidget {
  const DashboardLeaderboardCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = lkmPointsLeaderboardProvider('weekly');
    return _DashboardSection(
      title: 'home.leaderboard'.tr(),
      icon: Symbols.bar_chart,
      onRefresh: () => ref.invalidate(provider),
      onOpen: () => context.router.push(const PointsRoute()),
      child: _DashboardValue(
        value: ref.watch(provider),
        onRetry: () => ref.invalidate(provider),
        builder: (page) => page.items.isEmpty
            ? _Hint('home.empty'.tr())
            : Column(
                children: [
                  for (final (index, user) in page.items.take(5).indexed)
                    ListTile(
                      leading: Text('${index + 1}'),
                      title: Text(
                        user.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: Text('${user.balance}'),
                      onTap: () => context.router.push(
                        UserProfileRoute(id: user.userId),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}

/// Uses the upstream dashboard's card surface, spacing and typography.
class _DashboardSection extends StatelessWidget {
  const _DashboardSection({
    required this.title,
    required this.icon,
    required this.onRefresh,
    required this.onOpen,
    required this.child,
  });
  final String title;
  final IconData icon;
  final VoidCallback onRefresh;
  final VoidCallback onOpen;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      color: theme.colorScheme.surfaceContainerLow,
      elevation: 0,
      shadowColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(borderRadius: SolRadius.cardRadius),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              SolSpace.card,
              SolSpace.lg,
              8,
              8,
            ),
            child: Row(
              children: [
                Icon(icon, size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'refresh'.tr(),
                  onPressed: onRefresh,
                  icon: const Icon(Symbols.refresh, size: 20),
                ),
                IconButton(
                  tooltip: 'home.viewAll'.tr(),
                  onPressed: onOpen,
                  icon: const Icon(Symbols.arrow_forward, size: 20),
                ),
              ],
            ),
          ),
          child,
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

class _DashboardValue<T> extends StatelessWidget {
  const _DashboardValue({
    required this.value,
    required this.onRetry,
    required this.builder,
  });
  final AsyncValue<T> value;
  final VoidCallback onRetry;
  final Widget Function(T) builder;
  @override
  Widget build(BuildContext context) => value.when(
    skipLoadingOnRefresh: false,
    loading: () => const Padding(
      padding: EdgeInsets.all(24),
      child: Center(child: CircularProgressIndicator()),
    ),
    error: (_, _) => Column(
      children: [
        _Hint('home.loadFailed'.tr()),
        TextButton(onPressed: onRetry, child: Text('retry'.tr())),
      ],
    ),
    data: builder,
  );
}

class _Hint extends StatelessWidget {
  const _Hint(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(SolSpace.card),
    child: Text(
      text,
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
  );
}
