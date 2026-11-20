import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';

// Exercise the expression actually present in the staged original frontend.
const source = readFileSync(new URL('../dist/Wuwa Tappo.app/Contents/Resources/original/assets/index-BGIVWra7.js', import.meta.url), 'utf8');
const start = source.indexOf('Me("div",Rw,[(Ie(!0),Ne(Ar,null,Rr(Array.from(Js(w.value))');
const end = source.indexOf(',128))])', start);
assert(start >= 0 && end > start, 'Desktop counter glyph patch is missing');
const expression = source.slice(start, end + ',128))])'.length);
const render = vm.runInNewContext(`value => { const w={value}; return ${expression}; }`, {
  Me: (tag, props, children) => ({ tag, props, children }),
  Ne: (tag, props, children) => ({ tag, props, children }),
  Ie: () => undefined,
  Rr: (items, fn) => Array.from(items, fn),
  Js: value => value == null ? '' : String(value),
  Ar: 'fragment', Rw: { class: 'text web-bold-font' },
});

test('desktop counter retains the exact value using one inline glyph per character', () => {
  for (const value of [0, 8, 1000001, '9000000+', '１２３', '1😀2']) {
    const node = render(value);
    const glyphs = node.children[0].children;
    assert.equal(glyphs.map(glyph => glyph.children).join(''), String(value));
    assert.equal(glyphs.length, Array.from(String(value)).length);
    glyphs.forEach((glyph, index) => {
      assert.equal(glyph.tag, 'span');
      assert.equal(glyph.props.key, index);
      assert.equal(glyph.props.style, 'display:inline-block');
    });
  }
});
