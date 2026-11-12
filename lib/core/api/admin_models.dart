/// Projections of the service's admin contracts; no write-only/secret fields.
class AdminUser {
  AdminUser.fromJson(Map<String, dynamic> json)
    : id = json['id'] as String,
      username = json['username'] as String,
      level = json['account_level'] as String,
      locked = json['is_locked'] == true,
      createdAt = DateTime.parse(json['created_at'] as String),
      email = json['email'] as String?,
      phone = json['phone'] as String?;

  final String id, username, level;
  final bool locked;
  final DateTime createdAt;
  final String? email, phone;
}

class AdmissionUser {
  AdmissionUser.fromJson(Map<String, dynamic> json)
    : id = json['user_id'] as String,
      username = json['username'] as String,
      status = json['admission_status'] as String,
      email = json['email'] as String?,
      reason = json['apply_reason'] as String?,
      rejectedReason = json['reject_reason'] as String?,
      appliedAt = DateTime.tryParse('${json['applied_at'] ?? ''}');

  final String id, username, status;
  final String? email, reason, rejectedReason;
  final DateTime? appliedAt;
}

class AdminStats {
  AdminStats.fromJson(Map<String, dynamic> json)
    : users = (json['user_count'] as num).toInt(),
      posts = (json['post_count'] as num).toInt(),
      files = (json['file_count'] as num).toInt(),
      pendingFiles = (json['file_pending_count'] as num).toInt();
  final int users, posts, files, pendingFiles;
}

class AdminTrend {
  AdminTrend.fromJson(Map<String, dynamic> json)
    : date = json['date'] as String,
      users = (json['user_delta'] as num).toInt(),
      posts = (json['post_delta'] as num).toInt();
  final String date;
  final int users, posts;
}

class AdminReviewQueue {
  AdminReviewQueue.fromJson(Map<String, dynamic> json)
    : key = json['key'] as String,
      count = (json['count'] as num).toInt(),
      waitingSeconds = (json['oldest_waiting_seconds'] as num?)?.toInt();
  final String key;
  final int count;
  final int? waitingSeconds;
}

class AdminReviewSummary {
  AdminReviewSummary.fromJson(Map<String, dynamic> json)
    : total = (json['total_pending'] as num).toInt(),
      queues = (json['queues'] as List)
          .map((e) => AdminReviewQueue.fromJson(Map<String, dynamic>.from(e)))
          .toList();
  final int total;
  final List<AdminReviewQueue> queues;
}

/// The BFF intentionally returns unavailable/unconfigured as successful data.
/// Keep those states distinct from an available but empty list.
class AdminBotData {
  AdminBotData.fromJson(Map<String, dynamic> json)
    : configured = json['configured'] == true,
      available = json['available'] == true,
      reason = json['reason'] as String?,
      values = Map.unmodifiable(json),
      items = ((json['items'] ?? json['logs'] ?? []) as List)
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
  final bool configured, available;
  final String? reason;
  final Map<String, dynamic> values;
  final List<Map<String, dynamic>> items;
}

/// Only the configured deployment receives a one-use SSO ticket. Never persist
/// this URL or accept a redirect origin from a response.
Uri adminBotPanelUri(String serverUrl, String ticket, String route) {
  const routes = {
    '/',
    '/platforms',
    '/providers',
    '/config',
    '/plugins',
    '/knowledge-base',
    '/data/logs',
    '/settings',
  };
  final server = Uri.parse(serverUrl);
  if (!{'http', 'https'}.contains(server.scheme) ||
      server.host.isEmpty ||
      server.userInfo.isNotEmpty ||
      ticket.trim().isEmpty ||
      !routes.contains(route)) {
    throw ArgumentError('Invalid Bot panel destination');
  }
  return Uri.parse(server.origin).replace(
    path: '/bot/api/v1/auth/sso',
    queryParameters: {'ticket': ticket, 'next': route},
  );
}
