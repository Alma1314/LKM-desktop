import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:island/core/api/api_providers.dart';
import 'package:island/core/api/content_api.dart';

final contentApiProvider = Provider<ContentApi>((ref) {
  return ContentApi(ref.watch(lkmApiSessionProvider).client);
});

/// One content body by id. A missing/unpublished row reads as null.
final contentItemProvider = FutureProvider.autoDispose
    .family<LkmContentItem?, String>((ref, id) {
      final session = ref.watch(lkmApiSessionProvider);
      return session.run(() => ref.watch(contentApiProvider).item(id));
    });

/// Postable boards for the compose sheet (`status == active` filters in UI).
final contentBoardsProvider = FutureProvider.autoDispose<List<LkmBoard>>((
  ref,
) {
  final session = ref.watch(lkmApiSessionProvider);
  return session.run(() => ref.watch(contentApiProvider).boards());
});

/// Detail action buttons (like / favorite / forward) with optimistic updates.
class ContentViewerState {
  const ContentViewerState({
    required this.liked,
    required this.favorited,
    required this.likeCount,
    required this.bookmarkCount,
    required this.forwardCount,
    this.pending = false,
  });

  final bool liked;
  final bool favorited;
  final int likeCount;
  final int bookmarkCount;
  final int forwardCount;

  /// One like/favorite round-trip at a time; a double tap would flip the
  /// intent twice and leave the button out of sync.
  final bool pending;

  ContentViewerState copyWith({
    bool? liked,
    bool? favorited,
    int? likeCount,
    int? bookmarkCount,
    int? forwardCount,
    bool? pending,
  }) => ContentViewerState(
    liked: liked ?? this.liked,
    favorited: favorited ?? this.favorited,
    likeCount: likeCount ?? this.likeCount,
    bookmarkCount: bookmarkCount ?? this.bookmarkCount,
    forwardCount: forwardCount ?? this.forwardCount,
    pending: pending ?? this.pending,
  );
}

class ContentViewerNotifier extends AsyncNotifier<ContentViewerState> {
  ContentViewerNotifier(this.item);

  final LkmContentItem item;

  @override
  Future<ContentViewerState> build() async {
    final session = ref.read(lkmApiSessionProvider);
    final api = ref.read(contentApiProvider);
    final viewer = await session.run(() => api.viewerState(item.id));
    return ContentViewerState(
      liked: viewer?.liked ?? false,
      favorited: viewer?.favorited ?? false,
      likeCount: viewer?.likeCount ?? item.likeCount,
      bookmarkCount: viewer?.bookmarkCount ?? item.bookmarkCount,
      forwardCount: item.forwardCount,
    );
  }

  Future<void> toggleLike() async {
    final current = state.value;
    if (current == null || current.pending) return;
    final target = !current.liked;
    state = AsyncData(
      current.copyWith(
        liked: target,
        likeCount: current.likeCount + (target ? 1 : -1),
        pending: true,
      ),
    );
    final api = ref.read(contentApiProvider);
    try {
      final count = await ref
          .read(lkmApiSessionProvider)
          .run(() => target ? api.like(item.id) : api.unlike(item.id));
      state = AsyncData(state.value!.copyWith(likeCount: count, pending: false));
    } catch (_) {
      state = AsyncData(current.copyWith(pending: false));
      rethrow;
    }
  }

  Future<void> toggleFavorite() async {
    final current = state.value;
    if (current == null || current.pending) return;
    final target = !current.favorited;
    state = AsyncData(
      current.copyWith(
        favorited: target,
        bookmarkCount: current.bookmarkCount + (target ? 1 : -1),
        pending: true,
      ),
    );
    final api = ref.read(contentApiProvider);
    try {
      final count = await ref
          .read(lkmApiSessionProvider)
          .run(() => api.favorite(item.id, favorited: target));
      state = AsyncData(
        state.value!.copyWith(bookmarkCount: count, pending: false),
      );
    } catch (_) {
      state = AsyncData(current.copyWith(pending: false));
      rethrow;
    }
  }

  Future<void> forward() async {
    final count = await ref
        .read(lkmApiSessionProvider)
        .run(() => ref.read(contentApiProvider).forward(item.id));
    final latest = state.value;
    if (latest != null) {
      state = AsyncData(latest.copyWith(forwardCount: count));
    }
  }
}

final contentViewerProvider = AsyncNotifierProvider.autoDispose
    .family<ContentViewerNotifier, ContentViewerState, LkmContentItem>(
      ContentViewerNotifier.new,
    );

class ContentCommentsState {
  const ContentCommentsState({
    required this.items,
    required this.page,
    required this.pages,
    this.loadingMore = false,
    this.posting = false,
    this.error,
  });

  final List<LkmContentComment> items;
  final int page;
  final int pages;
  final bool loadingMore;
  final bool posting;
  final String? error;

  bool get hasMore => page < pages;

  ContentCommentsState copyWith({
    List<LkmContentComment>? items,
    int? page,
    int? pages,
    bool? loadingMore,
    bool? posting,
    String? error,
    bool clearError = false,
  }) => ContentCommentsState(
    items: items ?? this.items,
    page: page ?? this.page,
    pages: pages ?? this.pages,
    loadingMore: loadingMore ?? this.loadingMore,
    posting: posting ?? this.posting,
    error: clearError ? null : (error ?? this.error),
  );
}

class ContentCommentsNotifier extends AsyncNotifier<ContentCommentsState> {
  ContentCommentsNotifier(this.itemId);

  final String itemId;
  static const int pageSize = 20;

  @override
  Future<ContentCommentsState> build() => _page(1);

  Future<ContentCommentsState> _page(int page) async {
    final session = ref.read(lkmApiSessionProvider);
    final api = ref.read(contentApiProvider);
    final result = await session.run(
      () => api.comments(itemId, page: page, pageSize: pageSize),
    );
    return ContentCommentsState(
      items: result.items,
      page: result.page,
      pages: result.pages,
    );
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _page(1));
  }

  Future<void> loadMore() async {
    final current = state.value;
    if (current == null || current.loadingMore || !current.hasMore) return;

    state = AsyncData(current.copyWith(loadingMore: true, clearError: true));
    try {
      final next = await _page(current.page + 1);
      state = AsyncData(
        current.copyWith(
          items: [...current.items, ...next.items],
          page: next.page,
          pages: next.pages,
          loadingMore: false,
        ),
      );
    } catch (error) {
      state = AsyncData(current.copyWith(loadingMore: false, error: '$error'));
    }
  }

  /// Optimistically flips one comment's like, then adopts the server count.
  /// A failure rolls the whole list back to the pre-tap snapshot.
  Future<void> toggleCommentLike(String commentId) async {
    final current = state.value;
    if (current == null) return;
    final index = current.items.indexWhere((c) => c.id == commentId);
    if (index < 0) return;
    final comment = current.items[index];
    final target = !comment.liked;
    final optimistic = [...current.items];
    optimistic[index] = comment.copyWith(
      liked: target,
      likeCount: comment.likeCount + (target ? 1 : -1),
    );
    state = AsyncData(current.copyWith(items: optimistic));

    final api = ref.read(contentApiProvider);
    try {
      final count = await ref
          .read(lkmApiSessionProvider)
          .run(
            () => target
                ? api.likeComment(itemId, commentId)
                : api.unlikeComment(itemId, commentId),
          );
      final latest = state.value;
      if (latest == null) return;
      final list = [...latest.items];
      final at = list.indexWhere((c) => c.id == commentId);
      if (at >= 0) {
        list[at] = list[at].copyWith(likeCount: count);
        state = AsyncData(latest.copyWith(items: list, clearError: true));
      }
    } catch (error) {
      state = AsyncData(current.copyWith(error: '$error'));
    }
  }

  /// Posts a comment and reloads the first page so server-side ordering,
  /// floor numbers and counts are authoritative.
  Future<void> add(String content) async {
    final current = state.value;
    if (current == null || current.posting || content.trim().isEmpty) return;

    state = AsyncData(current.copyWith(posting: true, clearError: true));
    final session = ref.read(lkmApiSessionProvider);
    final api = ref.read(contentApiProvider);
    try {
      await session.run(() => api.addComment(itemId, content.trim()));
      final refreshed = await _page(1);
      state = AsyncData(refreshed);
    } catch (error) {
      state = AsyncData(current.copyWith(posting: false, error: '$error'));
    }
  }
}

final contentCommentsProvider = AsyncNotifierProvider.autoDispose
    .family<ContentCommentsNotifier, ContentCommentsState, String>(
      ContentCommentsNotifier.new,
    );
