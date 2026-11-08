import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:island/core/api/api_providers.dart';
import 'package:island/core/api/notification_api.dart';

final notificationApiProvider = Provider<NotificationApi>((ref) {
  return NotificationApi(ref.watch(lkmApiSessionProvider).client);
});

/// Badge count for the community bell. Stays 0 when signed out.
final lkmUnreadNotificationsProvider = FutureProvider.autoDispose<int>((
  ref,
) async {
  final session = ref.watch(lkmApiSessionProvider);
  if (!session.isSignedIn) return 0;
  return session.run(() => ref.watch(notificationApiProvider).unreadCount());
});

class NotificationsState {
  const NotificationsState({
    required this.items,
    required this.page,
    required this.pages,
    this.loadingMore = false,
    this.loadMoreError,
  });

  final List<LkmNotification> items;
  final int page;
  final int pages;
  final bool loadingMore;
  final String? loadMoreError;

  bool get hasMore => page < pages;
  int get unreadCount => items.where((e) => e.isUnread).length;

  NotificationsState copyWith({
    List<LkmNotification>? items,
    int? page,
    int? pages,
    bool? loadingMore,
    String? loadMoreError,
    bool clearLoadMoreError = false,
  }) => NotificationsState(
    items: items ?? this.items,
    page: page ?? this.page,
    pages: pages ?? this.pages,
    loadingMore: loadingMore ?? this.loadingMore,
    loadMoreError: clearLoadMoreError
        ? null
        : (loadMoreError ?? this.loadMoreError),
  );
}

class CommunityNotificationsNotifier extends AsyncNotifier<NotificationsState> {
  static const int pageSize = 30;

  @override
  Future<NotificationsState> build() async {
    if (!ref.watch(lkmApiSessionProvider).isSignedIn) {
      return const NotificationsState(items: [], page: 1, pages: 1);
    }
    return _page(1);
  }

  Future<NotificationsState> _page(int page) async {
    final session = ref.read(lkmApiSessionProvider);
    final api = ref.read(notificationApiProvider);
    final result = await session.run(
      () => api.list(page: page, limit: pageSize),
    );
    return NotificationsState(
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

    state = AsyncData(
      current.copyWith(loadingMore: true, clearLoadMoreError: true),
    );
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
      state = AsyncData(
        current.copyWith(loadingMore: false, loadMoreError: '$error'),
      );
    }
  }

  Future<void> markAllRead() async {
    final current = state.value;
    if (current == null || current.unreadCount == 0) return;
    final session = ref.read(lkmApiSessionProvider);
    final api = ref.read(notificationApiProvider);
    await session.run(() => api.markRead(all: true));
    final now = DateTime.now();
    state = AsyncData(
      current.copyWith(
        items: current.items
            .map((e) => e.isUnread ? e.withReadAt(now) : e)
            .toList(growable: false),
      ),
    );
    ref.invalidate(lkmUnreadNotificationsProvider);
  }

  Future<void> markRead(LkmNotification notification) async {
    final current = state.value;
    if (current == null || !notification.isUnread) return;
    final session = ref.read(lkmApiSessionProvider);
    final api = ref.read(notificationApiProvider);
    await session.run(() => api.markRead(ids: [notification.id]));
    state = AsyncData(
      current.copyWith(
        items: current.items
            .map(
              (e) => e.id == notification.id ? e.withReadAt(DateTime.now()) : e,
            )
            .toList(growable: false),
      ),
    );
    ref.invalidate(lkmUnreadNotificationsProvider);
  }
}

final communityNotificationsProvider =
    AsyncNotifierProvider.autoDispose<
      CommunityNotificationsNotifier,
      NotificationsState
    >(CommunityNotificationsNotifier.new);
