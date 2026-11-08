import 'dart:async';
import 'dart:io';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:island/core/services/event_bus.dart';
import 'package:protocol_handler/protocol_handler.dart';
import 'package:url_launcher/url_launcher_string.dart';

class DeeplinkService {
  static final DeeplinkService _instance = DeeplinkService._internal();
  factory DeeplinkService() => _instance;
  DeeplinkService._internal();

  StreamSubscription<LkmDeepLinkEvent>? _lkmDeepLinkSub;
  ProtocolListener? _protocolListener;
  static const MethodChannel _nativeChannel = MethodChannel(
    'ltd.lkmahz.desktop/deeplink',
  );
  void Function(Uri uri)? _onDeepLink;

  void initialize({required void Function(Uri uri) onDeepLink}) {
    _onDeepLink = onDeepLink;

    _lkmDeepLinkSub?.cancel();
    _lkmDeepLinkSub = eventBus.on<LkmDeepLinkEvent>().listen((event) {
      _onDeepLink?.call(event.uri);
    });

    if (!kIsWeb && (Platform.isIOS || Platform.isMacOS)) {
      _nativeChannel.setMethodCallHandler((call) async {
        if (call.method != 'onDeepLink') return;
        final rawUrl =
            await _nativeChannel.invokeMethod<String>(
              'consumePendingDeepLink',
            ) ??
            call.arguments?.toString();
        final uri = rawUrl == null ? null : Uri.tryParse(rawUrl);
        if (uri != null) _onDeepLink?.call(uri);
      });

      _nativeChannel.invokeMethod<String>('consumePendingDeepLink').then((
        initialUrl,
      ) {
        if (initialUrl == null) return;
        final uri = Uri.tryParse(initialUrl);
        if (uri != null) _onDeepLink?.call(uri);
      });
    }

    if (!kIsWeb &&
        (Platform.isLinux || Platform.isMacOS || Platform.isWindows)) {
      if (_protocolListener != null) {
        protocolHandler.removeListener(_protocolListener!);
      }
      _protocolListener = _ProtocolListener(
        onProtocolUrlReceived: (url) {
          final uri = Uri.tryParse(url);
          if (uri != null) _onDeepLink?.call(uri);
        },
      );
      protocolHandler.addListener(_protocolListener!);

      protocolHandler.getInitialUrl().then((initialUrl) {
        if (initialUrl == null) return;
        final uri = Uri.tryParse(initialUrl);
        if (uri != null) _onDeepLink?.call(uri);
      });
    }
  }

  void dispose() {
    _lkmDeepLinkSub?.cancel();
    _lkmDeepLinkSub = null;
    _onDeepLink = null;

    if (!kIsWeb && (Platform.isIOS || Platform.isMacOS)) {
      _nativeChannel.setMethodCallHandler(null);
    }

    if (!kIsWeb &&
        (Platform.isLinux || Platform.isMacOS || Platform.isWindows) &&
        _protocolListener != null) {
      protocolHandler.removeListener(_protocolListener!);
      _protocolListener = null;
    }
  }
}

String? parseWalletTransferRequestId(String rawValue) {
  final value = rawValue.trim();
  if (value.isEmpty) return null;

  final uri = Uri.tryParse(value);
  if (uri == null) return null;

  final segments = uri.pathSegments;
  final isWalletTransferRequest =
      uri.scheme == 'lkm' &&
      uri.host == 'wallet' &&
      segments.length == 3 &&
      segments[0] == 'transfer' &&
      segments[1] == 'requests';
  final isWebWalletTransferRequest =
      (uri.host == 'lkm-ahz.ltd' || uri.host.endsWith('.lkm-ahz.ltd')) &&
      segments.length >= 3 &&
      segments[0] == 'wallet' &&
      segments[1] == 'transfer' &&
      segments[2] == 'requests';

  if (isWalletTransferRequest) {
    final id = segments[2].trim();
    return id.isEmpty ? null : id;
  }

  if (isWebWalletTransferRequest && segments.length >= 4) {
    final id = segments[3].trim();
    return id.isEmpty ? null : id;
  }

  return null;
}

String? parseAuthQrChallengeId(String rawValue) {
  final value = rawValue.trim();
  if (value.isEmpty) return null;

  final uri = Uri.tryParse(value);
  if (uri == null) return null;

  final segments = uri.pathSegments;
  final isLkmQrLogin =
      uri.scheme == 'lkm' &&
      uri.host == 'auth' &&
      segments.length == 2 &&
      segments[0] == 'qr';
  final isWebQrLogin =
      (uri.host == 'lkm-ahz.ltd' || uri.host.endsWith('.lkm-ahz.ltd')) &&
      segments.length >= 3 &&
      segments[0] == 'auth' &&
      segments[1] == 'qr';

  if (isLkmQrLogin) {
    final id = segments[1].trim();
    return id.isEmpty ? null : id;
  }

  if (isWebQrLogin) {
    final id = segments[2].trim();
    return id.isEmpty ? null : id;
  }

  return null;
}

String? parseWalletOrderId(String rawValue) {
  final value = rawValue.trim();
  if (value.isEmpty) return null;

  final uri = Uri.tryParse(value);
  if (uri == null) return null;

  final segments = uri.pathSegments;
  final isLkmOrder =
      uri.scheme == 'lkm' &&
      (uri.host == 'orders' || uri.host == 'order') &&
      segments.length == 1;
  final isWebOrder =
      (uri.host == 'lkm-ahz.ltd' || uri.host.endsWith('.lkm-ahz.ltd')) &&
      segments.length >= 2 &&
      segments[0] == 'orders';

  if (isLkmOrder) {
    final id = segments[0].trim();
    return id.isEmpty ? null : id;
  }

  if (isWebOrder) {
    final id = segments[1].trim();
    return id.isEmpty ? null : id;
  }

  return null;
}

class PhysicalPassportDeepLink {
  final String? tagId;
  final Map<String, String>? queryParameters;

  const PhysicalPassportDeepLink({this.tagId, this.queryParameters});

  bool get isPathBased => tagId != null;
  bool get isQueryBased =>
      queryParameters != null && queryParameters!.isNotEmpty;
}

PhysicalPassportDeepLink? parsePhysicalPassportDeepLink(String rawValue) {
  final value = rawValue.trim();
  if (value.isEmpty) return null;

  final uri = Uri.tryParse(value);
  if (uri == null) return null;

  final isLkmPhpass = uri.scheme == 'lkm' && uri.host == 'phpass';
  final isWebPhpass =
      (uri.host == 'lkm-ahz.ltd' || uri.host.endsWith('.lkm-ahz.ltd')) &&
      uri.pathSegments.isNotEmpty &&
      uri.pathSegments[0] == 'phpass';

  if (isLkmPhpass) {
    if (uri.pathSegments.isNotEmpty) {
      final tagId = uri.pathSegments.first.trim();
      if (tagId.isNotEmpty) {
        return PhysicalPassportDeepLink(tagId: tagId);
      }
    }
    if (uri.queryParameters.isNotEmpty) {
      return PhysicalPassportDeepLink(queryParameters: uri.queryParameters);
    }
  }

  if (isWebPhpass) {
    if (uri.pathSegments.length >= 2) {
      final tagId = uri.pathSegments[1].trim();
      if (tagId.isNotEmpty) {
        return PhysicalPassportDeepLink(tagId: tagId);
      }
    }
    if (uri.queryParameters.isNotEmpty) {
      return PhysicalPassportDeepLink(queryParameters: uri.queryParameters);
    }
  }

  return null;
}

class _ProtocolListener implements ProtocolListener {
  final void Function(String) _onProtocolUrlReceived;

  _ProtocolListener({required void Function(String) onProtocolUrlReceived})
    : _onProtocolUrlReceived = onProtocolUrlReceived;

  @override
  void onProtocolUrlReceived(String url) => _onProtocolUrlReceived(url);
}

/// True when [uri] points at the LKM web app itself — its routes map 1:1
/// onto in-app routes. Subdomains (api., nt., fs., …) serve other apps and
/// are NOT in-app routes.
bool isLkmWebUri(Uri uri) =>
    (uri.scheme == 'http' || uri.scheme == 'https') && uri.host == 'lkm-ahz.ltd';

/// Converts a LKM link — either the `lkm://host/path` custom scheme or
/// the web app URL `https://lkm-ahz.ltd/path` — into the matching in-app route
/// path (`/host/path` and `/path` respectively). Returns null when [uri] is
/// not a LKM link.
String? lkmLinkToRoutePath(Uri uri) {
  String path;
  if (uri.scheme == 'lkm') {
    path = '/${uri.host}${uri.path}';
  } else if (isLkmWebUri(uri)) {
    path = uri.path.isEmpty ? '/' : uri.path;
    if (!path.startsWith('/')) path = '/$path';
  } else {
    return null;
  }
  // Normalize trailing slashes so `https://lkm-ahz.ltd/orders/123/` matches
  // the `/orders/:id` route instead of the 404 catch-all.
  if (path.length > 1 && path.endsWith('/')) {
    path = path.substring(0, path.length - 1);
  }
  // `lkm:///posts/123` (empty authority) yields `//posts/123` — collapse
  // it to a regular in-app path.
  if (path.startsWith('//')) {
    path = path.substring(1);
  }
  return path;
}

/// Normalizes a raw action URI to an in-app route path. Handles
/// `lkm://…`, `https://lkm-ahz.ltd/…` and bare `/…` paths. Returns null
/// when the value should be opened externally instead.
String? actionUriToRoutePath(String rawValue) {
  final value = rawValue.trim();
  if (value.startsWith('/')) return value;
  final uri = Uri.tryParse(value);
  if (uri == null) return null;
  return lkmLinkToRoutePath(uri);
}

/// The `https://lkm-ahz.ltd/…` web URL equivalent of a LKM link, for
/// opening in the browser when the app doesn't implement the route in-app.
/// Returns [uri] itself for `https://lkm-ahz.ltd/…` links and null for
/// anything else.
Uri? lkmLinkWebUrl(Uri uri) {
  if (isLkmWebUri(uri)) return uri;
  if (uri.scheme != 'lkm') return null;
  final path = uri.path.isEmpty ? '' : uri.path;
  final webUrl = Uri.https('lkm-ahz.ltd', '${uri.host}$path');
  return uri.queryParameters.isEmpty
      ? webUrl
      : webUrl.replace(queryParameters: uri.queryParameters);
}

/// Returns a LKM web URL on a host that is not claimed by the Android app.
///
/// Android app links can route `lkm-ahz.ltd` back into this app even when the
/// caller explicitly requests an external application. Use this URL when a
/// LKM route is not implemented in-app and must be opened in a browser.
Uri? lkmLinkBrowserUrl(Uri uri) {
  final webUrl = lkmLinkWebUrl(uri);
  return webUrl?.replace(host: 'www.lkm-ahz.ltd');
}

/// True when [path] resolves to a concrete route in [router]'s tree — i.e.
/// anything other than the 404 catch-all. Use to guard `navigatePath` so
/// LKM links to pages the app doesn't implement fall back to the browser
/// instead of landing on the in-app 404 page.
///
/// Must be called with the root router: nested routers only match their own
/// sub-collection and would report unknown paths for routes outside the tab.
bool isKnownInAppRoutePath(StackRouter router, String path) {
  final matches = router.matcher.match(path, includePrefixMatches: false);
  if (matches == null || matches.isEmpty) return false;
  return matches.every((m) => m.path != '*');
}

/// Navigates to [path] in-app when it maps to a concrete route; returns false
/// when the page isn't implemented in-app so callers can fall back (typically
/// opening the web URL in the browser) instead of showing the 404 page.
bool tryNavigateToRoutePath(StackRouter router, String path) {
  if (!isKnownInAppRoutePath(router, path)) return false;
  router.navigatePath(path);
  return true;
}

/// Handles an action URI consistently across notifications and deep links.
///
/// Concrete in-app routes are navigated in-app. Unknown LKM routes are
/// opened on the web; Android uses `www.lkm-ahz.ltd` to avoid re-entering the
/// app through its verified app link. Other external URLs are passed through
/// unchanged.
Future<bool> handleActionUri(StackRouter router, String rawValue) async {
  final routePath = actionUriToRoutePath(rawValue);
  if (routePath != null && tryNavigateToRoutePath(router, routePath)) {
    return true;
  }

  final uri = rawValue.trim().startsWith('/')
      ? Uri.tryParse('https://lkm-ahz.ltd${rawValue.trim()}')
      : Uri.tryParse(rawValue.trim());
  if (uri == null) return false;

  final lkmWebUrl = lkmLinkWebUrl(uri);
  final launchUri = !kIsWeb && Platform.isAndroid && lkmWebUrl != null
      ? lkmLinkBrowserUrl(uri)
      : lkmWebUrl ?? uri;
  if (launchUri == null) return false;

  return launchUrlString(
    launchUri.toString(),
    mode: LaunchMode.externalApplication,
  );
}

/// The web URL of a shareable chat room: `https://lkm-ahz.ltd/chat/<scope>/<slug>`
/// where [scope] is the owner account name or the realm slug.
Uri buildChatRoomShareUrl({required String scope, required String slug}) =>
    Uri.https('lkm-ahz.ltd', 'chat/$scope/$slug');

class ChatRoomShareLink {
  final String scope;
  final String slug;

  const ChatRoomShareLink({required this.scope, required this.slug});
}

/// The path segments of a LKM link, however it arrives: the web app URL
/// (`https://lkm-ahz.ltd/...`, `www.lkm-ahz.ltd`) or the `lkm://host/...`
/// custom scheme, whose authority becomes the first segment. Returns null when
/// [uri] is not a LKM link at all.
///
/// Subdomains are deliberately left out: `api.`, `nt.` and `fs.lkm-ahz.ltd`
/// serve other apps, not the routes these segments are read for.
List<String>? lkmLinkPathSegments(Uri uri) {
  if (uri.scheme == 'lkm') {
    // `lkm://chat/room/slug` puts `chat` in the authority, so the path is
    // the authority and the path glued together. `lkm:///posts/<id>` (empty
    // authority) yields `//posts/<id>`, which would parse as a *host* — collapse
    // it the way [lkmLinkToRoutePath] does.
    var path = '/${uri.host}${uri.path}';
    if (path.startsWith('//')) path = path.substring(1);
    return Uri.parse(path).pathSegments.where((s) => s.isNotEmpty).toList();
  }
  if ((uri.scheme == 'http' || uri.scheme == 'https') &&
      (uri.host == 'lkm-ahz.ltd' || uri.host == 'www.lkm-ahz.ltd')) {
    return uri.pathSegments.where((s) => s.isNotEmpty).toList();
  }
  return null;
}

/// The post id in a LKM post link — `https://lkm-ahz.ltd/posts/<id>` or
/// `lkm://posts/<id>`. Returns null for anything else, or for an empty id.
String? parsePostLinkId(Uri uri) {
  final segments = lkmLinkPathSegments(uri);
  if (segments == null || segments.length < 2 || segments.first != 'posts') {
    return null;
  }
  final id = segments[1].trim();
  return id.isEmpty ? null : id;
}

/// Parses a chat room share link produced by [buildChatRoomShareUrl].
/// Accepts the web URL, the `lkm://chat/...` custom scheme and bare
/// `/chat/<scope>/<slug>` paths. Returns null for anything else.
ChatRoomShareLink? parseChatRoomShareLink(String rawValue) {
  final value = rawValue.trim();
  final uri = value.startsWith('/')
      ? Uri.tryParse('https://lkm-ahz.ltd$value')
      : Uri.tryParse(value);
  if (uri == null) return null;

  final segments = lkmLinkPathSegments(uri);
  if (segments == null || segments.length != 3 || segments.first != 'chat') {
    return null;
  }
  final scope = segments[1].trim();
  final slug = segments[2].trim();
  if (scope.isEmpty || slug.isEmpty) return null;
  return ChatRoomShareLink(scope: scope, slug: slug);
}

