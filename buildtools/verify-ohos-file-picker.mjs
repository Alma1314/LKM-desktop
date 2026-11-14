import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { randomUUID } from 'node:crypto';
import { pathToFileURL } from 'node:url';
import { loadArkTs } from './ohos-test-loader.mjs';

const root = fs.mkdtempSync(path.join(os.tmpdir(), 'lkm-picker-'));
const sourceUri = 'file://docs/provider/file%20one.txt';
const outputUri = 'file://docs/provider/output.txt';
const source = path.join(root, 'source.txt');
const output = path.join(root, 'output.txt');
fs.writeFileSync(source, 'selected contents');
fs.writeFileSync(output, 'old file to truncate');
const providers = new Map([[sourceUri, source], [outputUri, output]]);
const open = new Set();
let selected = [sourceUri];
const nativeFs = {
  OpenMode: { READ_ONLY: fs.constants.O_RDONLY, READ_WRITE: fs.constants.O_RDWR, TRUNC: fs.constants.O_TRUNC },
  async open(uri, mode) { const fd = fs.openSync(providers.get(uri) ?? uri, mode); open.add(fd); return { fd }; },
  async close(file) { fs.closeSync(file.fd); open.delete(file.fd); },
  async copyFile(fd, destination) { fs.writeFileSync(destination, fs.readFileSync(fd)); },
  async write(fd, data) { return fs.writeSync(fd, Buffer.from(data), 0, Math.min(2, data.byteLength)); },
  mkdirSync(directory, recursive) { fs.mkdirSync(directory, { recursive }); },
  accessSync: fs.existsSync,
  async rmdir(directory) { fs.rmSync(directory, { recursive: true }); },
};
const picker = {
  DocumentSelectOptions: class {},
  DocumentSaveOptions: class {},
  DocumentSelectMode: { FOLDER: 1 },
  DocumentViewPicker: class {
    async select() { return selected; }
    async save() { return [outputUri]; }
  },
};
const esm = value => ({ __esModule: true, default: value });
const mocks = new Map([
  ['@ohos/flutter_ohos', {}],
  ['@ohos.file.fs', esm(nativeFs)],
  ['@ohos.file.picker', esm(picker)],
  ['@ohos.util', esm({ generateRandomUUID: randomUUID })],
  ['@ohos.file.fileuri', esm({
    FileUri: class { constructor(uri) { this.name = decodeURIComponent(new URL(uri).pathname.split('/').at(-1)); } },
    getUriFromPath: value => pathToFileURL(value).href,
  })],
]);
try {
  const url = new URL('../packages/file_picker/ohos/src/main/ets/components/plugin/FilePickerPlugin.ets', import.meta.url);
  const { default: Plugin } = loadArkTs(url, mocks);
  const plugin = new Plugin();
  plugin.onAttachedToAbility({ getAbility: () => ({ context: { cacheDir: root } }) });
  const call = (method, args = {}) => new Promise((resolve, reject) => {
    plugin.onMethodCall({ method, argument: key => args[key] }, {
      success: resolve,
      error: (code, message) => reject(Error(`${code}: ${message}`)),
      notImplemented: () => reject(Error('not implemented')),
    });
  });
  const picked = await call('pickFiles', { type: 0, multiple: false });
  assert.equal(picked.length, 1);
  assert.equal(fs.readFileSync(new URL(picked[0]), 'utf8'), 'selected contents');
  assert.equal(path.basename(new URL(picked[0]).pathname), 'file%20one.txt');
  assert.equal(open.size, 0);
  const bytes = Uint8Array.from([99, 1, 2, 3, 77]).subarray(1, 4);
  assert.equal(await call('saveFile', { fileName: 'output.txt', bytes }), outputUri);
  assert.deepEqual([...fs.readFileSync(output)], [1, 2, 3], 'honor byte views and partial writes');
  assert.equal(open.size, 0);
  selected = [];
  assert.equal((await call('pickFiles', { type: 0 })).length, 0);
  await call('clearTemporaryFiles');
  assert(!fs.existsSync(path.join(root, 'file_picker')));
  console.log('OHOS picker provider caching, descriptor cleanup, cancellation and partial writes passed.');
} finally {
  for (const fd of open) fs.closeSync(fd);
  fs.rmSync(root, { recursive: true, force: true });
}
