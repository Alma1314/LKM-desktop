import 'package:flutter_test/flutter_test.dart';

import 'package:island/community/feed_links.dart';

void main() {
  test('relative paths resolve against the configured server', () {
    expect(
      resolveFeedUrl('/forum/post/1', 'https://community.example'),
      'https://community.example/forum/post/1',
    );
  });

  test('absolute http(s) links pass through', () {
    expect(
      resolveFeedUrl('https://example.com/a', 'https://community.example'),
      'https://example.com/a',
    );
  });

  test('other schemes are rejected', () {
    expect(
      resolveFeedUrl('javascript:alert(1)', 'https://community.example'),
      isNull,
    );
    expect(resolveFeedUrl('data:text/html,x', 'https://community.example'), isNull);
    expect(
      resolveFeedUrl('ftp://example.com/a', 'https://community.example'),
      isNull,
    );
  });

  test('empty values and missing host are rejected', () {
    expect(resolveFeedUrl(null, 'https://community.example'), isNull);
    expect(resolveFeedUrl('  ', 'https://community.example'), isNull);
    expect(resolveFeedUrl('/forum/post/1', null), isNull);
  });

  test('server links map onto native routes', () {
    expect(
      parseFeedRoute('/content/posts/abc')?.kind,
      FeedRouteKind.content,
    );
    expect(parseFeedRoute('/content/posts/abc')?.id, 'abc');
    expect(parseFeedRoute('/forum/post/abc')?.kind, FeedRouteKind.content);
    expect(parseFeedRoute('/qa/q1?from=notice')?.kind, FeedRouteKind.qa);
    expect(parseFeedRoute('/projects/p1')?.kind, FeedRouteKind.project);
    expect(parseFeedRoute('/files/f1')?.kind, FeedRouteKind.file);
    expect(parseFeedRoute('/library/files/f1')?.kind, FeedRouteKind.file);
    expect(parseFeedRoute('/treehole/letters/1')?.kind, FeedRouteKind.treehole);
  });

  test('external and unknown links stay with the browser', () {
    expect(parseFeedRoute('https://example.com/qa/q1'), isNull);
    expect(parseFeedRoute('/unknown/thing'), isNull);
    expect(parseFeedRoute('/qa'), isNull);
    expect(parseFeedRoute(null), isNull);
  });
}
