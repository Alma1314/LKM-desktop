import 'api_client.dart';

/// One hit of `GET /search` — the same projection as a content list row, so
/// cards can reuse the feed presentation.
class SearchHit {
  const SearchHit({
    required this.id,
    required this.contentType,
    required this.title,
    required this.excerpt,
    required this.authorName,
    required this.likeCount,
    required this.commentCount,
    required this.viewCount,
    required this.createdAt,
    this.boardId,
    this.slug,
    this.authorId,
    this.publishedAt,
  });

  final String id;
  final String contentType;
  final String? boardId;
  final String title;
  final String excerpt;
  final String? slug;
  final String? authorId;
  final String authorName;
  final int likeCount;
  final int commentCount;
  final int viewCount;
  final DateTime? publishedAt;
  final DateTime createdAt;

  factory SearchHit.fromJson(Map<String, dynamic> json) {
    final created = DateTime.tryParse('${json['created_at'] ?? ''}');
    return SearchHit(
      id: '${json['id'] ?? ''}',
      contentType: '${json['content_type'] ?? ''}',
      boardId: json['board_id'] as String?,
      title: '${json['title'] ?? ''}',
      excerpt: '${json['excerpt'] ?? ''}',
      slug: json['slug'] as String?,
      authorId: json['author_id'] as String?,
      authorName: '${json['author_name'] ?? ''}',
      likeCount: _asInt(json['like_count']),
      commentCount: _asInt(json['comment_count']),
      viewCount: _asInt(json['view_count']),
      publishedAt: DateTime.tryParse(
        '${json['published_at'] ?? ''}',
      )?.toLocal(),
      createdAt: (created ?? DateTime.fromMillisecondsSinceEpoch(0)).toLocal(),
    );
  }

  static int _asInt(Object? value) => value is num ? value.toInt() : 0;
}

class SearchApi {
  const SearchApi(this._client);

  final ApiClient _client;

  Future<ApiPage<SearchHit>> search(
    String query, {
    String? contentType,
    int page = 1,
    int limit = 20,
  }) {
    return _client.getPage(
      '/search',
      query: {
        'q': query,
        'page': '$page',
        'limit': '$limit',
        'content_type': ?contentType,
      },
      parseItem: SearchHit.fromJson,
    );
  }
}
