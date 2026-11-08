import 'api_client.dart';

/// One entry of the unified feed (`GET /timeline`).
///
/// The feed merges several content sources server-side, so [itemType] is the
/// discriminator (`discussion` / `article` / `column` / `qa` / `project` /
/// `blog`) and the rest of the fields are the common projection only.
class FeedItem {
  const FeedItem({
    required this.itemType,
    required this.id,
    required this.authorName,
    required this.title,
    required this.contentPreview,
    required this.createdAt,
    required this.sortScore,
    this.authorId,
    this.boardId,
    this.url,
  });

  final String itemType;
  final String id;
  final String? authorId;
  final String authorName;
  final String title;
  final String contentPreview;
  final DateTime createdAt;
  final double sortScore;
  final String? boardId;

  /// Server-provided link, either absolute or a site-relative path. Callers
  /// must validate the scheme before handing it to a launcher.
  final String? url;

  factory FeedItem.fromJson(Map<String, dynamic> json) {
    final createdAt = DateTime.tryParse('${json['created_at'] ?? ''}');
    final score = json['sort_score'];
    return FeedItem(
      itemType: '${json['item_type'] ?? ''}',
      id: '${json['id'] ?? ''}',
      authorId: json['author_id'] as String?,
      authorName: '${json['author_name'] ?? ''}',
      title: '${json['title'] ?? ''}',
      contentPreview: '${json['content_preview'] ?? ''}',
      createdAt: (createdAt ?? DateTime.fromMillisecondsSinceEpoch(0))
          .toLocal(),
      sortScore: score is num ? score.toDouble() : 0,
      boardId: json['board_id'] as String?,
      url: json['url'] as String?,
    );
  }
}

/// One cursor page of the feed. `next_cursor == null` means the end.
class FeedPage {
  const FeedPage({required this.items, this.nextCursor});

  final List<FeedItem> items;
  final String? nextCursor;

  bool get hasMore => nextCursor != null;

  factory FeedPage.fromJson(Map<String, dynamic> json) {
    final raw = json['items'];
    return FeedPage(
      items: raw is List
          ? raw
                .whereType<Map>()
                .map((e) => FeedItem.fromJson(Map<String, dynamic>.from(e)))
                .toList(growable: false)
          : const [],
      nextCursor: json['next_cursor'] as String?,
    );
  }
}

/// `GET /api/v1/timeline` — cross-source timeline, cursor paginated.
class TimelineApi {
  const TimelineApi(this._client);

  final ApiClient _client;

  /// [mode] is `follow` (needs a signed-in session) or `hot` (public).
  /// Anonymous `follow` requests come back empty server-side, so the UI only
  /// offers follow once the session is signed in.
  Future<FeedPage> timeline({
    String mode = 'hot',
    String? cursor,
    int limit = 20,
  }) async {
    final data = await _client.getObject(
      '/timeline',
      query: {'mode': mode, 'limit': '$limit', 'cursor': ?cursor},
    );
    return FeedPage.fromJson(data);
  }
}
