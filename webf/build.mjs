import { fileURLToPath } from 'node:url';
import path from 'node:path';
import { readFile, writeFile, mkdir } from 'node:fs/promises';
import { build } from 'vite';
import vue from '@vitejs/plugin-vue';

const root = fileURLToPath(new URL('./', import.meta.url));
const result = await build({
  configFile: false,
  root,
  plugins: [vue()],
  define: { 'process.env.NODE_ENV': JSON.stringify('production'),
    __VUE_OPTIONS_API__: false, __VUE_PROD_DEVTOOLS__: false,
    __VUE_PROD_HYDRATION_MISMATCH_DETAILS__: false },
  build: {
    write: false, target: 'es2018', cssCodeSplit: false,
    lib: { entry: path.join(root, 'starhope/main.ts'),
      formats: ['iife'], name: 'StarHopeModule' },
  },
});
const output = (Array.isArray(result) ? result[0] : result).output;
const scripts = output.filter((item) => item.type === 'chunk');
if (scripts.length !== 1 || scripts[0].imports.length || scripts[0].dynamicImports.length) {
  throw new Error('StarHope must ship as one offline IIFE without module imports');
}
const styles = output.filter((item) => item.type === 'asset' && item.fileName.endsWith('.css'));
const html = `<!DOCTYPE html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>StarHope</title><style>${styles.map((item) => item.source).join('\n').replace(/<\/style/gi, '<\\/style')}</style></head><body><div id="app"></div><script>${scripts[0].code.replace(/<\/script/gi, '<\\/script')}</script></body></html>\n`;
const target = path.join(root, '../assets/webf/starhope/index.html');
if (process.argv.includes('--check')) {
  if (await readFile(target, 'utf8') !== html) throw new Error('StarHope asset is stale. Run pnpm --dir webf build');
  console.log('StarHope WebF asset matches source');
} else {
  await mkdir(path.dirname(target), { recursive: true });
  await writeFile(target, html);
  console.log(`StarHope WebF asset written (${Buffer.byteLength(html)} bytes)`);
}
