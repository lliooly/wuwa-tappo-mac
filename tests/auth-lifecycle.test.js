import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';

const source = readFileSync(new URL('../dist/Wuwa Tappo.app/Contents/Resources/original/assets/index-CuzHFfJW.js', import.meta.url), 'utf8');
const sessionSource = readFileSync(new URL('../original-adapter/session.js', import.meta.url), 'utf8');
function section(start, end) {
  const a = source.indexOf(start), b = source.indexOf(end, a);
  assert(a >= 0 && b > a, `Missing shipped auth section: ${start}`);
  // vm scripts have no module metadata; only replace the loader's base URL.
  return source.slice(a, b).replaceAll('import.meta.url', '"wuwa://fixture/auth.js"');
}

test('shipped auth errors clear both session values and propagate to another window', async () => {
  for (const code of [10002, 10003]) {
    const stored = { infoToken: { value: 'fixture', expires: Date.now() + 10000 },
      lastLoginTime: { value: 'fixture-time', expires: Date.now() + 10000 } };
    let remote;
    const makeSession = () => {
      const window = { __MACOS_INITIAL_SESSION__: structuredClone(stored), webkit: { messageHandlers: {
        originalSession: { async postMessage({ name, value, days }) {
          assert.equal(value, ''); assert.equal(days, -1);
          delete stored[name]; remote.receive(structuredClone(stored));
        } }
      } } };
      vm.runInNewContext(sessionSource, { window });
      return window.__MACOS_SESSION__;
    };
    remote = makeSession();
    const local = makeSession();
    let logouts = 0;
    const context = vm.createContext({
      setCookie: (...args) => local.set(...args),
      isApiSuccess: value => value === 0 || value === 200,
      // Resolve the module boundary without loading SDK or contacting services.
      __vitePreload: () => Promise.resolve({ logoutAccount() { logouts++; } }),
    });
    vm.runInContext(section('function clearAuthTokens()', 'let renewInFlight=') +
      section('function handleApiCode(', 'function unwrapApiData('), context);
    context.handleApiCode(code);
    assert.equal(local.get('infoToken'), null);
    assert.equal(local.get('lastLoginTime'), null);
    await local.flush();
    assert.equal(remote.get('infoToken'), null);
    assert.equal(remote.get('lastLoginTime'), null);
    assert.deepEqual(stored, {});
    assert.equal(logouts, 1);
  }
});

test('shipped business errors and success codes do not clear the session', () => {
  let clears = 0;
  const context = vm.createContext({ isApiSuccess: value => value === 0 || value === 200,
    clearAuthTokens() { clears++; }, __vitePreload() { throw Error('Unexpected logout'); } });
  vm.runInContext(section('function handleApiCode(', 'function unwrapApiData('), context);
  for (const code of [0, 200, 10001, 30001, 50001]) context.handleApiCode(code);
  assert.equal(clears, 0);
});

test('shipped renewal coalesces requests and only extends expiry after confirmed success', async () => {
  for (const outcome of ['success', 'invalid-data', 'network', 'auth']) {
    let release, calls = 0, extensions = 0;
    const gate = new Promise(resolve => { release = resolve; });
    const context = vm.createContext({
      shouldRenewToken: () => true,
      async refreshToken() {
        calls++; await gate;
        if (outcome === 'network') throw Object.assign(Error('fixture network failure'), { code: -1 });
        if (outcome === 'auth') throw Object.assign(Error('fixture expired session'), { code: 10002 });
        return outcome === 'success';
      },
      unwrapApiData: value => value,
      extendTokenExpireLocally() { extensions++; },
      parseApiErrorCode: error => error.code,
      console: { warn() {} },
    });
    vm.runInContext(section('let renewInFlight=null;', 'const tokenRenewal='), context);
    const first = context.renewTokenIfNeeded(), second = context.renewTokenIfNeeded();
    assert.equal(calls, 1);
    release();
    const results = await Promise.allSettled([first, second]);
    assert.equal(extensions, outcome === 'success' ? 1 : 0);
    for (const result of results) {
      assert.equal(result.status, outcome === 'auth' ? 'rejected' : 'fulfilled');
      if (result.status === 'fulfilled') assert.equal(result.value, outcome === 'success');
      else assert.equal(result.reason.code, 10002);
    }
  }
});
