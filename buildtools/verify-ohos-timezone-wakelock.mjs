import assert from 'node:assert/strict';
import { loadArkTs } from './ohos-test-loader.mjs';

// Exercise the real backends with SDK boundaries stubbed; HAP compilation checks ArkTS types.
const channels = new Map();
class MethodChannel {
  constructor(_, name) { channels.set(name, this); }
  setMethodCallHandler(handler) { this.handler = handler; }
}
let timezoneError = false;
const timezone = loadArkTs(new URL(
  '../packages/flutter_timezone/ohos/src/main/ets/components/plugin/FlutterTimezonePlugin.ets', import.meta.url,
), new Map([
  ['@ohos/flutter_ohos', { MethodChannel }],
  ['@kit.LocalizationKit', { i18n: {
    getTimeZone() {
      if (timezoneError) throw { code: 42, message: 'Timezone unavailable' };
      return { getID: () => 'Asia/Shanghai' };
    },
    TimeZone: { getAvailableIDs: () => ['Asia/Shanghai', 'Etc/UTC'] },
  } }],
])).default;
const binding = { getBinaryMessenger: () => ({}) };
const tz = new timezone();
tz.onAttachedToEngine(binding);
let response;
const result = {
  success: value => { response = ['success', value]; },
  error: (...args) => { response = ['error', ...args]; },
  notImplemented: () => { response = ['notImplemented']; },
};
tz.onMethodCall({ method: 'getLocalTimezone' }, result);
assert.deepEqual(Array.from(response), ['success', 'Asia/Shanghai']);
tz.onMethodCall({ method: 'getAvailableTimezones' }, result);
assert.deepEqual(Array.from(response[1]), ['Asia/Shanghai', 'Etc/UTC']);
timezoneError = true;
tz.onMethodCall({ method: 'getLocalTimezone' }, result);
assert.deepEqual(response, ['error', 'timezone_error', 'Timezone unavailable', 42]);
tz.onMethodCall({ method: 'unknown' }, result);
assert.equal(response[0], 'notImplemented');
tz.onDetachedFromEngine(binding);
assert.equal(channels.get('flutter_timezone').handler, null);

class Buffer {
  bytes = [];
  offset = 0;
  writeUint8(n) { this.bytes.push(n); }
}
let NativeArray = Array;
class StandardMessageCodec {
  writeValue(buffer, value) {
    if (value === null) buffer.writeUint8(0);
    else if (typeof value === 'boolean') buffer.writeUint8(value ? 1 : 2);
    else if (Array.isArray(value)) {
      buffer.writeUint8(12);
      buffer.writeUint8(value.length);
      for (const item of value) this.writeValue(buffer, item);
    } else throw Error('Unexpected codec value');
  }
  readValue(buffer) { return this.readValueOfType(buffer.bytes[buffer.offset++], buffer); }
  readValueOfType(type, buffer) {
    if (type === 0) return null;
    if (type === 1 || type === 2) return type === 1;
    if (type === 12) {
      const count = buffer.bytes[buffer.offset++];
      const list = new NativeArray();
      for (let i = 0; i < count; i++) list.push(this.readValue(buffer));
      return list;
    }
    throw Error('Unexpected codec tag');
  }
}
class BasicMessageChannel {
  constructor(_, name) { channels.set(name, this); }
  setMessageHandler(handler) { this.handler = handler; }
}
const sdk = '@ohos/flutter_ohos/src/main/ets/';
const api = loadArkTs(new URL(
  '../packages/wakelock_plus/ohos/src/main/ets/components/plugin/WakelockApi.ets', import.meta.url,
), new Map([
  [`${sdk}plugin/common/StandardMessageCodec`, StandardMessageCodec],
  [`${sdk}plugin/common/BasicMessageChannel`, BasicMessageChannel],
]));
NativeArray = new api.ToggleMessage(true).toList().constructor;
let keepScreenOn = false;
let fail = false;
let completeToggle;
let delayed = false;
let toggleStarted;
const started = new Promise(resolve => { toggleStarted = resolve; });
const plugin = loadArkTs(new URL(
  '../packages/wakelock_plus/ohos/src/main/ets/components/plugin/WakelockPlugin.ets', import.meta.url,
), new Map([
  ['./WakelockApi', api],
  ['@ohos.window', { getLastWindow: async () => {
    if (fail) throw { code: 1300002, message: 'Window unavailable' };
    return {
      async setWindowKeepScreenOn(enable) {
        if (delayed) await new Promise(resolve => {
          completeToggle = resolve;
          toggleStarted();
        });
        keepScreenOn = enable;
      },
      getWindowProperties: () => ({ isKeepScreenOn: keepScreenOn }),
    };
  } }],
])).default;
const wake = new plugin();
wake.onAttachedToEngine(binding);
const prefix = 'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi';
const codec = api.WakelockApi.getCodec();
async function invoke(method, bytes) {
  const input = new Buffer();
  input.bytes = bytes;
  let reply;
  await channels.get(`${prefix}.${method}`).handler.onMessage(
    codec.readValue(input), { reply: value => { reply = value; } },
  );
  return reply;
}
let reply = await invoke('toggle', [12, 1, 129, 12, 1, 1]);
assert.equal(reply[0], 'no_ability');
wake.onAttachedToAbility({ getAbility: () => ({ context: {} }) });
delayed = true;
let acknowledged = false;
const pending = invoke('toggle', [12, 1, 129, 12, 1, 1]).then(r => { acknowledged = true; return r; });
await started;
assert.equal(acknowledged, false);
assert.equal(keepScreenOn, false);
completeToggle();
assert.equal((await pending)[0], null);
reply = await invoke('isEnabled', [0]);
const output = new Buffer();
codec.writeValue(output, reply);
assert.deepEqual(output.bytes, [12, 1, 130, 12, 1, 1]);
delayed = false;
await invoke('toggle', [12, 1, 129, 12, 1, 2]);
assert.equal(keepScreenOn, false);
fail = true;
reply = await invoke('toggle', [12, 1, 129, 12, 1, 1]);
assert.equal(reply[0], 'window_error_1300002');
assert.match(reply[1], /Window unavailable/);
reply = await invoke('isEnabled', [0]);
assert.equal(reply[0], 'window_error_1300002');
assert.throws(() => api.ToggleMessage.fromList([null]), /Invalid ToggleMessage/);
wake.onDetachedFromAbility();
assert.equal((await invoke('isEnabled', [0]))[0], 'no_ability');
wake.onDetachedFromEngine(binding);
assert.equal(channels.get(`${prefix}.toggle`).handler, null);
assert.equal(channels.get(`${prefix}.isEnabled`).handler, null);
console.log('OHOS timezone + wakelock: identifiers, codec, awaited window operations, errors and detach passed');
