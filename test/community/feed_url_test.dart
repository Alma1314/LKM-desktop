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
}
