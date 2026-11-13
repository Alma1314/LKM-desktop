import { expect, test } from 'vitest';
import { mkdtemp, mkdir, copyFile, symlink, writeFile, readFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';

test.each(['tsx', 'jsx'])('React .%s and native entries are discovered without editing host or build configuration', async (extension) => {
  const source = fileURLToPath(new URL('./', import.meta.url));
  const directory = await mkdtemp(path.join(tmpdir(), 'lkm-new-mini-app-'));
  try {
    const root = path.join(directory, 'webf');
    const app = path.join(root, 'new-tool');
    await mkdir(app, { recursive: true });
    await copyFile(path.join(source, 'build.mjs'), path.join(root, 'build.mjs'));
    await symlink(path.join(source, 'node_modules'), path.join(root, 'node_modules'), process.platform === 'win32' ? 'junction' : 'dir');
    await writeFile(path.join(app, 'manifest.json'), JSON.stringify({
      id: 'new-tool', apiVersion: 1, version: '1.0.0', icon: 'x',
      name: { 'en-US': 'New tool' }, description: { 'en-US': 'Automatically discovered' },
    }));
    await writeFile(path.join(app, 'main.ts'), "document.getElementById('app')!.textContent = 'New tool works';");
    const reactApp = path.join(root, 'react-tool');
    await mkdir(reactApp);
    await writeFile(path.join(reactApp, 'manifest.json'), JSON.stringify({
      id: 'react-tool', apiVersion: 1, version: '1.0.0', icon: 'x',
      name: { 'en-US': 'React tool' }, description: { 'en-US': 'React entry' },
    }));
    await writeFile(path.join(reactApp, `main.${extension}`), `
      import { createRoot } from 'react-dom/client';
      function App() { return <p>React entry works</p>; }
      createRoot(document.getElementById('app')).render(<App />);
    `);
    for (const args of [[], ['--check']]) {
      const result = spawnSync(process.execPath, [path.join(root, 'build.mjs'), ...args], { encoding: 'utf8' });
      expect(result.status, result.stdout + result.stderr).toBe(0);
    }
    const catalog = JSON.parse(await readFile(path.join(directory, 'assets/webf/manifest.json'), 'utf8'));
    expect(catalog.apps.map((app: { id: string }) => app.id)).toEqual(['new-tool', 'react-tool']);
    expect(await readFile(path.join(directory, 'assets/webf/new-tool.html'), 'utf8')).toContain('New tool works');
    expect(await readFile(path.join(directory, 'assets/webf/react-tool.html'), 'utf8')).toContain('React entry works');
    await writeFile(path.join(reactApp, 'main.js'), '');
    const ambiguous = spawnSync(process.execPath, [path.join(root, 'build.mjs')], { encoding: 'utf8' });
    expect(ambiguous.status).not.toBe(0);
    expect(ambiguous.stderr).toContain('must have exactly one');
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
}, 30000);
