import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:island/community/content_detail_pod.dart';
import 'package:island/core/api/api_client.dart';
import 'package:island/core/api/api_providers.dart';
import 'package:island/core/api/api_session.dart';
import 'package:island/core/api/content_api.dart';

class _FakeContent implements ContentApi {
  _FakeContent(this.commentPages);

  final List<LkmCommentPage> commentPages;
  final List<int> requestedPages = [];
  final List<String> posted = [];

  LkmViewerState? viewer;
  int likeCount = 0;
  int bookmarkCount = 0;
  bool failLike = false;
  bool failFavorite = false;
  final List<String> writes = [];

  @override
  Future<LkmContentItem?> item(String id) async => null;

  @override
  Future<List<LkmBoard>> boards() async => const [];

  @override
  Future<ApiPage<LkmContentItem>> items({
    String? boardId,
    String? contentType,
    String? authorId,
    int page = 1,
    int pageSize = 20,
  }) async => const ApiPage.empty();

  @override
  Future<String> createDiscussion({
    required String boardId,
    required String title,
    required String content,
    List<String> tags = const [],
  }) async => 'new-item';

  @override
  Future<void> deleteItem(String contentId) async {}

  @override
  Future<LkmViewerState?> viewerState(String contentId) async => viewer;

  @override
  Future<int> like(String contentId) async {
    writes.add('like');
    if (failLike) throw StateError('like failed');
    return ++likeCount;
  }

  @override
  Future<int> unlike(String contentId) async {
    writes.add('unlike');
    if (failLike) throw StateError('unlike failed');
    return --likeCount;
  }

  @override
  Future<int> favorite(String contentId, {required bool favorited}) async {
    writes.add(favorited ? 'favorite' : 'unfavorite');
    if (failFavorite) throw StateError('favorite failed');
    bookmarkCount += favorited ? 1 : -1;
    return bookmarkCount;
  }

  @override
  Future<int> forward(String contentId) async => 4;

  @override
  Future<void> reportView(String contentId) async {}

  @override
  Future<int> likeComment(String itemId, String commentId) async => 1;

  @override
  Future<int> unlikeComment(String itemId, String commentId) async => 0;

  @override
  Future<void> report({
    required String targetType,
    required String targetId,
    required String reason,
  }) async {}

  @override
  Future<LkmCommentPage> comments(
    String itemId, {
    int page = 1,
    int pageSize = 20,
  }) async {
    requestedPages.add(page);
    return commentPages[requestedPages.length - 1];
  }

  @override
  Future<void> addComment(
    String itemId,
    String content, {
    String? parentId,
  }) async {
    posted.add(content);
  }

  @override
  String get graphqlUrl => 'https://community.example/graphql/v1';

  @override
  Future<ApiPage<LkmSavedItem>> favorites({
    int page = 1,
    int limit = 20,
  }) async => const ApiPage.empty();

  @override
  Future<ApiPage<LkmSavedItem>> history({int page = 1, int limit = 20}) async =>
      const ApiPage.empty();

  @override
  Future<List<LkmFollowBoard>> followingBoards() async => const [];

  @override
  Future<bool> setBoardFollow(String boardId, {required bool follow}) async =>
      follow;
}

LkmContentComment _comment(String id) => LkmContentComment(
  id: id,
  authorId: 'u1',
  authorName: 'bob',
  content: 'comment $id',
  floorNumber: 1,
  likeCount: 0,
  liked: false,
  createdAt: DateTime(2026, 11, 8),
);

LkmCommentPage _page(
  List<LkmContentComment> items, {
  required int page,
  required int pages,
}) =>
    LkmCommentPage(items: items, total: items.length, page: page, pages: pages);

Future<ProviderContainer> _container(_FakeContent fake) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final session = ApiSession(
    prefs: prefs,
    serverUrl: 'https://community.example',
  );
  final container = ProviderContainer(
    overrides: [
      lkmApiSessionProvider.overrideWithValue(session),
      contentApiProvider.overrideWithValue(fake),
    ],
  );
  addTearDown(container.dispose);
  final subscription = container.listen(
    contentCommentsProvider('item-1'),
    (_, _) {},
  );
  addTearDown(subscription.close);
  return container;
}

/// One instance: the viewer provider is keyed by the item object itself.
final _viewerItem = LkmContentItem(
  id: 'item-1',
  contentType: 'discussion',
  title: 't',
  excerpt: '',
  content: '',
  authorName: 'alma',
  tags: const [],
  viewCount: 0,
  likeCount: 3,
  commentCount: 0,
  bookmarkCount: 1,
  forwardCount: 0,
  createdAt: DateTime(2026, 11, 8),
);

Future<ProviderContainer> _viewerContainer(_FakeContent fake) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final session = ApiSession(
    prefs: prefs,
    serverUrl: 'https://community.example',
  );
  final container = ProviderContainer(
    overrides: [
      lkmApiSessionProvider.overrideWithValue(session),
      contentApiProvider.overrideWithValue(fake),
    ],
  );
  addTearDown(container.dispose);
  final subscription = container.listen(
    contentViewerProvider(_viewerItem),
    (_, _) {},
  );
  addTearDown(subscription.close);
  return container;
}

void main() {
  test('viewer state seeds from GraphQL, then adopts server counts', () async {
    final fake = _FakeContent(const [])
      ..viewer = const LkmViewerState(
        liked: false,
        favorited: false,
        likeCount: 3,
        bookmarkCount: 1,
      )
      ..likeCount = 3
      ..bookmarkCount = 1;
    final container = await _viewerContainer(fake);

    final initial = await container.read(
      contentViewerProvider(_viewerItem).future,
    );
    expect(initial.liked, isFalse);
    expect(initial.likeCount, 3);

    await container
        .read(contentViewerProvider(_viewerItem).notifier)
        .toggleLike();
    final liked = container.read(contentViewerProvider(_viewerItem)).value!;
    expect(liked.liked, isTrue);
    expect(liked.likeCount, 4);
    expect(liked.pending, isFalse);
    expect(fake.writes, ['like']);

    await container
        .read(contentViewerProvider(_viewerItem).notifier)
        .toggleFavorite();
    final favorited = container.read(contentViewerProvider(_viewerItem)).value!;
    expect(favorited.favorited, isTrue);
    expect(favorited.bookmarkCount, 2);
    expect(fake.writes, ['like', 'favorite']);
  });

  test('a failed like rolls the button back and surfaces the error', () async {
    final fake = _FakeContent(const [])
      ..viewer = const LkmViewerState(
        liked: false,
        favorited: false,
        likeCount: 3,
        bookmarkCount: 1,
      )
      ..likeCount = 3
      ..failLike = true;
    final container = await _viewerContainer(fake);
    await container.read(contentViewerProvider(_viewerItem).future);

    await expectLater(
      container.read(contentViewerProvider(_viewerItem).notifier).toggleLike(),
      throwsStateError,
    );

    final state = container.read(contentViewerProvider(_viewerItem)).value!;
    expect(state.liked, isFalse);
    expect(state.likeCount, 3);
    expect(state.pending, isFalse);
  });

  test('comment like flips one row against the server count', () async {
    final fake = _FakeContent([
      _page([_comment('a'), _comment('b')], page: 1, pages: 1),
    ]);
    final container = await _container(fake);
    await container.read(contentCommentsProvider('item-1').future);

    await container
        .read(contentCommentsProvider('item-1').notifier)
        .toggleCommentLike('a');

    final items = container
        .read(contentCommentsProvider('item-1'))
        .value!
        .items;
    expect(items[0].liked, isTrue);
    expect(items[0].likeCount, 1);
    expect(items[1].liked, isFalse);
  });

  test('loads the first page and appends the next', () async {
    final fake = _FakeContent([
      _page([_comment('a'), _comment('b')], page: 1, pages: 2),
      _page([_comment('c')], page: 2, pages: 2),
    ]);
    final container = await _container(fake);

    final first = await container.read(
      contentCommentsProvider('item-1').future,
    );
    expect(first.items.map((e) => e.id), ['a', 'b']);
    expect(first.hasMore, isTrue);

    await container.read(contentCommentsProvider('item-1').notifier).loadMore();

    final second = container.read(contentCommentsProvider('item-1')).value!;
    expect(second.items.map((e) => e.id), ['a', 'b', 'c']);
    expect(second.hasMore, isFalse);
    expect(fake.requestedPages, [1, 2]);
  });

  test('posting a comment writes it and reloads the first page', () async {
    final fake = _FakeContent([
      _page([_comment('a')], page: 1, pages: 1),
      _page([_comment('new'), _comment('a')], page: 1, pages: 1),
    ]);
    final container = await _container(fake);
    await container.read(contentCommentsProvider('item-1').future);

    await container
        .read(contentCommentsProvider('item-1').notifier)
        .add('  你好  ');

    expect(fake.posted.single, '你好');
    final state = container.read(contentCommentsProvider('item-1')).value!;
    expect(state.items.first.id, 'new');
    expect(state.posting, isFalse);
    expect(fake.requestedPages, [1, 1]);
  });

  test('an empty body is not posted', () async {
    final fake = _FakeContent([_page(const [], page: 1, pages: 0)]);
    final container = await _container(fake);
    await container.read(contentCommentsProvider('item-1').future);

    await container.read(contentCommentsProvider('item-1').notifier).add('   ');

    expect(fake.posted, isEmpty);
  });
}
