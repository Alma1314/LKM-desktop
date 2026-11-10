import 'api_client.dart';

int _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? 0;
  return 0;
}

bool _asBool(Object? value) => value == true;

class LkmPointsBalance {
  const LkmPointsBalance({required this.userId, required this.balance});

  final String userId;
  final int balance;

  factory LkmPointsBalance.fromJson(Map<String, dynamic> json) =>
      LkmPointsBalance(
        userId: '${json['user_id'] ?? ''}',
        balance: _asInt(json['balance']),
      );
}

class LkmPointsLedgerEntry {
  const LkmPointsLedgerEntry({
    required this.id,
    required this.delta,
    required this.balanceAfter,
    required this.reason,
    required this.refType,
    required this.refId,
    required this.createdAt,
  });

  final String id;
  final int delta;
  final int balanceAfter;

  /// Stable server key (`checkin`, `transfer_out`, ...); the UI maps it to a
  /// localized label and falls back to the raw key for unknown values.
  final String reason;
  final String refType;
  final String refId;
  final DateTime createdAt;

  factory LkmPointsLedgerEntry.fromJson(Map<String, dynamic> json) {
    final parsed = DateTime.tryParse('${json['created_at'] ?? ''}');
    return LkmPointsLedgerEntry(
      id: '${json['id'] ?? ''}',
      delta: _asInt(json['delta']),
      balanceAfter: _asInt(json['balance_after']),
      reason: '${json['reason'] ?? ''}',
      refType: '${json['ref_type'] ?? ''}',
      refId: '${json['ref_id'] ?? ''}',
      createdAt: (parsed ?? DateTime.fromMillisecondsSinceEpoch(0)).toLocal(),
    );
  }
}

class LkmPointsLeaderboardEntry {
  const LkmPointsLeaderboardEntry({
    required this.userId,
    required this.displayName,
    required this.balance,
    required this.title,
  });

  final String userId;
  final String displayName;
  final int balance;

  /// Title key suffix (`active`, `hardcore`, ...) — see
  /// `contributionData.leaderboard.titles.*`.
  final String title;

  factory LkmPointsLeaderboardEntry.fromJson(Map<String, dynamic> json) =>
      LkmPointsLeaderboardEntry(
        userId: '${json['user_id'] ?? ''}',
        displayName: '${json['display_name'] ?? ''}',
        balance: _asInt(json['balance']),
        title: '${json['title'] ?? ''}',
      );
}

class LkmPointsAchievement {
  const LkmPointsAchievement({
    required this.id,
    required this.key,
    required this.category,
    required this.icon,
    required this.nameKey,
    required this.descKey,
    required this.type,
    required this.threshold,
    required this.rewardPoints,
    required this.progress,
    required this.unlocked,
  });

  final String id;
  final String key;
  final String category;

  /// Iconify/Tabler name (`tabler:star`); the UI maps it to a Material symbol.
  final String icon;
  final String nameKey;
  final String descKey;
  final String type;
  final int threshold;
  final int rewardPoints;
  final int progress;
  final bool unlocked;

  double get progressRatio => threshold > 0
      ? (progress / threshold).clamp(0.0, 1.0)
      : 0.0;

  factory LkmPointsAchievement.fromJson(Map<String, dynamic> json) =>
      LkmPointsAchievement(
        id: '${json['id'] ?? ''}',
        key: '${json['key'] ?? ''}',
        category: '${json['category'] ?? ''}',
        icon: '${json['icon'] ?? ''}',
        nameKey: '${json['name_key'] ?? ''}',
        descKey: '${json['desc_key'] ?? ''}',
        type: '${json['type'] ?? ''}',
        threshold: _asInt(json['threshold']),
        rewardPoints: _asInt(json['reward_points']),
        progress: _asInt(json['progress']),
        unlocked: _asBool(json['unlocked']),
      );
}

class LkmPointsTask {
  const LkmPointsTask({
    required this.id,
    required this.key,
    required this.titleKey,
    required this.descKey,
    required this.category,
    required this.requirementCount,
    required this.rewardPoints,
    required this.currentProgress,
    required this.completed,
  });

  final String id;
  final String key;
  final String titleKey;
  final String descKey;
  final String category;
  final int requirementCount;
  final int rewardPoints;
  final int currentProgress;
  final bool completed;

  double get progressRatio => requirementCount > 0
      ? (currentProgress / requirementCount).clamp(0.0, 1.0)
      : 0.0;

  factory LkmPointsTask.fromJson(Map<String, dynamic> json) => LkmPointsTask(
    id: '${json['id'] ?? ''}',
    key: '${json['key'] ?? ''}',
    titleKey: '${json['title_key'] ?? ''}',
    descKey: '${json['desc_key'] ?? ''}',
    category: '${json['category'] ?? ''}',
    requirementCount: _asInt(json['requirement_count']),
    rewardPoints: _asInt(json['reward_points']),
    currentProgress: _asInt(json['current_progress']),
    completed: _asBool(json['completed']),
  );
}

class LkmPointsExchangeItem {
  const LkmPointsExchangeItem({
    required this.id,
    required this.key,
    required this.nameKey,
    required this.descKey,
    required this.pointsCost,
    required this.stock,
    required this.isVirtual,
  });

  final String id;
  final String key;
  final String nameKey;
  final String descKey;
  final int pointsCost;

  /// `-1` means unlimited, `0` means sold out.
  final int stock;
  final bool isVirtual;

  bool get soldOut => stock == 0;
  bool get lowStock => stock > 0 && stock < 20;

  factory LkmPointsExchangeItem.fromJson(Map<String, dynamic> json) =>
      LkmPointsExchangeItem(
        id: '${json['id'] ?? ''}',
        key: '${json['key'] ?? ''}',
        nameKey: '${json['name_key'] ?? ''}',
        descKey: '${json['desc_key'] ?? ''}',
        pointsCost: _asInt(json['points_cost']),
        stock: _asInt(json['stock']),
        isVirtual: _asBool(json['is_virtual']),
      );
}

class LkmPointsCheckin {
  const LkmPointsCheckin({
    required this.success,
    required this.earned,
    required this.checkinStreak,
    required this.todayChecked,
  });

  final bool success;
  final int earned;
  final int checkinStreak;
  final bool todayChecked;

  factory LkmPointsCheckin.fromJson(Map<String, dynamic> json) =>
      LkmPointsCheckin(
        success: _asBool(json['success']),
        earned: _asInt(json['earned']),
        checkinStreak: _asInt(json['checkin_streak']),
        todayChecked: _asBool(json['today_checked']),
      );
}

/// Read surface for `/api/v1/points` (balance, ledger, leaderboard,
/// achievements, tasks, exchange items, daily check-in).
///
/// The exchange list is read-only: the service exposes no redemption endpoint
/// yet, so the desktop UI points users at the website instead of faking a
/// purchase.
class PointsApi {
  const PointsApi(this._client);

  final ApiClient _client;

  Future<LkmPointsBalance> balance() async {
    final data = await _client.getObject('/points/me');
    return LkmPointsBalance.fromJson(data);
  }

  Future<ApiPage<LkmPointsLedgerEntry>> ledger({
    int page = 1,
    int limit = 20,
  }) => _client.getPage(
    '/points/me/ledger',
    query: {'page': page, 'limit': limit},
    parseItem: LkmPointsLedgerEntry.fromJson,
  );

  Future<LkmPointsCheckin> checkin() async {
    final data = await _client.post('/points/checkin');
    if (data is! Map) {
      throw const ApiException(
        code: ApiCode.invalidInput,
        message: '打卡响应格式异常',
        method: 'POST',
        path: '/points/checkin',
      );
    }
    return LkmPointsCheckin.fromJson(Map<String, dynamic>.from(data));
  }

  /// [period] is `total` / `daily` / `weekly`.
  Future<ApiPage<LkmPointsLeaderboardEntry>> leaderboard({
    String period = 'total',
    int limit = 50,
  }) => _client.getPage(
    '/points/leaderboard',
    query: {'period': period, 'limit': limit},
    parseItem: LkmPointsLeaderboardEntry.fromJson,
  );

  Future<List<LkmPointsAchievement>> achievements() => _client.getList(
    '/points/achievements',
    parseItem: LkmPointsAchievement.fromJson,
  );

  Future<List<LkmPointsTask>> tasks() =>
      _client.getList('/points/tasks', parseItem: LkmPointsTask.fromJson);

  Future<List<LkmPointsExchangeItem>> exchangeItems() => _client.getList(
    '/points/exchange-items',
    parseItem: LkmPointsExchangeItem.fromJson,
  );
}
