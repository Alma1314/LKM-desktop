import { afterEach, expect, test, vi } from 'vitest';
import { miniApp } from './sdk';
import { hostBridge } from './starhope/bridge';

afterEach(() => vi.unstubAllGlobals());

test('SDK serializes snapshots and propagates host failures without losing edits', async () => {
  const invokeMethod = vi.fn().mockResolvedValue(JSON.stringify({ ok: true, data: true }));
  vi.stubGlobal('window', { webf: { methodChannel: { invokeMethod } } });
  await miniApp.save([{ text: 'offline note' }]);
  expect(invokeMethod).toHaveBeenCalledWith('save', '[{"text":"offline note"}]');
  invokeMethod.mockResolvedValue(JSON.stringify({ ok: true, data: '[{"text":"offline note"}]' }));
  expect(await miniApp.load()).toEqual([{ text: 'offline note' }]);
  invokeMethod.mockResolvedValue(JSON.stringify({ ok: true, data: null }));
  expect(await miniApp.load()).toBeNull();
  invokeMethod.mockResolvedValue(JSON.stringify({ ok: false, error: 'session' }));
  await expect(miniApp.save([])).rejects.toThrow('session');
});

test('StarHope sync uses the same named request API as other mini apps', async () => {
  const invokeMethod = vi.fn().mockResolvedValue(JSON.stringify({ ok: true, data: {} }));
  vi.stubGlobal('window', { webf: { methodChannel: { invokeMethod } } });
  await hostBridge.call('pull', 'questions', '2026-11-13T00:00:00Z');
  expect(invokeMethod).toHaveBeenLastCalledWith('request', 'questions.pull', { query: { since: '2026-11-13T00:00:00Z' } });
  await hostBridge.call('push', 'sessions', [{ id: 'session-1' }], ['deleted']);
  expect(invokeMethod).toHaveBeenLastCalledWith('request', 'sessions.push', { body: { upserts: [{ id: 'session-1' }], deletes: ['deleted'] } });
});
