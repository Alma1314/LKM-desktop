import type { Bridge } from "./workspace";
import { miniApp } from "../sdk";

export const hostBridge: Bridge = {
  async call<T>(method: string, ...args: unknown[]): Promise<T> {
    if (method === 'pull') return miniApp.request<T>(`${args[0]}.pull`, {
      query: args[1] == null ? {} : { since: args[1] },
    });
    if (method === 'push') return miniApp.request<T>(`${args[0]}.push`, {
      body: { upserts: args[1], deletes: args[2] },
    });
    return miniApp.call<T>(method, ...args);
  },
};
