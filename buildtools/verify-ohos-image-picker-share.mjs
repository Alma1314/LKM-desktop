import assert from 'node:assert/strict';
import * as fs from 'node:fs';
import * as path from 'node:path';
import { tmpdir } from 'node:os';
import { randomUUID } from 'node:crypto';
import { loadArkTs } from './ohos-test-loader.mjs';

const root = fs.mkdtempSync(path.join(tmpdir(), 'ohos-picker-share-'));
const handles = new Map();
const provider = 'file://media/Photo/1/图片.jpg';
const image = path.join(root, '图片.jpg');
const video = path.join(root, 'video.mp4');
fs.writeFileSync(image, new Uint8Array([1, 2, 3]));
fs.writeFileSync(video, new Uint8Array([4, 5]));
const nativePath = value => value === provider ? image : value.replace(/^file:\/\//, '');
let copyError = false;
let delayCopy = false;
let resumeCopy;
const nativeFs = {
  OpenMode: { READ_ONLY: 0, CREATE: 64, READ_WRITE: 2, TRUNC: 512 },
  mkdirSync: (value, recursive = false) => fs.mkdirSync(value, { recursive }),
  openSync(value, flags = 0) {
    const target = nativePath(value);
    const fd = fs.openSync(target, flags);
    const result = { fd, name: path.basename(target) };
    handles.set(fd, result);
    return result;
  },
  closeSync(file) {
    assert.equal(handles.delete(file.fd), true, 'FD closed exactly once');
    fs.closeSync(file.fd);
  },
  copyFileSync(fd, target) {
    if (copyError) throw { code: 5, message: 'Copy failed' };
    fs.writeFileSync(target, fs.readFileSync(fd));
  },
  unlinkSync: value => fs.unlinkSync(value),
  writeSync: (fd, bytes) => fs.writeSync(fd, new Uint8Array(bytes).subarray(0, 3)),
  async open(value, flags) { return this.openSync(value, flags); },
  async close(file) { this.closeSync(file); },
  async copyFile(fd, target) {
    if (delayCopy) await new Promise(resolve => { resumeCopy = resolve; });
    this.copyFileSync(fd, target);
  },
};
const commonMocks = new Map([
  ['@ohos.file.fs', nativeFs], ['@ohos.util', { generateRandomUUID: randomUUID }],
  ['@ohos/flutter_ohos/src/main/ets/util/Log', { i() {}, e() {}, w() {}, d() {} }],
]);
const pickerDir = '../packages/image_picker_ohos/ohos/src/main/ets/image_picker/';
const fileUtils = loadArkTs(new URL(`${pickerDir}FileUtils.ets`, import.meta.url), commonMocks);
const copied = fileUtils.default.getPathFromUri({ cacheDir: root }, provider);
assert.deepEqual([...fs.readFileSync(copied)], [1, 2, 3]);
assert.equal(path.basename(copied), '图片.jpg');
copyError = true;
assert.throws(() => fileUtils.default.getPathFromUri({ cacheDir: root }, provider));
assert.equal(handles.size, 0);
copyError = false;
let desiredSize;
let released = 0;
const imageSdk = {
  createImageSource: () => ({
    getImageInfo: async () => ({ size: { width: 4000, height: 2000 } }),
    createPixelMap: async options => { desiredSize = options.desiredSize; return { release: async () => { released++; } }; },
    release: async () => { released++; },
  }),
  createImagePacker: () => ({ packing: async () => new Uint8Array([9, 8, 7, 6, 5, 4, 3]).buffer,
    release: async () => { released++; } }),
};
const resizerModule = loadArkTs(new URL(`${pickerDir}ImageResizer.ets`, import.meta.url),
  new Map([...commonMocks, ['@ohos.multimedia.image', imageSdk]]));
const exif = class { async copyExif() {} };
const resized = await new resizerModule.default({ cacheDir: root }, new exif()).resizeImageIfNeeded(image, 1000, 1000, 80);
assert.equal(desiredSize.width, 1000);
assert.equal(desiredSize.height, 500);
assert.equal(path.extname(resized), '.jpg');
assert.deepEqual([...fs.readFileSync(resized)], [9, 8, 7, 6, 5, 4, 3]);
assert.equal(released, 3);
assert.equal(handles.size, 0);

const channels = new Map();
class MethodChannel {
  constructor(_, name) { channels.set(name, this); }
  setMethodCallHandler(value) { this.handler = value; }
}
let select = async () => ({ photoUris: [] });
let cameraResult = { resultCode: -1, resultUri: '' };
const Plugin = loadArkTs(new URL(`${pickerDir}ImagePickerPlugin.ets`, import.meta.url), new Map([
  ...commonMocks,
  ['@ohos/flutter_ohos', { MethodChannel }],
  ['./FileUtils', fileUtils.default], ['./ImageResizer', resizerModule.default], ['./ExifDataCopier', exif],
  ['@kit.CoreFileKit', { fileUri: { getUriFromPath: value => `file://${value}` } }],
  ['@kit.CameraKit', { camera: { CameraPosition: { CAMERA_POSITION_FRONT: 1, CAMERA_POSITION_BACK: 0 } },
    cameraPicker: { PickerMediaType: { VIDEO: 'video', PHOTO: 'photo' }, pick: async (_, __, profile) => {
      if (cameraResult.resultCode === 0) fs.writeFileSync(nativePath(profile.saveUri), new Uint8Array([1, 2, 3]));
      return { ...cameraResult, resultUri: cameraResult.resultCode === 0 ? profile.saveUri : '' };
    } } }],
  ['@kit.MediaLibraryKit', { photoAccessHelper: { PhotoSelectOptions: class {},
    PhotoViewMIMETypes: { IMAGE_TYPE: 'image', VIDEO_TYPE: 'video' },
    PhotoViewPicker: class { select(options) { return select(options); } } } }],
])).default;
const plugin = new Plugin();
const binding = { getBinaryMessenger: () => ({}) };
plugin.onAttachedToEngine(binding);
function invoke(method, args = {}) {
  return new Promise(resolve => {
    let count = 0;
    const done = (...values) => { assert.equal(++count, 1, 'one reply per call'); resolve(values); };
    plugin.onMethodCall({ method, argument: key => args[key] ?? null }, {
      success: value => done('success', value), error: (...v) => done('error', ...v),
      notImplemented: () => done('notImplemented'),
    });
  });
}
assert.equal((await invoke('pickImage', { source: 1 }))[1], 'no_ability');
plugin.onAttachedToAbility({ getAbility: () => ({ context: { cacheDir: root } }) });
assert.deepEqual(await invoke('pickImage', { source: 1 }), ['success', null]);
assert.equal((await invoke('pickMultiImage'))[1].length, 0);
select = async options => { assert.equal(options.maxSelectNumber, 3); return { photoUris: [video, video] }; };
assert.equal((await invoke('pickMultiVideo', { limit: 3 }))[1].length, 2);
select = async () => { throw { code: 401, message: 'Picker unavailable' }; };
assert.equal((await invoke('pickImage', { source: 1 }))[1], 'picker_error');
assert.deepEqual(await invoke('pickImage', { source: 0 }), ['success', null]);
cameraResult.resultCode = 0;
assert.equal((await invoke('pickImage', { source: 0 }))[0], 'success');
let finishSelection;
select = () => new Promise(resolve => { finishSelection = resolve; });
const pending = invoke('pickMultiImage');
assert.equal((await invoke('pickMultiImage'))[1], 'already_active');
plugin.onDetachedFromAbility();
assert.equal((await pending)[1], 'no_ability');
finishSelection({ photoUris: [provider] });
await new Promise(resolve => setImmediate(resolve));
plugin.onDetachedFromEngine(binding);
assert.equal(channels.get('plugins.flutter.io/image_picker').handler, null);

let shown = 0;
let controller;
let failShow = false;
class SharedData {
  constructor(record) { this.records = [record]; }
  addRecord(record) { this.records.push(record); }
}
class ShareController {
  constructor(data) { this.data = data; controller = this; }
  on(_, callback) { this.callback = callback; }
  off(_, callback) { assert.equal(callback, this.callback); this.callback = null; }
  async show() { if (failShow) throw { code: 500, message: 'Show failed' }; shown++; }
}
const shareDir = '../packages/share_plus/ohos/src/main/ets/dev/fluttercommunity/plus/share/';
const Share = loadArkTs(new URL(`${shareDir}Share.ets`, import.meta.url), new Map([
  ...commonMocks,
  ['@kit.CoreFileKit', { fileUri: { getUriFromPath: value => `file://${value}` } }],
  ['@hms.collaboration.systemShare', { SharedData, ShareController, SharePreviewMode: { DETAIL: 1 }, SelectionMode: { SINGLE: 0 } }],
  ['@ohos.data.uniformTypeDescriptor', { UniformDataType: { PLAIN_TEXT: 'text', HYPERLINK: 'link', FILE: 'file' },
    getUniformDataTypeByMIMEType: value => value, getUniformDataTypeByFilenameExtension: () => 'file' }],
])).default;
const share = new Share({ cacheDir: root });
function shareCall(args) {
  return new Promise(resolve => share.share({ argument: key => args[key] ?? null }, {
    success: value => resolve(['success', value]), error: (...values) => resolve(['error', ...values]),
  }));
}
assert.equal((await shareCall({ text: 'hello' }))[1], 'no_ability');
share.setAbility({ context: {} });
delayCopy = true;
let settled = false;
const fileShare = shareCall({ paths: [image, video], mimeTypes: ['image/jpeg', 'video/mp4'], text: 'files' })
  .then(value => { settled = true; return value; });
for (let i = 0; !resumeCopy && i < 100; i++) await new Promise(resolve => setImmediate(resolve));
assert.equal(typeof resumeCopy, 'function');
assert.equal(shown, 0);
assert.equal(settled, false);
delayCopy = false;
resumeCopy();
for (let i = 0; !shown && i < 100; i++) await new Promise(resolve => setImmediate(resolve));
assert.equal(shown, 1);
assert.equal(controller.data.records.length, 3);
for (const record of controller.data.records.slice(1)) assert.equal(fs.existsSync(nativePath(record.uri)), true);
assert.equal(handles.size, 0);
assert.equal((await shareCall({ text: 'overlap' }))[1], 'already_active');
controller.callback();
assert.deepEqual(await fileShare, ['success', 'dev.fluttercommunity.plus/share/unavailable']);
assert.equal(controller.callback, null);
copyError = true;
assert.equal((await shareCall({ paths: [image], mimeTypes: ['image/jpeg'] }))[1], 'share_error');
assert.equal(handles.size, 0);
copyError = false;
failShow = true;
assert.equal((await shareCall({ text: 'hello' }))[1], 'share_error');
failShow = false;
const detached = shareCall({ uri: 'https://example.com' });
await new Promise(resolve => setImmediate(resolve));
assert.equal(controller.data.records[0].utd, 'link');
share.setAbility(null);
assert.equal((await detached)[1], 'no_ability');
assert.equal(controller.callback, null);
assert.equal(handles.size, 0);
fs.rmSync(root, { recursive: true, force: true });
console.log('OHOS picker + share: cancellation, multiple files, resize, FD cleanup, async copies, errors and detach passed');
