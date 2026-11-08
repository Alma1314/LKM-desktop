import 'api_client.dart';

/// Fields shared by every content read; kept in one place so the GraphQL
/// selection tracks the backend schema once.
const String _itemFields =
    'id contentType boardId authorId authorName publisher department '
    'columnId columnTitle qaQuestionId slug title excerpt summary cover '
    'keywords content tags status isPinned isFeatured viewCount likeCount '
    'commentCount bookmarkCount forwardCount readingTime createdAt '
    'publishedAt version';

const String _itemQuery =
    'query ContentItem(\$id: ID!) { contentItem(id: \$id) { $_itemFields } }';

const String _commentsQuery =
    'query ContentComments(\$itemId: ID!, \$page: Int!, \$pageSize: Int!) { '
    'contentComments(itemId: \$itemId, page: \$page, pageSize: \$pageSize) { '
    'items { id contentId authorId authorName content floorNumber parentId '
    'likeCount liked createdAt } total page pages } }';

/// One unified content row (`discussion` / `article` / `column_post` /
/// `blog_post`). The detail page is the first surface that needs the body,
/// which the REST contract does not expose.
class LkmContentItem {
  const LkmContentItem({
    required this.id,
    required this.contentType,
    required this.title,
    required this.excerpt,
    required this.content,
    required this.authorName,
    required this.tags,
    required this.viewCount,
    required this.likeCount,
    required this.commentCount,
    required this.createdAt,
    this.authorId,
    this.boardId,
    this.publisher,
    this.cover,
    this.columnTitle = '',
    this.slug,
    this.publishedAt,
  });

  final String id;
  final String contentType;
  final String? boardId;
  final String? authorId;
  final String authorName;
  final String? publisher;
  final String columnTitle;
  final String? slug;
  final String title;
  final String excerpt;

  /// Markdown body.
  final String content;
  final List<String> tags;
  final String? cover;
  final int viewCount;
  final int likeCount;
  final int commentCount;
  final DateTime createdAt;
  final DateTime? publishedAt;

  factory LkmContentItem.fromJson(Map<String, dynamic> json) {
    final created = DateTime.tryParse('${json['createdAt'] ?? ''}');
    final tags = json['tags'];
    return LkmContentItem(
      id: '${json['id'] ?? ''}',
      contentType: '${json['contentType'] ?? ''}',
      boardId: json['boardId'] as String?,
      authorId: json['authorId'] as String?,
      authorName: '${json['authorName'] ?? ''}',
      publisher: json['publisher'] as String?,
      columnTitle: '${json['columnTitle'] ?? ''}',
      slug: json['slug'] as String?,
      title: '${json['title'] ?? ''}',
      excerpt: '${json['excerpt'] ?? ''}',
      content: '${json['content'] ?? ''}',
      tags: tags is List
          ? tags.whereType<String>().toList(growable: false)
          : const [],
      cover: json['cover'] as String?,
      viewCount: _asInt(json['viewCount']),
      likeCount: _asInt(json['likeCount']),
      commentCount: _asInt(json['commentCount']),
      createdAt: (created ?? DateTime.fromMillisecondsSinceEpoch(0)).toLocal(),
      publishedAt: DateTime.tryParse('${json['publishedAt'] ?? ''}')?.toLocal(),
    );
  }

  static int _asInt(Object? value) => value is num ? value.toInt() : 0;
}

class LkmContentComment {
  const LkmContentComment({
    required this.id,
    required this.authorId,
    required this.authorName,
    required this.content,
    required this.floorNumber,
    required this.likeCount,
    required this.liked,
    required this.createdAt,
    this.parentId,
  });

  final String id;
  final String authorId;
  final String authorName;
  final String content;
  final int floorNumber;
  final String? parentId;
  final int likeCount;
  final bool liked;
  final DateTime createdAt;

  factory LkmContentComment.fromJson(Map<String, dynamic> json) {
    final created = DateTime.tryParse('${json['createdAt'] ?? ''}');
    return LkmContentComment(
      id: '${json['id'] ?? ''}',
      authorId: '${json['authorId'] ?? ''}',
      authorName: '${json['authorName'] ?? ''}',
      content: '${json['content'] ?? ''}',
      floorNumber: _asInt(json['floorNumber']),
      parentId: json['parentId'] as String?,
      likeCount: _asInt(json['likeCount']),
      liked: json['liked'] == true,
      createdAt: (created ?? DateTime.fromMillisecondsSinceEpoch(0)).toLocal(),
    );
  }

  static int _asInt(Object? value) => value is num ? value.toInt() : 0;
}

class LkmCommentPage {
  const LkmCommentPage({
    required this.items,
    required this.total,
    required this.page,
    required this.pages,
  });

  final List<LkmContentComment> items;
  final int total;
  final int page;
  final int pages;

  bool get hasMore => page < pages;

  factory LkmCommentPage.fromJson(Map<String, dynamic> json) {
    final items = json['items'];
    return LkmCommentPage(
      items: items is List
          ? items
                .whereType<Map>()
                .map(
                  (e) =>
                      LkmContentComment.fromJson(Map<String, dynamic>.from(e)),
                )
                .toList(growable: false)
          : const [],
      total: _asInt(json['total']),
      page: _asInt(json['page']),
      pages: _asInt(json['pages']),
    );
  }

  static int _asInt(Object? value) => value is num ? value.toInt() : 0;
}

/// Reads content detail over GraphQL and writes comments over REST — the same
/// split the website uses (`src/lib/api/modules/content.ts`).
class ContentApi {
  const ContentApi(this._client);

  final ApiClient _client;

  /// The GraphQL endpoint lives at the server root, not under `/api/v1`.
  String get graphqlUrl {
    final base = _client.baseUrl;
    final origin = base.endsWith(kApiPathPrefix)
        ? base.substring(0, base.length - kApiPathPrefix.length)
        : base;
    return '$origin/graphql/v1';
  }

  Future<LkmContentItem?> item(String id) async {
    final data = await _graphql(_itemQuery, {'id': id});
    final raw = data['contentItem'];
    if (raw is! Map) return null;
    return LkmContentItem.fromJson(Map<String, dynamic>.from(raw));
  }

  Future<LkmCommentPage> comments(
    String itemId, {
    int page = 1,
    int pageSize = 20,
  }) async {
    final data = await _graphql(_commentsQuery, {
      'itemId': itemId,
      'page': page,
      'pageSize': pageSize,
    });
    final raw = data['contentComments'];
    if (raw is! Map) {
      return const LkmCommentPage(items: [], total: 0, page: 1, pages: 0);
    }
    return LkmCommentPage.fromJson(Map<String, dynamic>.from(raw));
  }

  Future<void> addComment(
    String itemId,
    String content, {
    String? parentId,
  }) async {
    await _client.post(
      '/content/items/$itemId/comments',
      body: {'content': content, 'parent_id': ?parentId},
    );
  }

  Future<Map<String, dynamic>> _graphql(
    String query,
    Map<String, dynamic> variables,
  ) async {
    final body = await _client.post(
      graphqlUrl,
      body: {'query': query, 'variables': variables},
    );
    if (body is! Map) {
      throw ApiException(
        code: ApiCode.internalError,
        message: 'GraphQL 响应格式错误',
        path: '/graphql/v1',
      );
    }
    final errors = body['errors'];
    if (errors is List && errors.isNotEmpty) {
      final first = errors.first;
      final message = first is Map ? '${first['message'] ?? ''}' : '$first';
      throw ApiException(
        code: ApiCode.internalError,
        message: message.isEmpty ? 'GraphQL 请求失败' : message,
        path: '/graphql/v1',
      );
    }
    final data = body['data'];
    return data is Map ? Map<String, dynamic>.from(data) : const {};
  }
}
