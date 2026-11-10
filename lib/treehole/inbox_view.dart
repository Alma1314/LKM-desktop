import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';

import 'package:island/core/api/treehole_api.dart';
import 'package:island/shared/widgets/alert.dart';
import 'package:island/treehole/treehole_common.dart';
import 'package:island/treehole/treehole_pod.dart';

/// Conversations started from a letter reply or a picked bottle.
class TreeholeInboxView extends ConsumerWidget {
  const TreeholeInboxView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conversations = ref.watch(treeholeConversationsProvider);
    return conversations.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('$error', textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () => ref.invalidate(treeholeConversationsProvider),
              child: Text('retry'.tr()),
            ),
          ],
        ),
      ),
      data: (items) => items.isEmpty
          ? Center(child: Text('treeholeNoConversations'.tr()))
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, index) => _ConversationCard(
                key: ValueKey(items[index].id),
                conversation: items[index],
              ),
            ),
    );
  }
}

class _ConversationCard extends HookConsumerWidget {
  const _ConversationCard({super.key, required this.conversation});

  final LkmTreeholeConversation conversation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final expanded = useState(false);
    final busy = useState(false);
    final input = useTextEditingController();
    final api = ref.read(treeholeApiProvider);

    Future<void> run(Future<void> Function() task) async {
      if (busy.value) return;
      busy.value = true;
      try {
        await task();
      } catch (failure) {
        if (context.mounted) showSnackBar('$failure');
      } finally {
        busy.value = false;
      }
    }

    Future<void> send() async {
      final text = input.text.trim();
      if (text.isEmpty) return;
      await run(() async {
        await api.sendMessage(conversation.id, text);
        input.clear();
        ref.invalidate(treeholeConversationsProvider);
      });
    }

    Future<void> recall(LkmTreeholeMessage message) => run(() async {
      await api.recall(conversation.id, message.id);
      ref.invalidate(treeholeConversationsProvider);
    });

    Future<bool> confirm(String messageKey) => showTreeholeConfirm(
      context,
      title: 'treeholeConversationActions'.tr(),
      message: messageKey.tr(),
      confirmKey: 'confirm',
    );

    Future<void> block() async {
      if (!await confirm('treeholeBlockConfirm')) return;
      await run(() async {
        await api.block(conversation.id);
        ref.invalidate(treeholeConversationsProvider);
      });
    }

    Future<void> clear() async {
      if (!await confirm('treeholeClearConfirm')) return;
      await run(() async {
        await api.clear(conversation.id);
        ref.invalidate(treeholeConversationsProvider);
      });
    }

    Future<void> hide() async {
      if (!await confirm('treeholeHideConfirm')) return;
      await run(() async {
        await api.hideConversation(conversation.id);
        ref.invalidate(treeholeConversationsProvider);
      });
    }

    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => expanded.value = !expanded.value,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
              child: Row(
                children: [
                  const Text('✉️', style: TextStyle(fontSize: 18)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                conversation.peerCodename,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleSmall,
                              ),
                            ),
                            if (conversation.blocked) ...[
                              const SizedBox(width: 6),
                              Icon(
                                Symbols.block,
                                size: 14,
                                color: theme.colorScheme.error,
                              ),
                            ],
                          ],
                        ),
                        Text(
                          formatTreeholeTime(conversation.updatedAt),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    expanded.value ? Symbols.expand_less : Symbols.expand_more,
                    color: muted,
                  ),
                ],
              ),
            ),
          ),
          if (expanded.value) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
              child: Column(
                children: [
                  for (final message in conversation.messages)
                    _MessageBubble(
                      message: message,
                      onRecall:
                          busy.value ||
                              message.recalled ||
                              !message.isMine
                          ? null
                          : () => recall(message),
                    ),
                  if (conversation.messages.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        'treeholeNoMessages'.tr(),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: muted,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: input,
                      maxLength: 1000,
                      maxLines: 3,
                      minLines: 1,
                      decoration: InputDecoration(
                        hintText: conversation.blocked
                            ? 'treeholeConversationBlocked'.tr()
                            : 'treeholeMessageHint'.tr(),
                        counterText: '',
                        isDense: true,
                        border: const OutlineInputBorder(),
                      ),
                      enabled: !conversation.blocked,
                      onSubmitted: (_) => send(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    onPressed: busy.value || conversation.blocked
                        ? null
                        : send,
                    icon: const Icon(Symbols.send),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
              child: Wrap(
                children: [
                  TextButton.icon(
                    onPressed: busy.value || conversation.blocked ? null : block,
                    icon: const Icon(Symbols.block, size: 16),
                    label: Text('treeholeBlock'.tr()),
                  ),
                  TextButton.icon(
                    onPressed: busy.value ? null : clear,
                    icon: const Icon(Symbols.cleaning_services, size: 16),
                    label: Text('treeholeClearHistory'.tr()),
                  ),
                  TextButton.icon(
                    onPressed: busy.value ? null : hide,
                    icon: const Icon(Symbols.visibility_off, size: 16),
                    label: Text('treeholeHideConversation'.tr()),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message, this.onRecall});

  final LkmTreeholeMessage message;
  final VoidCallback? onRecall;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mine = message.isMine;
    return Align(
      alignment: mine
          ? AlignmentDirectional.centerEnd
          : AlignmentDirectional.centerStart,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 480),
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: mine
              ? theme.colorScheme.primaryContainer
              : theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              message.text,
              style: theme.textTheme.bodySmall?.copyWith(
                fontStyle: message.recalled ? FontStyle.italic : null,
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  formatTreeholeTime(message.at),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (onRecall != null) ...[
                  const SizedBox(width: 6),
                  InkWell(
                    onTap: onRecall,
                    child: Text(
                      'treeholeRecall'.tr(),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
