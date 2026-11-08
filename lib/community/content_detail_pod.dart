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
