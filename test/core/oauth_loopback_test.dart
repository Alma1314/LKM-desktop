import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:island/auth/oauth_desktop_native.dart';

void main() {
  test(
    'loopback ignores unrelated requests and accepts only the callback path',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final client = HttpClient();
      addTearDown(() async {
        client.close(force: true);
        await server.close(force: true);
      });
      final code = waitForOAuthCode(server);
      Future<int> get(String path) async {
        final request = await client.getUrl(
          Uri.parse('http://127.0.0.1:${server.port}$path'),
        );
        final response = await request.close();
        await response.drain<void>();
        return response.statusCode;
      }

      expect(await get('/favicon.ico'), HttpStatus.notFound);
      expect(await get('/?code=wrong-path'), HttpStatus.notFound);
      expect(await get('/callback?code=expected'), HttpStatus.ok);
      expect(await code, 'expected');
    },
  );
}
