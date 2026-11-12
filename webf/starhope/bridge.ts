import type { Bridge } from "./workspace";

declare global {
  interface Window {
    webf?: {
      methodChannel: {
        invokeMethod(method: string, ...args: unknown[]): Promise<string>;
      };
    };
  }
}

export const hostBridge: Bridge = {
  async call<T>(method: string, ...args: unknown[]): Promise<T> {
    if (!window.webf) throw new Error("host");
    const reply = JSON.parse(
      await window.webf.methodChannel.invokeMethod(method, ...args),
    ) as {
      ok: boolean;
      data?: T;
      error?: string;
    };
    if (!reply.ok) throw new Error(reply.error ?? "sync");
    return reply.data as T;
  },
};
