import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';
import { webcrypto } from 'node:crypto';

const source = readFileSync(new URL('../original-adapter/socket.js', import.meta.url), 'utf8');
class TestCloseEvent extends Event {
  constructor(type, properties) { super(type); Object.assign(this, properties); }
}
function setup() {
  const calls = [];
  const window = { __MACOS_ONLINE__: true, __MACOS_NATIVE_SOCKET__: true, __ORIGINAL_DIAGNOSTICS__: {},
    webkit: { messageHandlers: { originalSocket: { async postMessage(value) { calls.push(value); } } } } };
  vm.runInNewContext(source, { window, URL, EventTarget, Event, MessageEvent, CloseEvent: TestCloseEvent,
    DOMException, TextEncoder, Uint8Array, ArrayBuffer, Blob, atob, btoa, crypto: webcrypto });
  return { window, calls };
}

test('native transport preserves Socket.IO text, binary ordering, events and close', async () => {
  const { window, calls } = setup();
  const socket = new window.WebSocket('wss://api-mc-wuwatappo.kurogames-global.com/socket.io/?EIO=3&transport=websocket&token=test');
  const id = calls[0].id;
  let opened = 0, received, closed;
  socket.onopen = () => opened++;
  socket.onmessage = event => { received = event.data; };
  socket.onclose = event => { closed = event.code; };
  window.__MACOS_SOCKET_EVENT__(id, {type:'open'});
  assert.equal(opened, 1);
  socket.binaryType = 'arraybuffer';
  window.__MACOS_SOCKET_EVENT__(id, {type:'message',data:'AQID'});
  assert.deepEqual([...new Uint8Array(received)], [1,2,3]);
  socket.send('42["rc"]');
  socket.send(new Uint8Array([9,1,2,8]).subarray(1,3));
  socket.send(new Blob([new Uint8Array([3,4])]));
  socket.close();
  await new Promise(resolve => setImmediate(resolve));
  assert.deepEqual(calls.map(call => call.action), ['open','send','send','send','close']);
  assert.equal(calls[1].text, '42["rc"]');
  assert.equal(calls[2].data, 'AQI=');
  assert.equal(calls[3].data, 'AwQ=');
  window.__MACOS_SOCKET_EVENT__(id, {type:'message',text:'421["ru",{"private":"not recorded"}]'});
  assert.equal(window.__ORIGINAL_DIAGNOSTICS__.socketEventCounts.sent.rc, 1);
  assert.equal(window.__ORIGINAL_DIAGNOSTICS__.socketEventCounts.received.ru, 1);
  assert(!JSON.stringify(window.__ORIGINAL_DIAGNOSTICS__).includes('not recorded'));
  assert.equal(socket.bufferedAmount, 0);
  window.__MACOS_SOCKET_EVENT__(id, {type:'close',code:1000,wasClean:true});
  assert.equal(closed, 1000);
  assert.equal(socket.readyState, socket.CLOSED);
});
