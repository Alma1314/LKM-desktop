import 'api_client.dart';

/// One in-app notification (`GET /notification/me`).
class LkmNotification {
  const LkmNotification({
    required this.id,
    required this.type,
    required this.payload,
    required this.createdAt,
    this.actorId,
    this.targetId,
    this.readAt,
  });

  final String id;
  final String type;
  final String? actorId;
  final String? targetId;
  final Map<String, dynamic> payload;
  final DateTime? readAt;
  final DateTime createdAt;

  bool get isUnread => readAt == null;

  LkmNotification withReadAt(DateTime value) => LkmNotification(
    id: id,
    type: type,
    payload: payload,
    createdAt: createdAt,
    actorId: actorId,
    targetId: targetId,
    readAt: value,
  );

  factory LkmNotification.fromJson(Map<String, dynamic> json) {
    final payload = json['payload'];
    final createdAt = DateTime.tryParse('${json['created_at'] ?? ''}');
    return LkmNotification(
      id: '${json['id'] ?? ''}',
      type: '${json['type'] ?? ''}',
      actorId: json['actor_id'] as String?,
      targetId: json['target_id'] as String?,
      payload: payload is Map ? Map<String, dynamic>.from(payload) : const {},
      readAt: DateTime.tryParse('${json['read_at'] ?? ''}')?.toLocal(),
      createdAt: (createdAt ?? DateTime.fromMillisecondsSinceEpoch(0))
          .toLocal(),
    );
  }
}

/// `/notification` endpoints for the signed-in account.
class NotificationApi {
  const NotificationApi(this._client);

  final ApiClient _client;

  Future<ApiPage<LkmNotification>> list({
    int page = 1,
    int limit = 20,
    bool unreadOnly = false,
  }) {
    return _client.getPage(
      '/notification/me',
      query: {
        'page': '$page',
        'limit': '$limit',
        if (unreadOnly) 'unread': 'true',
      },
      parseItem: LkmNotification.fromJson,
    );
  }

  Future<int> unreadCount() async {
    final data = await _client.getObject('/notification/me/unread-count');
    final count = data['unread'];
    return count is num ? count.toInt() : 0;
  }

  /// Marks [ids] read, or everything when [all] is true. Returns the count the
  /// server actually updated (ids that were already read are not counted).
  Future<int> markRead({List<String> ids = const [], bool all = false}) async {
    final data = await _client.post(
      '/notification/me/read',
      body: {'ids': ids, 'all': all},
    );
    final updated = data is Map ? data['updated'] : null;
    return updated is num ? updated.toInt() : 0;
  }
}
