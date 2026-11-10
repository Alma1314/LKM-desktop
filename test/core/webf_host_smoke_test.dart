import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:island/core/webf/webf_demo_screen.dart';
import 'package:island/core/webf/webf_module_host.dart';
import 'package:webf/webf.dart';

void main() {
  test('WebfModuleHost carries its controller name and bundle', () {
    final host = WebfModuleHost(
      controllerName: 'smoke',
      bundle: WebFBundle.fromContent('<html></html>'),
    );

    expect(host.controllerName, 'smoke');
    expect(host.bundle, isNotNull);
  });

  test('WebfDemoScreen is a widget', () {
    expect(const WebfDemoScreen(), isA<Widget>());
  });
}
