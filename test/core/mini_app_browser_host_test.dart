@TestOn('browser')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:flutter_test/flutter_test.dart';
import 'package:island/core/api/api_session.dart';
import 'package:island/mini_apps/host/mini_app_browser.dart';
import 'package:island/mini_apps/mini_app_bridge.dart';
import 'package:island/mini_apps/mini_app_manifest.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web/web.dart' as web;

Future<String> testAsset(String name) async {
  const base = String.fromEnvironment('MINI_APP_TEST_ASSET_BASE');
  if (base.isEmpty) {
    throw StateError(
      'Run node webf/test-browser.mjs to serve the built assets.',
    );
  }
  final response = await web.window.fetch('$base$name'.toJS).toDart;
  if (!response.ok) throw StateError('Could not load test asset: $name');
  return (await response.text().toDart).toDart;
}

String testHtml(String html) {
  // Execute interactions inside the sandbox; the parent cannot read its DOM.
  return html.replaceFirst('</body>', r'''
<script>
(async () => {
  parent.postMessage(JSON.stringify({type:'phase',phase:'html-loaded'}), '*');
  window.addEventListener('error', event => parent.postMessage(JSON.stringify({type:'test-error',error:event.message}), '*'));
  const wait = () => new Promise(resolve => setTimeout(resolve, 50));
  const button = text => Array.from(document.querySelectorAll('button')).find(b => b.textContent.trim() === text);
  while (!button('Save note')) await wait();
  parent.postMessage(JSON.stringify({type:'phase',phase:'app-ready'}), '*');
  const field = document.querySelector('textarea');
  field.value = 'Saved through the browser SDK';
  field.dispatchEvent(new Event('input', { bubbles: true }));
  await wait();
  button('Save note').click();
  while (!document.querySelector('.text')) await wait();
  parent.postMessage(JSON.stringify({type: 'browser-test-done'}), '*');
})();
</script></body>''');
}

void main() {
  late SharedPreferences prefs;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });
  test('the same Notes bundle saves through an isolated browser host', () async {
    final assets = await Future.wait(
      ['manifest.json', 'notes.html'].map(testAsset),
    );
    final catalog = parseMiniAppCatalog(assets[0]);
    final app = catalog.singleWhere((app) => app.id == 'notes');
    String? saved;
    final bridge = MiniAppBridge(
      app: app,
      session: ApiSession(prefs: prefs, serverUrl: 'https://example.invalid'),
      userId: 'browser-user',
      isCurrent: () => true,
      read: () async => saved,
      save: (value) async {
        saved = value;
      },
      locale: 'en-US',
      dark: false,
    );
    final done = Completer<void>();
    final observations = <String>[];
    final frame = web.HTMLIFrameElement();
    final listener = ((web.MessageEvent event) {
      final data = event.data.dartify();
      if (data is String) {
        try {
          final message = jsonDecode(data);
          observations.add(
            '${event.origin}: $message; source=${identical(event.source, frame.contentWindow)}',
          );
          if (message is Map &&
              message['type'] == 'browser-test-done' &&
              !done.isCompleted) {
            done.complete();
          }
        } on FormatException {
          /* Other page messages are irrelevant. */
        }
      }
    }).toJS;
    web.window.addEventListener('message', listener);
    addTearDown(() {
      web.window.removeEventListener('message', listener);
      bridge.dispose();
    });
    final browser = MiniAppBrowser(
      frame: frame,
      html: testHtml(assets[1]),
      title: 'notes-browser',
      onMethodCall: bridge.call,
    );
    web.document.body!.appendChild(frame);
    addTearDown(() {
      browser.dispose();
      frame.remove();
    });
    try {
      await done.future.timeout(const Duration(seconds: 10));
    } catch (error) {
      fail(
        'Browser adapter failed: $error; saved=$saved; messages=$observations',
      );
    }
    expect(saved, contains('Saved through the browser SDK'));
    expect(frame.getAttribute('sandbox'), 'allow-scripts');
    // Messages from the outer window cannot impersonate the sandboxed app.
    web.window.postMessage(
      jsonEncode({
        'channel': 'lkm-mini-app',
        'type': 'request',
        'id': 999,
        'method': 'save',
        'args': ['"spoofed"'],
      }).toJS,
      '*'.toJS,
    );
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(saved, isNot(contains('spoofed')));
  });
}
