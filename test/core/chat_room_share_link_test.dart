import 'package:flutter_test/flutter_test.dart';
import 'package:island/core/services/deeplink_service.dart';

void main() {
  setUp(() {
    DeeplinkService().configureSiteUrl(() => 'https://community.example');
  });
  tearDown(() => DeeplinkService().dispose());
  group('buildChatRoomShareUrl', () {
    test('builds the web share URL', () {
      expect(
        buildChatRoomShareUrl(scope: 'alice', slug: 'lounge').toString(),
        'https://community.example/chat/alice/lounge',
      );
      expect(
        buildChatRoomShareUrl(scope: 'solsynth', slug: 'general').toString(),
        'https://community.example/chat/solsynth/general',
      );
    });
  });

  group('parseChatRoomShareLink', () {
    test('accepts the web URL', () {
      final link = parseChatRoomShareLink(
        'https://community.example/chat/alice/lounge',
      );
      expect(link, isNotNull);
      expect(link!.scope, 'alice');
      expect(link.slug, 'lounge');
    });

    test('accepts trailing slashes and query params on the selected host', () {
      final link = parseChatRoomShareLink(
        'https://community.example/chat/alice/lounge/?utm=qr',
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
        parseChatRoomShareLink('https://www.community.example/chat/a/b'),
        isNull,
      );
      expect(
        parseChatRoomShareLink(
          'https://community.example.evil.example/chat/a/b',
        ),
        isNull,
      );
      expect(
        parseChatRoomShareLink('https://evil.example/chat/alice/lounge'),
        isNull,
      );
    });

    test('rejects other LKM routes', () {
      expect(
        parseChatRoomShareLink('https://community.example/accounts/alice'),
        isNull,
      );
      expect(
        parseChatRoomShareLink('https://community.example/chat/alice'),
        isNull,
      );
      expect(
        parseChatRoomShareLink(
          'https://community.example/chat/alice/lounge/extra',
        ),
        isNull,
      );
    });

    test('rejects empty segments and unrelated text', () {
      expect(
        parseChatRoomShareLink('https://community.example/chat//lounge'),
        isNull,
      );
      expect(parseChatRoomShareLink('hello world'), isNull);
      expect(parseChatRoomShareLink(''), isNull);
    });
  });
}
