(() => {
  const callbacks = new Map();
  let nextCallback = 1;
  const listeners = new Map();
  const label = new URL(location.href).searchParams.get('window') || 'main';
  const report = (kind, value) => {
    window.webkit.messageHandlers.originalLog.postMessage({ label, kind, value: String(value).slice(0, 1500) });
  };
  window.__ORIGINAL_DIAGNOSTICS__ = { calls: [], errors: [], blockedNetwork: [] };
  const diagnostics = window.__ORIGINAL_DIAGNOSTICS__;
  diagnostics.clickReportSuccesses = 0;
  window.addEventListener('cat-click-report-success', () => { diagnostics.clickReportSuccesses++; });
  let pendingRoomInput;
  let latestRoomInput, panelStream;
  let clientRoomSequence = 0, mainRoomSequence = 0;
  window.addEventListener('error', event => {
    const text = event.message || `Resource: ${event.target?.src || event.target?.href}`;
    diagnostics.errors.push(text); report('error', text);
  }, true);
  window.addEventListener('unhandledrejection', event => {
    diagnostics.errors.push(String(event.reason)); report('rejection', event.reason);
  });
  const originalConsole = console.warn;
  console.warn = (...args) => { report('warn', args.map(String).join(' ')); originalConsole(...args); };
  const originalError = console.error;
  console.error = (...args) => { const text = args.map(value => value?.stack ? `${String(value)}\n${value.stack}` : String(value)).join(' '); diagnostics.errors.push(text); report('error', text); originalError(...args); };
  window.__ORIGINAL_RECEIVE__ = (event, payload) => {
    if (label === 'main' && event === 'cat-panel-action' && payload?.type === 'set-room-id-input') {
      mainRoomSequence = Number(payload.__macRoomSequence) || 0;
    }
    if (event === 'cat-panel-state' || event === 'cat-panel-room-members-patch') {
      if (label === 'panel' && event === 'cat-panel-state') {
        if (panelStream && panelStream !== payload.streamId) {
          clientRoomSequence = 0; pendingRoomInput = latestRoomInput = undefined;
          diagnostics.authoritativeRoomSequence = 0;
        }
        panelStream = payload.streamId;
      }
      const sequence = Number(payload.__macRoomSequence) || 0;
      diagnostics.roomTrace?.push({kind:'received', event, value:payload.roomIdInput, sequence, pending:pendingRoomInput});
      if (sequence >= (diagnostics.authoritativeRoomSequence || 0)) {
        diagnostics.authoritativeRoomInput = payload.roomIdInput;
        diagnostics.authoritativeRoomSequence = sequence;
      }
      // Both the full snapshot and the separate room patch carry an input value.
      // Preserve newer client text even if an older patch arrives after its ACK.
      if (label === 'panel' && sequence < clientRoomSequence) payload = {...payload, roomIdInput:latestRoomInput};
      else if (label === 'panel') {
        latestRoomInput = payload.roomIdInput;
        pendingRoomInput = undefined;
      }
      diagnostics.pendingRoomInput = pendingRoomInput;
      diagnostics.panelState = event === 'cat-panel-state' ? payload : {...diagnostics.panelState, ...payload};
    }
    for (const [id, listener] of listeners) {
      if (listener.event === event) callbacks.get(listener.handler)?.({ event, id, payload });
    }
  };
  window.__TAURI_EVENT_PLUGIN_INTERNALS__ = { unregisterListener: (_, id) => listeners.delete(id) };
  window.__TAURI_INTERNALS__ = {
    metadata: { currentWindow: { label }, currentWebview: { label } },
    transformCallback(callback, once = false) {
      const id = nextCallback++;
      callbacks.set(id, value => { if (once) callbacks.delete(id); callback(value); });
      return id;
    },
    unregisterCallback: id => callbacks.delete(id),
    convertFileSrc: path => `wuwa://app/${path.replace(/^\/+/, '')}`,
    async invoke(command, args = {}) {
      if (window.__MACOS_ONLINE__) await window.__MACOS_SESSION__.flush();
      diagnostics.calls.push(command);
      if (diagnostics.calls.length > 3000) diagnostics.calls.splice(0, 1000);
      if (command === 'plugin:event|listen') {
        const id = nextCallback++;
        listeners.set(id, { event: args.event, handler: args.handler });
        return id;
      }
      if (command === 'plugin:event|unlisten') { listeners.delete(args.eventId); return; }
      if (label === 'panel' && ['plugin:event|emit', 'plugin:event|emit_to'].includes(command) &&
          args.event === 'cat-panel-action' && args.payload?.type === 'set-room-id-input') {
        pendingRoomInput = String(args.payload.value ?? '');
        latestRoomInput = pendingRoomInput;
        args = {...args, payload:{...args.payload, __macRoomSequence:++clientRoomSequence}};
        diagnostics.roomTrace?.push({kind:'emitted', value:pendingRoomInput, sequence:clientRoomSequence});
        diagnostics.pendingRoomInput = pendingRoomInput;
      }
      if (label === 'main' && ['plugin:event|emit', 'plugin:event|emit_to'].includes(command) &&
          ['cat-panel-state','cat-panel-room-members-patch'].includes(args.event)) {
        args = {...args, payload:{...args.payload, __macRoomSequence:mainRoomSequence}};
      }
      // Tauri IPC serializes Vue reactive proxies. WK's direct object bridge silently drops them.
      try {
        return await window.webkit.messageHandlers.originalInvoke.postMessage({ label, command, args: JSON.parse(JSON.stringify(args)) });
      } catch (error) {
        // Rust's Result<String> rejects with a primitive string. WK wraps the
        // same reply in Error, which breaks original checks such as ==='duplicate'.
        throw error?.message ?? error;
      }
    }
  };
  window.isTauri = true;
  window.__MACOS_DIRECT_MOUSE__ = true;
  if (label === 'login' && !window.__MACOS_ONLINE__) {
    const placeholder = event => {
      if (event.type === 'keydown' && !['Enter', ' '].includes(event.key)) return;
      if (!event.target.closest?.('.login-dialog-button')) return;
      event.preventDefault(); event.stopImmediatePropagation();
      window.__WUWA_ORIGINAL__?.showToast('登录功能暂未接入');
    };
    document.addEventListener('click', placeholder, true);
    document.addEventListener('keydown', placeholder, true);
  }
  // Normal mode retains original fetch/XHR and Socket.IO. Audit mode never
  // reaches account services, even if the user has a saved production session.
  const nativeFetch = window.fetch.bind(window);
  window.fetch = (input, options) => {
    const url = new URL(typeof input === 'string' ? input : input.url, location.href);
    if (url.protocol === 'wuwa:' || window.__MACOS_ONLINE__) return nativeFetch(input, options);
    diagnostics.blockedNetwork.push(url.origin + url.pathname);
    return Promise.reject(new Error('Account/network services are outside the offline macOS port'));
  };
  class OfflineSocket {
    static CONNECTING = 0; static OPEN = 1; static CLOSING = 2; static CLOSED = 3;
    constructor() { throw new Error('Room/account connection is unavailable in offline mode'); }
  }
  if (!window.__MACOS_ONLINE__) window.WebSocket = OfflineSocket;
  else {
    const NativeWebSocket = window.WebSocket;
    window.WebSocket = class extends NativeWebSocket {
      constructor(url, protocols) {
        super(url, protocols);
        const parsed = new URL(url);
        const state = {host:parsed.host, path:parsed.pathname, eio:parsed.searchParams.get('EIO'), status:'connecting'};
        diagnostics.socketTransport = state;
        this.addEventListener('open', () => {state.status='open';});
        this.addEventListener('error', () => {state.status='error';});
        this.addEventListener('close', event => {state.status='closed';state.code=event.code;state.clean=event.wasClean;});
      }
    };
  }
  window.open = () => { report('unsupported', 'External browser requires native open_url'); return null; };
  window.__ORIGINAL_NATIVE_LABEL__ = label;
})();
