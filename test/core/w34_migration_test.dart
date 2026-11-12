import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:island/core/api/api_client.dart';
import 'package:island/core/api/projects_api.dart';
import 'package:island/core/api/qa_api.dart';
import 'package:island/core/api/treehole_api.dart';
import 'package:island/community/feed_links.dart';
import 'package:island/hub/ask_question_dialog.dart';
import 'package:island/hub/hub_screen.dart';
import 'package:island/treehole/treehole_screen.dart';
import 'package:island/treehole/settings_sheet.dart';
import 'package:island/treehole/local_store.dart';

class _Adapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  @override
  void close({bool force = false}) {}
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? stream,
    Future<void>? cancel,
  ) async {
    requests.add(options);
    return ResponseBody.fromString(
      jsonEncode({
        'code': 0,
        'data': {'url': '/api/v1/content/qa/questions/q1/images/i1'},
      }),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }
}

void main() {
  test(
    'image uploads use idempotent image IDs and multipart form data',
    () async {
      final adapter = _Adapter();
      final api = QaApi(
        ApiClient(
          serverUrl: 'http://localhost:8000',
          dio: Dio()..httpClientAdapter = adapter,
        ),
      );
      expect(
        await api.uploadImage(
          'q1',
          imageId: 'i1',
          bytes: Uint8List.fromList([1, 2]),
          filename: 'photo.png',
        ),
        endsWith('/images/i1'),
      );
      final request = adapter.requests.single;
      expect(request.path, '/content/qa/questions/q1/images');
      final form = request.data as FormData;
      expect(form.fields.toMap()['image_id'], 'i1');
      expect(form.files.single.key, 'file');
      expect(form.files.single.value.filename, 'photo.png');
    },
  );
  test(
    'project requests carry member claims without inventing recruitment fields',
    () async {
      final adapter = _Adapter();
      await ProjectsApi(
        ApiClient(
          serverUrl: 'http://localhost:8000',
          dio: Dio()..httpClientAdapter = adapter,
        ),
      ).apply(
        title: 'A',
        summary: 'B',
        description: 'C',
        memberClaims: [
          {'display_name': 'Ada', 'role_in_project': 'Design'},
        ],
      );
      expect(adapter.requests.single.path, '/projects/applications');
      expect((adapter.requests.single.data as Map)['member_claims'], [
        {'display_name': 'Ada', 'role_in_project': 'Design'},
      ]);
    },
  );
  test(
    'treehole backup isolates deployments and excludes visitor credentials',
    () async {
      SharedPreferences.setMockInitialValues({
        'lkm_treehole_session': 'private-cookie',
      });
      final prefs = await SharedPreferences.getInstance();
      final store = TreeholeLocalStore(prefs, 'http://localhost:8000');
      await store.patch('draft', {
        'content': 'Unfinished',
        'category': 'heart',
        'privacy': 'self',
      });
      await store.patch('scale', 1.3);
      final backup = store.export();
      expect(backup, isNot(contains('private-cookie')));
      final other = TreeholeLocalStore(prefs, 'http://localhost:8001');
      expect(other.read(), isEmpty);
      await other.import(backup);
      expect((other.read()['draft'] as Map)['content'], 'Unfinished');
      await expectLater(
        other.import('{"version":1,"scale":99}'),
        throwsFormatException,
      );
      await expectLater(
        other.import('{"version":1,"draft":{"privacy":"bad"}}'),
        throwsFormatException,
      );
      expect(other.read()['scale'], 1.3);
    },
  );
  test(
    'ranking excludes private, future and scheduled letters with deterministic ties',
    () {
      final now = DateTime(2026, 11, 12, 12);
      LkmTreeholeLetter letter(
        String id, {
        int days = 0,
        int likes = 0,
        int favorites = 0,
        String privacy = 'public',
        String status = 'published',
      }) => LkmTreeholeLetter.fromJson({
        'id': id,
        'privacy': privacy,
        'status': status,
        'createdAt': now.subtract(Duration(days: days)).millisecondsSinceEpoch,
        'likes': likes,
        'favorites': favorites,
      });
      final rows = [
        letter('old', days: 2, likes: 99),
        letter('a', likes: 2),
        letter('b', favorites: 2),
        letter('secret', privacy: 'self', likes: 100),
        letter('scheduled', status: 'scheduled', likes: 100),
        letter('future', days: -1, likes: 999),
      ];
      expect(rankTreeholeLetters(rows, now, 1).map((l) => l.id), ['a', 'b']);
      expect(rankTreeholeLetters(rows, now, 7).map((l) => l.id), [
        'old',
        'a',
        'b',
      ]);
    },
  );
  test('notification links require the exact configured origin', () {
    expect(
      parseFeedRoute(
        'https://site.example:8443/files/f1',
        serverHost: 'https://site.example:8443',
      )?.kind,
      FeedRouteKind.file,
    );
    expect(
      parseFeedRoute(
        'https://site.example/files/f1',
        serverHost: 'https://site.example:8443',
      ),
      isNull,
    );
    expect(
      parseFeedRoute(
        '//site.example/files/f1',
        serverHost: 'https://site.example',
      ),
      isNull,
    );
  });
  test(
    'scheduled and sealed dates use the existing epoch-millisecond contract',
    () {
      final time = DateTime.utc(2026, 12, 1);
      final input = LkmLetterInput(
        content: 'later',
        category: 'heart',
        privacy: 'self',
        codename: 'A',
        scheduledAt: time,
        sealUntil: time.add(const Duration(days: 1)),
      ).toJson();
      expect(input['scheduledAt'], time.millisecondsSinceEpoch);
      expect(
        input['sealUntil'],
        time.add(const Duration(days: 1)).millisecondsSinceEpoch,
      );
      expect(const AskQuestionDialog(), isNotNull);
      expect(const HubScreen(), isNotNull);
      expect(const TreeholeScreen(), isNotNull);
      expect(const TreeholeSettingsSheet(), isNotNull);
    },
  );
}

extension on List<MapEntry<String, String>> {
  Map<String, String> toMap() => Map.fromEntries(this);
}
