import 'package:island/core/webf/webf_module_host.dart';
import 'package:material_ui/material_ui.dart';
import 'package:webf/webf.dart';

/// Minimal smoke test for the WebF runtime.
///
/// ponytail: inline HTML for the first check; use WebFBundle.fromAsset once a
/// real module ships.
class WebfDemoScreen extends StatelessWidget {
  const WebfDemoScreen({super.key});

  static const _html = '''
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<style>
  html, body { margin: 0; height: 100%; }
  body {
    display: flex; align-items: center; justify-content: center;
    background: #f5f5f7; color: #111;
    font-family: sans-serif;
  }
  .card {
    display: flex; flex-direction: column; gap: 12px;
    width: 80%; max-width: 420px; padding: 24px;
    background: #fff; border-radius: 16px;
    box-shadow: 0 8px 30px rgba(0, 0, 0, 0.08);
  }
  .title { font-size: 20px; font-weight: 600; }
  button {
    padding: 10px 14px; border: 0; border-radius: 10px;
    background: #4b53c0; color: #fff; font-size: 15px;
  }
  .count { font-size: 28px; font-weight: 600; }
</style>
</head>
<body>
  <div class="card">
    <div class="title">WebF 已在桌面端运行</div>
    <div>视口：<span id="size"></span></div>
    <div>点击次数：<span id="count" class="count">0</span></div>
    <button id="tap">点我</button>
  </div>
  <script>
    var n = 0;
    function size() {
      document.getElementById('size').textContent =
        window.innerWidth + ' x ' + window.innerHeight;
    }
    document.getElementById('tap').addEventListener('click', function () {
      n = n + 1;
      document.getElementById('count').textContent = n;
    });
    window.addEventListener('resize', size);
    size();
  </script>
</body>
</html>
''';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('WebF demo')),
      body: WebfModuleHost(
        controllerName: 'webf-demo',
        bundle: WebFBundle.fromContent(_html),
      ),
    );
  }
}
