import assert from 'node:assert/strict';
import { loadArkTs } from './ohos-test-loader.mjs';

let handler;
class MethodChannel {
  setMethodCallHandler(value) { handler = value; }
}
const deviceInfo = { sdkApiVersion: 26 };
let reviewError;
let synchronousError = false;
let linkError;
let completeReview;
let reviewStarted;
const started = new Promise(resolve => { reviewStarted = resolve; });
const Plugin = loadArkTs(new URL(
  '../packages/in_app_review/ohos/src/main/ets/components/plugin/InAppReviewPlugin.ets', import.meta.url,
), new Map([
  ['@ohos/flutter_ohos', { MethodChannel }],
  ['@kit.BasicServicesKit', { deviceInfo }],
  ['@kit.AppGalleryKit', { commentManager: {
    showCommentDialog() {
      if (reviewError) {
        if (synchronousError) throw reviewError;
        return Promise.reject(reviewError);
      }
      reviewStarted();
      return new Promise(resolve => { completeReview = resolve; });
    },
  } }],
])).default;
let link;
const context = {
  abilityInfo: { bundleName: 'ltd.lkmahz.desktop' },
  async openLink(value, options) {
    if (linkError) throw linkError;
    link = value;
    assert.equal(options.appLinkingOnly, false);
  },
};
const binding = { getBinaryMessenger: () => ({}) };
const plugin = new Plugin();
plugin.onAttachedToEngine(binding);
function invoke(method, id = null) {
  return new Promise(resolve => {
    let replies = 0;
    const finish = (...args) => { assert.equal(++replies, 1); resolve(args); };
    handler.onMethodCall({ method, argument: () => id }, {
      success: value => finish('success', value),
      error: (...args) => finish('error', ...args),
      notImplemented: () => finish('notImplemented'),
    });
  });
}
assert.deepEqual(await invoke('isAvailable'), ['success', false]);
assert.equal((await invoke('requestReview'))[0], 'error');
plugin.onAttachedToAbility({ getAbility: () => ({ context }) });
deviceInfo.sdkApiVersion = 19;
assert.deepEqual(await invoke('isAvailable'), ['success', false]);
assert.equal((await invoke('requestReview'))[0], 'error');
deviceInfo.sdkApiVersion = 26;
assert.deepEqual(await invoke('isAvailable'), ['success', true]);
let acknowledged = false;
const pending = invoke('requestReview').then(r => { acknowledged = true; return r; });
await started;
assert.equal(acknowledged, false);
completeReview();
assert.deepEqual(await pending, ['success', null]);
assert.deepEqual(await invoke('openStoreListing'), ['success', null]);
assert.equal(link, 'https://appgallery.huawei.com/app/detail?id=ltd.lkmahz.desktop');
await invoke('openStoreListing', 'example.app&other=value');
assert.equal(link, 'https://appgallery.huawei.com/app/detail?id=example.app%26other%3Dvalue');
linkError = { code: 401, message: 'Invalid context' };
const error = await invoke('openStoreListing');
assert.deepEqual(error, ['error', 'error', 'Invalid context', 401]);
reviewError = { code: 1021500006, message: 'Not signed in' };
assert.deepEqual(await invoke('requestReview'), ['error', 'error', 'Not signed in', 1021500006]);
synchronousError = true;
assert.equal((await invoke('requestReview'))[0], 'error');
plugin.onDetachedFromAbility();
assert.deepEqual(await invoke('isAvailable'), ['success', false]);
assert.equal((await invoke('openStoreListing'))[0], 'error');
assert.deepEqual(await invoke('unknown'), ['notImplemented']);
plugin.onDetachedFromEngine(binding);
assert.equal(handler, null);
console.log('OHOS review: API gating, awaited completion, current bundle listing, errors and detach passed');
