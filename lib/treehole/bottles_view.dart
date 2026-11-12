import 'dart:math';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';

import 'package:island/core/api/treehole_api.dart';
import 'package:island/shared/widgets/alert.dart';
import 'package:island/treehole/treehole_common.dart';
import 'package:island/treehole/treehole_pod.dart';

/// Drift bottles: throw one from the shell's FAB, pick up someone else's here.
class TreeholeBottlesView extends HookConsumerWidget {
  const TreeholeBottlesView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = useState<String?>(null);
    final bottles = ref.watch(treeholeBottlesProvider);
    return bottles.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('$error', textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () => ref.invalidate(treeholeBottlesProvider),
              child: Text('retry'.tr()),
            ),
          ],
        ),
      ),
      data: (all) {
        final items = selected.value == null
            ? all
            : all.where((b) => b.id == selected.value).toList();
        final available = all
            .where((b) => b.ownerId != 'me_local' && !b.picked)
            .toList();
        return Column(
          children: [
            Wrap(
              children: [
                TextButton(
                  onPressed: available.isEmpty
                      ? null
                      : () => selected.value =
                            available[Random().nextInt(available.length)].id,
                  child: Text('treeholeRandom'.tr()),
                ),
                TextButton(
                  onPressed: () {
                    selected.value = null;
                    ref.invalidate(treeholeBottlesProvider);
                  },
                  child: Text('refresh'.tr()),
                ),
              ],
            ),
            Expanded(
              child: items.isEmpty
                  ? Center(child: Text('treeholeNoBottles'.tr()))
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                      itemCount: items.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                      itemBuilder: (context, index) =>
                          _BottleCard(bottle: items[index]),
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _BottleCard extends HookConsumerWidget {
  const _BottleCard({required this.bottle});

  final LkmTreeholeBottle bottle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final busy = useState(false);
    final api = ref.read(treeholeApiProvider);

    Future<void> reply() async {
      final text = await showTreeholeTextDialog(
        context,
        title: 'treeholePickBottle'.tr(),
        hint: 'treeholeBottleReplyHint'.tr(),
      );
      if (text == null || !context.mounted) return;
      busy.value = true;
      try {
        await api.replyBottle(bottle.id, text);
        ref.invalidate(treeholeBottlesProvider);
        if (context.mounted) showSnackBar('treeholeReplySent'.tr());
      } catch (failure) {
        if (context.mounted) showSnackBar('$failure');
      } finally {
        if (context.mounted) busy.value = false;
      }
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
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('🍾', style: TextStyle(fontSize: 18)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    formatTreeholeTime(bottle.createdAt),
                    style: theme.textTheme.bodySmall?.copyWith(color: muted),
                  ),
                ),
                if (bottle.picked)
                  Text(
                    'treeholeBottlePicked'.tr(),
                    style: theme.textTheme.bodySmall?.copyWith(color: muted),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(bottle.text, style: theme.textTheme.bodyMedium),
            if (bottle.isMine && bottle.reply != null) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.secondaryContainer.withValues(
                    alpha: 0.4,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${'treeholeBottleReply'.tr()}：${bottle.reply}',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ],
            if (!bottle.isMine && !bottle.picked)
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: TextButton.icon(
                  onPressed: busy.value ? null : reply,
                  icon: const Icon(Symbols.waving_hand, size: 18),
                  label: Text('treeholePickBottle'.tr()),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
