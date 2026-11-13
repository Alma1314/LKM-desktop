import 'package:island/treehole/local_store.dart';
import 'dart:math';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';

import 'package:island/core/api/treehole_api.dart';
import 'package:island/shared/widgets/alert.dart';
import 'package:island/treehole/letter_sheet.dart';
import 'package:island/treehole/treehole_common.dart';
import 'package:island/treehole/treehole_pod.dart';

/// Public/random letter wall. `scope == 'mine'` is the private view that also
/// exposes edit/delete and scheduled/sealed letters.
class TreeholeLettersView extends HookConsumerWidget {
  const TreeholeLettersView({super.key, this.scope, this.onReplied});

  /// `mine`, or null for the public/random wall.
  final String? scope;

  /// Switches the shell to the inbox after a reply starts a conversation.
  final VoidCallback? onReplied;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wallScope = useState('public');
    final effective = scope ?? wallScope.value;
    final raw = effective == 'random'
        ? ref.watch(treeholeRandomLettersProvider)
        : effective.startsWith('rank')
        ? ref.watch(treeholeRankLettersProvider)
        : ref.watch(treeholeLettersProvider(effective));
    final letters = effective.startsWith('rank')
        ? raw.whenData(
            (items) => rankTreeholeLetters(
              items,
              DateTime.now(),
              effective == 'rankToday' ? 1 : 7,
            ),
          )
        : raw;

    return Column(
      children: [
        if (scope == null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SegmentedButton<String>(
                  segments: [
                    ButtonSegment(
                      value: 'rankToday',
                      label: Text('migration34.today'.tr()),
                    ),
                    ButtonSegment(
                      value: 'rankWeek',
                      label: Text('migration34.week'.tr()),
                    ),
                    ButtonSegment(
                      value: 'public',
                      label: Text('treeholePrivacyPublic'.tr()),
                    ),
                    ButtonSegment(
                      value: 'random',
                      label: Text('treeholeRandom'.tr()),
                    ),
                  ],
                  selected: {wallScope.value},
                  onSelectionChanged: (value) => wallScope.value = value.first,
                ),
              ),
            ),
          ),
        Expanded(
          child: letters.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => _TreeholeError(
              error: error,
              onRetry: () {
                if (effective == 'random') {
                  ref.invalidate(treeholeRandomLettersProvider);
                } else if (effective.startsWith('rank')) {
                  ref.invalidate(treeholeRankLettersProvider);
                  ref.invalidate(treeholeRandomLettersProvider);
                } else {
                  ref.invalidate(treeholeLettersProvider(effective));
                }
              },
            ),
            data: (items) => effective == 'random'
                ? _RandomLetterView(letters: items, onReplied: onReplied)
                : items.isEmpty
                ? Center(child: Text('treeholeNoLetters'.tr()))
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (context, index) =>
                        _LetterCard(letter: items[index], onReplied: onReplied),
                  ),
          ),
        ),
      ],
    );
  }
}

class _RandomLetterView extends HookConsumerWidget {
  const _RandomLetterView({required this.letters, this.onReplied});
  final List<LkmTreeholeLetter> letters;
  final VoidCallback? onReplied;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chosen = useState<String?>(null);
    final busy = useState(false);
    final current = letters
        .where((letter) => letter.id == chosen.value)
        .firstOrNull;
    return Column(
      children: [
        TextButton.icon(
          icon: const Icon(Icons.shuffle),
          label: Text(
            (current == null ? 'treeholeDrawLetter' : 'treeholeSwitchLetter')
                .tr(),
          ),
          onPressed: busy.value
              ? null
              : () async {
                  busy.value = true;
                  try {
                    ref.invalidate(treeholeRandomLettersProvider);
                    final pool = await ref.read(
                      treeholeRandomLettersProvider.future,
                    );
                    if (!context.mounted) return;
                    final candidates = pool.length > 1
                        ? pool
                              .where((letter) => letter.id != chosen.value)
                              .toList()
                        : pool;
                    chosen.value = candidates.isEmpty
                        ? null
                        : candidates[Random().nextInt(candidates.length)].id;
                  } catch (error) {
                    if (context.mounted) showSnackBar('$error');
                  } finally {
                    if (context.mounted) busy.value = false;
                  }
                },
        ),
        if (busy.value) const LinearProgressIndicator(),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            children: [
              if (current != null)
                _LetterCard(letter: current, onReplied: onReplied)
              else if (letters.isEmpty)
                Center(child: Text('treeholeNoLetters'.tr())),
            ],
          ),
        ),
      ],
    );
  }
}

class _LetterCard extends HookConsumerWidget {
  const _LetterCard({required this.letter, this.onReplied});

  final LkmTreeholeLetter letter;
  final VoidCallback? onReplied;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final busy = useState(false);
    final category = treeholeCategory(letter.category);
    final api = ref.read(treeholeApiProvider);

    Future<void> run(Future<void> Function() task) async {
      if (busy.value) return;
      busy.value = true;
      try {
        await task();
      } catch (failure) {
        if (context.mounted) showSnackBar('$failure');
      } finally {
        if (context.mounted) busy.value = false;
      }
    }

    Future<void> react(String kind) => run(() async {
      await api.toggleReaction(letter.id, kind);
      ref.invalidate(treeholeLettersProvider);
      ref.invalidate(treeholeRankLettersProvider);
      ref.invalidate(treeholeRandomLettersProvider);
    });

    Future<void> reply() async {
      final text = await showTreeholeTextDialog(
        context,
        title: 'treeholeReply'.tr(),
        hint: 'treeholeReplyHint'.tr(),
      );
      if (text == null || !context.mounted) return;
      await run(() async {
        await api.replyLetter(letter.id, text);
        ref.invalidate(treeholeConversationsProvider);
        if (context.mounted) showSnackBar('treeholeReplySent'.tr());
        onReplied?.call();
      });
    }

    Future<void> report() async {
      final reason = await showTreeholeReportDialog(context);
      if (reason == null || !context.mounted) return;
      await run(() async {
        await api.report(
          targetType: 'letter',
          targetId: letter.id,
          reason: reason,
        );
        if (context.mounted) showSnackBar('abuseReportSuccess'.tr());
      });
    }

    Future<void> edit() async {
      await showModalBottomSheet<LkmTreeholeLetter>(
        context: context,
        isScrollControlled: true,
        builder: (_) => TreeholeLetterSheet(letter: letter),
      );
      ref.invalidate(treeholeLettersProvider);
      ref.invalidate(treeholeRankLettersProvider);
      ref.invalidate(treeholeRandomLettersProvider);
    }

    Future<void> remove() async {
      final confirmed = await showTreeholeConfirm(
        context,
        title: 'delete'.tr(),
        message: 'treeholeDeleteConfirm'.tr(),
        confirmKey: 'delete',
      );
      if (!confirmed || !context.mounted) return;
      await run(() async {
        await api.deleteLetter(letter.id);
        ref.invalidate(treeholeLettersProvider);
        ref.invalidate(treeholeRankLettersProvider);
        ref.invalidate(treeholeRandomLettersProvider);
        ref.invalidate(treeholeConversationsProvider);
      });
    }

    final scheduled = letter.status == 'scheduled';
    final sealed = letter.status == 'sealed';

    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(category.emoji, style: const TextStyle(fontSize: 18)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '${category.labelKey.tr()} · ${letter.codename}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(color: muted),
                  ),
                ),
                if (letter.privacy != 'public')
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Icon(
                      letter.privacy == 'self' ? Symbols.lock : Symbols.shuffle,
                      size: 14,
                      color: muted,
                    ),
                  ),
                Text(
                  formatTreeholeTime(letter.createdAt),
                  style: theme.textTheme.bodySmall?.copyWith(color: muted),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(letter.content, style: theme.textTheme.bodyMedium),
            if (letter.moods.isNotEmpty || letter.tags.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final mood in letter.moods)
                    _Chip(label: mood, muted: true),
                  for (final tag in letter.tags)
                    _Chip(label: treeholeTagLabel(tag)),
                ],
              ),
            ],
            if (scheduled || sealed) ...[
              const SizedBox(height: 8),
              Text(
                scheduled
                    ? 'treeholeScheduledAt'.tr(
                        args: [
                          formatTreeholeTime(
                            letter.scheduledAt ?? letter.createdAt,
                          ),
                        ],
                      )
                    : 'treeholeSealed'.tr(),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.tertiary,
                ),
              ),
            ],
            const SizedBox(height: 4),
            Row(
              children: [
                _Action(
                  icon: letter.liked
                      ? Symbols.favorite
                      : Symbols.favorite_border,
                  label: '${letter.likes}',
                  active: letter.liked,
                  color: theme.colorScheme.error,
                  onTap: busy.value ? null : () => react('like'),
                ),
                _Action(
                  icon: Symbols.bookmark,
                  label: '${letter.favorites}',
                  active: letter.favorited,
                  color: Colors.amber.shade700,
                  onTap: busy.value ? null : () => react('favorite'),
                ),
                if (!letter.isMine)
                  _Action(
                    icon: Symbols.chat_bubble_outline,
                    label: 'treeholeReply'.tr(),
                    onTap: busy.value ? null : reply,
                  ),
                _Action(
                  icon: Symbols.flag,
                  label: 'abuseReport'.tr(),
                  onTap: busy.value || letter.isMine ? null : report,
                ),
                const Spacer(),
                if (letter.isMine) ...[
                  IconButton(
                    tooltip: 'edit'.tr(),
                    visualDensity: VisualDensity.compact,
                    onPressed: busy.value ? null : edit,
                    icon: const Icon(Symbols.edit, size: 18),
                  ),
                  IconButton(
                    tooltip: 'delete'.tr(),
                    visualDensity: VisualDensity.compact,
                    onPressed: busy.value ? null : remove,
                    icon: const Icon(Symbols.delete, size: 18),
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

class _Chip extends StatelessWidget {
  const _Chip({required this.label, this.muted = false});

  final String label;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: muted
            ? theme.colorScheme.surfaceContainerHighest
            : theme.colorScheme.secondaryContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({
    required this.icon,
    required this.label,
    this.color,
    this.active = false,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final Color? color;
  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tint = active ? (color ?? theme.colorScheme.primary) : null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 18,
              color: tint ?? theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: tint ?? theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TreeholeError extends StatelessWidget {
  const _TreeholeError({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$error', textAlign: TextAlign.center),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: onRetry, child: Text('retry'.tr())),
        ],
      ),
    );
  }
}
