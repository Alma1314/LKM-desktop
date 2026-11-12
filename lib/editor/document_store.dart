import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Like the website version-store: local snapshots, scoped to deployment/account.
/// The service exposes current content only, so these are not Git history.
class DocumentStore {
  DocumentStore(this.prefs, String server, String user)
    : key = 'editor:${Uri.encodeComponent(server)}:$user';
  final SharedPreferences prefs;
  final String key;

  List<Map<String, dynamic>> documents() {
    final raw = prefs.getString(key);
    if (raw == null) return [];
    return (jsonDecode(raw) as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  Future<void> save(
    Map<String, dynamic> document, {
    bool snapshot = false,
  }) async {
    final docs = documents();
    final index = docs.indexWhere((d) => d['id'] == document['id']);
    final previous = index < 0 ? <String, dynamic>{} : docs.removeAt(index);
    final history = List<Map<String, dynamic>>.from(
      (previous['history'] as List? ?? []).map(
        (e) => Map<String, dynamic>.from(e as Map),
      ),
    );
    if (snapshot &&
        (history.isEmpty ||
            history.first['content'] != document['content'] ||
            history.first['title'] != document['title'])) {
      history.insert(0, {
        'content': document['content'],
        'title': document['title'],
        'time': DateTime.now().toIso8601String(),
      });
      // ponytail: retain the latest 50 local snapshots, use a DB for larger archives.
      if (history.length > 50) history.removeRange(50, history.length);
    }
    docs.insert(0, {...document, 'history': history});
    if (!await prefs.setString(key, jsonEncode(docs))) {
      throw StateError('Could not save document');
    }
  }
}
