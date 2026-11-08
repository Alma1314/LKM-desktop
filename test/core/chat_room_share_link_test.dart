import 'package:flutter_test/flutter_test.dart';
import 'package:island/core/services/deeplink_service.dart';

void main() {
  group('buildChatRoomShareUrl', () {
    test('builds the web share URL', () {
      expect(
        buildChatRoomShareUrl(scope: 'alice', slug: 'lounge').toString(),
        'https://lkm-ahz.ltd/chat/alice/lounge',
      );
      expect(
        buildChatRoomShareUrl(scope: 'solsynth', slug: 'general').toString(),
        'https://lkm-ahz.ltd/chat/solsynth/general',
      );
    });
  });

  group('parseChatRoomShareLink', () {
    test('accepts the web URL', () {
      final link = parseChatRoomShareLink(
        'https://lkm-ahz.ltd/chat/alice/lounge',
      );
      expect(link, isNotNull);
      expect(link!.scope, 'alice');
      expect(link.slug, 'lounge');
    });

    test('accepts subdomain hosts and trailing slashes and query params', () {
      final link = parseChatRoomShareLink(
        'https://www.lkm-ahz.ltd/chat/alice/lounge/?utm=qr',
      );
      expect(link, isNotNull);
      expect(link!.scope, 'alice');
      expect(link.slug, 'lounge');
    });

    test('accepts bare in-app paths', () {
      final link = parseChatRoomShareLink('/chat/realm-slug/room-slug');
      expect(link, isNotNull);
      expect(link!.scope, 'realm-slug');
      expect(link.slug, 'room-slug');
    });

    test('accepts the LKM custom scheme', () {
      final link = parseChatRoomShareLink('lkm://chat/alice/lounge');
      expect(link, isNotNull);
      expect(link!.scope, 'alice');
      expect(link.slug, 'lounge');
    });

    test('rejects non-LKM hosts', () {
      expect(
        parseChatRoomShareLink('https://evil.example/chat/alice/lounge'),
        isNull,
      );
    });

    test('rejects other LKM routes', () {
      expect(parseChatRoomShareLink('https://lkm-ahz.ltd/accounts/alice'), isNull);
      expect(parseChatRoomShareLink('https://lkm-ahz.ltd/chat/alice'), isNull);
      expect(
        parseChatRoomShareLink('https://lkm-ahz.ltd/chat/alice/lounge/extra'),
        isNull,
      );
    });

    test('rejects empty segments and unrelated text', () {
      expect(parseChatRoomShareLink('https://lkm-ahz.ltd/chat//lounge'), isNull);
      expect(parseChatRoomShareLink('hello world'), isNull);
      expect(parseChatRoomShareLink(''), isNull);
    });
  });
}
