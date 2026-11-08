import 'package:solar_network_sdk/solar_network_sdk.dart';
import 'package:test/test.dart';

/// Actor endpoint payload as served by a Solar Network build that predates the
/// fediverse actor/publisher merge: the ActivityPub actor document itself, with
/// `type` holding the actor kind and every member flat.
const _legacyActorJson = {
  'id': 'f1bd2951-d320-430f-af22-3038ff291ea9',
  'type': 'Person',
  'uri': 'https://sc.littlesheep.me/users/littlesheep',
  'username': 'littlesheep',
  'display_name': 'LittleSheep',
  'bio': '<p>If you see this actor being active</p>',
  'inbox_uri': null,
  'outbox_uri': null,
  'followers_uri': null,
  'following_uri': null,
  'featured_uri': null,
  'public_key_id': null,
  'public_key': null,
  'metadata': null,
  'avatar_url': 'https://sc.littlesheep.me/fileserver/a.jpeg',
  'header_url': 'https://sc.littlesheep.me/fileserver/b.jpeg',
  'is_bot': false,
  'is_locked': false,
  'is_discoverable': true,
  'is_community': false,
  'realm_id': null,
  'instance_id': 'c226685f-ddc1-442e-a089-9de5c92b4bdf',
  'instance': {
    'id': 'c226685f-ddc1-442e-a089-9de5c92b4bdf',
    'domain': 'sc.littlesheep.me',
    'name': 'sc.littlesheep.me',
  },
  'last_fetched_at': '2026-04-11T04:37:40.136647Z',
  'last_activity_at': null,
  'outbox_fetched_at': null,
  'publisher_id': null,
  'full_handle': 'littlesheep@sc.littlesheep.me',
  'web_url': 'https://sc.littlesheep.me/@littlesheep',
  'followers_count': 0,
  'following_count': 0,
  'post_count': 0,
  'total_post_count': null,
  'created_at': '1970-01-01T00:00:00Z',
  'updated_at': '1970-01-01T00:00:00Z',
  'deleted_at': null,
};

/// Publisher payload as served once remote actors were merged into the publisher
/// table but before the ActivityPub identity was nested.
const _flatMergedJson = {
  'id': '90b66864-d100-4755-a089-825c7ce49785',
  'type': 2, // PublisherType.fediverse
  'name': 'littlesheep2code',
  'nick': 'littlesheep2code',
  'bio': 'Builder of the #solar-network',
  'actor_type': 'Person',
  'username': 'littlesheep2code',
  'avatar_url': 'https://files.mastodon.social/a.png',
  'followers_count': 3,
  'following_count': 4,
  'post_count': 8,
  'is_following': true,
  'instance': {'domain': 'mastodon.social', 'software': 'Mastodon'},
};

/// Current publisher payload: the ActivityPub identity lives under `activitypub`
/// and avatars/headers are file references addressed by `url`.
const _nestedJson = {
  'id': '52f7c7eb-da51-49cd-a326-af8df68a9aad',
  'type': 2, // PublisherType.fediverse
  'name': 'littlesheep2code@mastodon.social',
  'nick': 'LittleSheep',
  'bio': '<p>Builder</p>',
  'picture': {
    'id': '',
    'name': '',
    'file_meta': <String, dynamic>{},
    'user_meta': <String, dynamic>{},
    'sensitive_marks': <int>[],
    'mime_type': null,
    'hash': null,
    'size': 0,
    'has_compression': false,
    'has_thumbnail': false,
    'status': 0,
    'url': 'https://files.mastodon.social/accounts/avatars/x.png',
    'width': null,
    'height': null,
    'blurhash': null,
    'usage': null,
    'application_type': null,
    'created_at': '2025-12-29T16:44:39Z',
    'updated_at': '2025-12-29T16:44:40Z',
    'deleted_at': null,
  },
  'background': {
    'id': '',
    'name': '',
    'url': 'https://files.mastodon.social/accounts/headers/y.jpg',
  },
  'display_name': 'LittleSheep',
  'activitypub': {
    'uri': 'https://mastodon.social/ap/users/115797665137366717',
    'actor_type': 'Person',
    'username': 'littlesheep2code',
    'instance_id': '90b66864-d100-4755-a089-825c7ce49785',
    'instance_domain': 'mastodon.social',
    'inbox_uri': 'https://mastodon.social/ap/users/1/inbox',
    'outbox_uri': 'https://mastodon.social/ap/users/1/outbox',
    'followers_uri': null,
    'following_uri': null,
    'featured_uri': null,
    'public_key_id': 'https://mastodon.social/ap/users/1#main-key',
    'public_key': 'PEM',
    'is_bot': false,
    'is_locked': false,
    'is_discoverable': true,
    'is_community': false,
    'last_fetched_at': null,
    'last_activity_at': null,
    'outbox_fetched_at': null,
    'followers_count': 0,
    'following_count': 0,
    'post_count': 0,
    'total_post_count': null,
    'full_handle': 'littlesheep2code@mastodon.social',
    'web_url': 'https://mastodon.social/ap/@115797665137366717',
  },
  'account_id': null,
  'realm_id': null,
  'rating': 100,
  'rating_level': 0,
  'resource_identifier':
      'publisher:52f7c7eb-da51-49cd-a326-af8df68a9aad',
  'created_at': '2025-12-29T16:44:39Z',
  'updated_at': '2025-12-29T16:44:40Z',
  'deleted_at': null,
};

void main() {
  group('SnPublisher.fromJson current payload', () {
    test('reads the nested activitypub identity', () {
      final publisher = SnPublisher.fromJson(_nestedJson);

      expect(publisher.isFediverse, isTrue);
      expect(publisher.type, PublisherType.fediverse.index);
      expect(publisher.nick, 'LittleSheep');
      expect(publisher.displayName, 'LittleSheep');
      expect(publisher.effectiveName, 'LittleSheep');
      expect(
        publisher.activitypub?.uri,
        'https://mastodon.social/ap/users/115797665137366717',
      );
      expect(publisher.activitypub?.actorType, 'Person');
      expect(publisher.activitypub?.username, 'littlesheep2code');
      expect(publisher.activitypub?.publicKeyId,
          'https://mastodon.social/ap/users/1#main-key');
      expect(publisher.activitypub?.publicKey, 'PEM');
      expect(publisher.activitypub?.isLocked, isFalse);
      expect(publisher.activitypub?.isDiscoverable, isTrue);
      expect(publisher.activitypub?.fullHandle,
          'littlesheep2code@mastodon.social');
      expect(publisher.activitypub?.webUrl,
          'https://mastodon.social/ap/@115797665137366717');
      expect(publisher.domain, 'mastodon.social');
      expect(publisher.handle, 'littlesheep2code@mastodon.social');
    });

    test('resolves avatars and headers from the file references', () {
      final publisher = SnPublisher.fromJson(_nestedJson);

      expect(publisher.picture?.storageUrl,
          'https://files.mastodon.social/accounts/avatars/x.png');
      expect(publisher.picture?.id, '');
      expect(publisher.background?.storageUrl,
          'https://files.mastodon.social/accounts/headers/y.jpg');
    });

    test('leaves the identity null for a local publisher', () {
      final publisher = SnPublisher.fromJson({
        'id': 'publisher-1',
        'type': PublisherType.organizational.index,
        'name': 'solar',
        'nick': 'Solar Network',
        'picture': {'id': 'file-1', 'name': 'a.png'},
        'is_following': false,
      });

      expect(publisher.activitypub, isNull);
      expect(publisher.isFediverse, isFalse);
      expect(publisher.effectiveName, 'Solar Network');
      expect(publisher.handle, 'solar');
      expect(publisher.picture?.storageUrl, isNull);
      expect(publisher.picture?.id, 'file-1');
    });
  });

  group('SnPublisher.fromJson legacy payloads', () {
    test('lifts the flat ActivityPub actor document into activitypub', () {
      final publisher = SnPublisher.fromJson(_legacyActorJson);

      expect(publisher.type, PublisherType.fediverse.index);
      expect(publisher.isFediverse, isTrue);
      expect(publisher.activitypub?.actorType, 'Person');
      expect(publisher.id, 'f1bd2951-d320-430f-af22-3038ff291ea9');
      expect(publisher.activitypub?.uri,
          'https://sc.littlesheep.me/users/littlesheep');
      expect(publisher.activitypub?.username, 'littlesheep');
      expect(publisher.displayName, 'LittleSheep');
      expect(publisher.effectiveName, 'LittleSheep');
      expect(publisher.activitypub?.fullHandle,
          'littlesheep@sc.littlesheep.me');
      expect(publisher.activitypub?.webUrl,
          'https://sc.littlesheep.me/@littlesheep');
      expect(publisher.instance?.domain, 'sc.littlesheep.me');
      expect(publisher.domain, 'sc.littlesheep.me');
      expect(publisher.handle, 'littlesheep@sc.littlesheep.me');
      expect(publisher.activitypub?.isBot, isFalse);
      expect(publisher.activitypub?.isDiscoverable, isTrue);
      expect(publisher.activitypub?.followersCount, 0);
      expect(publisher.picture?.storageUrl,
          'https://sc.littlesheep.me/fileserver/a.jpeg');
      expect(publisher.background?.storageUrl,
          'https://sc.littlesheep.me/fileserver/b.jpeg');
    });

    test('keeps an explicit actor type over the legacy type member', () {
      final publisher = SnPublisher.fromJson({
        ..._legacyActorJson,
        'actor_type': 'Service',
      });

      expect(publisher.activitypub?.actorType, 'Service');
      expect(publisher.type, PublisherType.fediverse.index);
    });

    test('lifts the flat merged publisher shape into activitypub', () {
      final publisher = SnPublisher.fromJson(_flatMergedJson);

      expect(publisher.type, PublisherType.fediverse.index);
      expect(publisher.activitypub?.actorType, 'Person');
      expect(publisher.nick, 'littlesheep2code');
      expect(publisher.activitypub?.postCount, 8);
      expect(publisher.activitypub?.followersCount, 3);
      expect(publisher.isFollowing, isTrue);
      expect(publisher.domain, 'mastodon.social');
      expect(publisher.picture?.storageUrl,
          'https://files.mastodon.social/a.png');
    });
  });
}
