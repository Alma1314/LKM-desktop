/// Shared card layout IDs and migration for mobile / desktop dashboards.
class DashboardLayout {
  DashboardLayout._();

  /// Default card order for both mobile (single column) and desktop (waterfall).
  static const defaultCardLayouts = [
    'personal',
    'questions',
    'projects',
    'columns',
    'competitions',
    'leaderboard',
  ];

  /// Legacy full-height column groups → individual section cards.
  static const columnToCards = <String, List<String>>{
    'activityColumn': ['checkIn', 'fortuneGraph', 'fortuneCard'],
    'postsColumn': ['columns'],
    'socialColumn': ['friendsOverview', 'notifications'],
    'chatsColumn': ['chatList'],
  };

  /// Normalize a saved layout list: expand old column IDs, drop unactivated.
  static List<String> resolveCardLayouts(List<String>? layouts) {
    const legacyDefault = [
      'checkIn',
      'weather',
      'fortuneCard',
      'postFeatured',
      'friendsOverview',
      'notifications',
      'chatList',
      'fortuneGraph',
    ];
    final source =
        (layouts == null ||
            layouts.isEmpty ||
            layouts.join(',') == legacyDefault.join(','))
        ? defaultCardLayouts
        : layouts;
    return source
        .expand((id) => columnToCards[id] ?? <String>[id])
        .map((id) => id == 'postFeatured' ? 'columns' : id)
        .toSet()
        .where((id) => id != 'accountUnactivated')
        .toList();
  }
}
