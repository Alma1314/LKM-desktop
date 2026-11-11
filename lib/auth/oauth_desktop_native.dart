import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:url_launcher/url_launcher_string.dart';

import 'package:island/core/api/auth_api.dart';

class OAuthLoopbackException implements Exception {
  const OAuthLoopbackException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Opens the system browser for GitHub login and waits on a loopback callback.
///
/// The service redirects back with a one-time `code`; only the process holding
/// the PKCE `verifier` can exchange it for tokens, so another local listener
/// that races the port gets nothing usable.
Future<LkmAuthResult> runGithubLogin(AuthApi api) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  try {
    final verifier = _verifier();
    final redirect = 'http://127.0.0.1:${server.port}/callback';
    final launched = await launchUrlString(
      api.githubLoginUrl(
        redirectUri: redirect,
        challenge: _challenge(verifier),
      ),
      mode: LaunchMode.externalApplication,
    );
    if (!launched) {
      throw const OAuthLoopbackException('无法打开浏览器完成 GitHub 登录');
    }
    final code = await _waitForCode(server);
    return await api.exchangeDesktopCode(code: code, verifier: verifier);
  } finally {
    await server.close(force: true);
  }
}

/// Binds GitHub from the signed-in account settings. Returns true when the
/// callback reported success.
Future<bool> runGithubBind(AuthApi api) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  try {
    final redirect = 'http://127.0.0.1:${server.port}/callback';
    final verifier = _verifier();
    final url = await api.githubBindUrl(
      redirectUri: redirect,
      challenge: _challenge(verifier),
    );
    if (url.isEmpty) {
      throw const OAuthLoopbackException('服务器未返回 GitHub 授权地址');
    }
    final launched = await launchUrlString(
      url,
      mode: LaunchMode.externalApplication,
    );
    if (!launched) {
      throw const OAuthLoopbackException('无法打开浏览器完成 GitHub 绑定');
    }
    return await _waitForCode(server) == 'bound';
  } finally {
    await server.close(force: true);
  }
}

String _verifier() {
  final random = Random.secure();
  final bytes = List<int>.generate(32, (_) => random.nextInt(256));
  return base64UrlEncode(bytes).replaceAll('=', '');
}

String _challenge(String verifier) =>
    sha256.convert(utf8.encode(verifier)).toString();

/// Serves exactly one callback request, closes the browser tab, and returns
/// the `code` query parameter. The server is closed by the caller.
Future<String> _waitForCode(HttpServer server) async {
  final HttpRequest request;
  try {
    request = await server.first.timeout(const Duration(minutes: 3));
  } on Object {
    throw const OAuthLoopbackException('等待 GitHub 授权回调超时');
  }
  final uri = request.uri;
  request.response.headers.contentType = ContentType.html;
  request.response.write(
    '<html><body style="font-family:sans-serif">'
    '<p>授权已完成，可以关闭此页面并返回 LKM 桌面端。</p>'
    '</body></html>',
  );
  await request.response.close();

  final error = uri.queryParameters['error'];
  if (error != null && error.isNotEmpty) {
    throw OAuthLoopbackException(error);
  }
  final code = uri.queryParameters['code'];
  if (code == null || code.isEmpty) {
    throw const OAuthLoopbackException('GitHub 回调缺少授权码');
  }
  return code;
}
