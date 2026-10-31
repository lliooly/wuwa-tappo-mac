(() => {
  if (!window.__MACOS_ONLINE__ || !window.__MACOS_NATIVE_SOCKET__) return;
  const sockets = new Map();
  const bridge = value => window.webkit.messageHandlers.originalSocket.postMessage(value);
  const eventCounts = window.__ORIGINAL_DIAGNOSTICS__.socketEventCounts = {sent:{},received:{}};
  const knownEvents = new Set(['cr','rm','rd','rc','re','ru','rj','rl','ro','rs','fd']);
  function recordEvent(direction, text) {
    // Only retain protocol event names and counts, never member IDs or payloads.
    if (typeof text !== 'string') return;
    const match = /^42\d*(\[.*)/s.exec(text);
    if (!match) return;
    try {
      const name = JSON.parse(match[1])[0];
      if (knownEvents.has(name)) eventCounts[direction][name] = (eventCounts[direction][name] || 0) + 1;
    } catch {}
  }
  class MacWebSocket extends EventTarget {
    static CONNECTING = 0; static OPEN = 1; static CLOSING = 2; static CLOSED = 3;
    CONNECTING = 0; OPEN = 1; CLOSING = 2; CLOSED = 3;
    readyState = 0; bufferedAmount = 0; binaryType = 'blob'; extensions = ''; protocol = '';
    onopen = null; onclose = null; onmessage = null; onerror = null;
    #id = crypto.randomUUID();
    #outgoing = Promise.resolve();
    constructor(url, protocols) {
      super();
      const parsed = new URL(url);
      if (parsed.protocol !== 'wss:' || parsed.hostname !== 'api-mc-wuwatappo.kurogames-global.com' || parsed.pathname !== '/socket.io/') {
        throw new DOMException('Unsupported WebSocket endpoint', 'SecurityError');
      }
      if (protocols && (typeof protocols === 'string' ? protocols.length : protocols.length)) {
        throw new DOMException('Socket.IO transport does not use subprotocols', 'SyntaxError');
      }
      this.url = parsed.href;
      this.state = {host:parsed.host,path:parsed.pathname,eio:parsed.searchParams.get('EIO'),transport:'native',status:'connecting'};
      window.__ORIGINAL_DIAGNOSTICS__.socketTransport = this.state;
      sockets.set(this.#id, this);
      bridge({action:'open', id:this.#id, url:this.url}).catch(() => {
        this.receive({type:'error',bridgeError:'Native socket request rejected'}); this.receive({type:'close',code:1006,wasClean:false});
      });
    }
    receive(value) {
      if (this.readyState === 3) return;
      let event;
      if (value.type === 'open') {
        if (this.readyState === 2) return;
        this.readyState = 1; this.protocol = value.protocol || ''; this.state.status = 'open';
        event = new Event('open');
      } else if (value.type === 'message') {
        let data = value.text;
        recordEvent('received', data);
        if (value.data !== undefined) {
          const bytes = Uint8Array.from(atob(value.data), character => character.charCodeAt(0));
          data = this.binaryType === 'arraybuffer' ? bytes.buffer : new Blob([bytes]);
        }
        event = new MessageEvent('message', {data});
      } else if (value.type === 'close') {
        this.readyState = 3; this.state.status = 'closed'; this.state.code = value.code;
        this.state.clean = !!value.wasClean; sockets.delete(this.#id);
        event = new CloseEvent('close', {code:value.code || 1006,reason:value.reason || '',wasClean:!!value.wasClean});
      } else {
        this.state.status = 'error'; this.state.httpStatus = value.httpStatus || 0; this.state.errorCode = value.errorCode || 0;
        if (value.bridgeError) this.state.bridgeError = value.bridgeError;
        event = new Event('error');
      }
      this.dispatchEvent(event); this['on' + event.type]?.call(this, event);
    }
    send(value) {
      if (this.readyState === 0) throw new DOMException('WebSocket is connecting', 'InvalidStateError');
      if (this.readyState !== 1) return;
      const size = typeof value === 'string' ? new TextEncoder().encode(value).length : value.size ?? value.byteLength;
      this.bufferedAmount += size;
      this.#outgoing = this.#outgoing.then(async () => {
        const payload = {action:'send',id:this.#id};
        if (typeof value === 'string') { payload.text = value; recordEvent('sent', value); }
        else {
          const buffer = value instanceof Blob ? await value.arrayBuffer() : value;
          const bytes = ArrayBuffer.isView(buffer) ? new Uint8Array(buffer.buffer,buffer.byteOffset,buffer.byteLength) : new Uint8Array(buffer);
          let binary = ''; for (const byte of bytes) binary += String.fromCharCode(byte);
          payload.data = btoa(binary);
        }
        await bridge(payload);
      }).catch(() => this.receive({type:'error'})).finally(() => {this.bufferedAmount -= size;});
    }
    close(code = 1000, reason = '') {
      if (code !== 1000 && (code < 3000 || code > 4999)) throw new DOMException('Invalid close code','InvalidAccessError');
      if (new TextEncoder().encode(reason).length > 123) throw new DOMException('Close reason is too long','SyntaxError');
      if (this.readyState >= 2) return;
      this.readyState = 2;
      this.#outgoing.then(() => bridge({action:'close',id:this.#id,code,reason})).catch(() => this.receive({type:'close',code:1006,wasClean:false}));
    }
  }
  window.__MACOS_SOCKET_EVENT__ = (id, value) => sockets.get(id)?.receive(value);
  window.WebSocket = MacWebSocket;
})();
