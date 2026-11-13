import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Browser platform adapter, independent of Flutter's rendering lifecycle.
class MiniAppBrowser {
  MiniAppBrowser({
    required this.frame,
    required String html,
    required Future<String> Function(String, dynamic) onMethodCall,
    required String title,
  }) : _onMethodCall = onMethodCall {
    _listener = ((web.MessageEvent event) {
      unawaited(_receive(event));
    }).toJS;
    web.window.addEventListener('message', _listener);
    frame.setAttribute('sandbox', 'allow-scripts');
    frame.setAttribute('title', title);
    frame.style
      ..width = '100%'
      ..height = '100%'
      ..border = '0';
    frame.srcdoc = html.toJS;
  }

  final web.HTMLIFrameElement frame;
  final Future<String> Function(String, dynamic) _onMethodCall;
  late final JSFunction _listener;
  bool _disposed = false;

  Future<void> _receive(web.MessageEvent event) async {
    if (_disposed ||
        !identical(event.source, frame.contentWindow) ||
        event.origin != 'null') {
      return;
    }
    try {
      final data = event.data.dartify();
      if (data is! String) return;
      final message = jsonDecode(data);
      if (message is! Map ||
          message['channel'] != 'lkm-mini-app' ||
          message['type'] != 'request' ||
          message['id'] is! int ||
          message['method'] is! String ||
          message['args'] is! List) {
        return;
      }
      final reply = await _onMethodCall(
        message['method'] as String,
        message['args'],
      );
      if (_disposed) return;
      // The sandbox has an opaque origin. Validate source before using *.
      frame.contentWindow?.postMessage(
        jsonEncode({
          'channel': 'lkm-mini-app',
          'type': 'response',
          'id': message['id'],
          'reply': reply,
        }).toJS,
        '*'.toJS,
      );
    } on FormatException {
      // Ignore messages which are not part of the mini app protocol.
    }
  }

  void dispose() {
    _disposed = true;
    web.window.removeEventListener('message', _listener);
    frame.srcdoc = ''.toJS;
  }
}
