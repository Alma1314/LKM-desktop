import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:island/core/api/api_client.dart';
import 'package:island/core/api/columns_api.dart';
import 'package:island/core/api/content_api.dart';
import 'package:island/core/api/projects_api.dart';
import 'package:island/core/api/qa_api.dart';

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

ResponseBody _json(Object? body, {int status = 200}) =>
    ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );

ResponseBody _envelope(Object? data) =>
    _json({'code': 0, 'message': 'ok', 'data': data});

ApiClient _client(_Adapter adapter) => ApiClient(
  serverUrl: 'https://community.example',
  dio: Dio()..httpClientAdapter = adapter,
);

void main() {
  test('qa list sends filters and decodes snake_case rows', () async {
    final adapter = _Adapter(
      (options) => _envelope({
        'items': [
          {
            'id': 'q1',
            'author_id': 'u1',
            'author_name': 'Ada',
            'title': 'Why is the sky blue?',
            'situation': 'Curious',
            'content': 'Light scatters',
            'category': 'help',
            'status': 'open',
            'bounty_people': 1,
            'bounty_per_person': 50,
            'bounty_total': 50,
            'bounty_distributed': 0,
            'urgent': true,
            'answer_count': 2,
            'created_at': '2026-11-09T10:00:00Z',
          },
        ],
        'total': 1,
        'page': 1,
        'pages': 1,
      }),
    );
    final page = await QaApi(_client(adapter)).questions(
      category: 'help',
      sort: 'bounty',
      page: 1,
    );

    final request = adapter.requests.single;
    expect(request.path, '/content/qa/questions');
    expect(request.queryParameters['category'], 'help');
    expect(request.queryParameters['sort'], 'bounty');
    final question = page.items.single;
    expect(question.id, 'q1');
    expect(question.authorName, 'Ada');
    expect(question.bountyTotal, 50);
    expect(question.urgent, isTrue);
    expect(question.createdAt.toUtc(), DateTime.utc(2026, 11, 9, 10));
  });

  test('qa ask posts the bounty form and decodes the created row', () async {
    final adapter = _Adapter(
      (options) => _envelope({
        'id': 'q2',
        'author_id': 'u1',
        'author_name': 'Ada',
        'title': 'T',
        'situation': 'S',
        'content': 'C',
        'category': 'volunteer',
        'status': 'open',
        'bounty_people': 1,
        'bounty_per_person': 0,
        'bounty_total': 0,
        'bounty_distributed': 0,
        'urgent': false,
        'answer_count': 0,
        'created_at': '2026-11-09T10:00:00Z',
      }),
    );
    final question = await QaApi(_client(adapter)).ask(
      title: 'T',
      situation: 'S',
      content: 'C',
      category: 'volunteer',
      bountyPeople: 1,
      bountyPerPerson: 0,
      bountyDays: 7,
      urgent: false,
    );

    final request = adapter.requests.single;
    expect(request.method, 'POST');
    expect(request.path, '/content/qa/questions');
    final body = request.data as Map;
    expect(body['category'], 'volunteer');
    expect(body['bounty_days'], 7);
    expect(body['images'], isEmpty);
    expect(question.id, 'q2');
  });

  test('qa answer and accept hit the answer endpoints', () async {
    final adapter = _Adapter(
      (options) => _envelope({
        'id': 'a1',
        'question_id': 'q1',
        'author_id': 'u2',
        'author_name': 'Bob',
        'content': 'Because',
        'is_accepted': options.path.endsWith('/accept'),
        'created_at': '2026-11-09T11:00:00Z',
      }),
    );
    final api = QaApi(_client(adapter));
    await api.answer('q1', 'Because');
    final accepted = await api.accept('q1', 'a1');

    expect(adapter.requests[0].path, '/content/qa/questions/q1/answers');
    expect(adapter.requests[1].path, '/content/qa/questions/q1/accept');
    expect((adapter.requests[1].data as Map)['answer_id'], 'a1');
    expect(accepted.isAccepted, isTrue);
  });

  test('qa detail decodes answers and images', () async {
    final adapter = _Adapter(
      (options) => _envelope({
        'id': 'q1',
        'author_id': 'u1',
        'author_name': 'Ada',
        'title': 'T',
        'situation': 'S',
        'content': 'C',
        'category': 'help',
        'status': 'accepted',
        'bounty_people': 1,
        'bounty_per_person': 50,
        'bounty_total': 50,
        'bounty_distributed': 50,
        'urgent': false,
        'answer_count': 1,
        'created_at': '2026-11-09T10:00:00Z',
        'images': ['/api/v1/content/qa/questions/q1/images/i1'],
        'answers': [
          {
            'id': 'a1',
            'question_id': 'q1',
            'author_id': 'u2',
            'author_name': 'Bob',
            'content': 'Because',
            'is_accepted': true,
            'created_at': '2026-11-09T11:00:00Z',
          },
        ],
      }),
    );
    final question = await QaApi(_client(adapter)).question('q1');

    expect(adapter.requests.single.path, '/content/qa/questions/q1');
    expect(question.answers.single.isAccepted, isTrue);
    expect(question.images, hasLength(1));
  });

  test('columns graphql posts to the root and decodes camelCase', () async {
    final adapter = _Adapter(
      (options) => _json({
        'data': {
          'columns': {
            'items': [
              {
                'id': 'c1',
                'title': 'Math',
                'description': 'Numbers',
                'authorName': 'Ada',
                'isVerified': true,
                'articleCount': 3,
                'tags': ['math'],
                'status': 'active',
                'followerCount': 12,
              },
            ],
            'total': 1,
            'page': 1,
            'pages': 1,
          },
        },
      }),
    );
    final page = await ColumnsApi(_client(adapter)).columns();

    final request = adapter.requests.single;
    expect(request.uri.toString(), contains('/graphql/v1'));
    expect((request.data as Map)['query'], contains('columns'));
    expect(page.items.single.title, 'Math');
    expect(page.items.single.isVerified, isTrue);
    expect(page.items.single.followerCount, 12);
  });

  test('column posts decode summary and counters', () async {
    final adapter = _Adapter(
      (options) => _json({
        'data': {
          'columnPosts': {
            'items': [
              {
                'id': 'p1',
                'columnId': 'c1',
                'authorId': 'u1',
                'title': 'Post',
                'summary': 'Short',
                'content': 'Body',
                'viewCount': 5,
                'likeCount': 2,
                'commentCount': 1,
                'status': 'published',
                'publishedAt': '2026-11-01T00:00:00Z',
              },
            ],
            'total': 1,
            'page': 1,
            'pages': 2,
          },
        },
      }),
    );
    final page = await ColumnsApi(_client(adapter)).posts('c1');

    expect(adapter.requests.single.uri.toString(), contains('/graphql/v1'));
    expect(page.hasMore, isTrue);
    expect(page.items.single.summary, 'Short');
    expect(page.items.single.viewCount, 5);
  });

  test('projects list decodes the showcase fields', () async {
    final adapter = _Adapter(
      (options) => _envelope([
        {
          'id': 'p1',
          'title': 'Rocket',
          'summary': 'Up',
          'description': 'Details',
          'applicant_name': 'Ada',
          'is_incubated': true,
          'is_recruiting': true,
          'is_pinned': false,
          'progress': 40,
          'recruiting_roles': ['Engineer'],
          'tags': ['space'],
          'reports': [
            {'title': 'Week 1', 'content': 'Done', 'revision': 1, 'date': '11-01'},
          ],
          'members': [
            {
              'id': 'm1',
              'display_name': 'Ada',
              'role_in_project': 'Lead',
            },
          ],
          'status': 'approved',
          'created_at': '2026-11-01T00:00:00Z',
        },
      ]),
    );
    final projects = await ProjectsApi(_client(adapter)).projects();

    expect(adapter.requests.single.path, '/projects');
    final project = projects.single;
    expect(project.isIncubated, isTrue);
    expect(project.progress, 40);
    expect(project.recruitingRoles.single, 'Engineer');
    expect(project.members.single.roleInProject, 'Lead');
    expect(project.reports.single.title, 'Week 1');
  });

  test('project apply posts the incubation form', () async {
    final adapter = _Adapter(
      (options) => _envelope({'id': 'a1'}),
    );
    await ProjectsApi(_client(adapter)).apply(
      title: 'Rocket',
      summary: 'Up',
      description: 'Details',
    );

    final request = adapter.requests.single;
    expect(request.path, '/projects/applications');
    expect((request.data as Map)['title'], 'Rocket');
  });

  test('content items page filters by board', () async {
    final adapter = _Adapter(
      (options) => _json({
        'data': {
          'contentItems': {
            'items': [
              {
                'id': 'i1',
                'contentType': 'discussion',
                'boardId': 'b1',
                'authorName': 'Ada',
                'title': 'Hello',
                'excerpt': 'Hi',
                'content': 'Body',
                'tags': [],
                'status': 'published',
                'viewCount': 1,
                'likeCount': 0,
                'commentCount': 0,
                'bookmarkCount': 0,
                'forwardCount': 0,
                'createdAt': '2026-11-01T00:00:00Z',
              },
            ],
            'total': 1,
            'page': 1,
            'pages': 1,
          },
        },
      }),
    );
    final page = await ContentApi(_client(adapter)).items(boardId: 'b1');

    expect((adapter.requests.single.data as Map)['variables'], containsPair('boardId', 'b1'));
    expect(page.items.single.boardId, 'b1');
    expect(page.items.single.title, 'Hello');
  });
}
