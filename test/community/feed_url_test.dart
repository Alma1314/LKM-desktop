import 'package:flutter_test/flutter_test.dart';

import 'package:island/community/feed_links.dart';

void main() {
  test('relative paths resolve against the configured server', () {
    expect(
      resolveFeedUrl('/forum/post/1', 'https://lkm-ahz.ltd'),
      'https://lkm-ahz.ltd/forum/post/1',
    );
  });

  test('absolute http(s) links pass through', () {
    expect(
      resolveFeedUrl('https://example.com/a', 'https://lkm-ahz.ltd'),
      'https://example.com/a',
    );
  });

  test('other schemes are rejected', () {
    expect(
      resolveFeedUrl('javascript:alert(1)', 'https://lkm-ahz.ltd'),
      isNull,
    );
    expect(resolveFeedUrl('data:text/html,x', 'https://lkm-ahz.ltd'), isNull);
    expect(
      resolveFeedUrl('ftp://example.com/a', 'https://lkm-ahz.ltd'),
      isNull,
    );
  });

  test('empty values and missing host are rejected', () {
    expect(resolveFeedUrl(null, 'https://lkm-ahz.ltd'), isNull);
    expect(resolveFeedUrl('  ', 'https://lkm-ahz.ltd'), isNull);
    expect(resolveFeedUrl('/forum/post/1', null), isNull);
  });
}
