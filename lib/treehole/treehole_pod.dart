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
      return ref.watch(treeholeApiProvider).bottles();
    });

final treeholeWishesProvider =
    FutureProvider.autoDispose<List<LkmTreeholeWish>>((ref) {
      return ref.watch(treeholeApiProvider).wishes();
    });

final treeholeConversationsProvider =
    FutureProvider.autoDispose<List<LkmTreeholeConversation>>((ref) {
      return ref.watch(treeholeApiProvider).conversations();
    });
