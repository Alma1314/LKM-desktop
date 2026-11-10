import 'package:auto_route/auto_route.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:url_launcher/url_launcher_string.dart';

import 'package:island/community/compose_sheet.dart';
import 'package:island/community/feed_links.dart';
import 'package:island/community/feed_pod.dart';
import 'package:island/community/notification_pod.dart';
import 'package:island/community/notifications_sheet.dart';
import 'package:island/community/search_sheet.dart';
import 'package:island/community/widgets/feed_item_card.dart';
import 'package:island/core/api/api_providers.dart';
import 'package:island/core/api/timeline_api.dart';
import 'package:island/route.gr.dart';
import 'package:island/shared/widgets/alert.dart';
import 'package:island/shared/widgets/app_scaffold.dart';

/// The community tab: LKM-service timeline with follow/hot modes.
@RoutePage()
class CommunityFeedScreen extends HookConsumerWidget {
  const CommunityFeedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feed = ref.watch(communityFeedProvider);
    final signedIn = ref.watch(lkmApiSessionProvider).isSignedIn;
    final unread = ref.watch(lkmUnreadNotificationsProvider).value ?? 0;
    final state = feed.value;
    final mode = state?.mode ?? (signedIn ? 'follow' : 'hot');
    final notifier = ref.read(communityFeedProvider.notifier);

    // A pushed notification moves the badge immediately; the inbox itself
    // refreshes when opened.
    ref.listen(lkmWsEventsProvider, (_, next) {
      next.whenData((event) {
        if (event.event == 'notification_created') {
          ref.invalidate(lkmUnreadNotificationsProvider);
        }
      });
    });

    return AppScaffold(
      isNoBackground: false,
      body: SafeArea(
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 8, 0),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'community'.tr(),
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                      ),
                      if (signedIn)
                        IconButton(
                          tooltip: 'lkmComposeTitle'.tr(),
                          onPressed: () async {
                            final id = await showModalBottomSheet<String>(
                              context: context,
                              isScrollControlled: true,
                              builder: (_) => const LkmComposeSheet(),
                            );
                            if (id == null) return;
                            await notifier.refresh();
                            if (context.mounted) {
                              context.router.push(
                                ContentDetailRoute(id: id),
                              );
                            }
                          },
                          icon: const Icon(Symbols.edit_square),
                        ),
                      IconButton(
                        tooltip: 'treehole'.tr(),
                        onPressed: () => context.router.push(TreeholeRoute()),
                        icon: const Icon(Symbols.forest),
                      ),
                      IconButton(
                        tooltip: 'contribution.title'.tr(),
                        onPressed: () => context.router.push(PointsRoute()),
                        icon: const Icon(Symbols.emoji_events),
                      ),
                      IconButton(
                        tooltip: 'hub.title'.tr(),
                        onPressed: () => context.router.push(HubRoute()),
                        icon: const Icon(Symbols.widgets),
                      ),
                      IconButton(
                        tooltip: 'search'.tr(),
                        onPressed: () => showModalBottomSheet<void>(
                          context: context,
                          isScrollControlled: true,
                          builder: (_) => const LkmSearchSheet(),
                        ),
                        icon: const Icon(Symbols.search),
                      ),
                      IconButton(
                        tooltip: 'notifications'.tr(),
                        onPressed: () => showModalBottomSheet<void>(
                          context: context,
                          isScrollControlled: true,
                          builder: (_) => const LkmNotificationsSheet(),
                        ),
                        icon: Badge.count(
                          count: unread,
                          isLabelVisible: unread > 0,
                          child: const Icon(Symbols.notifications_rounded),
                        ),
                      ),
                      IconButton(
                        tooltip: 'feedRefresh'.tr(),
                        onPressed: feed.isLoading ? null : notifier.refresh,
                        icon: const Icon(Symbols.refresh_rounded),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: SegmentedButton<String>(
                      segments: [
                        ButtonSegment(
                          value: 'follow',
                          label: Text('feedFollow'.tr()),
                          enabled: signedIn,
                          tooltip: signedIn ? null : 'feedLoginToFollow'.tr(),
                        ),
                        ButtonSegment(
                          value: 'hot',
                          label: Text('feedHot'.tr()),
                        ),
                      ],
                      selected: {mode},
                      onSelectionChanged: (selection) =>
                          notifier.switchMode(selection.first),
                    ),
                  ),
                ),
                Expanded(
                  child: feed.when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (error, _) =>
                        _FeedError(error: error, onRetry: notifier.refresh),
                    data: (state) => state.items.isEmpty
                        ? _FeedEmpty(onRefresh: notifier.refresh)
                        : _FeedList(
                            state: state,
                            onLoadMore: notifier.loadMore,
                            onRefresh: notifier.refresh,
                            onOpen: (item) => _openItem(context, ref, item),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FeedList extends StatelessWidget {
  const _FeedList({
    required this.state,
    required this.onLoadMore,
    required this.onRefresh,
    required this.onOpen,
  });

  final CommunityFeedState state;
  final Future<void> Function() onLoadMore;
  final Future<void> Function() onRefresh;
  final void Function(FeedItem) onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        itemCount: state.items.length + 1,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          if (index < state.items.length) {
            final item = state.items[index];
            return FeedItemCard(item: item, onTap: () => onOpen(item));
          }
          if (state.loadingMore) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            );
          }
          if (state.loadMoreError != null) {
            return Column(
              children: [
                Text(
                  'feedLoadFailed'.tr(),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
                TextButton(
                  onPressed: onLoadMore,
                  child: Text('feedLoadMore'.tr()),
                ),
              ],
            );
          }
          if (!state.hasMore) return const SizedBox.shrink();
          return Center(
            child: TextButton(
              onPressed: onLoadMore,
              child: Text('feedLoadMore'.tr()),
            ),
          );
        },
      ),
    );
  }
}

class _FeedEmpty extends StatelessWidget {
  const _FeedEmpty({required this.onRefresh});

  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'feedEmpty'.tr(),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          TextButton(onPressed: onRefresh, child: Text('feedRefresh'.tr())),
        ],
      ),
    );
  }
}

class _FeedError extends StatelessWidget {
  const _FeedError({required this.error, required this.onRetry});

  final Object error;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'feedLoadFailed'.tr(),
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '$error',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(onPressed: onRetry, child: Text('feedRetry'.tr())),
          ],
        ),
      ),
    );
  }
}

/// Feed sources that are rows of the unified `content_items` table and can be
/// read by id over GraphQL. `qa` and `project` live in their own tables, so
/// they keep opening the site URL.
bool _hasNativeDetail(String itemType) =>
    itemType == 'discussion' ||
    itemType == 'article' ||
    itemType == 'column' ||
    itemType == 'blog';

void _openItem(BuildContext context, WidgetRef ref, FeedItem item) {
  if (_hasNativeDetail(item.itemType)) {
    context.router.push(ContentDetailRoute(id: item.id));
    return;
  }
  final target = resolveFeedUrl(item.url, ref.read(lkmServerUrlProvider));
  if (target == null) {
    showSnackBar('feedNoLink'.tr());
    return;
  }
  launchUrlString(target, mode: LaunchMode.externalApplication);
}
