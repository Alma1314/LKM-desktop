import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:island/community/content_detail_pod.dart';
import 'package:island/core/api/api_providers.dart';
import 'package:island/core/api/api_session.dart';
import 'package:island/core/api/content_api.dart';

class _FakeContent implements ContentApi {
  _FakeContent(this.commentPages);

  final List<LkmCommentPage> commentPages;
  final List<int> requestedPages = [];
  final List<String> posted = [];

  @override
  Future<LkmContentItem?> item(String id) async => null;

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
  String get graphqlUrl => 'https://lkm-ahz.ltd/graphql/v1';
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
  final session = ApiSession(prefs: prefs, serverUrl: 'https://lkm-ahz.ltd');
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

void main() {
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
