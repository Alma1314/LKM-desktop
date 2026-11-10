import 'api_client.dart';

/// One published exam or competition from `/exam`.
///
/// `starts_at`/`ends_at` are set for competitions (the window doubles as the
/// schedule); certification exams leave both null and have no public
/// leaderboard.
class Exam {
  const Exam({
    required this.id,
    required this.type,
    required this.title,
    required this.subject,
    required this.difficulty,
    required this.passScore,
    required this.timeLimitMin,
    required this.isPublished,
    required this.questionCount,
    required this.createdAt,
    this.description,
    this.unlockLevel,
    this.unlockRole,
    this.startsAt,
    this.endsAt,
  });

  final String id;
  final String type;
  final String title;
  final String subject;
  final int difficulty;
  final String? description;
  final int passScore;
  final int timeLimitMin;
  final bool isPublished;
  final String? unlockLevel;
  final String? unlockRole;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final int questionCount;
  final DateTime createdAt;

  bool get isCompetition => type == 'competition';

  bool get unlocksSomething =>
      (unlockLevel != null && unlockLevel!.isNotEmpty) ||
      (unlockRole != null && unlockRole!.isNotEmpty);

  factory Exam.fromJson(Map<String, dynamic> json) {
    return Exam(
      id: '${json['id'] ?? ''}',
      type: '${json['type'] ?? 'exam'}',
      title: '${json['title'] ?? ''}',
      subject: '${json['subject'] ?? ''}',
      difficulty: _asInt(json['difficulty'], 1),
      description: json['description'] as String?,
      passScore: _asInt(json['pass_score']),
      timeLimitMin: _asInt(json['time_limit_min']),
      isPublished: json['is_published'] != false,
      unlockLevel: json['unlock_level'] as String?,
      unlockRole: json['unlock_role'] as String?,
      startsAt: _asLocal(json['starts_at']),
      endsAt: _asLocal(json['ends_at']),
      questionCount: _asInt(json['question_count']),
      createdAt: _asLocal(json['created_at']) ?? DateTime(1970),
    );
  }
}

class ExamOption {
  const ExamOption({required this.key, required this.text});

  final String key;
  final String text;

  factory ExamOption.fromJson(Map<String, dynamic> json) => ExamOption(
    key: '${json['key'] ?? ''}',
    text: '${json['text'] ?? ''}',
  );
}

/// A question as shown to the candidate — deliberately without the answer.
class ExamQuestion {
  const ExamQuestion({
    required this.id,
    required this.kind,
    required this.content,
    required this.options,
    required this.difficulty,
    required this.score,
    required this.sortOrder,
  });

  final String id;

  /// `single` (multiple choice) or `judge` (true/false).
  final String kind;
  final String content;
  final List<ExamOption> options;
  final int difficulty;
  final int score;
  final int sortOrder;

  bool get isJudge => kind == 'judge';

  factory ExamQuestion.fromJson(Map<String, dynamic> json) {
    final raw = json['options'];
    return ExamQuestion(
      id: '${json['id'] ?? ''}',
      kind: '${json['kind'] ?? 'single'}',
      content: '${json['content'] ?? ''}',
      options: raw is List
          ? raw
                .whereType<Map>()
                .map((e) => ExamOption.fromJson(Map<String, dynamic>.from(e)))
                .toList(growable: false)
          : const [],
      difficulty: _asInt(json['difficulty'], 1),
      score: _asInt(json['score']),
      sortOrder: _asInt(json['sort_order']),
    );
  }
}

/// An open attempt: the server has already snapshotted the questions.
class ExamAttempt {
  const ExamAttempt({
    required this.attemptId,
    required this.examId,
    required this.questions,
    required this.timeLimitMin,
    this.deadline,
  });

  final String attemptId;
  final String examId;
  final List<ExamQuestion> questions;
  final int timeLimitMin;

  /// Only set for windowless exams; the service refuses late submissions on
  /// its own clock, so this drives the countdown, not the enforcement.
  final DateTime? deadline;

  factory ExamAttempt.fromJson(Map<String, dynamic> json) {
    final questions = json['questions'];
    return ExamAttempt(
      attemptId: '${json['attempt_id'] ?? ''}',
      examId: '${json['exam_id'] ?? ''}',
      questions: questions is List
          ? questions
                .whereType<Map>()
                .map((e) => ExamQuestion.fromJson(Map<String, dynamic>.from(e)))
                .toList(growable: false)
          : const [],
      timeLimitMin: _asInt(json['time_limit_min']),
      deadline: _asLocal(json['deadline']),
    );
  }
}

class ExamResult {
  const ExamResult({
    required this.attemptId,
    required this.examId,
    required this.score,
    required this.passScore,
    required this.passed,
    this.unlockLevel,
    this.unlockRole,
    this.certificateId,
  });

  final String attemptId;
  final String examId;
  final int score;
  final int passScore;
  final bool passed;
  final String? unlockLevel;
  final String? unlockRole;
  final String? certificateId;

  factory ExamResult.fromJson(Map<String, dynamic> json) => ExamResult(
    attemptId: '${json['attempt_id'] ?? ''}',
    examId: '${json['exam_id'] ?? ''}',
    score: _asInt(json['score']),
    passScore: _asInt(json['pass_score']),
    passed: json['passed'] == true,
    unlockLevel: json['unlock_level'] as String?,
    unlockRole: json['unlock_role'] as String?,
    certificateId: json['certificate_id'] as String?,
  );
}

class ExamCertificate {
  const ExamCertificate({
    required this.id,
    required this.examId,
    required this.examTitle,
    required this.score,
    required this.passed,
    required this.certNo,
    required this.issuedAt,
  });

  final String id;
  final String examId;
  final String examTitle;
  final int score;
  final bool passed;
  final String certNo;
  final DateTime issuedAt;

  factory ExamCertificate.fromJson(Map<String, dynamic> json) =>
      ExamCertificate(
        id: '${json['id'] ?? ''}',
        examId: '${json['exam_id'] ?? ''}',
        examTitle: '${json['exam_title'] ?? ''}',
        score: _asInt(json['score']),
        passed: json['passed'] == true,
        certNo: '${json['cert_no'] ?? ''}',
        issuedAt: _asLocal(json['issued_at']) ?? DateTime(1970),
      );
}

class ExamRanking {
  const ExamRanking({
    required this.userId,
    required this.displayName,
    required this.score,
    required this.certified,
  });

  final String userId;
  final String displayName;
  final int score;
  final bool certified;

  factory ExamRanking.fromJson(Map<String, dynamic> json) => ExamRanking(
    userId: '${json['user_id'] ?? ''}',
    displayName: '${json['display_name'] ?? ''}',
    score: _asInt(json['score']),
    certified: json['certified'] == true,
  );
}

/// Reads and writes `/exam/*`: the hall, the attempt lifecycle, certificates
/// and the competition leaderboard.
class ExamApi {
  const ExamApi(this._client);

  final ApiClient _client;

  /// Public page; [type] is `exam` or `competition`, null for both.
  Future<ApiPage<Exam>> exams({
    String? type,
    int page = 1,
    int limit = 20,
  }) {
    return _client.getPage(
      '/exam',
      query: {'page': page, 'limit': limit, 'type': ?type},
      parseItem: Exam.fromJson,
    );
  }

  Future<Exam> exam(String id) async {
    final json = await _client.getObject('/exam/$id');
    return Exam.fromJson(json);
  }

  /// Starts (or restarts) an attempt; certification exams that are already
  /// passed answer with a domain error and must not be retried blindly.
  Future<ExamAttempt> startAttempt(String examId) async {
    final json = await _client.post('/exam/$examId/attempts');
    if (json is! Map) throw _shape('POST', '/exam/$examId/attempts');
    return ExamAttempt.fromJson(Map<String, dynamic>.from(json));
  }

  /// [answers] maps question ids to the selected option key (`A`/`B`/…) or
  /// `T`/`F` for judge questions. Scoring happens on the service.
  Future<ExamResult> submitAttempt(
    String attemptId,
    Map<String, String> answers,
  ) async {
    final json = await _client.post(
      '/exam/attempts/$attemptId/submit',
      body: {'answers': answers},
    );
    if (json is! Map) throw _shape('POST', '/exam/attempts/$attemptId/submit');
    return ExamResult.fromJson(Map<String, dynamic>.from(json));
  }

  Future<List<ExamCertificate>> myCertificates() {
    return _client.getList(
      '/exam/certificates/mine',
      parseItem: ExamCertificate.fromJson,
    );
  }

  /// Empty for certification exams — the service only ranks `competition`.
  Future<ApiPage<ExamRanking>> leaderboard(
    String examId, {
    int page = 1,
    int limit = 20,
  }) {
    return _client.getPage(
      '/exam/$examId/leaderboard',
      query: {'page': page, 'limit': limit},
      parseItem: ExamRanking.fromJson,
    );
  }

  static ApiException _shape(String method, String path) => ApiException(
    code: ApiCode.internalError,
    message: '考试响应格式错误',
    method: method,
    path: path,
  );
}

int _asInt(Object? value, [int fallback = 0]) =>
    value is num ? value.toInt() : fallback;

DateTime? _asLocal(Object? value) {
  final raw = '${value ?? ''}';
  if (raw.isEmpty || raw == 'null') return null;
  return DateTime.tryParse(raw)?.toLocal();
}
