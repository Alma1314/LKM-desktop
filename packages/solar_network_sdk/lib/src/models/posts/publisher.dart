import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:solar_network_sdk/solar_network_sdk.dart';

part 'publisher.freezed.dart';
part 'publisher.g.dart';

/// Kind of a publisher. Remote fediverse actors are mirrored as
/// [PublisherType.fediverse] publishers, so every actor-shaped payload is a
/// publisher on the wire.
enum PublisherType {
  @JsonValue(0)
  individual,
  @JsonValue(1)
  organizational,
  @JsonValue(2)
  fediverse,
}

/// State of the single relationship row that backs both local subscriptions
/// and gatekept follow requests.
enum PublisherSubscriptionState {
  @JsonValue(0)
  pending,
  @JsonValue(1)
  accepted,
  @JsonValue(2)
  rejected,
}

enum SubscriptionEndReason {
  @JsonValue(0)
  userLeft,
  @JsonValue(1)
  removedByPublisher,
}

/// ActivityPub members that older builds served flat on the publisher instead of
/// inside `activitypub`. The names match the nested members one to one.
const _legacyIdentityKeys = [
  'uri',
  'actor_type',
  'username',
  'instance_id',
  'instance_domain',
  'inbox_uri',
  'outbox_uri',
  'followers_uri',
  'following_uri',
  'featured_uri',
  'public_key_id',
  'public_key',
  'is_bot',
  'is_locked',
  'is_discoverable',
  'is_community',
  'last_fetched_at',
  'last_activity_at',
  'outbox_fetched_at',
  'followers_count',
  'following_count',
  'post_count',
  'total_post_count',
  'full_handle',
  'web_url',
];

/// Wraps an external image URL in the file reference shape the server sends,
/// mirroring `SnCloudFileReferenceObject.FromExternalUrl`.
Map<String, dynamic>? _externalImage(Object? url) =>
    url is String && url.isNotEmpty ? {'id': '', 'name': '', 'url': url} : null;

/// Normalizes a publisher payload from any server generation into the current
/// wire shape: the ActivityPub identity nested under `activitypub` and external
/// avatars/headers expressed as file references.
///
/// Two older shapes are still readable through [SnPublisher.fromJson]:
///
/// * the ActivityPub actor document itself, where `type` carries the actor kind
///   (`Person`, `Service`, ...) instead of the numeric [PublisherType];
/// * the merged publisher row from before the identity was nested, which served
///   `uri`, `actor_type`, `avatar_url`, the counters and the rest flat.
Map<String, dynamic> _normalizePayload(Map<String, dynamic> json) {
  final normalized = Map<String, dynamic>.of(json);

  final type = normalized['type'];
  if (type is String) {
    normalized['type'] = PublisherType.fediverse.index;
    normalized['actor_type'] ??= type;
  }

  if (normalized['activitypub'] == null) {
    final identity = <String, dynamic>{
      for (final key in _legacyIdentityKeys)
        if (normalized.containsKey(key)) key: normalized[key],
    };
    if (identity.isNotEmpty) normalized['activitypub'] = identity;
  }

  normalized['picture'] ??= _externalImage(normalized['avatar_url']);
  normalized['background'] ??= _externalImage(normalized['header_url']);
  return normalized;
}

@freezed
sealed class SnPublisher with _$SnPublisher {
  const SnPublisher._();

  const factory SnPublisher({
    @Default('') String id,
    @Default(0) int type,
    @Default('') String name,
    @Default('') String nick,
    @Default('') String bio,
    String? realmNick,
    String? realmBio,
    int? realmExperience,
    int? realmLevel,
    double? realmLevelingProgress,
    SnRealmLabel? realmLabel,
    SnCloudFileReference? picture,
    SnCloudFileReference? background,
    SnAccount? account,
    String? accountId,
    @Default(null) DateTime? createdAt,
    @Default(null) DateTime? updatedAt,
    DateTime? deletedAt,
    String? realmId,
    SnRealm? realm,
    SnVerificationMark? verification,
    @Default(false) bool isShadowbanned,
    @Default(false) bool isGatekept,
    @Default(false) bool isModerateSubscription,
    @Default(100.0) double rating,
    @JsonKey(name: 'rating_level') @Default(0) int ratingLevel,
    int? shadowbanReason,
    DateTime? shadowbannedAt,
    bool? gatekeptFollows,
    bool? moderateSubscription,
    String? payoutWalletId,

    /// Actor-shaped alias of [nick]; served at the top level of the payload.
    String? displayName,

    /// Fediverse identity, filled for remote actors and for local publishers
    /// with ActivityPub enabled. Null for everything else.
    SnPublisherActivityPub? activitypub,

    /// Instance metadata. Only builds that predate the actor/publisher merge
    /// send it; [domain] falls back to it.
    SnActivityPubInstance? instance,

    Map<String, dynamic>? meta,
    Map<String, dynamic>? metadata,
    @Default(false) bool isFollowing,
  }) = _SnPublisher;

  factory SnPublisher.fromJson(Map<String, dynamic> json) =>
      _$SnPublisherFromJson(_normalizePayload(json));

  /// Whether this publisher is a mirrored remote fediverse actor.
  bool get isFediverse => type == PublisherType.fediverse.index;

  /// Instance domain of a fediverse publisher, when known.
  String? get domain {
    final value = activitypub?.instanceDomain ?? instance?.domain;
    return (value == null || value.isEmpty) ? null : value;
  }

  /// Local account handle, or the user@domain handle for remote actors.
  String get handle {
    final actorUsername = activitypub?.username;
    final localName =
        actorUsername?.isNotEmpty == true ? actorUsername! : name;
    final host = domain;
    if (isFediverse && host != null) return localName + '@' + host;
    return localName;
  }

  /// Best available human readable name.
  String get effectiveName {
    for (final candidate in [nick, displayName, activitypub?.username, name]) {
      if (candidate != null && candidate.trim().isNotEmpty) return candidate;
    }
    return handle;
  }
}

/// ActivityPub identity of a publisher, nested under the `activitypub` member so
/// actor plumbing does not bloat every publisher payload.
@freezed
sealed class SnPublisherActivityPub with _$SnPublisherActivityPub {
  const factory SnPublisherActivityPub({
    String? uri,
    String? actorType,
    String? username,
    String? instanceId,
    String? instanceDomain,
    String? inboxUri,
    String? outboxUri,
    String? followersUri,
    String? followingUri,
    String? featuredUri,
    String? publicKeyId,
    String? publicKey,
    @Default(false) bool isBot,
    @Default(false) bool isLocked,
    @Default(true) bool isDiscoverable,
    @Default(false) bool isCommunity,
    DateTime? lastFetchedAt,
    DateTime? lastActivityAt,
    DateTime? outboxFetchedAt,
    @Default(0) int followersCount,
    @Default(0) int followingCount,
    @Default(0) int postCount,
    int? totalPostCount,
    String? fullHandle,
    String? webUrl,
  }) = _SnPublisherActivityPub;

  factory SnPublisherActivityPub.fromJson(Map<String, dynamic> json) =>
      _$SnPublisherActivityPubFromJson(json);
}

@freezed
sealed class SnPublisherMember with _$SnPublisherMember {
  const factory SnPublisherMember({
    required String publisherId,
    required SnPublisher? publisher,
    required String accountId,
    required SnAccount? account,
    required int role,
    required DateTime? joinedAt,
    required DateTime createdAt,
    required DateTime updatedAt,
    required DateTime? deletedAt,
  }) = _SnPublisherMember;

  factory SnPublisherMember.fromJson(Map<String, dynamic> json) =>
      _$SnPublisherMemberFromJson(json);
}

/// A single relationship between an account (or remote actor) and a publisher.
///
/// Backs local subscriptions, gatekept follow requests and ActivityPub
/// actor-to-actor follows.
@freezed
sealed class SnPublisherSubscription with _$SnPublisherSubscription {
  const SnPublisherSubscription._();

  const factory SnPublisherSubscription({
    required String id,
    String? accountId,
    String? followerPublisherId,
    SnPublisher? followerPublisher,
    required String publisherId,
    SnPublisher? publisher,
    @Default(PublisherSubscriptionState.accepted)
    PublisherSubscriptionState state,
    DateTime? followedAt,
    DateTime? reviewedAt,
    String? reviewedByAccountId,
    String? rejectReason,
    @Default(false) bool isMuting,
    @Default(false) bool isBlocking,
    @Default(true) bool notify,
    DateTime? lastReadAt,
    String? realmId,
    SnAccount? account,
    DateTime? endedAt,
    SubscriptionEndReason? endReason,
    String? endedByAccountId,
    @Default(true) bool isActive,
    @Default(false) bool isPending,
    required DateTime createdAt,
    required DateTime updatedAt,
    DateTime? deletedAt,
  }) = _SnPublisherSubscription;

  factory SnPublisherSubscription.fromJson(Map<String, dynamic> json) =>
      _$SnPublisherSubscriptionFromJson(json);

  bool get isPendingRequest =>
      isPending || state == PublisherSubscriptionState.pending;
  bool get isRejected => state == PublisherSubscriptionState.rejected;
  bool get isEnded => endedAt != null;
}

@freezed
sealed class SnPublisherSubscriptionStatus
    with _$SnPublisherSubscriptionStatus {
  const factory SnPublisherSubscriptionStatus({
    SnPublisherSubscription? subscription,
    SnPublisherSubscription? followRequest,
    @Default(false) bool requiresApproval,
    @Default('none') String status,
    @Default('') String message,
    @Default(false) bool isPending,
    @Default(false) bool isActive,
    @Default(true) bool notify,
  }) = _SnPublisherSubscriptionStatus;

  factory SnPublisherSubscriptionStatus.fromJson(Map<String, dynamic> json) =>
      _$SnPublisherSubscriptionStatusFromJson(json);
}

@freezed
sealed class SnPublisherSubscriber with _$SnPublisherSubscriber {
  const factory SnPublisherSubscriber({
    required SnPublisherSubscription subscription,
    required SnAccount? account,
  }) = _SnPublisherSubscriber;

  factory SnPublisherSubscriber.fromJson(Map<String, dynamic> json) =>
      _$SnPublisherSubscriberFromJson(json);
}

/// Relationship of the current account with a publisher, including mutes and
/// blocks that do not remove the subscription row.
@freezed
sealed class SnPublisherRelationship with _$SnPublisherRelationship {
  const factory SnPublisherRelationship({
    SnPublisherSubscription? subscription,
    @Default(false) bool isBlocking,
    @Default(false) bool isMuting,
    @Default(false) bool isSubscribed,
  }) = _SnPublisherRelationship;

  factory SnPublisherRelationship.fromJson(Map<String, dynamic> json) =>
      _$SnPublisherRelationshipFromJson(json);
}

/// Read status of a publisher subscription, used by the subscriptions list.
@freezed
sealed class SnPublisherSubscriptionReadStatus
    with _$SnPublisherSubscriptionReadStatus {
  const factory SnPublisherSubscriptionReadStatus({
    required SnPublisherSubscription subscription,
    DateTime? latestContentAt,
    @Default(false) bool hasNewContent,
  }) = _SnPublisherSubscriptionReadStatus;

  factory SnPublisherSubscriptionReadStatus.fromJson(
    Map<String, dynamic> json,
  ) => _$SnPublisherSubscriptionReadStatusFromJson(json);
}

/// A subscription entry enriched with live stream and read state.
@freezed
sealed class SnPublisherSubscriptionWithStatus
    with _$SnPublisherSubscriptionWithStatus {
  const factory SnPublisherSubscriptionWithStatus({
    required SnPublisherSubscription subscription,
    @Default(false) bool isLive,
    DateTime? latestContentAt,
    @Default(false) bool hasNewContent,
  }) = _SnPublisherSubscriptionWithStatus;

  factory SnPublisherSubscriptionWithStatus.fromJson(
    Map<String, dynamic> json,
  ) => _$SnPublisherSubscriptionWithStatusFromJson(json);
}

/// Relationship the current account has with a remote fediverse actor.
@freezed
sealed class FediverseActorRelationship with _$FediverseActorRelationship {
  const factory FediverseActorRelationship({
    @Default('') String actorId,
    @Default('') String actorUsername,
    String? actorInstance,
    @Default('') String actorHandle,
    @Default(false) bool isFollowing,
    @Default(false) bool isFollowedBy,
    @Default(false) bool isPending,
  }) = _FediverseActorRelationship;

  factory FediverseActorRelationship.fromJson(Map<String, dynamic> json) =>
      _$FediverseActorRelationshipFromJson(json);
}
