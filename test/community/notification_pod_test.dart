import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:island/community/notification_pod.dart';
import 'package:island/core/api/api_client.dart';
import 'package:island/core/api/api_providers.dart';
import 'package:island/core/api/api_session.dart';
import 'package:island/core/api/notification_api.dart';

class _FakeNotifications implements NotificationApi {
  _FakeNotifications(this.pages);

  final List<ApiPage<LkmNotification>> pages;
  final List<int> requestedPages = [];
  final List<List<String>> markedIds = [];
  int markAllCalls = 0;

  @override
  Future<ApiPage<LkmNotification>> list({
    int page = 1,
    int limit = 20,
    bool unreadOnly = false,
  }) async {
    requestedPages.add(page);
    return pages[page - 1];
  }

  @override
  Future<int> unreadCount() async => 0;

  @override
  Future<int> markRead({List<String> ids = const [], bool all = false}) async {
    if (all) {
      markAllCalls++;
    } else {
      markedIds.add(ids);
    }
    return all ? 99 : ids.length;
  }
}

LkmNotification _notification(String id, {bool read = false}) =>
    LkmNotification(
      id: id,
      type: 'content_liked',
      payload: const {'title': 't'},
      createdAt: DateTime(2026, 11, 8, 12, 30),
      readAt: read ? DateTime(2026, 11, 8, 13) : null,
    );

ApiPage<LkmNotification> _page(
  List<LkmNotification> items, {
  required int page,
  required int pages,
}) => ApiPage(items: items, total: items.length, page: page, pages: pages);

Future<ProviderContainer> _container(_FakeNotifications fake) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final session = ApiSession(prefs: prefs, serverUrl: 'https://lkm-ahz.ltd');
  await session.adopt(
    const LkmTokenPair(accessToken: 'access', refreshToken: 'refresh'),
  );
  final container = ProviderContainer(
    overrides: [
      lkmApiSessionProvider.overrideWithValue(session),
      notificationApiProvider.overrideWithValue(fake),
    ],
  );
  addTearDown(container.dispose);
  final subscription = container.listen(
    communityNotificationsProvider,
    (_, _) {},
  );
  addTearDown(subscription.close);
  return container;
}

void main() {
  test('loads the first page and appends the next', () async {
    final fake = _FakeNotifications([
      _page([_notification('a'), _notification('b')], page: 1, pages: 2),
      _page([_notification('c')], page: 2, pages: 2),
    ]);
    final container = await _container(fake);

    final first = await container.read(communityNotificationsProvider.future);
    expect(first.items.map((e) => e.id), ['a', 'b']);
    expect(first.hasMore, isTrue);

    await container.read(communityNotificationsProvider.notifier).loadMore();

    final second = container.read(communityNotificationsProvider).value!;
    expect(second.items.map((e) => e.id), ['a', 'b', 'c']);
    expect(second.hasMore, isFalse);
    expect(fake.requestedPages, [1, 2]);
  });

  test('marking one read updates that entry and calls the API', () async {
    final fake = _FakeNotifications([
      _page([_notification('a'), _notification('b')], page: 1, pages: 1),
    ]);
    final container = await _container(fake);
    final initial = await container.read(communityNotificationsProvider.future);

    await container
        .read(communityNotificationsProvider.notifier)
        .markRead(initial.items.first);

    final state = container.read(communityNotificationsProvider).value!;
    expect(state.items.first.isUnread, isFalse);
    expect(state.items.last.isUnread, isTrue);
    expect(fake.markedIds.single, ['a']);
  });

  test('mark all read clears every unread entry', () async {
    final fake = _FakeNotifications([
      _page(
        [_notification('a'), _notification('b', read: true)],
        page: 1,
        pages: 1,
      ),
    ]);
    final container = await _container(fake);
    await container.read(communityNotificationsProvider.future);

    await container.read(communityNotificationsProvider.notifier).markAllRead();

    final state = container.read(communityNotificationsProvider).value!;
    expect(state.unreadCount, 0);
    expect(fake.markAllCalls, 1);
  });
}
