import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';

const source = readFileSync(new URL('../dist/Wuwa Tappo.app/Contents/Resources/original/assets/index-CuzHFfJW.js', import.meta.url), 'utf8');
const start = source.indexOf('function toFiniteNumber(');
const end = source.indexOf('function getPresetList(', start);
assert(start > 0 && end > start);
const normalize = vm.runInNewContext(source.slice(start,end) + ';normalizePresetList');
test('preset string IDs remain server IDs when selecting or deleting a saved preset', () => {
  const rows = normalize([{preset_id:'417',character_asset_id:'12'}, {id:418,character_asset_id:12}]);
  assert.equal(rows[0].preset_id, 417);
  assert.equal(rows[1].preset_id, 418);
});
