import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:island/core/api/admin_api.dart';
import 'package:island/core/api/api_client.dart';
import 'package:island/core/api/api_providers.dart';
import 'package:island/core/config.dart';

final adminApiProvider = Provider<AdminApi>((ref) {
  final api = AdminApi(
    client: ref.watch(lkmApiSessionProvider).client,
    prefs: ref.watch(sharedPreferencesProvider),
  )..restore();
  return api;
});

/// Whether the admin cookie session is present. Mutated only by the login /
/// logout views; every data provider below watches it so a fresh sign-in
/// refetches without the screens manually invalidating each other.
class AdminSignedInNotifier extends Notifier<bool> {
  @override
  bool build() => ref.watch(adminApiProvider).isSignedIn;

  void set(bool value) => state = value;
}

final adminSignedInProvider = NotifierProvider<AdminSignedInNotifier, bool>(
  AdminSignedInNotifier.new,
);

/// Permission points of the current admin session; null when signed out.
final adminMeProvider = FutureProvider.autoDispose<AdminSessionInfo?>((ref) {
  if (!ref.watch(adminSignedInProvider)) return Future.value(null);
  return ref.watch(adminApiProvider).me();
});

final adminRulesProvider = FutureProvider.autoDispose<List<AdminRule>>((ref) {
  if (!ref.watch(adminSignedInProvider)) return const [];
  return ref.watch(adminApiProvider).rules();
});

typedef AdminContentQuery = ({int page, String? type});

final adminContentProvider = FutureProvider.autoDispose
    .family<ApiPage<AdminContentItem>, AdminContentQuery>((ref, query) {
      if (!ref.watch(adminSignedInProvider)) return const ApiPage.empty();
      return ref
          .watch(adminApiProvider)
          .contentItems(page: query.page, contentType: query.type);
    });

typedef AdminReportQuery = ({int page, String? status});

final adminReportsProvider = FutureProvider.autoDispose
    .family<ApiPage<AdminReport>, AdminReportQuery>((ref, query) {
      if (!ref.watch(adminSignedInProvider)) return const ApiPage.empty();
      return ref
          .watch(adminApiProvider)
          .reports(page: query.page, status: query.status);
    });

typedef AdminFileQuery = ({int page, String status});

final adminFilesProvider = FutureProvider.autoDispose
    .family<ApiPage<AdminFile>, AdminFileQuery>((ref, query) {
      if (!ref.watch(adminSignedInProvider)) return const ApiPage.empty();
      return ref
          .watch(adminApiProvider)
          .files(page: query.page, status: query.status);
    });

final adminDlqProvider = FutureProvider.autoDispose
    .family<List<AdminDlqItem>, String>((ref, status) {
      if (!ref.watch(adminSignedInProvider)) return const [];
      return ref.watch(adminApiProvider).dlq(status: status);
    });

final adminStatsProvider = FutureProvider.autoDispose<AdminStats>((ref) {
  if (!ref.watch(adminSignedInProvider))
    throw StateError('Admin session required');
  return ref.watch(adminApiProvider).stats();
});
final adminTrendProvider = FutureProvider.autoDispose<List<AdminTrend>>((ref) {
  if (!ref.watch(adminSignedInProvider))
    throw StateError('Admin session required');
  return ref.watch(adminApiProvider).trend();
});
final adminReviewSummaryProvider =
    FutureProvider.autoDispose<AdminReviewSummary>((ref) {
      if (!ref.watch(adminSignedInProvider))
        throw StateError('Admin session required');
      return ref.watch(adminApiProvider).reviewSummary();
    });

typedef AdminUserQuery = ({int page, String keyword, bool pii});
final adminUsersProvider = FutureProvider.autoDispose
    .family<ApiPage<AdminUser>, AdminUserQuery>((ref, query) {
      if (!ref.watch(adminSignedInProvider)) return const ApiPage.empty();
      return ref
          .watch(adminApiProvider)
          .users(
            page: query.page,
            keyword: query.keyword,
            includePii: query.pii,
          );
    });
final adminAdmissionProvider = FutureProvider.autoDispose<List<AdmissionUser>>((
  ref,
) {
  if (!ref.watch(adminSignedInProvider)) return const [];
  return ref.watch(adminApiProvider).admissionUsers();
});
final adminRecentUsersProvider = FutureProvider.autoDispose<ApiPage<AdminUser>>(
  (ref) {
    if (!ref.watch(adminSignedInProvider)) return const ApiPage.empty();
    return ref.watch(adminApiProvider).users(limit: 5);
  },
);
final adminRecentContentProvider =
    FutureProvider.autoDispose<ApiPage<AdminContentItem>>((ref) {
      if (!ref.watch(adminSignedInProvider)) return const ApiPage.empty();
      return ref.watch(adminApiProvider).contentItems(limit: 5);
    });
final adminRecentReportsProvider =
    FutureProvider.autoDispose<ApiPage<AdminReport>>((ref) {
      if (!ref.watch(adminSignedInProvider)) return const ApiPage.empty();
      return ref.watch(adminApiProvider).reports(limit: 5);
    });
final adminBotProvider = FutureProvider.autoDispose
    .family<AdminBotData, String>((ref, section) {
      if (!ref.watch(adminSignedInProvider))
        throw StateError('Admin session required');
      return ref.watch(adminApiProvider).botData(section);
    });
