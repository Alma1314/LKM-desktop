import 'package:auto_route/auto_route.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';

import 'package:island/core/api/api_providers.dart';
import 'package:island/core/api/points_api.dart';
import 'package:island/points/points_pod.dart';
import 'package:island/route.gr.dart';
import 'package:island/shared/hooks/material_hooks.dart';
import 'package:island/shared/widgets/alert.dart';
import 'package:island/shared/widgets/app_scaffold.dart';

/// Points hub aligned with the website's contribution page: achievements,
/// ledger, leaderboard, exchange list and the daily check-in plus tasks.
@RoutePage()
class PointsScreen extends HookConsumerWidget {
  const PointsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = useMaterialTabController(initialLength: 5);

    void refreshAll() {
      ref.invalidate(lkmPointsBalanceProvider);
      ref.invalidate(lkmPointsLedgerProvider);
      ref.invalidate(lkmPointsAchievementsProvider);
      ref.invalidate(lkmPointsTasksProvider);
      ref.invalidate(lkmPointsExchangeProvider);
      ref.invalidate(lkmPointsLeaderboardProvider);
    }

    return AppScaffold(
      isNoBackground: false,
      appBar: AppBar(
        leading: const AutoLeadingButton(),
        title: Text('contribution.title'.tr()),
        actions: [
          IconButton(
            tooltip: 'refresh'.tr(),
            onPressed: refreshAll,
            icon: const Icon(Symbols.refresh_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          const _BalanceHeader(),
          TabBar(
            controller: controller,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(
                icon: const Icon(Symbols.emoji_events),
                text: 'contribution.tabAchievements'.tr(),
              ),
              Tab(
                icon: const Icon(Symbols.paid),
                text: 'contribution.tabPoints'.tr(),
              ),
              Tab(
                icon: const Icon(Symbols.bar_chart),
                text: 'contribution.tabLeaderboard'.tr(),
              ),
              Tab(
                icon: const Icon(Symbols.card_giftcard),
                text: 'contribution.tabExchange'.tr(),
              ),
              Tab(
                icon: const Icon(Symbols.checklist),
                text: 'contribution.tabTasks'.tr(),
              ),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: controller,
              children: const [
                _AchievementsTab(),
                _LedgerTab(),
                _LeaderboardTab(),
                _ExchangeTab(),
                _TasksTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BalanceHeader extends ConsumerWidget {
  const _BalanceHeader();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final signedIn = ref.watch(lkmApiSessionProvider).isSignedIn;
    final balance = ref.watch(lkmPointsBalanceProvider);
    final me = balance.value;

    LkmPointsLeaderboardEntry? myEntry;
    if (signedIn && me != null) {
      final board = ref.watch(lkmPointsLeaderboardProvider('weekly')).value;
      for (final entry in board?.items ?? const <LkmPointsLeaderboardEntry>[]) {
        if (entry.userId == me.userId) {
          myEntry = entry;
          break;
        }
      }
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
      child: Row(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: theme.colorScheme.primaryContainer,
            child: const Icon(Symbols.paid),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'contribution.currentPoints'.tr(),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                Row(
                  children: [
                    Text(
                      signedIn ? '${me?.balance ?? 0}' : '—',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    if (myEntry != null && myEntry.title.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          'contributionData.leaderboard.titles.${myEntry.title}'
                              .tr(),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onPrimaryContainer,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          if (!signedIn)
            TextButton(
              onPressed: () => context.router.push(LoginRoute()),
              child: Text('login'.tr()),
            ),
        ],
      ),
    );
  }
}

class _AchievementsTab extends ConsumerWidget {
  const _AchievementsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final signedIn = ref.watch(lkmApiSessionProvider).isSignedIn;
    if (!signedIn) return const _LoginRequired();

    final achievements = ref.watch(lkmPointsAchievementsProvider);
    return _AsyncBody(
      value: achievements,
      onRetry: () => ref.invalidate(lkmPointsAchievementsProvider),
      builder: (items) => items.isEmpty
          ? const _EmptyHint()
          : GridView.builder(
              padding: const EdgeInsets.all(16),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 220,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 0.82,
              ),
              itemCount: items.length,
              itemBuilder: (_, index) => _AchievementCard(item: items[index]),
            ),
    );
  }
}

class _AchievementCard extends StatelessWidget {
  const _AchievementCard({required this.item});

  final LkmPointsAchievement item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final unlocked = item.unlocked;

    return Opacity(
      opacity: unlocked ? 1 : 0.55,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
        child: Column(
          children: [
            CircleAvatar(
              backgroundColor: unlocked
                  ? theme.colorScheme.primaryContainer
                  : theme.colorScheme.surfaceContainerHighest,
              child: Icon(
                _achievementIcon(item.icon),
                color: unlocked
                    ? theme.colorScheme.onPrimaryContainer
                    : muted,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              item.nameKey.tr(),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Expanded(
              child: Text(
                item.descKey.tr(),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(color: muted),
              ),
            ),
            if (!unlocked) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: item.progressRatio,
                  minHeight: 4,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${item.progress}/${item.threshold}',
                style: theme.textTheme.labelSmall?.copyWith(color: muted),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _LedgerTab extends ConsumerWidget {
  const _LedgerTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final signedIn = ref.watch(lkmApiSessionProvider).isSignedIn;
    if (!signedIn) return const _LoginRequired();

    final ledger = ref.watch(lkmPointsLedgerProvider);
    return _AsyncBody(
      value: ledger,
      onRetry: () => ref.invalidate(lkmPointsLedgerProvider),
      builder: (page) => page.items.isEmpty
          ? const _EmptyHint()
          : ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: page.items.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (_, index) =>
                  _LedgerRow(entry: page.items[index]),
            ),
    );
  }
}

class _LedgerRow extends StatelessWidget {
  const _LedgerRow({required this.entry});

  final LkmPointsLedgerEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final positive = entry.delta > 0;
    final key = kPointsLogKeys[entry.reason];

    return ListTile(
      title: Text(key == null ? entry.reason : 'contributionData.pointLogs.$key'.tr()),
      subtitle: Text(_formatLedgerTime(entry.createdAt)),
      trailing: Text(
        '${positive ? '+' : ''}${entry.delta}',
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
          color: positive ? Colors.green : theme.colorScheme.error,
        ),
      ),
    );
  }
}

const _periods = ['daily', 'weekly', 'total'];

class _LeaderboardTab extends HookConsumerWidget {
  const _LeaderboardTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final period = useState('weekly');
    final board = ref.watch(lkmPointsLeaderboardProvider(period.value));

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: SegmentedButton<String>(
            segments: [
              for (final p in _periods)
                ButtonSegment(
                  value: p,
                  label: Text('contribution.period${_periodSuffix(p)}'.tr()),
                ),
            ],
            selected: {period.value},
            onSelectionChanged: (selection) => period.value = selection.first,
          ),
        ),
        Expanded(
          child: _AsyncBody(
            value: board,
            onRetry: () =>
                ref.invalidate(lkmPointsLeaderboardProvider(period.value)),
            builder: (page) => page.items.isEmpty
                ? const _EmptyHint()
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: page.items.length,
                    itemBuilder: (_, index) => _LeaderboardRow(
                      entry: page.items[index],
                      rank: index + 1,
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  static String _periodSuffix(String period) => switch (period) {
    'daily' => 'Daily',
    'weekly' => 'Weekly',
    _ => 'Total',
  };
}

class _LeaderboardRow extends StatelessWidget {
  const _LeaderboardRow({required this.entry, required this.rank});

  final LkmPointsLeaderboardEntry entry;
  final int rank;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final medal = switch (rank) {
      1 => '🥇',
      2 => '🥈',
      3 => '🥉',
      _ => '$rank',
    };

    return ListTile(
      onTap: entry.userId.isEmpty
          ? null
          : () => context.router.push(UserProfileRoute(id: entry.userId)),
      leading: SizedBox(
        width: 40,
        child: Center(
          child: Text(medal, style: theme.textTheme.titleMedium),
        ),
      ),
      title: Text(
        entry.displayName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: entry.title.isEmpty
          ? null
          : Text('contributionData.leaderboard.titles.${entry.title}'.tr()),
      trailing: Text(
        'contribution.pointsSuffix'.tr(
          namedArgs: {'points': '${entry.balance}'},
        ),
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _ExchangeTab extends ConsumerWidget {
  const _ExchangeTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(lkmPointsExchangeProvider);
    return _AsyncBody(
      value: items,
      onRetry: () => ref.invalidate(lkmPointsExchangeProvider),
      builder: (list) => list.isEmpty
          ? const _EmptyHint()
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: list.length,
              itemBuilder: (_, index) => _ExchangeCard(item: list[index]),
            ),
    );
  }
}

class _ExchangeCard extends StatelessWidget {
  const _ExchangeCard({required this.item});

  final LkmPointsExchangeItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Chip(
                label: Text(
                  item.isVirtual
                      ? 'contribution.virtual'.tr()
                      : 'contribution.physical'.tr(),
                ),
                visualDensity: VisualDensity.compact,
              ),
              if (item.lowStock) ...[
                const SizedBox(width: 8),
                Text(
                  'contribution.lowStock'.tr(
                    namedArgs: {'stock': '${item.stock}'},
                  ),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Text(
            item.nameKey.tr(),
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            item.descKey.tr(),
            style: theme.textTheme.bodySmall?.copyWith(color: muted),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  'contribution.pointsCost'.tr(
                    namedArgs: {'points': '${item.pointsCost}'},
                  ),
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              FilledButton.tonal(
                onPressed: item.soldOut
                    ? null
                    : () => showInfoAlert(
                        'contribution.exchangeUnavailable'.tr(),
                        'contribution.title'.tr(),
                      ),
                child: Text(
                  item.soldOut
                      ? 'contribution.soldOut'.tr()
                      : 'contribution.exchange'.tr(),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TasksTab extends HookConsumerWidget {
  const _TasksTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Hooks must run before any conditional return.
    final busy = useState(false);
    final signedIn = ref.watch(lkmApiSessionProvider).isSignedIn;
    if (!signedIn) return const _LoginRequired();

    final tasks = ref.watch(lkmPointsTasksProvider);

    return _AsyncBody(
      value: tasks,
      onRetry: () => ref.invalidate(lkmPointsTasksProvider),
      builder: (list) {
        LkmPointsTask? checkinTask;
        for (final task in list) {
          if (task.category == 'checkin') {
            checkinTask = task;
            break;
          }
        }
        final checkedIn = checkinTask?.completed ?? false;
        final reward = checkinTask?.rewardPoints ?? 5;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _CheckinCard(
              checkedIn: checkedIn,
              reward: reward,
              busy: busy.value,
              onCheckin: () async {
                if (busy.value) return;
                busy.value = true;
                try {
                  final session = ref.read(lkmApiSessionProvider);
                  final result = await session.run(
                    () => ref.read(pointsApiProvider).checkin(),
                  );
                  if (context.mounted) {
                    showSnackBar(
                      result.earned > 0
                          ? 'contribution.checkinSuccess'.tr(
                              namedArgs: {'points': '${result.earned}'},
                            )
                          : 'contribution.checkedIn'.tr(),
                    );
                  }
                  ref.invalidate(lkmPointsBalanceProvider);
                  ref.invalidate(lkmPointsLedgerProvider);
                  ref.invalidate(lkmPointsTasksProvider);
                  ref.invalidate(lkmPointsAchievementsProvider);
                  ref.invalidate(lkmPointsLeaderboardProvider);
                } catch (failure) {
                  if (context.mounted) showErrorAlert(failure);
                } finally {
                  busy.value = false;
                }
              },
            ),
            const SizedBox(height: 16),
            Text(
              'contribution.dailyTasks'.tr(),
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            for (final task in list) _TaskRow(task: task),
          ],
        );
      },
    );
  }
}

class _CheckinCard extends StatelessWidget {
  const _CheckinCard({
    required this.checkedIn,
    required this.reward,
    required this.busy,
    required this.onCheckin,
  });

  final bool checkedIn;
  final int reward;
  final bool busy;
  final VoidCallback onCheckin;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        children: [
          const Text('📅', style: TextStyle(fontSize: 36)),
          const SizedBox(height: 8),
          Text(
            'contribution.dailyCheckin'.tr(),
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: checkedIn || busy ? null : onCheckin,
            child: Text(
              checkedIn
                  ? 'contribution.checkedIn'.tr()
                  : 'contribution.checkinReward'.tr(
                      namedArgs: {'points': '$reward'},
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TaskRow extends StatelessWidget {
  const _TaskRow({required this.task});

  final LkmPointsTask task;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: task.completed
            ? theme.colorScheme.primaryContainer.withValues(alpha: 0.35)
            : theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Row(
        children: [
          Icon(
            task.completed
                ? Symbols.check_circle
                : Symbols.radio_button_unchecked,
            color: task.completed ? Colors.green : muted,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task.titleKey.tr(),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    decoration: task.completed
                        ? TextDecoration.lineThrough
                        : null,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${task.descKey.tr()} · '
                  '${'contribution.taskReward'.tr(namedArgs: {'points': '${task.rewardPoints}'})}',
                  style: theme.textTheme.bodySmall?.copyWith(color: muted),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: task.progressRatio,
                          minHeight: 4,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${task.currentProgress}/${task.requirementCount}',
                      style: theme.textTheme.labelSmall?.copyWith(color: muted),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _formatLedgerTime(DateTime time) {
  final local = time.toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}

/// Maps the server's Tabler icon names onto the bundled Material symbols.
IconData _achievementIcon(String icon) => switch (icon) {
  'tabler:star' => Symbols.star,
  'tabler:pencil' => Symbols.edit,
  'tabler:pencil-plus' => Symbols.note_add,
  'tabler:star-filled' => Symbols.grade,
  'tabler:writing' => Symbols.draw,
  'tabler:heart-handshake' => Symbols.handshake,
  'tabler:brain' => Symbols.psychology,
  'tabler:file-check' => Symbols.task,
  'tabler:calendar-check' => Symbols.event_available,
  'tabler:calendar-star' => Symbols.event,
  'tabler:rocket' => Symbols.rocket_launch,
  'tabler:article' => Symbols.article,
  _ => Symbols.emoji_events,
};

class _AsyncBody<T> extends StatelessWidget {
  const _AsyncBody({
    required this.value,
    required this.builder,
    this.onRetry,
  });

  final AsyncValue<T> value;
  final Widget Function(T data) builder;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    if (value.hasError) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'contribution.loadFailed'.tr(),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 8),
              TextButton(onPressed: onRetry, child: Text('refresh'.tr())),
            ],
          ],
        ),
      );
    }
    final data = value.value;
    if (data == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return builder(data);
  }
}

class _LoginRequired extends StatelessWidget {
  const _LoginRequired();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('contribution.loginRequired'.tr()),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => context.router.push(LoginRoute()),
              child: Text('login'.tr()),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        'contribution.empty'.tr(),
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
