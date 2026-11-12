import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:island/core/api/api_client.dart';
import 'package:island/core/api/exam_api.dart';

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

Map<String, dynamic> _examJson({
  String type = 'competition',
  String? startsAt = '2026-11-10T00:00:00Z',
  String? endsAt = '2026-11-12T00:00:00Z',
}) => {
  'id': 'e1',
  'type': type,
  'title': 'Math Cup',
  'subject': 'math',
  'difficulty': 2,
  'description': 'Solve things',
  'pass_score': 60,
  'time_limit_min': 90,
  'is_published': true,
  'unlock_level': null,
  'unlock_role': null,
  'starts_at': startsAt,
  'ends_at': endsAt,
  'question_count': 3,
  'created_at': '2026-11-01T00:00:00Z',
  'updated_at': '2026-11-01T00:00:00Z',
};

void main() {
  test('exam list sends the type filter and decodes the window', () async {
    final adapter = _Adapter(
      (options) => _envelope({
        'items': [_examJson()],
        'total': 1,
        'page': 1,
        'pages': 1,
      }),
    );
    final page = await ExamApi(_client(adapter)).exams(type: 'competition');

    final request = adapter.requests.single;
    expect(request.path, '/exam');
    expect(request.queryParameters['type'], 'competition');
    final exam = page.items.single;
    expect(exam.isCompetition, isTrue);
    expect(exam.passScore, 60);
    expect(exam.timeLimitMin, 90);
    expect(exam.questionCount, 3);
    expect(exam.startsAt!.toUtc(), DateTime.utc(2026, 11, 10));
    expect(exam.endsAt!.toUtc(), DateTime.utc(2026, 11, 12));
  });

  test('exam detail decodes a windowless certification exam', () async {
    final adapter = _Adapter(
      (options) => _envelope(
        _examJson(type: 'exam', startsAt: null, endsAt: null)
          ..['unlock_level'] = 'normal',
      ),
    );
    final exam = await ExamApi(_client(adapter)).exam('e1');

    expect(adapter.requests.single.path, '/exam/e1');
    expect(exam.isCompetition, isFalse);
    expect(exam.startsAt, isNull);
    expect(exam.unlockLevel, 'normal');
    expect(exam.unlocksSomething, isTrue);
  });

  test('start attempt decodes the candidate-safe question list', () async {
    final adapter = _Adapter(
      (options) => _envelope({
        'attempt_id': 'a1',
        'exam_id': 'e1',
        'time_limit_min': 30,
        'deadline': null,
        'questions': [
          {
            'id': 'q1',
            'kind': 'single',
            'content': '1+1?',
            'options': [
              {'key': 'A', 'text': '1'},
              {'key': 'B', 'text': '2'},
            ],
            'difficulty': 1,
            'score': 10,
            'sort_order': 0,
          },
          {
            'id': 'q2',
            'kind': 'judge',
            'content': 'Sky is blue.',
            'options': [],
            'difficulty': 1,
            'score': 10,
            'sort_order': 1,
          },
        ],
      }),
    );
    final attempt = await ExamApi(_client(adapter)).startAttempt('e1');

    final request = adapter.requests.single;
    expect(request.method, 'POST');
    expect(request.path, '/exam/e1/attempts');
    expect(attempt.attemptId, 'a1');
    expect(attempt.questions, hasLength(2));
    expect(attempt.questions.first.options.last.text, '2');
    expect(attempt.questions.last.isJudge, isTrue);
    expect(attempt.deadline, isNull);
  });

  test('submit posts the answer map and decodes the result', () async {
    final adapter = _Adapter(
      (options) => _envelope({
        'attempt_id': 'a1',
        'exam_id': 'e1',
        'score': 80,
        'pass_score': 60,
        'passed': true,
        'unlock_level': null,
        'unlock_role': 'author',
        'certificate_id': 'c1',
      }),
    );
    final result = await ExamApi(
      _client(adapter),
    ).submitAttempt('a1', {'q1': 'B', 'q2': 'T'});

    final request = adapter.requests.single;
    expect(request.path, '/exam/attempts/a1/submit');
    expect((request.data as Map)['answers'], {'q1': 'B', 'q2': 'T'});
    expect(result.passed, isTrue);
    expect(result.score, 80);
    expect(result.unlockRole, 'author');
    expect(result.certificateId, 'c1');
  });

  test('certificates decode the list data envelope', () async {
    final adapter = _Adapter(
      (options) => _envelope({
        'items': [
          {
            'id': 'c1',
            'exam_id': 'e1',
            'user_id': 'u1',
            'exam_title': 'Math Cup',
            'score': 80,
            'passed': true,
            'cert_no': 'abc123',
            'issued_at': '2026-11-11T08:00:00Z',
          },
        ],
      }),
    );
    final certificates = await ExamApi(_client(adapter)).myCertificates();

    expect(adapter.requests.single.path, '/exam/certificates/mine');
    expect(certificates.single.examTitle, 'Math Cup');
    expect(certificates.single.certNo, 'abc123');
    expect(certificates.single.issuedAt.toUtc(), DateTime.utc(2026, 11, 11, 8));
  });

  test('leaderboard pages decode ranked entries', () async {
    final adapter = _Adapter(
      (options) => _envelope({
        'items': [
          {
            'user_id': 'u1',
            'display_name': 'Ada',
            'score': 95,
            'certified': true,
          },
        ],
        'total': 1,
        'page': 1,
        'pages': 1,
      }),
    );
    final page = await ExamApi(_client(adapter)).leaderboard('e1');

    expect(adapter.requests.single.path, '/exam/e1/leaderboard');
    expect(page.items.single.displayName, 'Ada');
    expect(page.items.single.score, 95);
  });
}
