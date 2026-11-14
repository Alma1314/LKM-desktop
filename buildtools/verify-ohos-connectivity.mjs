import assert from 'node:assert/strict';
import { loadArkTs } from './ohos-test-loader.mjs';

// Exercise the actual ArkTS logic with an SDK stub; Hvigor checks the real SDK.
const root = new URL('../packages/connectivity_plus/ohos/src/main/ets/dev/fluttercommunity/plus/connectivity/', import.meta.url);
const tick = () => new Promise(setImmediate);
const subscriptions = [];
let bearers = [1, 4];
let pendingCapabilities;
const sdk = {
  NetBearType: { BEARER_CELLULAR: 0, BEARER_WIFI: 1, BEARER_BLUETOOTH: 2, BEARER_ETHERNET: 3, BEARER_VPN: 4 },
  async getDefaultNet() { return { netId: 1 }; },
  async getNetCapabilities() {
    if (pendingCapabilities) return new Promise(resolve => { pendingCapabilities = resolve; });
    return { bearerTypes: bearers };
  },
  createNetConnection() {
    const subscription = {
      cancelled: false,
      handlers: new Map(),
      on(name, handler) { this.handlers.set(name, handler); },
      register(callback) { callback(); },
      unregister(callback) { this.cancelled = true; callback(); },
    };
    subscriptions.push(subscription);
    return subscription;
  },
};
const modules = new Map([['@ohos.net.connection', { __esModule: true, default: sdk }]]);
function load(name) {
  const exports = loadArkTs(new URL(`${name}.ets`, root), modules);
  modules.set(`./${name}`, exports);
  return exports;
}
const { Connectivity } = load('Connectivity');
const connectivity = new Connectivity();
for (const [input, expected] of [
  [[], ['none']], [[1, 4, 1], ['wifi', 'vpn']], [[0, 2, 3], ['mobile', 'bluetooth', 'ethernet']], [[99], ['other']],
]) {
  const actual = connectivity.hasTransport(input);
  assert(Array.isArray(actual), 'StandardMessageCodec requires a plain array');
  assert.deepEqual([...actual], expected);
}
const { ConnectivityBroadcastReceiver } = load('ConnectivityBroadcastReceiver');
const receiver = new ConnectivityBroadcastReceiver(connectivity);
const events = [];
const sink = { success: data => events.push([...data]), error: (...error) => { throw Error(error.join(':')); } };
receiver.onListen({}, sink);
await tick();
assert.deepEqual(events, [['wifi', 'vpn']]);
bearers = [0];
subscriptions[0].handlers.get('netLost')();
await tick();
assert.deepEqual(events.at(-1), ['mobile'], 'losing one transport must not hide another');
receiver.onCancel();
assert(subscriptions[0].cancelled);
pendingCapabilities = true;
receiver.onListen({}, sink);
await tick();
const before = events.length;
receiver.onCancel();
pendingCapabilities({ bearerTypes: [1] });
await tick();
assert.equal(events.length, before, 'discard async results after cancellation');
assert(subscriptions[1].cancelled);
console.log('OHOS connectivity transport lists, codec arrays and subscription cleanup passed.');
