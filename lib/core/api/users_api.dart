import 'api_client.dart';

/// Public account profile (`ProfileInfo`): what another user's page can show.
class LkmUserProfile {
  const LkmUserProfile({
    required this.userId,
    required this.role,
    this.nickname,
    this.avatar,
  });

  final String userId;
  final String role;
  final String? nickname;
  final String? avatar;

  String get displayName => (nickname != null && nickname!.trim().isNotEmpty)
      ? nickname!.trim()
      : userId;

  factory LkmUserProfile.fromJson(Map<String, dynamic> json) {
    return LkmUserProfile(
      userId: '${json['user_id'] ?? ''}',
      role: '${json['role'] ?? 'member'}',
      nickname: json['nickname'] as String?,
      avatar: json['avatar'] as String?,
    );
  }
}

class LkmFollowUser {
  const LkmFollowUser({
    required this.userId,
    required this.displayName,
    this.avatar,
  });

  final String userId;
  final String displayName;
  final String? avatar;

  factory LkmFollowUser.fromJson(Map<String, dynamic> json) => LkmFollowUser(
    userId: '${json['user_id'] ?? ''}',
    displayName: '${json['display_name'] ?? ''}',
    avatar: json['avatar'] as String?,
  );
}

/// Account read surface plus the follow relation.
class UsersApi {
  const UsersApi(this._client);

  final ApiClient _client;

  Future<LkmUserProfile> profile(String userId) async {
    final data = await _client.getObject('/auth/$userId');
    return LkmUserProfile.fromJson(data);
  }

  /// Public lookup; the only profile read that works signed out.
  Future<LkmUserProfile> profileByUsername(String username) async {
    final data = await _client.getObject(
      '/auth/user/by-username/${Uri.encodeComponent(username)}',
    );
    return LkmUserProfile.fromJson(data);
  }

  Future<bool> followStatus(String userId) async {
    final data = await _client.getObject('/users/$userId/follow/status');
    return data['is_following'] == true;
  }

  Future<bool> setFollow(String userId, {required bool follow}) async {
    final data = follow
        ? await _client.post('/users/$userId/follow')
        : await _client.delete('/users/$userId/follow');
    return data is Map && data['following'] == true;
  }

  Future<List<LkmFollowUser>> following() async {
    final data = await _client.getObject('/users/me/following');
    final items = data['items'];
    return items is List
        ? items
              .whereType<Map>()
              .map((e) => LkmFollowUser.fromJson(Map<String, dynamic>.from(e)))
              .toList(growable: false)
        : const [];
  }
}
