import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { PetAnimation } from '../src/animation/pet-animation.js';
import { findAppearance, resolveLayers } from '../src/assets/appearance.js';

class Clock {
  now = 0;
  sequence = 0;
  tasks = new Map();
  setTimeout(callback, delay) {
    const id = ++this.sequence;
    this.tasks.set(id, { at: this.now + delay, callback });
    return id;
  }
  clearTimeout(id) { this.tasks.delete(id); }
  advance(ms) {
    const end = this.now + ms;
    for (;;) {
      const next = [...this.tasks].filter(([, task]) => task.at <= end)
        .sort((a, b) => a[1].at - b[1].at || a[0] - b[0])[0];
      if (!next) break;
      this.now = next[1].at;
      this.tasks.delete(next[0]);
      next[1].callback();
    }
    this.now = end;
  }
}

function fixture() {
  const clock = new Clock();
  const pet = new PetAnimation({ clock });
  pet.start();
  return { pet, clock };
}

test('single clap, long hold, repeat suppression and persistent alternation', () => {
  const { pet, clock } = fixture();
  assert.equal(pet.keyDown('A'), 'left');
  clock.advance(219);
  assert.equal(pet.body, 2);
  assert.equal(pet.keyDown('A'), null);
  clock.advance(1);
  assert.equal(pet.body, 1);
  assert.equal(pet.keyUp('A'), true);
  assert.equal(pet.keyUp('A'), false);
  assert.equal(pet.keyDown('A'), 'right');
  assert.equal(pet.body, 3);
});

test('new input replaces timeout; any recorded release returns idle', () => {
  const { pet, clock } = fixture();
  pet.keyDown('A');
  clock.advance(150);
  pet.keyDown('B');
  clock.advance(70);
  assert.equal(pet.body, 3);
  pet.keyUp('A');
  assert.equal(pet.body, 1);
  assert.equal(pet.keys.has('B'), true);
  pet.mouseButton('press');
  clock.advance(150); // B's old timeout must not reset the newer clap.
  assert.equal(pet.body, 2);
  clock.advance(70);
  assert.equal(pet.body, 1);
});

test('blink is independent, fixed at 5000/250 ms; start is idempotent', () => {
  const { pet, clock } = fixture();
  pet.start();
  assert.equal(clock.tasks.size, 1);
  clock.advance(4999);
  assert.equal(pet.head, 1);
  pet.clap();
  clock.advance(1);
  assert.deepEqual(pet.state, { body: 2, head: 2 });
  clock.advance(219);
  assert.deepEqual(pet.state, { body: 1, head: 2 });
  clock.advance(31);
  assert.equal(pet.head, 1);
  clock.advance(4750);
  assert.equal(pet.head, 2);
});

test('mouse and gamepad pulse share direction; explicit remote side does not', () => {
  const { pet } = fixture();
  assert.equal(pet.mouseButton('press'), 'left');
  pet.mouseButton('release');
  assert.equal(pet.body, 1);
  assert.equal(pet.clap(), 'right'); // Native gamepad/global-clap adapter calls clap.
  pet.applySide('right');
  assert.equal(pet.clap(), 'left');
});

test('force-update lock suppresses input but preserves blinking', () => {
  const { pet, clock } = fixture();
  pet.locked = true;
  assert.equal(pet.keyDown('A'), null);
  assert.equal(pet.keys.has('A'), true);
  assert.equal(pet.keyUp('A'), false);
  assert.equal(pet.mouseButton('press'), null);
  clock.advance(5000);
  assert.deepEqual(pet.state, { body: 1, head: 2 });
  pet.locked = false;
  assert.equal(pet.clap(), 'left');
});

test('recovery clears stuck keys and disposal prevents future activity', () => {
  const { pet, clock } = fixture();
  pet.keyDown('A');
  pet.resetInput();
  assert.equal(pet.keyUp('A'), false);
  assert.equal(pet.keyDown('A'), 'right');
  pet.dispose();
  assert.equal(clock.tasks.size, 0);
  const state = pet.state;
  clock.advance(10000);
  pet.start();
  pet.clap();
  assert.deepEqual(pet.state, state);
});

const assetBase = new URL('../../wuwa-tappo-assets/', import.meta.url);
const catalog = JSON.parse(readFileSync(new URL('data/catalog.json', assetBase), 'utf8'));
test('real catalog resolves every character layer and accessory without guessing paths', () => {
  for (const character of catalog.items.filter(item => item.type === 'character_skin')) {
    for (const body of [1, 2, 3]) for (const head of [1, 2]) {
      const layers = resolveLayers({ character, state: { body, head }, baseUrl: assetBase });
      assert.deepEqual(layers.map(layer => layer.kind), ['head', 'body']);
      for (const layer of layers) assert.equal(existsSync(new URL(layer.src)), true);
    }
  }
  const character = findAppearance(catalog, 'character_skin', 'role_1501_1001.png');
  for (const accessory of catalog.items.filter(item => item.type === 'accessory')) {
    const layers = resolveLayers({ character, accessory, state: { body: 1, head: 1 }, baseUrl: assetBase });
    assert.equal(layers[2].src, new URL(accessory.files.image.path, assetBase).href);
    assert.equal(existsSync(new URL(layers[2].src)), true);
  }
});

test('offset comes from character only; missing layers fail instead of falling back', () => {
  const original = findAppearance(catalog, 'character_skin', 'role_1501_1001.png');
  const accessory = findAppearance(catalog, 'accessory', 'accessory_1000.png');
  const args = { accessory, state: { body: 1, head: 2 }, baseUrl: assetBase, fallbackOffset: { x: 90, y: 80 } };
  const character = { ...original, assetMetadata: { offset_x: 7, offset_y: -3 } };
  const layers = resolveLayers({ ...args, character });
  assert.deepEqual(layers.map(({ x, y }) => [x, y]), [[0, 0], [0, 0], [7, -3]]);
  assert.equal(resolveLayers({ ...args, character: { ...character, assetMetadata: null } })[2].x, 90);
  const broken = { ...character, files: { ...character.files, body2: null } };
  assert.throws(() => resolveLayers({ ...args, character: broken }), /body2/);
});
