import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:island/core/api/api_providers.dart';
import 'package:island/core/api/auth_api.dart';
import 'package:island/core/api/users_api.dart';

final usersApiProvider = Provider<UsersApi>((ref) {
  return UsersApi(ref.watch(lkmApiSessionProvider).client);
});

/// The signed-in LKM account, or null when signed out.
final lkmMeProvider = FutureProvider.autoDispose<LkmAccount?>((ref) async {
  final session = ref.watch(lkmApiSessionProvider);
  if (!session.isSignedIn) return null;
  return session.run(() => AuthApi(session.client).me());
});

final userProfileProvider = FutureProvider.autoDispose
    .family<LkmUserProfile, String>((ref, userId) {
      final session = ref.watch(lkmApiSessionProvider);
      return session.run(() => ref.watch(usersApiProvider).profile(userId));
    });

final myFollowingProvider = FutureProvider.autoDispose<List<LkmFollowUser>>((
  ref,
) async {
  final session = ref.watch(lkmApiSessionProvider);
  if (!session.isSignedIn) return const [];
  return session.run(() => ref.watch(usersApiProvider).following());
});

class FollowNotifier extends AsyncNotifier<bool> {
  FollowNotifier(this.userId);

  final String userId;

  @override
  Future<bool> build() async {
    final session = ref.watch(lkmApiSessionProvider);
    if (!session.isSignedIn) return false;
    return session.run(() => ref.read(usersApiProvider).followStatus(userId));
  }

  /// Optimistic toggle; rolls back when the write fails so the button never
  /// shows a state the server rejected.
  Future<void> toggle() async {
    final current = state.value ?? false;
    final next = !current;
    state = AsyncData(next);
    final session = ref.read(lkmApiSessionProvider);
    try {
      await session.run(
        () => ref.read(usersApiProvider).setFollow(userId, follow: next),
      );
      ref.invalidate(myFollowingProvider);
    } catch (_) {
      state = AsyncData(current);
      rethrow;
    }
  }
}

final followProvider = AsyncNotifierProvider.autoDispose
    .family<FollowNotifier, bool, String>(FollowNotifier.new);
