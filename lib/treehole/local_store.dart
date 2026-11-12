import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:island/core/api/treehole_api.dart';

/// Local UI preferences and one unfinished letter, isolated by deployment.
/// Backup deliberately excludes the anonymous session cookie and credentials.
class TreeholeLocalStore {
  TreeholeLocalStore(this.prefs, String server)
    : key = 'treehole-local:$server';
  final SharedPreferences prefs;
  final String key;
  Map<String, dynamic> read() {
    try {
      return Map<String, dynamic>.from(
        jsonDecode(prefs.getString(key) ?? '{}') as Map,
      );
    } catch (_) {
      return {};
    }
  }

  Future<void> write(Map<String, dynamic> data) async {
    await prefs.setString(key, jsonEncode(data));
  }

  Future<void> patch(String field, Object? value) =>
      write({...read(), field: value});
  String export() => jsonEncode({'version': 1, ...read()});
  Future<void> import(String source) async {
    final data = jsonDecode(source);
    if (data is! Map || data['version'] != 1)
      throw const FormatException('Invalid backup');
    final result = <String, dynamic>{};
    if (data['theme'] != null) {
      if (!['system', 'light', 'dark'].contains(data['theme']))
        throw const FormatException('Invalid theme');
      result['theme'] = data['theme'];
    }
    for (final k in ['contrast', 'mute', 'limit']) {
      if (data[k] != null) {
        if (data[k] is! bool) throw const FormatException('Invalid preference');
        result[k] = data[k];
      }
    }
    if (data['scale'] != null) {
      if (data['scale'] is! num || data['scale'] < 0.8 || data['scale'] > 1.6)
        throw const FormatException('Invalid font size');
      result['scale'] = data['scale'];
    }
    if (data['draft'] != null) {
      if (data['draft'] is! Map) throw const FormatException('Invalid draft');
      final draft = Map<String, dynamic>.from(data['draft']);
      for (final k in [
        'content',
        'codename',
        'category',
        'privacy',
        'scheduled',
        'sealed',
      ]) {
        if (draft[k] != null &&
            (draft[k] is! String || (draft[k] as String).length > 1000))
          throw const FormatException('Invalid draft field');
      }
      for (final k in ['moods', 'tags']) {
        if (draft[k] != null &&
            (draft[k] is! List ||
                (draft[k] as List).length > 3 ||
                (draft[k] as List).any((e) => e is! String)))
          throw const FormatException('Invalid draft tags');
      }
      if (draft['privacy'] != null &&
          !['public', 'self', 'random'].contains(draft['privacy']))
        throw const FormatException('Invalid privacy');
      if (draft['category'] != null &&
          ![
            'confess',
            'heart',
            'roast',
            'help',
            'campus',
            'work',
            'crush',
            'heal',
            'fun',
            'insight',
          ].contains(draft['category']))
        throw const FormatException('Invalid category');
      result['draft'] = {
        for (final k in [
          'content',
          'codename',
          'category',
          'privacy',
          'scheduled',
          'sealed',
          'moods',
          'tags',
        ])
          if (draft.containsKey(k)) k: draft[k],
      };
    }
    await write(result);
  }
}

List<LkmTreeholeLetter> rankTreeholeLetters(
  List<LkmTreeholeLetter> letters,
  DateTime now,
  int days,
) {
  final cutoff = now.subtract(Duration(days: days));
  final rows = letters
      .where(
        (l) =>
            l.status == 'published' &&
            l.privacy == 'public' &&
            !l.createdAt.isBefore(cutoff) &&
            !l.createdAt.isAfter(now),
      )
      .toList();
  rows.sort((a, b) {
    final heat = (b.likes + b.favorites).compareTo(a.likes + a.favorites);
    if (heat != 0) return heat;
    final date = b.createdAt.compareTo(a.createdAt);
    return date != 0 ? date : a.id.compareTo(b.id);
  });
  return rows.take(20).toList();
}
