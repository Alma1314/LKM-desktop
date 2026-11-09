import 'package:auto_route/auto_route.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:island/community/content_detail_pod.dart';
import 'package:island/community/feed_pod.dart';
import 'package:island/community/user_pod.dart';
import 'package:island/core/api/api_providers.dart';
import 'package:island/core/api/content_api.dart';
import 'package:island/route.gr.dart';
import 'package:island/shared/widgets/alert.dart';
import 'package:island/shared/widgets/app_scaffold.dart';
import 'package:island/shared/widgets/content/markdown.dart';

/// Native content detail: body over GraphQL, comments over GraphQL, posting
/// over the REST write endpoint.
@RoutePage()
class ContentDetailScreen extends HookConsumerWidget {
  const ContentDetailScreen({super.key, required this.id});

  final String id;

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text('deletePost'.tr()),
            content: Text('lkmDeletePostConfirm'.tr()),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: Text('cancel'.tr()),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: Text('delete'.tr()),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !context.mounted) return;
    try {
      await ref
          .read(lkmApiSessionProvider)
          .run(() => ref.read(contentApiProvider).deleteItem(id));
      ref.invalidate(communityFeedProvider);
      if (context.mounted) context.router.maybePop();
    } catch (error) {
      if (context.mounted) showSnackBar('$error');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final item = ref.watch(contentItemProvider(id));
    final authorId = item.value?.authorId;
    final myId = ref.watch(lkmMeProvider).value?.id;
    final isAuthor = authorId != null && myId != null && authorId == myId;

    return AppScaffold(
      isNoBackground: false,
      appBar: AppBar(
        leading: const AutoLeadingButton(),
        title: Text('contentDetail'.tr()),
        actions: [
          if (isAuthor)
            IconButton(
              tooltip: 'deletePost'.tr(),
              onPressed: () => _delete(context, ref),
              icon: const Icon(Symbols.delete),
            ),
        ],
      ),
      body: item.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _ErrorView(
          error: error,
          onRetry: () => ref.invalidate(contentItemProvider(id)),
        ),
        data: (item) => item == null
            ? Center(
                child: Text(
                  'contentNotFound'.tr(),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              )
            : _DetailBody(item: item),
      ),
    );
  }
}

class _DetailBody extends HookConsumerWidget {
  const _DetailBody({required this.item});

  final LkmContentItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final comments = ref.watch(contentCommentsProvider(item.id));
    final notifier = ref.read(contentCommentsProvider(item.id).notifier);
    final signedIn = ref.watch(lkmApiSessionProvider).isSignedIn;
    final controller = useTextEditingController();
    final muted = theme.colorScheme.onSurfaceVariant;

    // View bookkeeping is background accounting: silence every failure so a
    // permission quirk never interrupts someone reading the body.
    useEffect(() {
      if (!signedIn) return null;
      final session = ref.read(lkmApiSessionProvider);
      final api = ref.read(contentApiProvider);
      session.run(() => api.reportView(item.id)).ignore();
      return null;
    }, [item.id, signedIn]);

    Future<void> send() async {
      final text = controller.text.trim();
      if (text.isEmpty) return;
      controller.clear();
      await notifier.add(text);
      final failure = ref.read(contentCommentsProvider(item.id)).value?.error;
      if (failure != null && context.mounted) {
        showSnackBar(failure);
      }
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
      children: [
        Text(
          item.title,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: Row(
                children: [
                  if (item.authorName.isNotEmpty)
                    InkWell(
                      onTap: item.authorId == null
                          ? null
                          : () => context.router.push(
                              UserProfileRoute(id: item.authorId!),
                            ),
                      child: Text(
                        item.authorName,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: muted,
                        ),
                      ),
                    ),
                  Text(
                    ' · ${_formatDate(item.createdAt)}',
                    style: theme.textTheme.bodySmall?.copyWith(color: muted),
                  ),
                ],
              ),
            ),
            Icon(Symbols.visibility, size: 16, color: muted),
            const SizedBox(width: 4),
            Text(
              '${item.viewCount}',
              style: theme.textTheme.bodySmall?.copyWith(color: muted),
            ),
            const SizedBox(width: 12),
            Icon(Symbols.favorite, size: 16, color: muted),
            const SizedBox(width: 4),
            Text(
              '${item.likeCount}',
              style: theme.textTheme.bodySmall?.copyWith(color: muted),
            ),
          ],
        ),
        if (item.cover != null && item.cover!.isNotEmpty) ...[
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: CachedNetworkImage(
              imageUrl: item.cover!,
              height: 220,
              width: double.infinity,
              fit: BoxFit.cover,
              errorWidget: (_, _, _) => const SizedBox.shrink(),
            ),
          ),
        ],
        const Divider(height: 32),
        MarkdownTextContent(content: item.content, isSelectable: true),
        if (item.tags.isNotEmpty) ...[
          const SizedBox(height: 16),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final tag in item.tags)
                Chip(label: Text(tag), visualDensity: VisualDensity.compact),
            ],
          ),
        ],
        const Divider(height: 32),
        _ActionsRow(item: item, signedIn: signedIn),
        const Divider(height: 32),
        Text(
          '${'contentComments'.tr()} (${item.commentCount})',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        comments.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
          error: (error, _) =>
              _CommentError(error: error, onRetry: notifier.refresh),
          data: (state) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (state.items.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    'contentNoComments'.tr(),
                    style: theme.textTheme.bodySmall?.copyWith(color: muted),
                  ),
                ),
              for (final comment in state.items)
                _CommentTile(
                  comment: comment,
                  onToggleLike: signedIn
                      ? () => notifier.toggleCommentLike(comment.id)
                      : null,
                ),
              if (state.hasMore)
                Center(
                  child: TextButton(
                    onPressed: state.loadingMore ? null : notifier.loadMore,
                    child: Text('feedLoadMore'.tr()),
                  ),
                ),
              if (state.error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    state.error!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (signedIn)
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  minLines: 1,
                  maxLines: 4,
                  decoration: InputDecoration(
                    hintText: 'contentCommentHint'.tr(),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                tooltip: 'contentCommentSend'.tr(),
                onPressed: send,
                icon: const Icon(Symbols.send_rounded),
              ),
            ],
          )
        else
          Text(
            'contentLoginToComment'.tr(),
            style: theme.textTheme.bodySmall?.copyWith(color: muted),
          ),
      ],
    );
  }
}

/// Like / favorite / forward / report, mirroring the website's actions row.
/// Likes and favorites need a signed-in session (the backend gates them);
/// tapping while signed out leads to the login screen instead of failing.
class _ActionsRow extends HookConsumerWidget {
  const _ActionsRow({required this.item, required this.signedIn});

  final LkmContentItem item;
  final bool signedIn;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final viewer = ref.watch(contentViewerProvider(item));
    final notifier = ref.read(contentViewerProvider(item).notifier);
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;

    void requireLogin(VoidCallback action) {
      if (signedIn) {
        action();
      } else {
        context.router.push(LoginRoute());
      }
    }

    Future<void> share() async {
      final host = ref.read(lkmServerUrlProvider);
      await Clipboard.setData(
        ClipboardData(text: '$host/forum/post/${item.id}'),
      );
      if (!context.mounted) return;
      showSnackBar('copiedToClipboard'.tr());
      try {
        await notifier.forward();
      } catch (_) {
        // The link is already on the clipboard; a failed count bump is not
        // worth an error toast.
      }
    }

    Future<void> report() async {
      const reasonKeys = [
        'abuseReportTypeInappropriate',
        'abuseReportTypeOffensiveContent',
        'abuseReportTypeHarassment',
        'abuseReportTypeCopyright',
        'abuseReportTypeOther',
      ];
      final reason = await showDialog<String>(
        context: context,
        builder: (dialogContext) => SimpleDialog(
          title: Text('abuseReportTitle'.tr()),
          children: [
            for (final key in reasonKeys)
              SimpleDialogOption(
                onPressed: () => Navigator.of(dialogContext).pop(key.tr()),
                child: Text(key.tr()),
              ),
          ],
        ),
      );
      if (reason == null || !context.mounted) return;
      try {
        await ref.read(lkmApiSessionProvider).run(
          () => ref
              .read(contentApiProvider)
              .report(targetType: 'post', targetId: item.id, reason: reason),
        );
        if (context.mounted) showSnackBar('abuseReportSuccess'.tr());
      } catch (error) {
        if (context.mounted) showSnackBar('$error');
      }
    }

    Widget action(
      IconData icon,
      String label, {
      Color? color,
      bool active = false,
      VoidCallback? onTap,
    }) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 20, color: active ? color : muted),
              if (label.isNotEmpty) ...[
                const SizedBox(width: 6),
                Text(
                  label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: active ? color : muted,
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }

    return viewer.when(
      loading: () => const SizedBox(height: 36),
      error: (_, _) => const SizedBox(height: 36),
      data: (state) {
        final busy = state.pending;
        Future<void> run(Future<void> Function() task) async {
          try {
            await task();
          } catch (error) {
            if (context.mounted) showSnackBar('$error');
          }
        }

        return Wrap(
          spacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            action(
              state.liked ? Symbols.favorite : Symbols.favorite_border,
              '${state.likeCount}',
              color: theme.colorScheme.error,
              active: state.liked,
              onTap: busy ? null : () => requireLogin(
                () => run(notifier.toggleLike),
              ),
            ),
            action(
              Symbols.bookmark,
              '${state.bookmarkCount}',
              color: Colors.amber.shade700,
              active: state.favorited,
              onTap: busy ? null : () => requireLogin(
                () => run(notifier.toggleFavorite),
              ),
            ),
            action(Symbols.share, '${state.forwardCount}', onTap: share),
            const SizedBox(width: 8),
            action(Symbols.flag, 'abuseReport'.tr(), onTap: report),
          ],
        );
      },
    );
  }
}

class _CommentTile extends StatelessWidget {
  const _CommentTile({required this.comment, this.onToggleLike});

  final LkmContentComment comment;
  final VoidCallback? onToggleLike;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: comment.authorId.isEmpty
                      ? null
                      : () => context.router.push(
                          UserProfileRoute(id: comment.authorId),
                        ),
                  child: Text(
                    comment.authorName,
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              Text(
                '#${comment.floorNumber} · ${_formatDate(comment.createdAt)}',
                style: theme.textTheme.bodySmall?.copyWith(color: muted),
              ),
            ],
          ),
          const SizedBox(height: 4),
          SelectableText(comment.content, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 4),
          InkWell(
            onTap: onToggleLike,
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    comment.liked ? Symbols.favorite : Symbols.favorite_border,
                    size: 14,
                    color: comment.liked ? theme.colorScheme.error : muted,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${comment.likeCount}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: comment.liked ? theme.colorScheme.error : muted,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CommentError extends StatelessWidget {
  const _CommentError({required this.error, required this.onRetry});

  final Object error;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        children: [
          Text(
            'feedLoadFailed'.tr(),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
          TextButton(onPressed: onRetry, child: Text('feedRetry'.tr())),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

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

String _formatDate(DateTime date) => date.toIso8601String().substring(0, 10);
