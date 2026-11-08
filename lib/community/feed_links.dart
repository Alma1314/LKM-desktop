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
