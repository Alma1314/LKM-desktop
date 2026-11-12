import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:island/treehole/local_store.dart';
import 'package:island/treehole/settings_sheet.dart';
import 'package:island/core/config.dart';
import 'package:island/core/api/api_providers.dart';
import 'package:auto_route/auto_route.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';

import 'package:island/shared/hooks/material_hooks.dart';
import 'package:island/shared/widgets/alert.dart';
import 'package:island/shared/widgets/app_scaffold.dart';
import 'package:island/treehole/bottles_view.dart';
import 'package:island/treehole/inbox_view.dart';
import 'package:island/treehole/letter_sheet.dart';
import 'package:island/treehole/letters_view.dart';
import 'package:island/treehole/treehole_common.dart';
import 'package:island/treehole/treehole_pod.dart';
import 'package:island/treehole/wishes_view.dart';

/// The anonymous treehole: letters, drift bottles, wishes and conversations.
@RoutePage()
class TreeholeScreen extends HookConsumerWidget {
  const TreeholeScreen({super.key});

  static const _inboxTab = 3;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final local = TreeholeLocalStore(
      ref.watch(sharedPreferencesProvider),
      ref.watch(lkmServerUrlProvider),
    );
    final preferences = useState(local.read());
    final base = Theme.of(context);
    final mode = preferences.value['theme'];
    final dark =
        mode == 'dark' ||
        (mode != 'light' && base.brightness == Brightness.dark);
    final palette = preferences.value['contrast'] == true
        ? (dark
              ? const ColorScheme.highContrastDark()
              : const ColorScheme.highContrastLight())
        : ColorScheme.fromSeed(
            seedColor: base.colorScheme.primary,
            brightness: dark ? Brightness.dark : Brightness.light,
          );
    final controller = useMaterialTabController(initialLength: 5);

    void refreshAll() {
      ref.invalidate(treeholeLettersProvider);
      ref.invalidate(treeholeRankLettersProvider);
      ref.invalidate(treeholeBottlesProvider);
      ref.invalidate(treeholeWishesProvider);
      ref.invalidate(treeholeConversationsProvider);
    }

    Future<void> compose() async {
      final tab = controller.index;
      if (tab == 1) {
        final text = await showTreeholeTextDialog(
          context,
          title: 'treeholeThrowBottle'.tr(),
          hint: 'treeholeBottleHint'.tr(),
        );
        if (text == null || !context.mounted) return;
        try {
          await ref.read(treeholeApiProvider).createBottle(text);
          ref.invalidate(treeholeBottlesProvider);
        } catch (failure) {
          if (context.mounted) showSnackBar('$failure');
        }
        return;
      }
      if (tab == 2) {
        final text = await showTreeholeTextDialog(
          context,
          title: 'treeholeMakeWish'.tr(),
          hint: 'treeholeWishHint'.tr(),
        );
        if (text == null || !context.mounted) return;
        try {
          await ref.read(treeholeApiProvider).createWish(text);
          ref.invalidate(treeholeWishesProvider);
        } catch (failure) {
          if (context.mounted) showSnackBar('$failure');
        }
        return;
      }
      if (tab == _inboxTab) return;
      final letter = await showModalBottomSheet<Object>(
        context: context,
        isScrollControlled: true,
        builder: (_) => const TreeholeLetterSheet(),
      );
      if (letter != null) {
        ref.invalidate(treeholeLettersProvider);
        ref.invalidate(treeholeRankLettersProvider);
      }
    }

    final screen = AppScaffold(
      isNoBackground: false,
      appBar: AppBar(
        leading: const AutoLeadingButton(),
        title: Text('treehole'.tr()),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'settings'.tr(),
            onPressed: () async {
              await showDialog<void>(
                context: context,
                builder: (_) => const TreeholeSettingsSheet(),
              );
              if (context.mounted) preferences.value = local.read();
            },
          ),
          IconButton(
            tooltip: 'refresh'.tr(),
            onPressed: refreshAll,
            icon: const Icon(Symbols.refresh_rounded),
          ),
        ],
        bottom: TabBar(
          controller: controller,
          tabs: [
            Tab(text: 'treeholeLetters'.tr()),
            Tab(text: 'treeholeBottles'.tr()),
            Tab(text: 'treeholeWishes'.tr()),
            Tab(text: 'treeholeInbox'.tr()),
            Tab(text: 'treeholeMine'.tr()),
          ],
        ),
      ),
      floatingActionButton: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          final index = controller.index;
          return index == _inboxTab
              ? const SizedBox.shrink()
              : FloatingActionButton.extended(
                  onPressed: compose,
                  icon: const Icon(Symbols.edit_square),
                  label: Text(switch (index) {
                    1 => 'treeholeThrowBottle'.tr(),
                    2 => 'treeholeMakeWish'.tr(),
                    _ => 'treeholeWriteLetter'.tr(),
                  }),
                );
        },
      ),
      body: TabBarView(
        controller: controller,
        children: [
          TreeholeLettersView(onReplied: () => controller.animateTo(_inboxTab)),
          const TreeholeBottlesView(),
          const TreeholeWishesView(),
          const TreeholeInboxView(),
          const TreeholeLettersView(scope: 'mine'),
        ],
      ),
    );
    return Theme(
      data: base.copyWith(colorScheme: palette),
      child: MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(
            (preferences.value['scale'] as num? ?? 1).toDouble(),
          ),
        ),
        child: screen,
      ),
    );
  }
}
