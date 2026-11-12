import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'api_client.dart';

/// One question row from `/content/qa/questions`.
///
/// The REST contract is snake_case; the detail endpoint returns the same
/// shape plus `answers`/`images`, so a single model covers both.
class QaQuestion {
  const QaQuestion({
    required this.id,
    required this.authorId,
    required this.authorName,
    required this.title,
    required this.situation,
    required this.content,
    required this.category,
    required this.status,
    required this.bountyPeople,
    required this.bountyPerPerson,
    required this.bountyTotal,
    required this.bountyDistributed,
    required this.urgent,
    required this.answerCount,
    required this.createdAt,
    this.bountyExpiresAt,
    this.acceptedAnswerId,
    this.answers = const [],
    this.images = const [],
  });

  final String id;
  final String authorId;
  final String authorName;
  final String title;
  final String situation;
  final String content;

  /// `help` or `volunteer`.
  final String category;

  /// `open`, `accepted` or `closed`.
  final String status;
  final int bountyPeople;
  final int bountyPerPerson;
  final int bountyTotal;
  final int bountyDistributed;
  final bool urgent;
  final int answerCount;
  final DateTime createdAt;
  final DateTime? bountyExpiresAt;
  final String? acceptedAnswerId;
  final List<QaAnswer> answers;
  final List<String> images;

  bool get isOpen => status == 'open';

  factory QaQuestion.fromJson(Map<String, dynamic> json) {
    final answers = json['answers'];
    final images = json['images'];
    return QaQuestion(
      id: '${json['id'] ?? ''}',
      authorId: '${json['author_id'] ?? ''}',
      authorName: '${json['author_name'] ?? ''}',
      title: '${json['title'] ?? ''}',
      situation: '${json['situation'] ?? ''}',
      content: '${json['content'] ?? ''}',
      category: '${json['category'] ?? 'help'}',
      status: '${json['status'] ?? 'open'}',
      bountyPeople: _asInt(json['bounty_people']),
      bountyPerPerson: _asInt(json['bounty_per_person']),
      bountyTotal: _asInt(json['bounty_total']),
      bountyDistributed: _asInt(json['bounty_distributed']),
      urgent: json['urgent'] == true,
      answerCount: _asInt(json['answer_count']),
      createdAt:
          (DateTime.tryParse('${json['created_at'] ?? ''}') ??
                  DateTime.fromMillisecondsSinceEpoch(0))
              .toLocal(),
      bountyExpiresAt: DateTime.tryParse(
        '${json['bounty_expires_at'] ?? ''}',
      )?.toLocal(),
      acceptedAnswerId: json['accepted_answer_id'] as String?,
      answers: answers is List
          ? answers
                .whereType<Map>()
                .map((e) => QaAnswer.fromJson(Map<String, dynamic>.from(e)))
                .toList(growable: false)
          : const [],
      images: images is List
          ? images.whereType<String>().toList(growable: false)
          : const [],
    );
  }

  static int _asInt(Object? value) => value is num ? value.toInt() : 0;
}

class QaAnswer {
  const QaAnswer({
    required this.id,
    required this.questionId,
    required this.authorId,
    required this.authorName,
    required this.content,
    required this.isAccepted,
    required this.createdAt,
  });

  final String id;
  final String questionId;
  final String authorId;
  final String authorName;
  final String content;
  final bool isAccepted;
  final DateTime createdAt;

  factory QaAnswer.fromJson(Map<String, dynamic> json) {
    return QaAnswer(
      id: '${json['id'] ?? ''}',
      questionId: '${json['question_id'] ?? ''}',
      authorId: '${json['author_id'] ?? ''}',
      authorName: '${json['author_name'] ?? ''}',
      content: '${json['content'] ?? ''}',
      isAccepted: json['is_accepted'] == true,
      createdAt:
          (DateTime.tryParse('${json['created_at'] ?? ''}') ??
                  DateTime.fromMillisecondsSinceEpoch(0))
              .toLocal(),
    );
  }
}

/// Reads and writes `/content/qa/*`. Asking locks the bounty in escrow on the
/// service side; the desktop sends whatever the form collected.
class QaApi {
  const QaApi(this._client);

  final ApiClient _client;

  Future<ApiPage<QaQuestion>> questions({
    String? category,
    String sort = 'newest',
    String? authorId,
    int page = 1,
    int limit = 20,
  }) {
    return _client.getPage(
      '/content/qa/questions',
      query: {
        'page': page,
        'limit': limit,
        'sort': sort,
        'category': ?category,
        'author_id': ?authorId,
      },
      parseItem: QaQuestion.fromJson,
    );
  }

  Future<QaQuestion> question(String id) async {
    final json = await _client.getObject('/content/qa/questions/$id');
    return QaQuestion.fromJson(json);
  }

  Future<QaQuestion> ask({
    required String title,
    required String situation,
    required String content,
    required String category,
    required int bountyPeople,
    required int bountyPerPerson,
    required int bountyDays,
    required bool urgent,
  }) async {
    final json = await _client.post(
      '/content/qa/questions',
      body: {
        'title': title,
        'situation': situation,
        'content': content,
        'category': category,
        'bounty_people': bountyPeople,
        'bounty_per_person': bountyPerPerson,
        'bounty_days': bountyDays,
        'urgent': urgent,
        'images': const <String>[],
      },
    );
    if (json is! Map) throw _shape('POST', '/content/qa/questions');
    return QaQuestion.fromJson(Map<String, dynamic>.from(json));
  }

  Future<String> uploadImage(
    String questionId, {
    required String imageId,
    required Uint8List bytes,
    required String filename,
  }) async {
    final result = await _client.postForm(
      '/content/qa/questions/$questionId/images',
      form: FormData.fromMap({
        'image_id': imageId,
        'file': MultipartFile.fromBytes(bytes, filename: filename),
      }),
    );
    if (result is! Map || result['url'] is! String) {
      throw _shape('POST', '/content/qa/questions/$questionId/images');
    }
    return result['url'] as String;
  }

  Future<QaAnswer> answer(String questionId, String content) async {
    final json = await _client.post(
      '/content/qa/questions/$questionId/answers',
      body: {'content': content},
    );
    if (json is! Map) {
      throw _shape('POST', '/content/qa/questions/$questionId/answers');
    }
    return QaAnswer.fromJson(Map<String, dynamic>.from(json));
  }

  Future<QaAnswer> accept(String questionId, String answerId) async {
    final json = await _client.post(
      '/content/qa/questions/$questionId/accept',
      body: {'answer_id': answerId},
    );
    if (json is! Map) {
      throw _shape('POST', '/content/qa/questions/$questionId/accept');
    }
    return QaAnswer.fromJson(Map<String, dynamic>.from(json));
  }

  Future<QaQuestion> close(String questionId) async {
    final json = await _client.post('/content/qa/questions/$questionId/close');
    if (json is! Map) {
      throw _shape('POST', '/content/qa/questions/$questionId/close');
    }
    return QaQuestion.fromJson(Map<String, dynamic>.from(json));
  }

  static ApiException _shape(String method, String path) => ApiException(
    code: ApiCode.internalError,
    message: '问答响应格式错误',
    method: method,
    path: path,
  );
}
