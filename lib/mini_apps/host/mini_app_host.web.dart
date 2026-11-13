import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/widgets.dart';
import 'package:island/mini_apps/host/mini_app_browser.dart';
import 'package:web/web.dart' as web;

/// Flutter's browser view only loads assets and attaches the platform adapter.
class MiniAppHost extends StatefulWidget {
  const MiniAppHost({
    super.key,
    required this.controllerName,
    required this.asset,
    required this.onMethodCall,
    required this.loadingWidget,
  });

  final String controllerName;
  final String asset;
  final Future<String> Function(String, dynamic) onMethodCall;
  final Widget loadingWidget;

  @override
  State<MiniAppHost> createState() => _MiniAppHostState();
}

class _MiniAppHostState extends State<MiniAppHost> {
  Future<String>? _html;
  MiniAppBrowser? _browser;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _html ??= DefaultAssetBundle.of(context).loadString(widget.asset);
  }

  @override
  void dispose() {
    _browser?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<String>(
    future: _html,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return Center(child: Text('miniApps.loadFailed'.tr()));
      }
      if (!snapshot.hasData) return widget.loadingWidget;
      return HtmlElementView.fromTagName(
        tagName: 'iframe',
        onElementCreated: (element) {
          _browser?.dispose();
          _browser = MiniAppBrowser(
            frame: element as web.HTMLIFrameElement,
            html: snapshot.data!,
            title: widget.controllerName,
            onMethodCall: widget.onMethodCall,
          );
        },
      );
    },
  );
}
