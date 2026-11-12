import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:island/community/content_detail_pod.dart';
import 'package:island/core/api/api_client.dart';
import 'package:island/core/api/api_providers.dart';
import 'package:island/core/api/columns_api.dart';
import 'package:island/core/api/content_api.dart';
import 'package:island/core/api/projects_api.dart';
import 'package:island/core/api/qa_api.dart';

final qaApiProvider = Provider<QaApi>((ref) {
  return QaApi(ref.watch(lkmApiSessionProvider).client);
});

final columnsApiProvider = Provider<ColumnsApi>((ref) {
  return ColumnsApi(ref.watch(lkmApiSessionProvider).client);
});

final projectsApiProvider = Provider<ProjectsApi>((ref) {
  return ProjectsApi(ref.watch(lkmApiSessionProvider).client);
});

/// A QA list selection: category (`help`/`volunteer`/null for all) plus sort.
typedef QaFilter = ({String? category, String sort});

/// QA questions are public, so this is fetched signed out too.
final qaQuestionsProvider = FutureProvider.autoDispose
    .family<ApiPage<QaQuestion>, QaFilter>((ref, filter) {
      final session = ref.watch(lkmApiSessionProvider);
      return session.run(
        () => ref
            .watch(qaApiProvider)
            .questions(category: filter.category, sort: filter.sort),
      );
    });

/// One question with answers; the family id keeps each detail page cached.
final qaQuestionProvider = FutureProvider.autoDispose
    .family<QaQuestion, String>((ref, id) {
      final session = ref.watch(lkmApiSessionProvider);
      return session.run(() => ref.watch(qaApiProvider).question(id));
    });

final columnsProvider = FutureProvider.autoDispose<ColumnPage>((ref) {
  final session = ref.watch(lkmApiSessionProvider);
  return session.run(() => ref.watch(columnsApiProvider).columns());
});

final columnPostsProvider = FutureProvider.autoDispose
    .family<ColumnPostPage, String>((ref, columnId) {
      final session = ref.watch(lkmApiSessionProvider);
      return session.run(
        () => ref.watch(columnsApiProvider).posts(columnId),
      );
    });

/// Projects are public; the hall list is small enough for one page.
final projectsProvider = FutureProvider.autoDispose<List<ProjectSummary>>((ref) {
  final session = ref.watch(lkmApiSessionProvider);
  return session.run(() => ref.watch(projectsApiProvider).projects());
});

final projectProvider = FutureProvider.autoDispose
    .family<ProjectSummary, String>((ref, id) {
      final session = ref.watch(lkmApiSessionProvider);
      return session.run(() => ref.watch(projectsApiProvider).project(id));
    });

final myProjectApplicationsProvider =
    FutureProvider.autoDispose<List<ProjectApplication>>((ref) async {
      final session = ref.watch(lkmApiSessionProvider);
      if (!session.isSignedIn) return const [];
      return session.run(
        () => ref.watch(projectsApiProvider).myApplications(),
      );
    });

/// Published content inside one board, one page per call. The board detail
/// screen owns the accumulated list.
final boardItemsProvider = FutureProvider.autoDispose
    .family<ApiPage<LkmContentItem>, ({String boardId, int page})>((ref, key) {
      final session = ref.watch(lkmApiSessionProvider);
      return session.run(
        () => ref
            .watch(contentApiProvider)
            .items(boardId: key.boardId, page: key.page),
      );
    });

/// The board detail's first page, large enough to rank locally like the
/// website does. ponytail: 50-item cap, switch back to server paging if a
/// board ever outgrows one page.
final boardFeedProvider = FutureProvider.autoDispose
    .family<List<LkmContentItem>, String>((ref, boardId) async {
      final session = ref.watch(lkmApiSessionProvider);
      final page = await session.run(
        () => ref
            .watch(contentApiProvider)
            .items(boardId: boardId, pageSize: 50),
      );
      return page.items;
    });

/// Boards the signed-in viewer follows; also the source of truth for the
/// follow button on a board page.
final followingBoardsProvider =
    FutureProvider.autoDispose<List<LkmFollowBoard>>((ref) {
      final session = ref.watch(lkmApiSessionProvider);
      if (!session.isSignedIn) return const <LkmFollowBoard>[];
      return session.run(
        () => ref.watch(contentApiProvider).followingBoards(),
      );
    });

/// Board ordering shared by the 最新/热门 switch: pinned first; hot ranks
/// featured before unfeatured and then by views, latest by publish time.
List<LkmContentItem> orderBoardItems(
  List<LkmContentItem> items, {
  required bool hot,
}) {
  final sorted = [...items];
  sorted.sort((a, b) {
    if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
    if (hot) {
      if (a.isFeatured != b.isFeatured) return a.isFeatured ? -1 : 1;
      return b.viewCount.compareTo(a.viewCount);
    }
    return b.createdAt.compareTo(a.createdAt);
  });
  return sorted;
}
