import 'dart:async';
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
    final code = await waitForOAuthCode(server);
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
    return await waitForOAuthCode(server) == 'bound';
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

/// Ignores unrelated requests (e.g. favicon) without extending the deadline.
Future<String> waitForOAuthCode(HttpServer server) async {
  final requests = StreamIterator(server);
  final deadline = DateTime.now().add(const Duration(minutes: 3));
  try {
    while (await requests.moveNext().timeout(
      deadline.difference(DateTime.now()),
    )) {
      final request = requests.current;
      final uri = request.uri;
      if (request.method != 'GET' ||
          uri.path != '/callback' ||
          (!uri.queryParameters.containsKey('code') &&
              !uri.queryParameters.containsKey('error'))) {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
        continue;
      }
      request.response.headers.contentType = ContentType.html;
      final error = uri.queryParameters['error'];
      final code = uri.queryParameters['code'];
      request.response.write(
        '<html><body style="font-family:sans-serif"><p>'
        '${error == null && code != null && code.isNotEmpty ? '授权已完成，可以返回 LKM 桌面端。' : '授权失败，请返回 LKM 桌面端重试。'}'
        '</p></body></html>',
      );
      await request.response.close();
      if (error != null && error.isNotEmpty)
        throw OAuthLoopbackException(error);
      if (code == null || code.isEmpty)
        throw const OAuthLoopbackException('GitHub 回调缺少授权码');
      return code;
    }
    throw const OAuthLoopbackException('授权回调已关闭');
  } on TimeoutException {
    throw const OAuthLoopbackException('等待 GitHub 授权回调超时');
  } finally {
    await requests.cancel();
  }
}
