import { fileURLToPath } from 'node:url';
import path from 'node:path';
import { readFile, writeFile, mkdir, readdir, unlink } from 'node:fs/promises';
import { build } from 'vite';
import vue from '@vitejs/plugin-vue';

const root = fileURLToPath(new URL('./', import.meta.url));
const target = path.join(root, '../assets/webf');
const check = process.argv.includes('--check');
const apps = [];
const generated = new Map();
const escapeHtml = (value) => value.replace(/[&<>"']/g, (c) =>
  ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]);

for (const dir of (await readdir(root, { withFileTypes: true })).sort((a, b) => a.name.localeCompare(b.name))) {
  if (!dir.isDirectory() || dir.name === 'node_modules') continue;
  let source;
  try {
    source = await readFile(path.join(root, dir.name, 'manifest.json'), 'utf8');
  } catch (error) {
    if (error.code === 'ENOENT') continue;
    throw error;
  }
  const app = JSON.parse(source);
  const localized = (value) => value && typeof value === 'object' && !Array.isArray(value)
    && Object.keys(value).length > 0
    && Object.values(value).every((v) => typeof v === 'string' && v.length > 0);
  if (!/^[a-z][a-z0-9-]{0,63}$/.test(app.id) || app.id !== dir.name
      || app.apiVersion !== 1 || typeof app.version !== 'string' || !app.version
      || typeof app.icon !== 'string' || !app.icon
      || !localized(app.name) || !localized(app.description)
      || (app.requests !== undefined && (!app.requests || typeof app.requests !== 'object'
        || Array.isArray(app.requests)))) {
    throw new Error(`Invalid manifest: ${dir.name}`);
  }
  for (const request of Object.values(app.requests ?? {})) {
    if (!request || !['GET', 'POST', 'PUT', 'PATCH', 'DELETE'].includes(request.method)
        || typeof request.path !== 'string'
        || !/^\/[a-zA-Z0-9_-]+(?:\/[a-zA-Z0-9_-]+)*$/.test(request.path)) {
      throw new Error(`Invalid request declaration: ${dir.name}`);
    }
  }
  const entries = (await readdir(path.join(root, dir.name)))
    .filter((name) => /^main\.(ts|tsx|js|jsx)$/.test(name));
  if (entries.length !== 1) {
    throw new Error(`${app.id} must have exactly one main.ts, main.tsx, main.js or main.jsx entry`);
  }
  apps.push(app);
  const result = await build({
    configFile: false,
    root,
    plugins: [vue()],
    oxc: { jsx: { runtime: 'automatic', importSource: 'react' } },
    define: { 'process.env.NODE_ENV': JSON.stringify('production'),
      __VUE_OPTIONS_API__: false, __VUE_PROD_DEVTOOLS__: false,
      __VUE_PROD_HYDRATION_MISMATCH_DETAILS__: false },
    build: {
      write: false, target: 'es2018', cssCodeSplit: false,
      lib: { entry: path.join(root, dir.name, entries[0]),
        formats: ['iife'], name: 'LkmMiniApp' },
    },
  });
  const output = (Array.isArray(result) ? result[0] : result).output;
  const scripts = output.filter((item) => item.type === 'chunk');
  const styles = output.filter((item) => item.type === 'asset' && item.fileName.endsWith('.css'));
  if (scripts.length !== 1 || scripts[0].imports.length || scripts[0].dynamicImports.length
      || output.length !== scripts.length + styles.length) {
    throw new Error(`${app.id} must ship as one offline IIFE with inline resources`);
  }
  const title = escapeHtml(app.name['en-US'] ?? Object.values(app.name)[0]);
  const html = `<!DOCTYPE html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>${title}</title><style>${styles.map((item) => item.source).join('\n').replace(/<\/style/gi, '<\\/style')}</style></head><body><div id="app"></div><script>${scripts[0].code.replace(/<\/script/gi, '<\\/script')}</script></body></html>\n`;
  generated.set(`${app.id}.html`, html);
}
if (!apps.length) throw new Error('No official mini apps found');
generated.set('manifest.json', `${JSON.stringify({ apiVersion: 1, apps }, null, 2)}\n`);

await mkdir(target, { recursive: true });
for (const [filename, content] of generated) {
  if (check) {
    if (await readFile(path.join(target, filename), 'utf8') !== content) {
      throw new Error(`${filename} is stale. Run pnpm --dir webf build`);
    }
  } else {
    await writeFile(path.join(target, filename), content);
  }
}
for (const name of await readdir(target)) {
  if (name.endsWith('.html') && !generated.has(name)) {
    if (check) throw new Error(`Stale mini app asset: ${name}`);
    await unlink(path.join(target, name));
  }
}
console.log(`${apps.length} official mini apps ${check ? 'match source' : 'built'}`);
