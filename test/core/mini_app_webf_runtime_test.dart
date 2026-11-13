import 'dart:io';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:island/core/api/api_session.dart';
import 'package:island/core/webf/webf_module_host.dart';
import 'package:island/mini_apps/mini_app_bridge.dart';
import 'package:island/mini_apps/mini_app_manifest.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webf/webf.dart';

void main() {
  final libraryPath = Platform.environment['WEBF_LIBRARY_PATH'];
  for (final appId in ['notes', 'pomodoro']) {
    testWidgets('$appId runs through the shared SDK and native bridge', (
      tester,
    ) async {
      WebFDynamicLibrary.dynamicLibraryPath = libraryPath!;
      NavigatorModule.setCustomUserAgent('lkm/mini-app-test');
      SharedPreferences.setMockInitialValues({});
      final temp = Directory.systemTemp.createTempSync('lkm-mini-app-webf-');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        getWebFMethodChannel(),
        (_) async => temp.path,
      );
      messenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (_) async => temp.path,
      );
      WebFControllerManager.instance.initialize(
        const WebFControllerManagerConfig(
          maxAliveInstances: 2,
          maxAttachedInstances: 1,
          enableDevTools: false,
        ),
      );
      tester.view.physicalSize = const Size(1000, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final app = parseMiniAppCatalog(
        File('assets/webf/manifest.json').readAsStringSync(),
      ).singleWhere((app) => app.id == appId);
      final session = ApiSession(
        prefs: await SharedPreferences.getInstance(),
        serverUrl: 'http://localhost:8000',
      );
      String? snapshot;
      final bridge = MiniAppBridge(
        app: app,
        session: session,
        userId: 'one',
        isCurrent: () => true,
        read: () async => snapshot,
        save: (value) async {
          snapshot = value;
        },
        locale: 'en-US',
        dark: false,
      );
      final errors = <String>[];
      Map<String, dynamic>? buttonPosition;
      final screenshotKey = GlobalKey();
      WebFController? controller;
      final html = File(app.asset).readAsStringSync();
      await tester.runAsync(() async {
        final font = File('assets/fonts/Nunito-Regular.ttf').readAsBytesSync();
        for (final family in ['Helvetica', 'Arial', 'sans-serif']) {
          await (FontLoader(
            family,
          )..addFont(Future.value(ByteData.sublistView(font)))).load();
        }
        controller = await WebFControllerManager.instance.addWithPreload(
          name: '$appId-runtime',
          timeout: const Duration(seconds: 15),
          createController: () {
            final c = WebFController(
              viewportWidth: 1000,
              viewportHeight: 800,
              onJSError: errors.add,
            );
            c.javascriptChannel.onMethodCall = (method, arguments) async {
              if (method == 'test:bounds') {
                buttonPosition =
                    jsonDecode(arguments.single as String)
                        as Map<String, dynamic>;
                return jsonEncode({'ok': true, 'data': true});
              }
              return bridge.call(method, arguments);
            };
            return c;
          },
          bundle: WebFBundle.fromContent(
            html,
            url: 'assets:///${app.asset}',
            contentType: htmlContentType,
          ),
        );
        await controller!.controlledInitCompleter.future.timeout(
          const Duration(seconds: 15),
        );
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(fontFamily: 'Helvetica'),
          home: Scaffold(
            body: RepaintBoundary(
              key: screenshotKey,
              child: WebfModuleHost(
                controllerName: '$appId-runtime',
                bundle: WebFBundle.fromContent(html),
              ),
            ),
          ),
        ),
      );
      Future<void> js(String script) async {
        await tester.runAsync(() async {
          await controller!.view.evaluateJavaScripts(script);
        });
        for (var i = 0; i < 6; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 80)),
          );
          await tester.pump(const Duration(milliseconds: 80));
        }
      }

      Future<void> tapButton(String text, {bool last = false}) async {
        await js('''
          var targets = Array.from(document.querySelectorAll('button')).filter(b => b.textContent.trim() === ${jsonEncode(text)});
          var rect = targets[${last ? 'targets.length - 1' : '0'}].getBoundingClientRect();
          window.webf.methodChannel.invokeMethod('test:bounds', JSON.stringify({x:rect.left + rect.width / 2, y:rect.top + rect.height / 2}));
        ''');
        await tester.tapAt(
          Offset(
            (buttonPosition!['x'] as num).toDouble(),
            (buttonPosition!['y'] as num).toDouble(),
          ),
        );
        await js('void 0;');
      }

      await js(
        "window.button = text => Array.from(document.querySelectorAll('button')).find(b => b.textContent.trim() === text);",
      );
      expect(errors, isEmpty, reason: errors.join('\n'));
      if (appId == 'notes') {
        // React delegates events to the root. Exercise the native text input
        // instead of dispatching a JS event on WebF's Flutter-backed textarea.
        await tester.enterText(
          find.byType(EditableText),
          'One small step, saved offline.',
        );
        await js('void 0;');
        await tapButton('Save note');
        expect(snapshot, contains('One small step, saved offline.'));
        await tapButton('Edit');
        await tester.enterText(find.byType(EditableText), 'A revised thought.');
        await js('void 0;');
        await tapButton('Save note');
        expect(snapshot, contains('A revised thought.'));
        expect(snapshot, isNot(contains('One small step')));
      } else {
        await js("button('Start').click();");
        expect(snapshot, contains('"endsAt":'));
        expect(snapshot, isNot(contains('"endsAt":null')));
        await js("button('Pause').click();");
        expect(snapshot, contains('"endsAt":null'));
        await js("button('Reset').click();");
        expect(snapshot, contains('1500000'));
      }
      expect(errors, isEmpty, reason: errors.join('\n'));
      final screenshots = Platform.environment['MINI_APP_SCREENSHOT_DIR'];
      if (screenshots != null) {
        await js('document.body.getBoundingClientRect();');
        await tester.runAsync(() async {
          final boundary =
              screenshotKey.currentContext!.findRenderObject()
                  as RenderRepaintBoundary;
          final image = await boundary.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          Directory(screenshots).createSync(recursive: true);
          File(
            '$screenshots/$appId.png',
          ).writeAsBytesSync(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      if (appId == 'notes') {
        await tapButton('Delete');
        await tapButton('Delete', last: true);
        expect(snapshot, '[]');
      }
      bridge.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() async {
        await WebFControllerManager.instance.removeAndDisposeController(
          '$appId-runtime',
        );
        await WebFControllerManager.instance.stopDevTools();
        await temp.delete(recursive: true);
      });
    }, skip: libraryPath == null);
  }
}
