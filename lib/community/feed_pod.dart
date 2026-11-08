import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:island/core/api/api_providers.dart';
import 'package:island/core/api/timeline_api.dart';

/// The timeline client for the configured server.
///
/// Kept separate from the session so tests can swap the transport while the
/// notifier's cursor bookkeeping stays under test.
final timelineApiProvider = Provider<TimelineApi>((ref) {
  return TimelineApi(ref.watch(lkmApiSessionProvider).client);
});

class CommunityFeedState {
  const CommunityFeedState({
    required this.mode,
    required this.items,
    this.nextCursor,
    this.loadingMore = false,
    this.loadMoreError,
  });

  /// `follow` or `hot`.
  final String mode;
  final List<FeedItem> items;
  final String? nextCursor;
  final bool loadingMore;

  /// Failure of a further-page request, kept beside the list so one bad page
  /// does not blank out the entries already on screen.
  final String? loadMoreError;

  bool get hasMore => nextCursor != null;

  CommunityFeedState copyWith({
    List<FeedItem>? items,
    String? nextCursor,
    bool clearNextCursor = false,
    bool? loadingMore,
    String? loadMoreError,
    bool clearLoadMoreError = false,
  }) => CommunityFeedState(
    mode: mode,
    items: items ?? this.items,
    nextCursor: clearNextCursor ? null : (nextCursor ?? this.nextCursor),
    loadingMore: loadingMore ?? this.loadingMore,
    loadMoreError: clearLoadMoreError
        ? null
        : (loadMoreError ?? this.loadMoreError),
  );
}

/// Cursor-paginated timeline. The first page follows the session: follow when
/// signed in, hot otherwise — the service returns an empty follow feed to
/// anonymous callers.
class CommunityFeedNotifier extends AsyncNotifier<CommunityFeedState> {
  static const int pageSize = 20;

  @override
  Future<CommunityFeedState> build() {
    final signedIn = ref.watch(lkmApiSessionProvider).isSignedIn;
    return _firstPage(signedIn ? 'follow' : 'hot');
  }

  Future<FeedPage> _fetch({required String mode, String? cursor}) {
    final session = ref.read(lkmApiSessionProvider);
    final api = ref.read(timelineApiProvider);
    return session.run(
      () => api.timeline(mode: mode, cursor: cursor, limit: pageSize),
    );
  }

  Future<CommunityFeedState> _firstPage(String mode) async {
    final page = await _fetch(mode: mode);
    return CommunityFeedState(
      mode: mode,
      items: page.items,
      nextCursor: page.nextCursor,
    );
  }

  Future<void> switchMode(String mode) async {
    if (state.value?.mode == mode) return;
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _firstPage(mode));
  }

  Future<void> refresh() async {
    final mode = state.value?.mode ?? 'hot';
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _firstPage(mode));
  }

  Future<void> loadMore() async {
    final current = state.value;
    if (current == null || current.loadingMore || !current.hasMore) return;

    state = AsyncData(
      current.copyWith(loadingMore: true, clearLoadMoreError: true),
    );
    try {
      final page = await _fetch(mode: current.mode, cursor: current.nextCursor);
      state = AsyncData(
        current.copyWith(
          items: [...current.items, ...page.items],
          nextCursor: page.nextCursor,
          clearNextCursor: page.nextCursor == null,
          loadingMore: false,
        ),
      );
    } catch (error) {
      state = AsyncData(
        current.copyWith(loadingMore: false, loadMoreError: '$error'),
      );
    }
  }
}

final communityFeedProvider =
    AsyncNotifierProvider.autoDispose<
      CommunityFeedNotifier,
      CommunityFeedState
    >(CommunityFeedNotifier.new);
