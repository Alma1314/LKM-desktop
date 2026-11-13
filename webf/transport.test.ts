import { afterEach, expect, test, vi } from 'vitest';
import { invokeHost } from './transport';

afterEach(() => { vi.unstubAllGlobals(); vi.useRealTimers(); });

test('browser transport correlates concurrent calls and ignores unrelated sources', async () => {
  const listeners = new Set<(event: {source: unknown; data: string}) => void>();
  const parent = { postMessage: vi.fn() };
  vi.stubGlobal('window', {
    parent, addEventListener: (_: string, listener: typeof listeners extends Set<infer T> ? T : never) => listeners.add(listener),
    removeEventListener: (_: string, listener: typeof listeners extends Set<infer T> ? T : never) => listeners.delete(listener),
  });
  const first = invokeHost('context');
  const second = invokeHost('load');
  const requests = parent.postMessage.mock.calls.map(([data]) => JSON.parse(data as string));
  const respond = (id: number, reply: string, source: unknown = parent) => {
    for (const listener of listeners) listener({ source, data: JSON.stringify({ channel: 'lkm-mini-app', type: 'response', id, reply }) });
  };
  respond(requests[0].id, 'spoofed', {});
  expect(listeners.size).toBe(2);
  respond(requests[1].id, 'stored');
  expect(await second).toBe('stored');
  respond(requests[0].id, 'context');
  expect(await first).toBe('context');
  expect(listeners.size).toBe(0);
});

test('browser requests time out and remove message listeners', async () => {
  vi.useFakeTimers();
  const removeEventListener = vi.fn();
  vi.stubGlobal('window', { parent: { postMessage: vi.fn() }, addEventListener: vi.fn(), removeEventListener });
  const pending = invokeHost('load');
  const rejected = expect(pending).rejects.toThrow('host');
  await vi.advanceTimersByTimeAsync(60000);
  await rejected;
  expect(removeEventListener).toHaveBeenCalledOnce();
});
