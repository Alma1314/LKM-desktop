import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:island/community/user_pod.dart';
import 'package:island/core/api/api_providers.dart';
import 'package:island/core/api/api_session.dart';
import 'package:island/core/api/auth_api.dart';
import 'package:island/core/config.dart';
import 'package:island/editor/document_store.dart';
import 'package:island/editor/series_editor_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Adapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  String content = '# other device';
  @override
  void close({bool force = false}) {}
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? stream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromString(
      jsonEncode(
        options.method == 'PUT'
            ? {'code': 0, 'message': 'ok', 'data': null}
            : {
                'data': {
                  'blogSeriesDetail': {
                    'id': 's1',
                    'title': 'Series',
                    'ownerId': 'u1',
                    'fileTree': [
                      {'name': 'a.md', 'type': 'blob'},
                    ],
                  },
                  'blogFileContent': {'content': content},
                },
              },
      ),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }
}

void main() {
  testWidgets(
    'restored drafts retain their baseline and cannot overwrite remote changes',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      await EasyLocalization.ensureInitialized();
      final prefs = await SharedPreferences.getInstance();
      final adapter = _Adapter();
      final session = ApiSession(
        prefs: prefs,
        serverUrl: kLkmServerDefault,
        dio: Dio()..httpClientAdapter = adapter,
      );
      final store = DocumentStore(prefs, kLkmServerDefault, 'u1');
      final draft = {
        'id': 'draft1',
        'series': 's1',
        'path': 'a.md',
        'title': 'Draft',
        'content': '# unsaved edit',
        'baseContent': '# original',
      };
      await store.save(draft, snapshot: true);
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.runAsync(() async {
        await tester.pumpWidget(
          EasyLocalization(
            supportedLocales: const [Locale('en', 'US')],
            path: 'assets/i18n',
            saveLocale: false,
            child: ProviderScope(
              overrides: [
                sharedPreferencesProvider.overrideWithValue(prefs),
                lkmApiSessionProvider.overrideWithValue(session),
                lkmMeProvider.overrideWith(
                  (ref) async => const LkmAccount(
                    id: 'u1',
                    username: 'user',
                    accountLevel: 'normal',
                    role: 'member',
                  ),
                ),
              ],
              child: Builder(
                builder: (context) => MaterialApp(
                  localizationsDelegates: [
                    ...context.localizationDelegates,
                    FlutterQuillLocalizations.delegate,
                  ],
                  supportedLocales: context.supportedLocales,
                  locale: context.locale,
                  home: const SeriesEditorScreen(),
                ),
              ),
            ),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pumpAndSettle();
      final dynamic editor = tester.state(
        find.byKey(const ValueKey('$kLkmServerDefault:u1')),
      );
      await tester.runAsync(
        () async => await editor.run(() async {
          await editor.openLocal(draft);
        }),
      );
      await tester.pumpAndSettle();
      expect(editor.savedContent, '# original');
      await tester.runAsync(() => editor.run(editor.save) as Future<void>);
      await tester.pumpAndSettle();
      expect(editor.error, isNotNull);
      expect(adapter.requests.where((r) => r.method == 'PUT'), isEmpty);
      expect(
        store.documents().firstWhere((d) => d['id'] == 'draft1')['content'],
        '# unsaved edit',
      );

      adapter.content = '# original';
      await tester.runAsync(() => editor.run(editor.save) as Future<void>);
      await tester.pumpAndSettle();
      expect(editor.error, isNull);
      expect(adapter.requests.where((r) => r.method == 'PUT').length, 1);
      expect(
        store.documents().firstWhere((d) => d['id'] == 'draft1')['baseContent'],
        '# unsaved edit',
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
  );
}
