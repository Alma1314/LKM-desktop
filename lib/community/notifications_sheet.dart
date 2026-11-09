import 'package:easy_localization/easy_localization.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:url_launcher/url_launcher_string.dart';

import 'package:island/community/feed_links.dart';
import 'package:island/community/notification_pod.dart';
import 'package:island/core/api/api_providers.dart';
import 'package:island/core/api/notification_api.dart';
import 'package:island/shared/widgets/layouts/sheet_scaffold.dart';

/// The LKM-service notification inbox, opened from the community bell.
class LkmNotificationsSheet extends HookConsumerWidget {
  const LkmNotificationsSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifications = ref.watch(communityNotificationsProvider);
    final notifier = ref.read(communityNotificationsProvider.notifier);

    ref.listen(lkmWsEventsProvider, (_, next) {
      next.whenData((event) {
        if (event.event == 'notification_created') {
          notifier.refresh();
        }
      });
    });

    return SheetScaffold(
      titleText: 'notifications'.tr(),
      actions: [
        TextButton(
          onPressed: notifier.markAllRead,
          child: Text('notificationMarkAllRead'.tr()),
        ),
      ],
      child: notifications.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) =>
            _ErrorView(error: error, onRetry: notifier.refresh),
        data: (state) => state.items.isEmpty
            ? Center(
                child: Text(
                  'notificationEmpty'.tr(),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              )
            : _NotificationList(
                state: state,
                onOpen: (item) => _open(context, ref, item),
                onLoadMore: notifier.loadMore,
              ),
      ),
    );
  }
}

class _NotificationList extends StatelessWidget {
  const _NotificationList({
    required this.state,
    required this.onOpen,
    required this.onLoadMore,
  });

  final NotificationsState state;
  final void Function(LkmNotification) onOpen;
  final Future<void> Function() onLoadMore;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 24),
      itemCount: state.items.length + 1,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        if (index == state.items.length) {
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
          if (state.loadMoreError != null || state.hasMore) {
            return Center(
              child: TextButton(
                onPressed: onLoadMore,
                child: Text('feedLoadMore'.tr()),
              ),
            );
          }
          return const SizedBox.shrink();
        }

        final item = state.items[index];
        final title = item.payload['title'];
        return ListTile(
          onTap: () => onOpen(item),
          leading: Icon(
            _iconForType(item.type),
            color: item.isUnread
                ? theme.colorScheme.primary
                : theme.colorScheme.onSurfaceVariant,
          ),
          title: Text(
            title is String && title.isNotEmpty ? title : _typeLabel(item.type),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: item.isUnread
                ? const TextStyle(fontWeight: FontWeight.w600)
                : null,
          ),
          subtitle: Text(
            '${_typeLabel(item.type)} · ${_formatTime(item.createdAt)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: item.isUnread
              ? Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary,
                    shape: BoxShape.circle,
                  ),
                )
              : null,
        );
      },
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.error, required this.onRetry});

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

Future<void> _open(
  BuildContext context,
  WidgetRef ref,
  LkmNotification item,
) async {
  await ref.read(communityNotificationsProvider.notifier).markRead(item);
  final rawUrl = item.payload['url'];
  final target = resolveFeedUrl(
    rawUrl is String ? rawUrl : null,
    ref.read(lkmServerUrlProvider),
  );
  if (target != null) {
    await launchUrlString(target, mode: LaunchMode.externalApplication);
  }
}

IconData _iconForType(String type) => switch (type) {
  'content_liked' => Symbols.favorite_rounded,
  'content_commented' => Symbols.mode_comment_rounded,
  'comment_replied' => Symbols.reply_rounded,
  'qa_answer_accepted' => Symbols.check_circle_rounded,
  'review_digest' => Symbols.assignment_rounded,
  _ => Symbols.notifications_rounded,
};

String _typeLabel(String type) => switch (type) {
  'content_liked' => 'notificationTypeContentLiked'.tr(),
  'content_commented' => 'notificationTypeContentCommented'.tr(),
  'comment_replied' => 'notificationTypeCommentReplied'.tr(),
  'qa_answer_accepted' => 'notificationTypeQaAccepted'.tr(),
  'review_digest' => 'notificationTypeReviewDigest'.tr(),
  _ => type,
};

String _formatTime(DateTime date) {
  final iso = date.toIso8601String();
  return iso.substring(5, 16).replaceFirst('T', ' ');
}
