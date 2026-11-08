import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:island/community/feed_pod.dart';
import 'package:island/core/api/api_providers.dart';
import 'package:island/core/api/api_session.dart';
import 'package:island/core/api/timeline_api.dart';

class _FakeTimeline implements TimelineApi {
  _FakeTimeline(this.pages);

  /// Each call consumes the next page; a thrown entry simulates a failure.
  final List<Object> pages;
  final List<String?> cursors = [];

  @override
  Future<FeedPage> timeline({
    String mode = 'hot',
    String? cursor,
    int limit = 20,
  }) async {
    cursors.add(cursor);
    final page = pages[cursors.length - 1];
    if (page is FeedPage) return page;
    throw page;
  }
}

FeedItem _item(String id) => FeedItem(
  itemType: 'discussion',
  id: id,
  authorName: 'alma',
  title: 'title $id',
  contentPreview: '',
  createdAt: DateTime(2026, 11, 8),
  sortScore: 0,
);

FeedPage _page(List<String> ids, {String? next}) =>
    FeedPage(items: ids.map(_item).toList(), nextCursor: next);

Future<ProviderContainer> _container(_FakeTimeline fake) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final session = ApiSession(prefs: prefs, serverUrl: 'https://lkm-ahz.ltd');
  final container = ProviderContainer(
    overrides: [
      lkmApiSessionProvider.overrideWithValue(session),
      timelineApiProvider.overrideWithValue(fake),
    ],
  );
  addTearDown(container.dispose);
  // Keep the auto-dispose provider alive across awaits.
  final subscription = container.listen(communityFeedProvider, (_, _) {});
  addTearDown(subscription.close);
  return container;
}

void main() {
  test(
    'loads hot for an anonymous session and appends the next page',
    () async {
      final fake = _FakeTimeline([
        _page(['a', 'b'], next: 'cursor-1'),
        _page(['c'], next: null),
      ]);
      final container = await _container(fake);

      final first = await container.read(communityFeedProvider.future);
      expect(first.mode, 'hot');
      expect(first.items.map((e) => e.id), ['a', 'b']);
      expect(first.hasMore, isTrue);

      await container.read(communityFeedProvider.notifier).loadMore();

      final second = container.read(communityFeedProvider).value!;
      expect(second.items.map((e) => e.id), ['a', 'b', 'c']);
      expect(second.nextCursor, isNull);
      expect(second.hasMore, isFalse);
      expect(fake.cursors, [null, 'cursor-1']);

      // Exhausted: a second loadMore must not hit the network again.
      await container.read(communityFeedProvider.notifier).loadMore();
      expect(fake.cursors, hasLength(2));
    },
  );

  test('a failed further page keeps the entries already shown', () async {
    final fake = _FakeTimeline([
      _page(['a'], next: 'cursor-1'),
      StateError('boom'),
    ]);
    final container = await _container(fake);

    await container.read(communityFeedProvider.future);
    await container.read(communityFeedProvider.notifier).loadMore();

    final state = container.read(communityFeedProvider).value!;
    expect(state.items.map((e) => e.id), ['a']);
    expect(state.loadingMore, isFalse);
    expect(state.loadMoreError, contains('boom'));
    expect(state.hasMore, isTrue);
  });
}
