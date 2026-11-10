import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:island/core/api/api_client.dart';

/// Persisted anonymous visitor token for the treehole.
///
/// The service identifies a treehole visitor by the `lkm-treehole-session`
/// cookie only (see `LKM-service/app/modules/treehole/deps.py`); it is not the
/// bearer token and does not carry a login. The token is derived from its
/// hash server-side, so any token issued by one deployment is just a fresh
/// anonymous identity on another.
const String kLkmTreeholeTokenKey = 'lkm_treehole_session';

const String _cookieName = 'lkm-treehole-session';

DateTime _msDate(Object? value, {DateTime? fallback}) => value is num
    ? DateTime.fromMillisecondsSinceEpoch(value.toInt()).toLocal()
    : (fallback ?? DateTime.fromMillisecondsSinceEpoch(0));

int _asInt(Object? value) => value is num ? value.toInt() : 0;

List<String> _asStrings(Object? value) =>
    value is List ? value.whereType<String>().toList(growable: false) : const [];

/// One anonymous letter. Field names mirror `_letter_data` in the service.
class LkmTreeholeLetter {
  const LkmTreeholeLetter({
    required this.id,
    required this.content,
    required this.category,
    required this.privacy,
    required this.codename,
    required this.moods,
    required this.tags,
    required this.paper,
    required this.status,
    required this.createdAt,
    required this.likes,
    required this.favorites,
    required this.liked,
    required this.favorited,
    required this.isMine,
    this.scheduledAt,
    this.sealUntil,
  });

  final String id;
  final String content;

  /// `confess` / `heart` / `roast` / ... (see the website's CATEGORIES).
  final String category;

  /// `public` / `self` / `random`.
  final String privacy;
  final String codename;
  final List<String> moods;
  final List<String> tags;
  final String paper;

  /// `published` / `scheduled` / `sealed`.
  final String status;
  final DateTime createdAt;
  final DateTime? scheduledAt;
  final DateTime? sealUntil;
  final int likes;
  final int favorites;
  final bool liked;
  final bool favorited;
  final bool isMine;

  factory LkmTreeholeLetter.fromJson(Map<String, dynamic> json) {
    return LkmTreeholeLetter(
      id: '${json['id'] ?? ''}',
      content: '${json['content'] ?? ''}',
      category: '${json['category'] ?? ''}',
      privacy: '${json['privacy'] ?? 'public'}',
      codename: '${json['codename'] ?? ''}',
      moods: _asStrings(json['moods']),
      tags: _asStrings(json['tags']),
      paper: '${json['paper'] ?? 'paper'}',
      status: '${json['status'] ?? 'published'}',
      createdAt: _msDate(json['createdAt']),
      scheduledAt: json['scheduledAt'] is num
          ? _msDate(json['scheduledAt'])
          : null,
      sealUntil: json['sealUntil'] is num ? _msDate(json['sealUntil']) : null,
      likes: _asInt(json['likes']),
      favorites: _asInt(json['favorites']),
      liked: json['liked'] == true,
      favorited: json['favorited'] == true,
      isMine: json['isMine'] == true,
    );
  }
}

/// Write payload for create/edit letter.
class LkmLetterInput {
  const LkmLetterInput({
    required this.content,
    required this.category,
    required this.privacy,
    required this.codename,
    this.moods = const [],
    this.tags = const [],
    this.sticker = '',
    this.paper = 'paper',
    this.scheduledAt,
    this.sealUntil,
  });

  final String content;
  final String category;
  final String privacy;
  final String codename;
  final List<String> moods;
  final List<String> tags;
  final String sticker;
  final String paper;
  final DateTime? scheduledAt;
  final DateTime? sealUntil;

  Map<String, dynamic> toJson() => {
    'content': content,
    'category': category,
    'privacy': privacy,
    'codename': codename,
    'moods': moods,
    'tags': tags,
    'sticker': sticker,
    'paper': paper,
    if (scheduledAt != null)
      'scheduledAt': scheduledAt!.millisecondsSinceEpoch,
    if (sealUntil != null) 'sealUntil': sealUntil!.millisecondsSinceEpoch,
  };
}

class LkmTreeholeBottle {
  const LkmTreeholeBottle({
    required this.id,
    required this.text,
    required this.createdAt,
    required this.picked,
    this.ownerId,
    this.reply,
    this.repliedAt,
  });

  final String id;
  final String text;
  final DateTime createdAt;

  /// `me_local` when this bottle was thrown by the current visitor.
  final String? ownerId;
  final bool picked;

  /// Only present for bottles the visitor owns.
  final String? reply;
  final DateTime? repliedAt;

  bool get isMine => ownerId != null;

  factory LkmTreeholeBottle.fromJson(Map<String, dynamic> json) {
    return LkmTreeholeBottle(
      id: '${json['id'] ?? ''}',
      text: '${json['text'] ?? ''}',
      createdAt: _msDate(json['createdAt']),
      ownerId: json['ownerId'] as String?,
      picked: json['picked'] == true,
      reply: json['reply'] as String?,
      repliedAt: json['repliedAt'] is num ? _msDate(json['repliedAt']) : null,
    );
  }
}

class LkmTreeholeWish {
  const LkmTreeholeWish({
    required this.id,
    required this.text,
    required this.lights,
    required this.createdAt,
    this.ownerId,
  });

  final String id;
  final String text;
  final int lights;
  final DateTime createdAt;
  final String? ownerId;

  bool get isMine => ownerId != null;

  factory LkmTreeholeWish.fromJson(Map<String, dynamic> json) {
    return LkmTreeholeWish(
      id: '${json['id'] ?? ''}',
      text: '${json['text'] ?? ''}',
      lights: _asInt(json['lights']),
      createdAt: _msDate(json['createdAt']),
      ownerId: json['ownerId'] as String?,
    );
  }
}

class LkmTreeholeMessage {
  const LkmTreeholeMessage({
    required this.id,
    required this.text,
    required this.recalled,
    required this.from,
    required this.at,
  });

  final String id;
  final String text;
  final bool recalled;

  /// `me` or `peer`.
  final String from;
  final DateTime at;

  bool get isMine => from == 'me';

  factory LkmTreeholeMessage.fromJson(Map<String, dynamic> json) {
    return LkmTreeholeMessage(
      id: '${json['id'] ?? ''}',
      text: '${json['text'] ?? ''}',
      recalled: json['recalled'] == true,
      from: '${json['from'] ?? 'peer'}',
      at: _msDate(json['at']),
    );
  }
}

class LkmTreeholeConversation {
  const LkmTreeholeConversation({
    required this.id,
    required this.peerLetterId,
    required this.myLetterId,
    required this.peerCodename,
    required this.myCodename,
    required this.blocked,
    required this.updatedAt,
    required this.messages,
  });

  final String id;
  final String peerLetterId;
  final String myLetterId;
  final String peerCodename;
  final String myCodename;
  final bool blocked;
  final DateTime updatedAt;
  final List<LkmTreeholeMessage> messages;

  factory LkmTreeholeConversation.fromJson(Map<String, dynamic> json) {
    final messages = json['messages'];
    return LkmTreeholeConversation(
      id: '${json['id'] ?? ''}',
      peerLetterId: '${json['peerLetterId'] ?? ''}',
      myLetterId: '${json['myLetterId'] ?? ''}',
      peerCodename: '${json['peerCodename'] ?? ''}',
      myCodename: '${json['myCodename'] ?? ''}',
      blocked: json['blocked'] == true,
      updatedAt: _msDate(json['updatedAt']),
      messages: messages is List
          ? messages
                .whereType<Map>()
                .map(
                  (e) =>
                      LkmTreeholeMessage.fromJson(Map<String, dynamic>.from(e)),
                )
                .toList(growable: false)
          : const [],
    );
  }
}

/// Anonymous treehole client: 17 endpoints under `/api/v1/treehole`.
///
/// The identity is a cookie the client has to carry itself (desktop has no
/// cookie jar), so every call goes out with an explicit `Cookie` header after
/// [ensureSession] has obtained one.
class TreeholeApi {
  TreeholeApi(this._client, this._prefs);

  final ApiClient _client;
  final SharedPreferences _prefs;
  Future<void>? _ensuring;

  String? get _token => _prefs.getString(kLkmTreeholeTokenKey);

  /// Obtains and persists the anonymous visitor token, once per app run.
  Future<void> ensureSession() {
    if (_token != null) return Future<void>.value();
    return _ensuring ??= _bootstrap().whenComplete(() => _ensuring = null);
  }

  Future<void> _bootstrap() async {
    final existing = _token;
    final response = await _client.dio.post<dynamic>(
      '/treehole/session',
      options: Options(
        headers: existing == null ? null : {'Cookie': '$_cookieName=$existing'},
        validateStatus: (_) => true,
      ),
    );
    final data = response.data;
    final code = data is Map ? _asInt(data['code']) : -1;
    if (code != ApiCode.ok) {
      throw ApiException(
        code: code,
        message: data is Map ? '${data['message'] ?? '树洞会话建立失败'}' : '树洞会话建立失败',
        statusCode: response.statusCode,
        method: 'POST',
        path: '/treehole/session',
      );
    }
    // The service re-issues a token only when the sent one was missing or
    // malformed; a recognized cookie keeps its identity and is not echoed.
    for (final raw in response.headers['set-cookie'] ?? const <String>[]) {
      final match = RegExp(
        '$_cookieName=([A-Za-z0-9_-]{43})',
      ).firstMatch(raw);
      if (match != null) {
        await _prefs.setString(kLkmTreeholeTokenKey, match.group(1)!);
        return;
      }
    }
    if (existing != null) return;
    throw const ApiTransportException('树洞会话建立失败：响应缺少 cookie');
  }

  Future<Map<String, String>> _headers() async {
    await ensureSession();
    return {'Cookie': '$_cookieName=${_token ?? ''}'};
  }

  Future<List<LkmTreeholeLetter>> letters({
    String scope = 'public',
    int page = 1,
    int limit = 100,
  }) async {
    return _client.getList(
      '/treehole/letters',
      query: {'scope': scope, 'page': page, 'limit': limit},
      headers: await _headers(),
      parseItem: LkmTreeholeLetter.fromJson,
    );
  }

  Future<LkmTreeholeLetter> createLetter(LkmLetterInput input) async {
    final data = await _client.post(
      '/treehole/letters',
      body: input.toJson(),
      headers: await _headers(),
    );
    return LkmTreeholeLetter.fromJson(data as Map<String, dynamic>);
  }

  Future<LkmTreeholeLetter> editLetter(
    String id,
    LkmLetterInput input,
  ) async {
    final data = await _client.put(
      '/treehole/letters/$id',
      body: input.toJson(),
      headers: await _headers(),
    );
    return LkmTreeholeLetter.fromJson(data as Map<String, dynamic>);
  }

  Future<void> deleteLetter(String id) async {
    await _client.delete('/treehole/letters/$id', headers: await _headers());
  }

  /// Toggles `like` / `favorite` and returns the updated letter.
  Future<LkmTreeholeLetter> toggleReaction(String id, String kind) async {
    final data = await _client.post(
      '/treehole/letters/$id/reactions/$kind',
      headers: await _headers(),
    );
    final letter = (data as Map)['letter'];
    return LkmTreeholeLetter.fromJson(Map<String, dynamic>.from(letter as Map));
  }

  /// Sends the first message of a conversation. Returns the conversation id.
  Future<String> replyLetter(String id, String text) async {
    final data = await _client.post(
      '/treehole/letters/$id/reply',
      body: {'text': text},
      headers: await _headers(),
    );
    return '${(data as Map)['conversationId'] ?? ''}';
  }

  Future<void> report({
    required String targetType,
    required String targetId,
    required String reason,
    String detail = '',
  }) async {
    await _client.post(
      '/treehole/reports',
      body: {
        'targetType': targetType,
        'targetId': targetId,
        'reason': reason,
        'detail': detail,
      },
      headers: await _headers(),
    );
  }

  Future<List<LkmTreeholeBottle>> bottles({int page = 1}) async {
    return _client.getList(
      '/treehole/bottles',
      query: {'page': page},
      headers: await _headers(),
      parseItem: LkmTreeholeBottle.fromJson,
    );
  }

  Future<void> createBottle(String text) async {
    await _client.post(
      '/treehole/bottles',
      body: {'text': text},
      headers: await _headers(),
    );
  }

  Future<void> replyBottle(String id, String text) async {
    await _client.post(
      '/treehole/bottles/$id/reply',
      body: {'text': text},
      headers: await _headers(),
    );
  }

  Future<List<LkmTreeholeWish>> wishes({int page = 1}) async {
    return _client.getList(
      '/treehole/wishes',
      query: {'page': page},
      headers: await _headers(),
      parseItem: LkmTreeholeWish.fromJson,
    );
  }

  Future<void> createWish(String text) async {
    await _client.post(
      '/treehole/wishes',
      body: {'text': text},
      headers: await _headers(),
    );
  }

  Future<void> editWish(String id, String text) async {
    await _client.put(
      '/treehole/wishes/$id',
      body: {'text': text},
      headers: await _headers(),
    );
  }

  Future<void> deleteWish(String id) async {
    await _client.delete('/treehole/wishes/$id', headers: await _headers());
  }

  /// Lights a wish once per visitor; returns the new total.
  Future<int> lightWish(String id) async {
    final data = await _client.post(
      '/treehole/wishes/$id/light',
      headers: await _headers(),
    );
    return _asInt((data as Map)['lights']);
  }

  Future<List<LkmTreeholeConversation>> conversations({int page = 1}) async {
    return _client.getList(
      '/treehole/conversations',
      query: {'page': page},
      headers: await _headers(),
      parseItem: LkmTreeholeConversation.fromJson,
    );
  }

  Future<void> sendMessage(String convId, String text) async {
    await _client.post(
      '/treehole/conversations/$convId/messages',
      body: {'text': text},
      headers: await _headers(),
    );
  }

  Future<void> recall(String convId, String messageId) async {
    await _client.post(
      '/treehole/conversations/$convId/messages/$messageId/recall',
      headers: await _headers(),
    );
  }

  Future<void> block(String convId) async {
    await _client.post(
      '/treehole/conversations/$convId/block',
      headers: await _headers(),
    );
  }

  Future<void> clear(String convId) async {
    await _client.post(
      '/treehole/conversations/$convId/clear',
      headers: await _headers(),
    );
  }

  Future<void> hideConversation(String convId) async {
    await _client.delete(
      '/treehole/conversations/$convId',
      headers: await _headers(),
    );
  }
}
