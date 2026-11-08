import 'package:flutter_test/flutter_test.dart';
import 'package:island/core/services/deeplink_service.dart';
import 'package:island/route.dart';

void main() {
  final router = AppRouter();

  group('isKnownInAppRoutePath', () {
    test('accepts every concrete in-app route', () {
      for (final path in [
        '/',
        '/explore',
        '/chat',
        '/chat/room-1',
        '/chat/room-1/detail',
        '/chat/room-1/search',
        '/chat/search',
        '/realms',
        '/realms/foo',
        '/account/me/leveling',
        '/account/stickers',
        '/account/stickers/pack-1',
        '/wallet',
        '/wallet/transactions/42',
        '/orders/42',
        '/posts/123',
        '/posts/123?tab=comments',
        '/publishers/name',
        '/accounts/some-name',
        '/calendar/name',
        '/calendar/name/events/42',
        '/settings',
        '/search',
        '/files/abc',
        '/creators/pub/posts',
        '/creators/pub/stickers/pack-1',
      ]) {
        expect(isKnownInAppRoutePath(router, path), isTrue, reason: path);
      }
    });

    test('rejects paths that only match the 404 catch-all', () {
      for (final path in [
        '/nonexistent',
        '/posts/123/extra',
        '/realms/foo/bar',
        '/wallet/transactions',
        '/account/workspaces',
        '/account/me/leveling/extra',
        '/chat/room-1/unknown',
      ]) {
        expect(isKnownInAppRoutePath(router, path), isFalse, reason: path);
      }
    });
  });

  test('lkmLinkWebUrl maps custom-scheme links to the web app', () {
    expect(
      lkmLinkWebUrl(Uri.parse('lkm://posts/123'))?.toString(),
      'https://lkm-ahz.ltd/posts/123',
    );
    expect(
      lkmLinkWebUrl(
        Uri.parse('lkm://posts/123?tab=comments'),
      )?.toString(),
      'https://lkm-ahz.ltd/posts/123?tab=comments',
    );
    expect(
      lkmLinkWebUrl(Uri.parse('https://lkm-ahz.ltd/posts/123'))?.toString(),
      'https://lkm-ahz.ltd/posts/123',
    );
    expect(lkmLinkWebUrl(Uri.parse('https://example.com/x')), isNull);
    expect(lkmLinkWebUrl(Uri.parse('https://api.lkm-ahz.ltd/x')), isNull);
  });

  test('lkmLinkBrowserUrl avoids Android app-link re-entry', () {
    expect(
      lkmLinkBrowserUrl(Uri.parse('lkm://posts/123'))?.toString(),
      'https://www.lkm-ahz.ltd/posts/123',
    );
    expect(
      lkmLinkBrowserUrl(
        Uri.parse('https://lkm-ahz.ltd/nonexistent'),
      )?.toString(),
      'https://www.lkm-ahz.ltd/nonexistent',
    );
    expect(lkmLinkBrowserUrl(Uri.parse('https://example.com/x')), isNull);
  });
}
