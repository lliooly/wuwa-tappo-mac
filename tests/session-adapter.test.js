import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';

const source = readFileSync(new URL('../original-adapter/session.js', import.meta.url), 'utf8');
function client(postMessage, initial = {}) {
  const window = { __MACOS_INITIAL_SESSION__: initial, webkit: { messageHandlers: { originalSession: { postMessage } } } };
  vm.runInNewContext(source, { window, Date, Set, Number, String, Error, Promise });
  return window.__MACOS_SESSION__;
}

test('session values update synchronously and persist in order before IPC events', async () => {
  const calls = [];
  let release;
  const first = new Promise(resolve => { release = resolve; });
  const session = client(async payload => { calls.push(payload); if (calls.length === 1) await first; });
  session.set('infoToken', 'test-token', 7);
  session.set('lastLoginTime', '123', 7);
  assert.equal(session.get('infoToken'), 'test-token');
  await Promise.resolve();
  assert.equal(calls.length, 1);
  release(); await session.flush();
  assert.deepEqual(calls.map(c => c.name), ['infoToken', 'lastLoginTime']);
  session.set('infoToken', '', -1); await session.flush();
  assert.equal(session.get('infoToken'), null);
});

test('session expiry, native cross-window snapshots and persistence failures', async () => {
  const session = client(async () => { throw Error('Keychain unavailable'); }, { infoToken: { value: 'expired', expires: 1 } });
  assert.equal(session.get('infoToken'), null);
  session.receive({ infoToken: { value: 'other-window', expires: Date.now() + 10000 } });
  assert.equal(session.get('infoToken'), 'other-window');
  session.set('infoToken', 'new', 7);
  await assert.rejects(session.flush(), /could not be saved/);
  assert.throws(() => session.set('unsupported', 'value', 7), /Unsupported/);
});
