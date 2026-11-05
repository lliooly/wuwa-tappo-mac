import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';
import vm from 'node:vm';

// Execute the recovered release expressions themselves. Account state is a
// fixture for pure visibility checks; no account service or inventory is used.
const paths = [
  new URL('../recovered/wuwa-tappo-cn-1.0.4/frontend/assets/index-BFg5ADH5.js', import.meta.url),
  new URL('../dist/Wuwa Tappo.app/Contents/Resources/original/assets/index-BFg5ADH5.js', import.meta.url),
];

function section(source, start, end) {
  const first = source.indexOf(start), last = source.indexOf(end, first);
  assert(first >= 0 && last > first, `Original chest source changed: ${start}`);
  return source.slice(first, last);
}

function originalRules(source, values = {}) {
  const constants = source.match(/gr=([^,]+),Ws=([^,]+),Jy=([^,]+),/);
  assert(constants, 'Missing original chest constants');
  const ref = value => ({ value });
  let loginEntries = 0;
  const context = {
    pe: getter => ({ get value() { return getter(); } }),
    A: { isLoggedIn: values.loggedIn ?? true, totalClickCount: values.clicks ?? 0 },
    _t: ref(values.loading ?? false), On: ref(false),
    Bt: ref(values.leftMs ?? 0), Nt: ref(values.rightMs ?? 0),
    Me: ref(values.clicks ?? 0), Cr: ref(values.always ?? false), P: ref(values.hover ?? false),
    Do: ref(0), Lo: ref(0), Bi: ref(false), Hi: ref(false), Ni: ref(false), qi: ref(false),
    Ir: null, Mr: null, performance: { now: () => 100 }, fs: () => 1_000_000,
    Pe: () => false, du: () => {}, Q: () => { loginEntries++; },
    Dm: () => { throw Error('Guest chest attempted a reward request'); },
  };
  const code = `const gr=${constants[1]},Ws=${constants[2]},Jy=${constants[3]};`
    + section(source, 'function lc(e){', 'function $r(e,t){')
    + section(source, 'const Vn=pe(', 'function qh(){')
    + section(source, 'function Ih(e){', 'function dc(){')
    + section(source, 'async function gc(e){', 'function Gn(')
    + `;({snapshot:()=>({left:Zr.value,right:ei.value,leftReady:Vn.value,rightReady:Wn.value,
      actionable:Hh(),duration:gr,minimum:Ws,twoSlots:Jy}),
      remaining:ho,seconds:cc,format:lc,cooldown:Ih,open:gc})`;
  const api = vm.runInNewContext(code, context);
  return { api, context, loginEntries: () => loginEntries };
}

for (const path of paths) {
  const source = readFileSync(path, 'utf8');
  const label = path.pathname.includes('/recovered/') ? 'official recovery' : 'shipped macOS bundle';
  test(`${label}: guest always has two login entries regardless of clicks`, async () => {
    for (const clicks of [0, 999, 1000, 1999, 2000]) {
      const { api, context, loginEntries } = originalRules(source, { loggedIn: false, clicks });
      assert.equal(api.snapshot().left, true);
      assert.equal(api.snapshot().right, true);
      await api.open('left');
      await api.open('right');
      assert.equal(loginEntries(), 2);
      assert.equal(context.A.totalClickCount, clicks);
      assert.equal(context.Ir, null);
      assert.equal(context.Mr, null);
    }
  });
  test(`${label}: logged-in visibility follows character balance and cooldowns`, () => {
    const cases = [
      [{ clicks: 999, always: true, hover: true }, [false, false]],
      [{ clicks: 1000 }, [true, false]],
      [{ clicks: 1999 }, [true, false]],
      [{ clicks: 1000, leftMs: 1000 }, [false, true]],
      [{ clicks: 1000, leftMs: 1000, rightMs: 1000 }, [false, false]],
      [{ clicks: 1000, leftMs: 1000, rightMs: 1000, hover: true }, [false, true]],
      [{ clicks: 2000 }, [true, true]],
      [{ clicks: 2000, leftMs: 1000 }, [false, true]],
      [{ clicks: 2000, leftMs: 1000, rightMs: 1000 }, [false, false]],
      [{ clicks: 2000, leftMs: 1000, rightMs: 1000, hover: true }, [true, true]],
      [{ clicks: 2000, leftMs: 1000, rightMs: 1000, always: true }, [true, true]],
    ];
    for (const [values, expected] of cases) {
      const state = originalRules(source, values).api.snapshot();
      assert.deepEqual([state.left, state.right], expected, JSON.stringify(values));
      assert.equal(state.actionable, (state.left && state.leftReady) || (state.right && state.rightReady));
    }
  });
  test(`${label}: thirty-minute per-slot cooldown and deadline boundaries`, () => {
    const { api, context } = originalRules(source);
    assert.equal(api.snapshot().duration, 1_800_000);
    assert.equal(api.snapshot().minimum, 1000);
    assert.equal(api.snapshot().twoSlots, 2000);
    api.cooldown('left');
    assert.equal(context.Ir, 1_800_100);
    assert.equal(context.Bt.value, 1_800_000);
    assert.equal(context.Nt.value, 0);
    assert.equal(context.Mr, null);
    assert.equal(api.remaining(1_000_001), 1);
    assert.equal(api.remaining(1_000_000), 0);
    assert.equal(api.remaining(999_999), 0);
    for (const invalid of [undefined, null, -1, NaN, Infinity]) assert.equal(api.remaining(invalid), 0);
    assert.equal(api.format(api.seconds(1_800_000)), '30:00');
    assert.equal(api.format(api.seconds(1)), '00:01');
  });
}
