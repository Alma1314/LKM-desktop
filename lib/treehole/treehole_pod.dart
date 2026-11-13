import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:island/core/api/api_providers.dart';
import 'package:island/core/api/treehole_api.dart';
import 'package:island/core/config.dart';

/// Anonymous treehole client. The session cookie lives in prefs, so this only
/// needs the host and the shared [ApiClient].
final treeholeApiProvider = Provider<TreeholeApi>((ref) {
  return TreeholeApi(
    ref.watch(lkmApiSessionProvider).client,
    ref.watch(sharedPreferencesProvider),
  );
});

/// `scope` is `public` / `random` / `mine` (the service's letter scopes).
final treeholeLettersProvider = FutureProvider.autoDispose
    .family<List<LkmTreeholeLetter>, String>((ref, scope) {
      return ref.watch(treeholeApiProvider).letters(scope: scope);
    });

final treeholeBottlesProvider =
    FutureProvider.autoDispose<List<LkmTreeholeBottle>>((ref) {
      final api = ref.watch(treeholeApiProvider);
      return () async {
        final all = <LkmTreeholeBottle>[];
        for (var page = 1; ; page++) {
          final rows = await api.bottles(page: page);
          all.addAll(rows);
          if (rows.length < 100) break;
        }
        return all;
      }();
    });

final treeholeWishesProvider =
    FutureProvider.autoDispose<List<LkmTreeholeWish>>((ref) {
      return ref.watch(treeholeApiProvider).wishes();
    });

final treeholeConversationsProvider =
    FutureProvider.autoDispose<List<LkmTreeholeConversation>>((ref) {
      return ref.watch(treeholeApiProvider).conversations();
    });

final treeholeRankLettersProvider =
    FutureProvider.autoDispose<List<LkmTreeholeLetter>>((ref) async {
      final api = ref.watch(treeholeApiProvider);
      final all = <LkmTreeholeLetter>[];
      for (var page = 1; ; page++) {
        final items = await api.letters(
          scope: 'public',
          page: page,
          limit: 100,
        );
        all.addAll(items);
        if (items.length < 100) break;
      }
      return all;
    });

/// The random-reading pool includes public and random letters, never our own.
final treeholeRandomLettersProvider =
    FutureProvider.autoDispose<List<LkmTreeholeLetter>>((ref) async {
      final api = ref.watch(treeholeApiProvider);
      final pool = <String, LkmTreeholeLetter>{};
      for (final scope in ['public', 'random']) {
        for (var page = 1; ; page++) {
          final rows = await api.letters(scope: scope, page: page, limit: 100);
          for (final letter in rows) {
            if (!letter.isMine && letter.status == 'published')
              pool[letter.id] = letter;
          }
          if (rows.length < 100) break;
        }
      }
      return pool.values.toList();
    });
