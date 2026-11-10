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

const String _itemsQuery =
    'query ContentItems(\$page: Int!, \$pageSize: Int!, \$boardId: ID, '
    '\$contentType: String) { contentItems(page: \$page, pageSize: \$pageSize, '
    'boardId: \$boardId, contentType: \$contentType) { '
    'items { $_itemFields } total page pages } }';

const String _commentsQuery =
    'query ContentComments(\$itemId: ID!, \$page: Int!, \$pageSize: Int!) { '
    'contentComments(itemId: \$itemId, page: \$page, pageSize: \$pageSize) { '
    'items { id contentId authorId authorName content floorNumber parentId '
    'likeCount liked createdAt } total page pages } }';

/// Detail-page interaction buttons: server truth for "did I like/save this",
/// without re-fetching the body. Anonymous visitors still get the counts.
const String _viewerStateQuery =
    'query ContentViewerState(\$contentId: ID!) { '
    'contentViewerState(contentId: \$contentId) { liked favorited '
    'likeCount bookmarkCount } }';

const String _boardsQuery =
    'query Boards { boards { id slug title parentId status isPublic } }';

/// The GraphQL endpoint lives at the server root, not under `/api/v1`.
String graphqlUrlFor(ApiClient client) {
  final base = client.baseUrl;
  final origin = base.endsWith(kApiPathPrefix)
      ? base.substring(0, base.length - kApiPathPrefix.length)
      : base;
  return '$origin/graphql/v1';
}

/// POSTs one GraphQL query and unwraps the `{data, errors}` body.
///
/// Shared by [ContentApi] and the columns reader so the error mapping and the
/// root-level URL stay in one place.
Future<Map<String, dynamic>> graphqlRequest(
  ApiClient client,
  String query,
  Map<String, dynamic> variables,
) async {
  final body = await client.post(
    graphqlUrlFor(client),
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

/// A forum board (`status == active` is the only postable state).
class LkmBoard {
  const LkmBoard({
    required this.id,
    required this.slug,
    required this.title,
    required this.status,
    this.parentId,
    this.isPublic = true,
  });

  final String id;
  final String slug;
  final String title;
  final String status;
  final String? parentId;
  final bool isPublic;

  bool get isActive => status == 'active';

  factory LkmBoard.fromJson(Map<String, dynamic> json) => LkmBoard(
    id: '${json['id'] ?? ''}',
    slug: '${json['slug'] ?? ''}',
    title: '${json['title'] ?? ''}',
    status: '${json['status'] ?? ''}',
    parentId: json['parentId'] as String?,
    isPublic: json['isPublic'] != false,
  );
}

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
    this.bookmarkCount = 0,
    this.forwardCount = 0,
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
  final int bookmarkCount;
  final int forwardCount;
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
      bookmarkCount: _asInt(json['bookmarkCount']),
      forwardCount: _asInt(json['forwardCount']),
      createdAt: (created ?? DateTime.fromMillisecondsSinceEpoch(0)).toLocal(),
      publishedAt: DateTime.tryParse('${json['publishedAt'] ?? ''}')?.toLocal(),
    );
  }

  static int _asInt(Object? value) => value is num ? value.toInt() : 0;
}

/// [GraphQL `contentViewerState`] initial values for the detail actions row.
class LkmViewerState {
  const LkmViewerState({
    required this.liked,
    required this.favorited,
    required this.likeCount,
    required this.bookmarkCount,
  });

  final bool liked;
  final bool favorited;
  final int likeCount;
  final int bookmarkCount;

  factory LkmViewerState.fromJson(Map<String, dynamic> json) {
    return LkmViewerState(
      liked: json['liked'] == true,
      favorited: json['favorited'] == true,
      likeCount: LkmContentItem._asInt(json['likeCount']),
      bookmarkCount: LkmContentItem._asInt(json['bookmarkCount']),
    );
  }
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

  LkmContentComment copyWith({int? likeCount, bool? liked}) {
    return LkmContentComment(
      id: id,
      authorId: authorId,
      authorName: authorName,
      content: content,
      floorNumber: floorNumber,
      likeCount: likeCount ?? this.likeCount,
      liked: liked ?? this.liked,
      createdAt: createdAt,
      parentId: parentId,
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

  String get graphqlUrl => graphqlUrlFor(_client);

  Future<LkmContentItem?> item(String id) async {
    final data = await _graphql(_itemQuery, {'id': id});
    final raw = data['contentItem'];
    if (raw is! Map) return null;
    return LkmContentItem.fromJson(Map<String, dynamic>.from(raw));
  }

  /// Published content page, optionally narrowed to one board.
  Future<ApiPage<LkmContentItem>> items({
    String? boardId,
    String? contentType,
    int page = 1,
    int pageSize = 20,
  }) async {
    final data = await _graphql(_itemsQuery, {
      'boardId': boardId,
      'contentType': contentType,
      'page': page,
      'pageSize': pageSize,
    });
    final raw = data['contentItems'];
    if (raw is! Map) return const ApiPage.empty();
    final items = raw['items'];
    final parsed = items is List
        ? items
              .whereType<Map>()
              .map((e) => LkmContentItem.fromJson(Map<String, dynamic>.from(e)))
              .toList(growable: false)
        : const <LkmContentItem>[];
    int asInt(Object? value) => value is num ? value.toInt() : 0;
    return ApiPage(
      items: parsed,
      total: asInt(raw['total']) == 0 ? parsed.length : asInt(raw['total']),
      page: asInt(raw['page']) == 0 ? page : asInt(raw['page']),
      pages: asInt(raw['pages']) == 0 ? page : asInt(raw['pages']),
    );
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

  Future<List<LkmBoard>> boards() async {
    final data = await _graphql(_boardsQuery, const {});
    final raw = data['boards'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => LkmBoard.fromJson(Map<String, dynamic>.from(e)))
        .toList(growable: false);
  }

  /// Creates a discussion post and returns its id. Forum posts are the only
  /// write shape the desktop exposes for now: articles/columns/blog/QA have
  /// their own review pipelines and stay on the website.
  Future<String> createDiscussion({
    required String boardId,
    required String title,
    required String content,
    List<String> tags = const [],
  }) async {
    final body = await _client.post(
      '/content/items',
      body: {
        'content_type': 'discussion',
        'board_id': boardId,
        'title': title,
        'content': content,
        'tags': tags,
      },
    );
    final id = body is Map ? body['id'] : null;
    if (id == null) {
      throw ApiException(
        code: ApiCode.internalError,
        message: '创建内容后未返回 id',
        path: '/content/items',
      );
    }
    return '$id';
  }

  Future<void> deleteItem(String contentId) async {
    await _client.delete('/content/items/$contentId');
  }

  Future<LkmViewerState?> viewerState(String contentId) async {
    final data = await _graphql(_viewerStateQuery, {'contentId': contentId});
    final raw = data['contentViewerState'];
    if (raw is! Map) return null;
    return LkmViewerState.fromJson(Map<String, dynamic>.from(raw));
  }

  /// Returns the server's new like count (like/unlike are exclusive REST verbs).
  Future<int> like(String contentId) async {
    final body = await _client.post('/content/items/$contentId/like');
    return _count(body, 'like_count');
  }

  Future<int> unlike(String contentId) async {
    final body = await _client.delete('/content/items/$contentId/like');
    return _count(body, 'like_count');
  }

  /// Returns the server's new bookmark count after favoriting/unfavoriting.
  Future<int> favorite(String contentId, {required bool favorited}) async {
    final path = '/interaction/favorites/$contentId';
    final body = favorited
        ? await _client.post(path)
        : await _client.delete(path);
    return _count(body, 'bookmark_count');
  }

  /// Called after the link is copied; returns the new forward count.
  Future<int> forward(String contentId) async {
    final body = await _client.post('/content/items/$contentId/forward');
    return _count(body, 'forward_count');
  }

  /// Fire-and-forget view bookkeeping; the caller decides whether to log.
  Future<void> reportView(String contentId) async {
    await _client.post('/interaction/views/$contentId');
  }

  Future<int> likeComment(String itemId, String commentId) async {
    final body = await _client.post(
      '/content/items/$itemId/comments/$commentId/like',
    );
    return _count(body, 'like_count');
  }

  Future<int> unlikeComment(String itemId, String commentId) async {
    final body = await _client.delete(
      '/content/items/$itemId/comments/$commentId/like',
    );
    return _count(body, 'like_count');
  }

  Future<void> report({
    required String targetType,
    required String targetId,
    required String reason,
  }) async {
    await _client.post(
      '/content/reports',
      body: {
        'target_type': targetType,
        'target_id': targetId,
        'reason': reason,
      },
    );
  }

  static int _count(Object? body, String field) {
    if (body is Map && body[field] is num) return (body[field] as num).toInt();
    return 0;
  }

  Future<Map<String, dynamic>> _graphql(
    String query,
    Map<String, dynamic> variables,
  ) => graphqlRequest(_client, query, variables);
}
