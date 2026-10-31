import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';
import vm from 'node:vm';

// Execute the recovered release expressions themselves. Account state is a
// fixture for pure visibility checks; no account service or inventory is used.
const paths = [
  new URL('../recovered/wuwa-tappo-cn-1.0.3/frontend/assets/index-pp8VWaUF.js', import.meta.url),
  new URL('../dist/Wuwa Tappo.app/Contents/Resources/original/assets/index-pp8VWaUF.js', import.meta.url),
];

function section(source, start, end) {
  const first = source.indexOf(start), last = source.indexOf(end, first);
  assert(first >= 0 && last > first, `Original chest source changed: ${start}`);
  return source.slice(first, last);
}

function originalRules(source, values = {}) {
  const constants = source.match(/fr=([^,]+),Ns=([^,]+),Yy=([^,]+),/);
  assert(constants, 'Missing original chest constants');
  const ref = value => ({ value });
  let loginEntries = 0;
  const context = {
    pe: getter => ({ get value() { return getter(); } }),
    R: { isLoggedIn: values.loggedIn ?? true, totalClickCount: values.clicks ?? 0 },
    kt: ref(values.loading ?? false), Fn: ref(false),
    Nt: ref(values.leftMs ?? 0), Ht: ref(values.rightMs ?? 0),
    Re: ref(values.clicks ?? 0), yr: ref(values.always ?? false), T: ref(values.hover ?? false),
    Po: ref(0), To: ref(0), Ei: ref(false), xi: ref(false), Oi: ref(false), Fi: ref(false),
    kr: null, Cr: null, performance: { now: () => 100 }, is: () => 1_000_000,
    Ie: () => false, lu: () => {}, q: () => { loginEntries++; },
    Pm: () => { throw Error('Guest chest attempted a reward request'); },
  };
  const code = `const fr=${constants[1]},Ns=${constants[2]},Yy=${constants[3]};`
    + section(source, 'function rc(e){', 'function Yr(e,t){')
    + section(source, 'const Wn=pe(', 'function Lp(){')
    + section(source, 'function Cp(e){', 'function lc(){')
    + section(source, 'async function pc(e){', 'function Yn(')
    + `;({snapshot:()=>({left:zr.value,right:jr.value,leftReady:Wn.value,rightReady:Gn.value,
      actionable:Dp(),duration:fr,minimum:Ns,twoSlots:Yy}),
      remaining:co,seconds:ic,format:rc,cooldown:Cp,open:pc})`;
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
      assert.equal(context.R.totalClickCount, clicks);
      assert.equal(context.kr, null);
      assert.equal(context.Cr, null);
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
    assert.equal(context.kr, 1_800_100);
    assert.equal(context.Nt.value, 1_800_000);
    assert.equal(context.Ht.value, 0);
    assert.equal(context.Cr, null);
    assert.equal(api.remaining(1_000_001), 1);
    assert.equal(api.remaining(1_000_000), 0);
    assert.equal(api.remaining(999_999), 0);
    for (const invalid of [undefined, null, -1, NaN, Infinity]) assert.equal(api.remaining(invalid), 0);
    assert.equal(api.format(api.seconds(1_800_000)), '30:00');
    assert.equal(api.format(api.seconds(1)), '00:01');
  });
}
