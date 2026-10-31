import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';

// Execute the method actually shipped in the staged original Pinia store.
const source = readFileSync(new URL('../dist/Wuwa Tappo.app/Contents/Resources/original/assets/index-CuzHFfJW.js', import.meta.url), 'utf8');
const start = source.indexOf('applyClickReportSuccess(e){');
const end = source.indexOf(',applyChestClickConsume(e){', start);
assert(start > 0 && end > start);
const api = vm.runInNewContext('({' + source.slice(start, end) + '})', {
  parseClickCount: value => Math.max(0, Math.floor(Number(value) || 0)),
  isFrozenClickCount: value => value > Number.MAX_SAFE_INTEGER,
});

test('acknowledgement keeps input received after the report snapshot', () => {
  for (const [server, pending, ack, expectedServer, expectedPending] of [
    [100, 4, 102, 102, 2],
    [100, 2, 102, 102, 0],
    [110, 3, 102, 110, 3], // A newer chest/report confirmation already arrived.
  ]) {
    const state = { userInfo: { total_click_count: server }, localClickCount: pending, serverClickSpend: 0,
      get serverClickTotal() { return this.userInfo.total_click_count; },
      get cumulativeClickCount() { return this.serverClickTotal + this.localClickCount; },
      setLocalClickCount(value) { this.localClickCount = value; } };
    api.applyClickReportSuccess.call(state, ack);
    assert.equal(state.userInfo.total_click_count, expectedServer);
    assert.equal(state.localClickCount, expectedPending);
  }
});
