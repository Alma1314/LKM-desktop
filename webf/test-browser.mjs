import { readFile } from 'node:fs/promises';
import { createServer } from 'node:http';
import { once } from 'node:events';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawn } from 'node:child_process';

const root = fileURLToPath(new URL('../', import.meta.url));
const [html, manifest] = await Promise.all([
  readFile(path.join(root, 'assets/webf/notes.html')),
  readFile(path.join(root, 'assets/webf/manifest.json')),
]);
// Flutter's browser test server does not serve app assets. Serve the actual
// bundles on loopback; embedding React in a -D argument exceeds OS limits.
const files = new Map([
  ['/notes.html', { type: 'text/html', data: html }],
  ['/manifest.json', { type: 'application/json', data: manifest }],
]);
const server = createServer((request, response) => {
  const file = files.get(request.url?.split('?')[0]);
  response.writeHead(file ? 200 : 404, {
    'Content-Type': file?.type ?? 'text/plain',
    'Access-Control-Allow-Origin': '*',
  });
  response.end(file?.data ?? 'Not found');
});
server.listen(0, '127.0.0.1');
await once(server, 'listening');
try {
  const { port } = server.address();
  const child = spawn(process.env.FLUTTER_BIN ?? 'flutter', [
    'test', '--no-pub', '--platform', 'chrome',
    `--dart-define=MINI_APP_TEST_ASSET_BASE=http://127.0.0.1:${port}/`,
    'test/core/mini_app_browser_host_test.dart',
  ], { cwd: root, stdio: 'inherit', shell: false });
  const [code] = await once(child, 'exit');
  process.exitCode = code ?? 1;
} finally {
  await new Promise((resolve, reject) => server.close(error => error ? reject(error) : resolve()));
}
