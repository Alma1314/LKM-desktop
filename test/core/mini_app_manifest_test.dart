import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:island/mini_apps/mini_app_manifest.dart';

void main() {
  final source = File('assets/webf/manifest.json').readAsStringSync();

  test(
    'all discovered mini apps have bundled entries and localized labels',
    () {
      final apps = parseMiniAppCatalog(source);
      expect(
        apps.map((app) => app.id),
        containsAll(['starhope', 'notes', 'pomodoro']),
      );
      for (final app in apps) {
        expect(File(app.asset).existsSync(), isTrue);
        expect(app.name('zh-CN'), isNotEmpty);
        expect(app.description('en-US'), isNotEmpty);
        expect(app.name('fr-FR'), app.name('en-US'));
      }
    },
  );

  test(
    'catalog rejects duplicate IDs, incompatible APIs and unsafe entries',
    () {
      Map<String, dynamic> catalog() =>
          jsonDecode(source) as Map<String, dynamic>;
      final duplicate = catalog();
      (duplicate['apps'] as List).add((duplicate['apps'] as List).first);
      expect(
        () => parseMiniAppCatalog(jsonEncode(duplicate)),
        throwsFormatException,
      );
      final incompatible = catalog()..['apiVersion'] = 2;
      expect(
        () => parseMiniAppCatalog(jsonEncode(incompatible)),
        throwsFormatException,
      );
      for (final id in ['../auth', 'https://elsewhere.invalid', 'notes/file']) {
        final invalid = catalog();
        invalid['apps'][0]['id'] = id;
        expect(
          () => parseMiniAppCatalog(jsonEncode(invalid)),
          throwsFormatException,
        );
      }
      for (final path in [
        '/../auth/me',
        '//elsewhere.invalid',
        '/auth%2fme',
        'https://elsewhere.invalid',
        '/safe?token=x',
      ]) {
        final invalid = catalog();
        invalid['apps'][0]['requests'] = {
          'escape': {'method': 'GET', 'path': path},
        };
        expect(
          () => parseMiniAppCatalog(jsonEncode(invalid)),
          throwsFormatException,
        );
      }
      final invalid = catalog();
      invalid['apps'][0]['apiVersion'] = 2;
      expect(
        () => parseMiniAppCatalog(jsonEncode(invalid)),
        throwsFormatException,
      );
    },
  );
}
