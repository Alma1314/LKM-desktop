import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:island/core/webf/webf_module_host.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webf/webf.dart';

/// Opt-in FFI smoke test, using the exact WebF library bundled by the platform.
/// WEBF_LIBRARY_PATH points at the directory containing libwebf.so / dylib.
void main() {
  final libraryPath = Platform.environment['WEBF_LIBRARY_PATH'];
  testWidgets('StarHope asset boots and creates an offline question in WebF', (
    tester,
  ) async {
    WebFDynamicLibrary.dynamicLibraryPath = libraryPath!;
    NavigatorModule.setCustomUserAgent('lkm/starhope-test');
    SharedPreferences.setMockInitialValues({});
    final temp = Directory.systemTemp.createTempSync('starhope-webf-');
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
    final screenshotKey = GlobalKey();
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    String? snapshot;
    final methods = <String>[];
    final errors = <String>[];
    WebFController? controller;
    final html = File('assets/webf/starhope/index.html').readAsStringSync();
    await tester.runAsync(() async {
      final font = File('assets/fonts/Nunito-Regular.ttf').readAsBytesSync();
      await (FontLoader(
        'Helvetica',
      )..addFont(Future.value(ByteData.sublistView(font)))).load();
      controller = await WebFControllerManager.instance.addWithPreload(
        name: 'starhope-runtime',
        timeout: const Duration(seconds: 15),
        createController: () {
          final c = WebFController(
            viewportWidth: 1200,
            viewportHeight: 900,
            onJSError: errors.add,
          );
          c.javascriptChannel.onMethodCall = (method, args) async {
            methods.add('$method:$args');
            Object? data;
            switch (method) {
              case 'context':
                data = {'userId': 'u1', 'locale': 'en-US', 'dark': false};
              case 'load':
                data = snapshot;
              case 'newId':
                data = 'q1';
              case 'save':
                snapshot = args.single as String;
                data = true;
              case 'pull':
                return jsonEncode({'ok': false, 'error': 'offline'});
            }
            return jsonEncode({'ok': true, 'data': data});
          };
          return c;
        },
        bundle: WebFBundle.fromContent(
          html,
          url: 'assets:///assets/webf/starhope/index.html',
          contentType: htmlContentType,
        ),
      );
      await controller!.controlledInitCompleter.future.timeout(
        const Duration(seconds: 15),
      );
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RepaintBoundary(
            key: screenshotKey,
            child: WebfModuleHost(
              controllerName: 'starhope-runtime',
              bundle: WebFBundle.fromContent(html),
            ),
          ),
        ),
      ),
    );
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 80)),
      );
      await tester.pump(const Duration(milliseconds: 80));
    }
    expect(errors, isEmpty, reason: errors.join('\n'));
    expect(
      methods.any((m) => m.startsWith('context:')),
      isTrue,
      reason: methods.toString(),
    );
    Future<void> js(String script) async {
      await tester.runAsync(() async {
        await controller!.view.evaluateJavaScripts(script);
      });
      for (var i = 0; i < 4; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 80)),
        );
        await tester.pump(const Duration(milliseconds: 80));
      }
    }

    await js(
      "window.button = text => Array.from(document.querySelectorAll('button')).find(b => b.textContent.trim() === text); button('Question bank').click();",
    );
    await js("button('New question').click();");
    await js(
      r"const fields = document.querySelectorAll('textarea'); const values = ['2 + 2?', '3\n4', '4', 'Math']; fields.forEach((field, i) => { field.value = values[i]; field.dispatchEvent(new Event('input')); });",
    );
    await js("button('Save').click();");
    expect(errors, isEmpty, reason: errors.join('\n'));
    expect(snapshot, isNotNull, reason: methods.toString());
    expect(snapshot, contains('2 + 2?'));
    final screenshot = Platform.environment['STARHOPE_SCREENSHOT'];
    if (screenshot != null) {
      await tester.runAsync(() async {
        final boundary =
            screenshotKey.currentContext!.findRenderObject()
                as RenderRepaintBoundary;
        final image = await boundary.toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        File(screenshot).writeAsBytesSync(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
    await js("button('Practice').click();");
    await js(
      "button('Select all').click(); button('Start selected questions').click();",
    );
    await js("button('3').click();");
    await js("button('Submit').click();");
    await js(
      "const submits = Array.from(document.querySelectorAll('button')).filter(b => b.textContent.trim() === 'Submit'); submits[submits.length - 1].click();",
    );
    expect(errors, isEmpty, reason: errors.join('\n'));
    final saved = jsonDecode(snapshot!);
    expect(saved['entries']['sessions']['q1']['data']['status'], 'completed');
    expect(
      saved['entries']['sessions']['q1']['data']['results']['q1']['correct'],
      false,
    );
    await js("button('Question bank').click();");
    await js("button('Edit').click();");
    await js("button('Multiple choice').click();");
    await js(
      r"const answerField = document.querySelectorAll('textarea')[2]; answerField.value = '3\n4'; answerField.dispatchEvent(new Event('input')); ",
    );
    await js("button('Save').click();");
    await js("button('Practice').click();");
    await js("button('Start selected questions').click();");
    await js("button('3').click(); button('4').click();");
    final multiple = jsonDecode(snapshot!);
    expect(multiple['entries']['sessions']['q1']['data']['answers']['q1'], [
      '3',
      '4',
    ]);
    expect(
      multiple['entries']['sessions']['q1']['data']['results']['q1']['correct'],
      true,
    );
    expect(errors, isEmpty, reason: errors.join('\n'));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(() async {
      await WebFControllerManager.instance.removeAndDisposeController(
        'starhope-runtime',
      );
      await WebFControllerManager.instance.stopDevTools();
      await temp.delete(recursive: true);
    });
  }, skip: libraryPath == null);
}
