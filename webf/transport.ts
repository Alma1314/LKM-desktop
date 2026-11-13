declare global {
  interface Window {
    webf?: {
      methodChannel: {
        invokeMethod(method: string, ...args: unknown[]): Promise<string>;
      };
    };
  }
}

let nextId = 0;

/** Transport layer only. Both renderers speak the same bridge protocol. */
export function invokeHost(method: string, ...args: unknown[]): Promise<string> {
  if (window.webf) return window.webf.methodChannel.invokeMethod(method, ...args);
  if (window.parent === window) return Promise.reject(new Error('host'));
  const id = ++nextId;
  return new Promise((resolve, reject) => {
    const timeout = setTimeout(() => { cleanup(); reject(new Error('host')); }, 60000);
    const cleanup = () => { clearTimeout(timeout); window.removeEventListener('message', receive); };
    const receive = (event: MessageEvent) => {
      if (event.source !== window.parent || typeof event.data !== 'string') return;
      let message;
      try { message = JSON.parse(event.data); } catch { return; }
      if (message?.channel !== 'lkm-mini-app' || message.type !== 'response'
          || message.id !== id || typeof message.reply !== 'string') return;
      cleanup(); resolve(message.reply);
    };
    window.addEventListener('message', receive);
    // A srcdoc sandbox has an opaque origin. The host validates source; the
    // child accepts replies only from its own parent and matching request ID.
    window.parent.postMessage(JSON.stringify({
      channel: 'lkm-mini-app', type: 'request', id, method, args,
    }), '*');
  });
}
