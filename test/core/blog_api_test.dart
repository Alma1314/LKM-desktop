import 'package:island/files/library_screen.dart';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:island/core/api/api_client.dart';
import 'package:island/core/api/blog_api.dart';
import 'package:island/editor/document_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:island/editor/series_editor_screen.dart';

class _Adapter implements HttpClientAdapter {
  _Adapter(this.handle);

  final ResponseBody Function(RequestOptions options) handle;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return handle(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(Object? body) => ResponseBody.fromString(
  jsonEncode(body),
  200,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

ResponseBody _envelope(Object? data) =>
    _json({'code': 0, 'message': 'ok', 'data': data});

void main() {
  test(
    'series tree and source read use GraphQL; writes encode nested paths',
    () async {
      final adapter = _Adapter((options) {
        if (options.uri.path == '/graphql/v1') {
          final query = (options.data as Map)['query'] as String;
          if (query.contains('BlogSeriesDetail'))
            return _json({
              'data': {
                'blogSeriesDetail': {
                  'id': 's1',
                  'ownerId': 'u1',
                  'title': 'Series',
                  'fileTree': [
                    {
                      'name': 'posts',
                      'type': 'tree',
                      'children': [
                        {'name': 'a b.md', 'type': 'blob'},
                        {'name': 'photo.png', 'type': 'blob'},
                      ],
                    },
                  ],
                },
              },
            });
          return _json({
            'data': {
              'blogFileContent': {
                'filepath': 'posts/a b.md',
                'content': '# test',
              },
            },
          });
        }
        return _envelope(null);
      });
      final api = BlogApi(
        ApiClient(
          serverUrl: 'https://example.com',
          dio: Dio()..httpClientAdapter = adapter,
        ),
      );
      expect((await api.detail('s1')).paths, ['posts/a b.md']);
      expect(await api.content('s1', 'posts/a b.md'), '# test');
      await api.save('s1', 'posts/a b.md', '# changed');
      expect(
        adapter.requests.last.uri.path,
        '/api/v1/blog/series/s1/files/posts/a%20b.md',
      );
      expect((adapter.requests.last.data as Map)['content'], '# changed');
      await api.publish('s1', 'posts/a b.md', 'Title');
      expect((adapter.requests.last.data as Map)['filepath'], 'posts/a b.md');
    },
  );
  test('unsafe and non-Markdown paths are rejected', () {
    for (final path in [
      '../a.md',
      '/a.md',
      'a/../b.md',
      'a//b.md',
      'a.png',
      'a\\b.md',
    ]) {
      expect(() => BlogApi.validatePath(path), throwsArgumentError);
    }
  });
  test('missing file fails rather than opening an empty document', () async {
    final adapter = _Adapter(
      (_) => _json({
        'data': {'blogFileContent': null},
      }),
    );
    final api = BlogApi(
      ApiClient(
        serverUrl: 'https://example.com',
        dio: Dio()..httpClientAdapter = adapter,
      ),
    );
    await expectLater(api.content('s1', 'a.md'), throwsFormatException);
  });
  test(
    'local draft survives restart; history deduplicates and isolates accounts',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final store = DocumentStore(prefs, 'https://example.com', 'u1');
      final doc = {'id': '1', 'title': 'Title', 'content': '# old'};
      await store.save(doc, snapshot: true);
      await store.save(doc, snapshot: true);
      await store.save({...doc, 'content': '# new'}, snapshot: true);
      final restored = DocumentStore(
        prefs,
        'https://example.com',
        'u1',
      ).documents().single;
      expect(restored['content'], '# new');
      expect((restored['history'] as List).map((e) => e['content']), [
        '# new',
        '# old',
      ]);
      expect(
        DocumentStore(prefs, 'https://example.com', 'u2').documents(),
        isEmpty,
      );
      expect(
        DocumentStore(prefs, 'https://other.com', 'u1').documents(),
        isEmpty,
      );
      expect(const SeriesEditorScreen(), isNotNull);
      expect(const LibraryScreen(), isNotNull);
    },
  );
}
