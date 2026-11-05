import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';
import vm from 'node:vm';

const source = readFileSync(new URL('../dist/Wuwa Tappo.app/Contents/Resources/original/assets/index-BFg5ADH5.js', import.meta.url), 'utf8');
const start = source.indexOf('let followSystemGameMode=');
const end = source.indexOf('async function Xc(){', start);
assert(start >= 0 && end > start, 'Missing shipped Game Mode adapter');

function fixture(gameMode) {
  const preferences = { gameMode, autoGameModeOnFullscreen: true };
  const effective = { value: gameMode };
  const methods = vm.runInNewContext(source.slice(start, end) + ';({updateSystemGameMode,Fp,Op})', {
    window: { __MACOS_SYSTEM_GAME_MODE__: { enabled: true, active: null }, addEventListener() {} },
    tn: effective, kt: async () => {}, sr: patch => Object.assign(preferences, patch),
    vu: () => {}, jm: () => {}, Et: () => preferences, _a: false,
  });
  return {
    preferences, effective, fullscreen: methods.Op, toggle: methods.Fp,
    system: (active, enabled = true) => methods.updateSystemGameMode({ active, enabled }),
  };
}

test('system Game Mode synchronizes both states regardless of the previous manual setting', () => {
  for (const initial of [false, true]) {
    const mode = fixture(initial);
    mode.system(false);
    assert.equal(mode.effective.value, false);
    assert.equal(mode.preferences.gameMode, false);
    mode.system(true);
    assert.equal(mode.effective.value, true);
    assert.equal(mode.preferences.gameMode, true);
    mode.system(false);
    assert.equal(mode.effective.value, false);
    assert.equal(mode.preferences.gameMode, false);
  }
});

test('following ignores manual and fullscreen changes and waits for an explicit system state', () => {
  const mode = fixture(false);
  mode.system(null);
  mode.fullscreen(true);
  mode.toggle();
  assert.equal(mode.effective.value, false);
  mode.system(true);
  mode.toggle();
  mode.fullscreen(false);
  assert.equal(mode.effective.value, true);
  mode.system(null);
  assert.equal(mode.effective.value, true);
  mode.system(false);
  assert.equal(mode.effective.value, false);
  mode.system(null, false);
  mode.toggle();
  assert.equal(mode.effective.value, true);
});
