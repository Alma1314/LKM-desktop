import 'api_client.dart';
import 'content_api.dart';

const String _columnFields =
    'id ownerId title description slug coverUrl authorName authorTitle '
    'authorBio avatarUrl isVerified followerCount likeCount subscribeCount '
    'articleCount tags badges boardId status';

const String _columnsQuery =
    'query Columns(\$page: Int!, \$pageSize: Int!) { '
    'columns(page: \$page, pageSize: \$pageSize) { $_columnFields '
    'total page pages } }';

const String _columnPostsQuery =
    'query ColumnPosts(\$columnId: ID!, \$page: Int!, \$pageSize: Int!) { '
    'columnPosts(columnId: \$columnId, page: \$page, pageSize: \$pageSize) { '
    'items { id columnId authorId title summary content coverImage viewCount '
    'likeCount commentCount status publishedAt } total page pages } }';

class ColumnSummary {
  const ColumnSummary({
    required this.id,
    required this.title,
    required this.description,
    required this.authorName,
    required this.isVerified,
    required this.articleCount,
    required this.tags,
    required this.status,
    this.slug,
    this.coverUrl,
    this.avatarUrl,
    this.followerCount = 0,
    this.likeCount = 0,
  });

  final String id;
  final String title;
  final String description;
  final String authorName;
  final bool isVerified;
  final int articleCount;
  final List<String> tags;
  final String status;
  final String? slug;
  final String? coverUrl;
  final String? avatarUrl;
  final int followerCount;
  final int likeCount;

  factory ColumnSummary.fromJson(Map<String, dynamic> json) {
    final tags = json['tags'];
    return ColumnSummary(
      id: '${json['id'] ?? ''}',
      title: '${json['title'] ?? ''}',
      description: '${json['description'] ?? ''}',
      authorName: '${json['authorName'] ?? ''}',
      isVerified: json['isVerified'] == true,
      articleCount: _asInt(json['articleCount']),
      tags: tags is List
          ? tags.whereType<String>().toList(growable: false)
          : const [],
      status: '${json['status'] ?? ''}',
      slug: json['slug'] as String?,
      coverUrl: json['coverUrl'] as String?,
      avatarUrl: json['avatarUrl'] as String?,
      followerCount: _asInt(json['followerCount']),
      likeCount: _asInt(json['likeCount']),
    );
  }

  static int _asInt(Object? value) => value is num ? value.toInt() : 0;
}

class ColumnPost {
  const ColumnPost({
    required this.id,
    required this.columnId,
    required this.authorId,
    required this.title,
    required this.summary,
    required this.content,
    required this.viewCount,
    required this.likeCount,
    required this.commentCount,
    required this.status,
    this.coverImage,
    this.publishedAt,
  });

  final String id;
  final String columnId;
  final String authorId;
  final String title;
  final String summary;
  final String content;
  final int viewCount;
  final int likeCount;
  final int commentCount;
  final String status;
  final String? coverImage;
  final DateTime? publishedAt;

  factory ColumnPost.fromJson(Map<String, dynamic> json) {
    final summary = json['summary'];
    return ColumnPost(
      id: '${json['id'] ?? ''}',
      columnId: '${json['columnId'] ?? ''}',
      authorId: '${json['authorId'] ?? ''}',
      title: '${json['title'] ?? ''}',
      summary: summary is String ? summary : '',
      content: '${json['content'] ?? ''}',
      viewCount: _asInt(json['viewCount']),
      likeCount: _asInt(json['likeCount']),
      commentCount: _asInt(json['commentCount']),
      status: '${json['status'] ?? ''}',
      coverImage: json['coverImage'] as String?,
      publishedAt: DateTime.tryParse(
        '${json['publishedAt'] ?? ''}',
      )?.toLocal(),
    );
  }

  static int _asInt(Object? value) => value is num ? value.toInt() : 0;
}

class ColumnPage {
  const ColumnPage({
    required this.items,
    required this.total,
    required this.page,
    required this.pages,
  });

  final List<ColumnSummary> items;
  final int total;
  final int page;
  final int pages;

  bool get hasMore => page < pages;

  factory ColumnPage.fromJson(Map<String, dynamic> json) {
    final items = json['items'];
    return ColumnPage(
      items: items is List
          ? items
                .whereType<Map>()
                .map((e) => ColumnSummary.fromJson(Map<String, dynamic>.from(e)))
                .toList(growable: false)
          : const [],
      total: ColumnSummary._asInt(json['total']),
      page: ColumnSummary._asInt(json['page']),
      pages: ColumnSummary._asInt(json['pages']),
    );
  }
}

class ColumnPostPage {
  const ColumnPostPage({
    required this.items,
    required this.total,
    required this.page,
    required this.pages,
  });

  final List<ColumnPost> items;
  final int total;
  final int page;
  final int pages;

  bool get hasMore => page < pages;

  factory ColumnPostPage.fromJson(Map<String, dynamic> json) {
    final items = json['items'];
    return ColumnPostPage(
      items: items is List
          ? items
                .whereType<Map>()
                .map(
                  (e) => ColumnPost.fromJson(Map<String, dynamic>.from(e)),
                )
                .toList(growable: false)
          : const [],
      total: ColumnSummary._asInt(json['total']),
      page: ColumnSummary._asInt(json['page']),
      pages: ColumnSummary._asInt(json['pages']),
    );
  }
}

/// Public column reading plus the one write the desktop exposes: applying for
/// a column. Column posting needs `columns.publish` and stays on the website
/// until there is a permission gate in the app.
class ColumnsApi {
  const ColumnsApi(this._client);

  final ApiClient _client;

  Future<ColumnPage> columns({int page = 1, int pageSize = 20}) async {
    final data = await graphqlRequest(_client, _columnsQuery, {
      'page': page,
      'pageSize': pageSize,
    });
    final raw = data['columns'];
    if (raw is! Map) {
      return const ColumnPage(items: [], total: 0, page: 1, pages: 0);
    }
    return ColumnPage.fromJson(Map<String, dynamic>.from(raw));
  }

  Future<ColumnPostPage> posts(
    String columnId, {
    int page = 1,
    int pageSize = 20,
  }) async {
    final data = await graphqlRequest(_client, _columnPostsQuery, {
      'columnId': columnId,
      'page': page,
      'pageSize': pageSize,
    });
    final raw = data['columnPosts'];
    if (raw is! Map) {
      return const ColumnPostPage(items: [], total: 0, page: 1, pages: 0);
    }
    return ColumnPostPage.fromJson(Map<String, dynamic>.from(raw));
  }

  Future<void> apply({
    required String title,
    required String description,
    required String reason,
  }) async {
    await _client.post(
      '/content/columns/applications',
      body: {
        'title': title,
        'description': description,
        'reason': reason,
      },
    );
  }
}
