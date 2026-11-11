import 'package:island/core/api/api_client.dart';
import 'package:island/core/api/content_api.dart';

class BlogSeries {
  const BlogSeries(this.id, this.title, this.ownerId, this.paths);
  final String id;
  final String title;
  final String ownerId;
  final List<String> paths;

  factory BlogSeries.fromJson(Map<String, dynamic> json) {
    final paths = <String>[];
    void walk(Object? nodes, String prefix) {
      if (nodes is! List) return;
      for (final node in nodes.whereType<Map>()) {
        final name = node['name'];
        if (name is! String) continue;
        final path = '$prefix$name';
        if (node['type'] == 'blob' &&
            RegExp(r'\.mdx?$', caseSensitive: false).hasMatch(path)) {
          paths.add(path);
        } else if (node['type'] == 'tree') {
          walk(node['children'], '$path/');
        }
      }
    }

    walk(json['fileTree'], '');
    return BlogSeries(
      '${json['id']}',
      '${json['title']}',
      '${json['ownerId']}',
      paths,
    );
  }
}

class BlogApi {
  const BlogApi(this.client);
  final ApiClient client;

  Future<BlogSeries> detail(String id) async {
    // Same six-level file tree selection as the website.
    var tree = 'name type';
    for (var i = 0; i < 5; i++) {
      tree = 'name type children { $tree }';
    }
    final data = await graphqlRequest(
      client,
      'query BlogSeriesDetail(\$id: ID!) { blogSeriesDetail(seriesId: \$id) { id title ownerId fileTree { $tree } } }',
      {'id': id},
    );
    final raw = data['blogSeriesDetail'];
    if (raw is! Map) throw const FormatException('Series not found');
    return BlogSeries.fromJson(Map<String, dynamic>.from(raw));
  }

  Future<String> content(String id, String path) async {
    validatePath(path);
    final data = await graphqlRequest(
      client,
      r'''query BlogFileContent($seriesId: ID!, $filepath: String!) {
      blogFileContent(seriesId: $seriesId, filepath: $filepath) { filepath content }
    }''',
      {'seriesId': id, 'filepath': path},
    );
    final raw = data['blogFileContent'];
    if (raw is! Map || raw['content'] is! String)
      throw const FormatException('File not found');
    return raw['content'] as String;
  }

  Future<String> createSeries(String title, String repoName) async {
    final raw = await client.post(
      '/blog/series',
      body: {'title': title, 'repo_name': repoName},
    );
    if (raw is! Map || raw['id'] is! String)
      throw const FormatException('Invalid series response');
    return raw['id'] as String;
  }

  Future<void> save(String id, String path, String content) async {
    validatePath(path);
    await client.put(
      '/blog/series/${Uri.encodeComponent(id)}/files/${path.split('/').map(Uri.encodeComponent).join('/')}',
      body: {'content': content, 'message': 'save'},
    );
  }

  Future<void> publish(String id, String path, String title) async {
    validatePath(path);
    await client.post(
      '/blog/series/${Uri.encodeComponent(id)}/publish',
      body: {
        'filepath': path,
        if (title.trim().isNotEmpty) 'override': {'title': title},
      },
    );
  }

  static void validatePath(String path) {
    if (path.isEmpty ||
        path.startsWith('/') ||
        path.contains('\\') ||
        path.split('/').any((s) => s.isEmpty || s == '..' || s == '.') ||
        !RegExp(r'\.mdx?$', caseSensitive: false).hasMatch(path)) {
      throw ArgumentError.value(
        path,
        'path',
        'Expected relative Markdown path',
      );
    }
  }
}
