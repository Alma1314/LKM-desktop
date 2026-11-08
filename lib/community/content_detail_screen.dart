import 'package:auto_route/auto_route.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:island/community/content_detail_pod.dart';
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final item = ref.watch(contentItemProvider(id));

    return AppScaffold(
      isNoBackground: false,
      appBar: AppBar(
        leading: const AutoLeadingButton(),
        title: Text('contentDetail'.tr()),
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
        const Divider(height: 40),
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
              for (final comment in state.items) _CommentTile(comment: comment),
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

class _CommentTile extends StatelessWidget {
  const _CommentTile({required this.comment});

  final LkmContentComment comment;

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
          if (comment.likeCount > 0) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Symbols.favorite, size: 14, color: muted),
                const SizedBox(width: 4),
                Text(
                  '${comment.likeCount}',
                  style: theme.textTheme.bodySmall?.copyWith(color: muted),
                ),
              ],
            ),
          ],
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
