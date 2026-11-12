import 'package:flutter_test/flutter_test.dart';

import 'package:island/core/api/content_api.dart';
import 'package:island/hub/hub_pod.dart';

LkmContentItem _item(
  String id, {
  bool pinned = false,
  bool featured = false,
  int views = 0,
  String created = '2026-11-01T00:00:00Z',
}) => LkmContentItem.fromJson({
  'id': id,
  'contentType': 'discussion',
  'title': id,
  'excerpt': '',
  'content': '',
  'authorName': '',
  'tags': const <String>[],
  'viewCount': views,
  'likeCount': 0,
  'commentCount': 0,
  'isPinned': pinned,
  'isFeatured': featured,
  'createdAt': created,
});

void main() {
  test('pinned posts lead both orderings', () {
    final items = [
      _item('new', created: '2026-11-10T00:00:00Z'),
      _item('pinned', pinned: true, created: '2026-10-01T00:00:00Z'),
    ];

    expect(orderBoardItems(items, hot: false).first.id, 'pinned');
    expect(orderBoardItems(items, hot: true).first.id, 'pinned');
  });

  test('hot ranks featured before views, latest by time', () {
    final items = [
      _item('plain', views: 99),
      _item('featured', featured: true, views: 1),
      _item('newest', created: '2026-11-09T00:00:00Z'),
    ];

    final hot = orderBoardItems(items, hot: true);
    expect(hot.map((e) => e.id), ['featured', 'plain', 'newest']);

    final latest = orderBoardItems(items, hot: false);
    expect(latest.first.id, 'newest');
  });
}
