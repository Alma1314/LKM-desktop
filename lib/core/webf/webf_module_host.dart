import 'dart:async';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:material_ui/material_ui.dart';
import 'package:webf/webf.dart';

bool _managerInitialized = false;

void _ensureManager() {
  if (_managerInitialized) return;
  WebFControllerManager.instance.initialize(
    WebFControllerManagerConfig(
      maxAliveInstances: 2,
      maxAttachedInstances: 1,
      autoDisposeWhenLimitReached: true,
      enableDevTools: kDebugMode,
    ),
  );
  _managerInitialized = true;
}

/// Hosts one WebF module by controller name.
///
/// ponytail: one controller per [controllerName]; if two screens ever embed the
/// same module at once, switch to per-instance names.
class WebfModuleHost extends StatefulWidget {
  const WebfModuleHost({
    super.key,
    required this.controllerName,
    required this.bundle,
    this.loadingWidget,
  });

  final String controllerName;
  final WebFBundle bundle;
  final Widget? loadingWidget;

  @override
  State<WebfModuleHost> createState() => _WebfModuleHostState();
}

class _WebfModuleHostState extends State<WebfModuleHost> {
  @override
  void initState() {
    super.initState();
    _ensureManager();
  }

  @override
  void dispose() {
    unawaited(
      WebFControllerManager.instance.removeAndDisposeController(
        widget.controllerName,
      ),
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return WebF.fromControllerName(
      controllerName: widget.controllerName,
      bundle: widget.bundle,
      createController: () => WebFController(),
      loadingWidget: widget.loadingWidget,
      errorBuilder: (context, error) => _error(error),
    );
  }

  Widget _error(Object? error) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Text('WebF 模块加载失败：$error'),
    ),
  );
}
