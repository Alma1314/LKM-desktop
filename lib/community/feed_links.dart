/// Resolves a server-provided link into something a launcher may open.
///
/// Links come from the service, so only `http(s)` and site-relative paths are
/// accepted — a `javascript:`/`data:` URI must never reach the launcher (nor,
/// later, a WebView).
String? resolveFeedUrl(String? url, String? serverHost) {
  final raw = url?.trim();
  if (raw == null || raw.isEmpty) return null;
  if (raw.startsWith('/')) {
    if (serverHost == null || serverHost.isEmpty) return null;
    return '$serverHost$raw';
  }
  if (RegExp('^https?://', caseSensitive: false).hasMatch(raw)) return raw;
  return null;
}

enum FeedRouteKind { content, qa, project, file, treehole }

class FeedRouteTarget {
  const FeedRouteTarget(this.kind, this.id);

  final FeedRouteKind kind;
  final String id;
}

/// Maps a site-relative service link onto a native desktop route.
///
/// Notification payloads carry the website's paths (`/content/posts/{id}`,
/// `/qa/{id}`, …); anything external or unrecognised returns null so callers
/// keep the old behaviour of opening it in the browser.
FeedRouteTarget? parseFeedRoute(String? url) {
  final raw = url?.trim();
  if (raw == null || raw.isEmpty || !raw.startsWith('/')) return null;
  final path = raw.split('#').first.split('?').first;
  final segments = path.split('/').where((s) => s.isNotEmpty).toList();
  if (segments.isEmpty) return null;

  String? idOf(List<String> prefix) {
    if (segments.length != prefix.length + 1) return null;
    for (var i = 0; i < prefix.length; i++) {
      if (segments[i] != prefix[i]) return null;
    }
    return segments.last;
  }

  final contentId =
      idOf(const ['content', 'posts']) ?? idOf(const ['forum', 'post']);
  if (contentId != null) return FeedRouteTarget(FeedRouteKind.content, contentId);
  final qaId = idOf(const ['qa']);
  if (qaId != null) return FeedRouteTarget(FeedRouteKind.qa, qaId);
  final projectId = idOf(const ['projects']);
  if (projectId != null) {
    return FeedRouteTarget(FeedRouteKind.project, projectId);
  }
  final fileId =
      idOf(const ['files']) ?? idOf(const ['library', 'files']);
  if (fileId != null) return FeedRouteTarget(FeedRouteKind.file, fileId);
  if (segments.first == 'treehole') {
    return const FeedRouteTarget(FeedRouteKind.treehole, '');
  }
  return null;
}
