import { invokeHost } from './transport';

export interface MiniAppContext {
  apiVersion: number;
  appId: string;
  version: string;
  userId: string;
  locale: string;
  dark: boolean;
}

async function call<T>(method: string, ...args: unknown[]): Promise<T> {
  const reply = JSON.parse(
    await invokeHost(method, ...args),
  ) as { ok: boolean; data?: T; error?: string };
  if (!reply.ok) throw new Error(reply.error ?? 'storage');
  return reply.data as T;
}

/** API v1. Storage is scoped by deployment, account and app by the host. */
export const miniApp = {
  call,
  context: () => call<MiniAppContext>('context'),
  newId: () => call<string>('newId'),
  async load<T>(): Promise<T | null> {
    const payload = await call<string | null>('load');
    return payload === null ? null : JSON.parse(payload) as T;
  },
  save: (value: unknown) => call<boolean>('save', JSON.stringify(value)),
  request: <T>(name: string, options: {
    query?: Record<string, unknown>; body?: unknown;
  } = {}) => call<T>('request', name, options),
};
