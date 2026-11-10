import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:island/core/api/api_client.dart';
import 'package:island/core/api/api_providers.dart';
import 'package:island/core/api/points_api.dart';

final pointsApiProvider = Provider<PointsApi>((ref) {
  return PointsApi(ref.watch(lkmApiSessionProvider).client);
});

/// Balance of the signed-in user; null when signed out.
final lkmPointsBalanceProvider =
    FutureProvider.autoDispose<LkmPointsBalance?>((ref) async {
      final session = ref.watch(lkmApiSessionProvider);
      if (!session.isSignedIn) return null;
      return session.run(() => ref.watch(pointsApiProvider).balance());
    });

final lkmPointsLedgerProvider =
    FutureProvider.autoDispose<ApiPage<LkmPointsLedgerEntry>>((ref) async {
      final session = ref.watch(lkmApiSessionProvider);
      if (!session.isSignedIn) return const ApiPage.empty();
      return session.run(() => ref.watch(pointsApiProvider).ledger());
    });

/// Leaderboard is public: it is fetched signed out too. [period] is
/// `total` / `daily` / `weekly`; keeping it as a family gives per-period
/// caching while the page stays mounted.
final lkmPointsLeaderboardProvider =
    FutureProvider.autoDispose
        .family<ApiPage<LkmPointsLeaderboardEntry>, String>((ref, period) {
          final session = ref.watch(lkmApiSessionProvider);
          return session.run(
            () => ref.watch(pointsApiProvider).leaderboard(period: period),
          );
        });

final lkmPointsAchievementsProvider =
    FutureProvider.autoDispose<List<LkmPointsAchievement>>((ref) async {
      final session = ref.watch(lkmApiSessionProvider);
      if (!session.isSignedIn) return const [];
      return session.run(() => ref.watch(pointsApiProvider).achievements());
    });

final lkmPointsTasksProvider =
    FutureProvider.autoDispose<List<LkmPointsTask>>((ref) async {
      final session = ref.watch(lkmApiSessionProvider);
      if (!session.isSignedIn) return const [];
      return session.run(() => ref.watch(pointsApiProvider).tasks());
    });

/// Exchange items are public but read-only: the service has no redemption
/// endpoint, so the UI only lists them.
final lkmPointsExchangeProvider =
    FutureProvider.autoDispose<List<LkmPointsExchangeItem>>((ref) {
      final session = ref.watch(lkmApiSessionProvider);
      return session.run(() => ref.watch(pointsApiProvider).exchangeItems());
    });

/// Persisted reason codes → `contributionData.pointLogs.*` keys. Unknown
/// codes fall back to the raw server value instead of leaking an i18n key.
const Map<String, String> kPointsLogKeys = {
  'checkin': 'checkin',
  'post': 'post',
  'comment': 'comment',
  'competition': 'competition',
  'file_approved': 'fileApproved',
  'answer_accepted': 'answerAccepted',
  'daily_task': 'dailyTask',
  'like': 'like',
  'qa_accept': 'qaAccept',
  'transfer_out': 'transfer',
  'transfer_in': 'transfer',
};
