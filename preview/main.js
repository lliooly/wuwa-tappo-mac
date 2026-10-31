import { PetAnimation } from '/src/animation/pet-animation.js';
import { findAppearance, resolveLayers, assetUrl } from '/src/assets/appearance.js';
import { createPetView } from '/src/render/pet-view.js';

const status = document.querySelector('#status');
const characterSelect = document.querySelector('#character');
const accessorySelect = document.querySelector('#accessory');
const baseUrl = new URL('/asset-library/', location.href);
const view = createPetView(document.querySelector('#pet'), 1.4);
let animation;
let revision = 0;

function preload(src) {
  return new Promise((resolve, reject) => {
    const img = new Image();
    img.onload = resolve;
    img.onerror = () => reject(new Error(`图片加载失败：${src}`));
    img.src = src;
  });
}

try {
  const response = await fetch(new URL('data/catalog.json', baseUrl));
  if (!response.ok) throw new Error(`素材索引读取失败：${response.status}`);
  const catalog = await response.json();
  for (const [type, select] of [['character_skin', characterSelect], ['accessory', accessorySelect]]) {
    if (type === 'accessory') select.add(new Option('不佩戴', ''));
    for (const item of catalog.items.filter(item => item.type === type)) {
      select.add(new Option(item.displayName ?? item.officialFilename, item.officialFilename));
    }
  }
  characterSelect.value = 'role_1501_1001.png';
  accessorySelect.value = 'accessory_1000.png';
  async function selectAppearance() {
    const current = ++revision;
    animation?.dispose();
    animation = null;
    document.querySelector('#pet').hidden = true;
    status.textContent = '正在加载分层…';
    try {
      const character = findAppearance(catalog, 'character_skin', characterSelect.value);
      const accessory = accessorySelect.value ? findAppearance(catalog, 'accessory', accessorySelect.value) : null;
      const render = state => {
        view.render(resolveLayers({ character, accessory, state, baseUrl }));
        status.textContent = `身体 ${state.body} · 头部 ${state.head}`;
      };
      resolveLayers({ character, accessory, state: { body: 1, head: 1 }, baseUrl });
      await Promise.all([
        ...['body1','body2','body3','head1','head2'].map(field => preload(assetUrl(character, field, baseUrl))),
        ...(accessory ? [preload(assetUrl(accessory, 'image', baseUrl))] : [])
      ]);
      if (current !== revision) return;
      document.querySelector('#pet').hidden = false;
      animation = new PetAnimation({ onChange: render });
      animation.start();
    } catch (error) {
      if (current === revision) status.textContent = error.message;
    }
  }
  characterSelect.addEventListener('change', selectAppearance);
  accessorySelect.addEventListener('change', selectAppearance);
  const control = event => event.target.closest?.('select,input,textarea,button');
  window.addEventListener('keydown', event => { if (!control(event)) animation?.keyDown(event.code); });
  window.addEventListener('keyup', event => animation?.keyUp(event.code));
  window.addEventListener('mousedown', event => { if (!control(event)) animation?.mouseButton('press'); });
  window.addEventListener('mouseup', () => animation?.mouseButton('release'));
  window.addEventListener('blur', () => animation?.resetInput());
  window.addEventListener('pagehide', () => animation?.dispose(), { once: true });
  await selectAppearance();
} catch (error) { status.textContent = error.message; }
