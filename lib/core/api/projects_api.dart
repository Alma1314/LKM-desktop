import 'api_client.dart';

class ProjectMember {
  const ProjectMember({
    required this.id,
    required this.displayName,
    required this.roleInProject,
  });

  final String id;
  final String displayName;
  final String roleInProject;

  factory ProjectMember.fromJson(Map<String, dynamic> json) {
    return ProjectMember(
      id: '${json['id'] ?? ''}',
      displayName: '${json['display_name'] ?? ''}',
      roleInProject: '${json['role_in_project'] ?? ''}',
    );
  }
}

class ProjectReport {
  const ProjectReport({
    required this.title,
    required this.content,
    required this.revision,
    required this.date,
  });

  final String title;
  final String content;
  final int revision;
  final String date;

  factory ProjectReport.fromJson(Map<String, dynamic> json) {
    return ProjectReport(
      title: '${json['title'] ?? ''}',
      content: '${json['content'] ?? ''}',
      revision: json['revision'] is num ? (json['revision'] as num).toInt() : 0,
      date: '${json['date'] ?? ''}',
    );
  }
}

/// One row of `/projects` (the project hall). Unlike the GraphQL projection
/// this carries the showcase fields (goals, progress, reports, members).
class ProjectSummary {
  const ProjectSummary({
    required this.id,
    required this.title,
    required this.summary,
    required this.description,
    required this.applicantName,
    required this.isIncubated,
    required this.isRecruiting,
    required this.isPinned,
    required this.progress,
    required this.recruitingRoles,
    required this.tags,
    required this.reports,
    required this.members,
    required this.status,
    this.background,
    this.goals,
    this.requirements,
    this.teamIntro,
    this.applicantId,
  });

  final String id;
  final String? applicantId;
  final String title;
  final String summary;
  final String description;
  final String applicantName;
  final bool isIncubated;
  final bool isRecruiting;
  final bool isPinned;
  final int progress;
  final List<String> recruitingRoles;
  final List<String> tags;
  final List<ProjectReport> reports;
  final List<ProjectMember> members;
  final String status;
  final String? background;
  final String? goals;
  final String? requirements;
  final String? teamIntro;

  factory ProjectSummary.fromJson(Map<String, dynamic> json) {
    final roles = json['recruiting_roles'];
    final tags = json['tags'];
    final reports = json['reports'];
    final members = json['members'];
    return ProjectSummary(
      id: '${json['id'] ?? ''}',
      applicantId: json['applicant_id'] as String?,
      title: '${json['title'] ?? ''}',
      summary: '${json['summary'] ?? ''}',
      description: '${json['description'] ?? ''}',
      applicantName: '${json['applicant_name'] ?? ''}',
      isIncubated: json['is_incubated'] == true,
      isRecruiting: json['is_recruiting'] == true,
      isPinned: json['is_pinned'] == true,
      progress: json['progress'] is num ? (json['progress'] as num).toInt() : 0,
      recruitingRoles: roles is List
          ? roles.whereType<String>().toList(growable: false)
          : const [],
      tags: tags is List
          ? tags.whereType<String>().toList(growable: false)
          : const [],
      reports: reports is List
          ? reports
                .whereType<Map>()
                .map(
                  (e) => ProjectReport.fromJson(Map<String, dynamic>.from(e)),
                )
                .toList(growable: false)
          : const [],
      members: members is List
          ? members
                .whereType<Map>()
                .map(
                  (e) => ProjectMember.fromJson(Map<String, dynamic>.from(e)),
                )
                .toList(growable: false)
          : const [],
      status: '${json['status'] ?? ''}',
      background: json['background'] as String?,
      goals: json['goals'] as String?,
      requirements: json['requirements'] as String?,
      teamIntro: json['team_intro'] as String?,
    );
  }
}

class ProjectApplication {
  const ProjectApplication({
    required this.id,
    required this.title,
    required this.summary,
    required this.status,
    this.reviewNote,
    this.reviewedAt,
    this.createdAt,
  });

  final String id;
  final String title;
  final String summary;
  final String status;
  final String? reviewNote;
  final DateTime? reviewedAt;
  final DateTime? createdAt;

  factory ProjectApplication.fromJson(Map<String, dynamic> json) {
    return ProjectApplication(
      id: '${json['id'] ?? ''}',
      title: '${json['title'] ?? ''}',
      summary: '${json['summary'] ?? ''}',
      status: '${json['status'] ?? ''}',
      reviewNote: json['review_note'] as String?,
      reviewedAt: DateTime.tryParse('${json['reviewed_at'] ?? ''}')?.toLocal(),
      createdAt: DateTime.tryParse('${json['created_at'] ?? ''}')?.toLocal(),
    );
  }
}

/// `/projects/*`: read the hall and submit an incubation application.
class ProjectsApi {
  const ProjectsApi(this._client);

  final ApiClient _client;

  Future<List<ProjectSummary>> projects() {
    return _client.getList('/projects', parseItem: ProjectSummary.fromJson);
  }

  Future<ProjectSummary> project(String id) async {
    final json = await _client.getObject('/projects/$id');
    return ProjectSummary.fromJson(json);
  }

  Future<List<ProjectApplication>> myApplications() {
    return _client.getList(
      '/projects/applications/me',
      parseItem: ProjectApplication.fromJson,
    );
  }

  Future<void> apply({
    required String title,
    required String summary,
    required String description,
    List<Map<String, String>> memberClaims = const [],
  }) async {
    await _client.post(
      '/projects/applications',
      body: {
        'title': title,
        'summary': summary,
        'description': description,
        if (memberClaims.isNotEmpty) 'member_claims': memberClaims,
      },
    );
  }
}
