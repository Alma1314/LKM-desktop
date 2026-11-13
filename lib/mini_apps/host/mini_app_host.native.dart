import 'package:flutter/widgets.dart';
import 'package:island/core/webf/webf_module_host.dart';
import 'package:webf/webf.dart';

/// Native renderer. The app and bridge do not depend on WebF types.
class MiniAppHost extends StatelessWidget {
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
  Widget build(BuildContext context) => WebfModuleHost(
    controllerName: controllerName,
    bundle: WebFBundle.fromUrl('assets:///$asset'),
    loadingWidget: loadingWidget,
    createController: () {
      final controller = WebFController();
      controller.javascriptChannel.onMethodCall = onMethodCall;
      return controller;
    },
  );
}
