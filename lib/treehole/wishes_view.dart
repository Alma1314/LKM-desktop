import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';

import 'package:island/core/api/treehole_api.dart';
import 'package:island/shared/widgets/alert.dart';
import 'package:island/treehole/treehole_common.dart';
import 'package:island/treehole/treehole_pod.dart';

/// Sky lanterns: light anyone's wish (once), edit or remove your own.
class TreeholeWishesView extends ConsumerWidget {
  const TreeholeWishesView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wishes = ref.watch(treeholeWishesProvider);
    return wishes.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('$error', textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () => ref.invalidate(treeholeWishesProvider),
              child: Text('retry'.tr()),
            ),
          ],
        ),
      ),
      data: (items) => items.isEmpty
          ? Center(child: Text('treeholeNoWishes'.tr()))
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, index) => _WishCard(wish: items[index]),
            ),
    );
  }
}

class _WishCard extends HookConsumerWidget {
  const _WishCard({required this.wish});

  final LkmTreeholeWish wish;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final busy = useState(false);
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

    Future<void> light() => run(() async {
      await api.lightWish(wish.id);
      ref.invalidate(treeholeWishesProvider);
    });

    Future<void> edit() async {
      final text = await showTreeholeTextDialog(
        context,
        title: 'treeholeEditWish'.tr(),
        initial: wish.text,
        confirmKey: 'done',
      );
      if (text == null || !context.mounted) return;
      await run(() async {
        await api.editWish(wish.id, text);
        ref.invalidate(treeholeWishesProvider);
      });
    }

    Future<void> remove() async {
      final confirmed = await showTreeholeConfirm(
        context,
        title: 'delete'.tr(),
        message: 'treeholeDeleteWishConfirm'.tr(),
        confirmKey: 'delete',
      );
      if (!confirmed || !context.mounted) return;
      await run(() async {
        await api.deleteWish(wish.id);
        ref.invalidate(treeholeWishesProvider);
      });
    }

    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              formatTreeholeTime(wish.createdAt),
              style: theme.textTheme.bodySmall?.copyWith(color: muted),
            ),
            const SizedBox(height: 6),
            Text(wish.text, style: theme.textTheme.bodyMedium),
            Row(
              children: [
                InkWell(
                  onTap: busy.value ? null : light,
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 8,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Symbols.local_fire_department,
                          size: 18,
                          color: Colors.amber.shade700,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${wish.lights}',
                          style: theme.textTheme.bodySmall,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'treeholeLightWish'.tr(),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const Spacer(),
                if (wish.isMine) ...[
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
