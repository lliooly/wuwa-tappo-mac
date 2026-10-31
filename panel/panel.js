(() => {
  'use strict';
  const data = window.PANEL_DATA;
  const root = document.querySelector('#panel');
  const ui = name => `../assets/界面/原版/${name}.png`;
  const asset = path => `../${path}`;
  const bridge = (type) => window.webkit?.messageHandlers.panel.postMessage({ type });
  let page = 'bag', filter = 'all', character = data.items[0];
  let accessory = data.items.find(item => item.type === 'accessory');
  let emotes = data.items.filter(item => item.type === 'emote').slice(0, 5);
  let noticeTimer;
  const loginOverlay = document.querySelector('#login-overlay');
  let loginReturnFocus;
  function openLogin() {
    loginReturnFocus = document.activeElement;
    document.querySelector('#login-status').textContent = '';
    loginOverlay.hidden = false;
    document.querySelector('.rail').inert = true;
    document.querySelector('main').inert = true;
    document.querySelector('.login-card').focus({ preventScroll: true });
  }
  function closeLogin() {
    loginOverlay.hidden = true;
    document.querySelector('.rail').inert = false;
    document.querySelector('main').inert = false;
    loginReturnFocus?.focus({ preventScroll: true });
  }
  const labels = { bag: '背包', atlas: '图鉴', synthesis: '合成', rooms: '联机', settings: '设置' };
  const icons = { character_skin: 'character', accessory: 'accessory', emote: 'emote' };
  const descriptions = {
    atlas: '角色、配件和表情图鉴将在这里展示。',
    synthesis: '收集物合成将在这里接入，当前不会消耗物品。',
    rooms: '创建房间、加入房间与好友列表将在这里接入。',
    settings: '账号、外观、输入监听和应用选项将在这里接入。'
  };
  function notice(text) {
    clearTimeout(noticeTimer);
    const out = document.querySelector('#notice'); out.textContent = text; out.classList.add('visible');
    noticeTimer = setTimeout(() => out.classList.remove('visible'), 2400);
  }
  function resize() {
    const width = root.classList.contains('collapsed') ? 958 : 1100;
    const scale = Math.min(innerWidth / width, innerHeight / 756);
    root.style.width = `${width}px`; root.style.transform = `scale(${scale})`;
    root.style.left = `${(innerWidth - width * scale) / 2}px`;
    root.style.top = `${(innerHeight - 756 * scale) / 2}px`;
  }
  function updateNav() {
    for (const button of document.querySelectorAll('[data-page]')) {
      const selected = button.dataset.page === page;
      button.classList.toggle('active', selected);
      button.setAttribute('aria-current', selected ? 'page' : 'false');
      const icon = button.querySelector('i');
      icon.style.backgroundImage = `url('${ui(`nav-${icon.dataset.icon}${selected ? '-active' : ''}`)}')`;
    }
  }
  function showPage(next) {
    page = next; updateNav(); document.title = `Wuwa Tappo · ${labels[page]}`;
    document.querySelector('#bag-page').hidden = page !== 'bag';
    document.querySelector('#placeholder-page').hidden = page === 'bag';
    if (page !== 'bag') {
      document.querySelector('#placeholder-title').textContent = labels[page];
      document.querySelector('#placeholder-description').textContent = descriptions[page];
      const nav = document.querySelector(`[data-page="${page}"] i`).dataset.icon;
      document.querySelector('#placeholder-icon').src = ui(`nav-${nav}-active`);
    }
  }
  function preview() {
    const container = document.querySelector('#preview-character'); container.replaceChildren();
    // Same source group for both head and body; accessory uses worn image and character offset.
    for (const key of ['head1', 'body1']) {
      const img = new Image(); img.className = 'layer'; img.alt = ''; img.src = asset(character.files[key]); container.append(img);
    }
    if (accessory) {
      const img = new Image(); img.className = 'layer'; img.alt = ''; img.src = asset(accessory.files.image);
      img.style.marginLeft = `${(character.offsetX || 0) * 1.2}px`;
      img.style.marginBottom = `${-(character.offsetY || 0) * 1.2}px`; container.append(img);
    }
    const slots = document.querySelector('#emote-slots'); slots.replaceChildren();
    emotes.forEach((item, index) => {
      const button = document.createElement('button'); button.className = 'slot';
      button.style.backgroundImage = `url('${ui(`preview-emote-${index + 1}`)}')`;
      button.title = item.name; button.setAttribute('aria-label', `表情位 ${index + 1}：${item.name}`);
      const img = new Image(); img.src = asset(item.files.image); img.alt = ''; button.append(img);
      button.onclick = () => notice(`表情位 ${index + 1}：${item.name}`); slots.append(button);
    });
  }
  function selected(item) {
    return item.id === character.id || item.id === accessory?.id || emotes.some(emote => emote.id === item.id);
  }
  function renderItems() {
    const list = document.querySelector('#items'); list.replaceChildren();
    for (const item of data.items.filter(item => filter === 'all' || item.type === filter)) {
      const button = document.createElement('button'); button.className = `card${selected(item) ? ' selected' : ''}`;
      button.dataset.type = item.type; button.title = `${item.name} · 点击预览`; button.setAttribute('aria-pressed', String(selected(item)));
      const thumb = document.createElement('span'); thumb.className = 'thumb';
      const img = new Image(); img.src = asset(item.files.atlas); img.alt = ''; thumb.append(img);
      const name = document.createElement('span'); name.className = 'name'; name.textContent = item.name;
      const icon = document.createElement('span'); icon.className = 'type-icon'; icon.style.backgroundImage = `url('${ui(`type-icon-${icons[item.type]}`)}')`;
      button.append(thumb, name, icon);
      button.onclick = () => {
        if (item.type === 'character_skin') character = item;
        else if (item.type === 'accessory') accessory = accessory?.id === item.id ? null : item;
        else {
          if (emotes.some(emote => emote.id === item.id)) { notice('这个表情已在预览槽位中'); return; }
          emotes = [...emotes.slice(0, 4), item];
        }
        preview(); renderItems();
      };
      list.append(button);
    }
  }
  for (let index = 0; index < 5; index++) {
    const button = document.createElement('button'); button.className = 'preset';
    button.setAttribute('aria-label', `预设位 ${index + 1}，登录后使用`);
    button.onclick = openLogin;
    document.querySelector('#preset-list').append(button);
  }
  document.querySelectorAll('[data-page]').forEach(button => button.onclick = () => showPage(button.dataset.page));
  const typeTabs = new OriginalTypeTabs(document.querySelector('.filters'), next => {
    filter = next;
    document.querySelector('#items').scrollTop = 0;
    renderItems();
  });
  document.querySelector('.filters').addEventListener('keydown', event => {
    const index = [...document.querySelectorAll('[data-filter]')].indexOf(event.target);
    if (index < 0) return;
    let next;
    if (event.key === 'ArrowRight') next = (index + 1) % 4;
    if (event.key === 'ArrowLeft') next = (index + 3) % 4;
    if (event.key === 'Home') next = 0;
    if (event.key === 'End') next = 3;
    if (next === undefined) return;
    event.preventDefault(); typeTabs.hover = null; typeTabs.select(next); typeTabs.buttons[next].focus();
  });
  document.querySelector('#login-close').onclick = closeLogin;
  for (const [id, label] of [['login-passport', '通行证登录'], ['login-uid', '游戏UID登录']]) {
    document.querySelector(`#${id}`).onclick = () => {
      document.querySelector('#login-status').textContent = `${label}尚未接入，当前不会提交账号信息。`;
    };
  }
  document.querySelector('#collapse i').style.backgroundImage = `url('${ui('nav-shrink')}')`;
  document.querySelector('#collapse').onclick = () => {
    root.classList.toggle('collapsed');
    document.querySelector('#collapse').setAttribute('aria-expanded', String(!root.classList.contains('collapsed'))); resize();
  };
  document.querySelector('#close').onclick = () => bridge('close');
  document.querySelector('#return-bag').onclick = () => showPage('bag');
  document.querySelectorAll('.drag-region').forEach(region => region.onmousedown = event => { if (event.button === 0) bridge('drag'); });
  document.addEventListener('keydown', event => {
    if (!loginOverlay.hidden) {
      if (event.key === 'Escape') { event.preventDefault(); event.stopPropagation(); closeLogin(); }
      if (event.key === 'Tab') {
        const controls = [...loginOverlay.querySelectorAll('button')];
        const index = controls.indexOf(document.activeElement);
        if (event.shiftKey && index <= 0) { event.preventDefault(); controls.at(-1).focus(); }
        else if (!event.shiftKey && index === controls.length - 1) { event.preventDefault(); controls[0].focus(); }
      }
    } else if (event.key === 'Escape') bridge('close');
  });
  document.addEventListener('contextmenu', event => event.preventDefault());
  document.addEventListener('error', event => {
    if (event.target instanceof HTMLImageElement) notice('素材加载失败，请重新构建应用');
  }, true);
  window.addEventListener('resize', resize);
  window.panelTest = {
    async run() {
      const assert = (condition, message) => { if (!condition) throw Error(message); };
      assert(document.querySelectorAll('.card').length === 12, 'default items');
      assert(document.querySelectorAll('.slot').length === 5, 'emote slots');
      assert(document.querySelectorAll('.preset').length === 5, 'preset placeholders');
      document.querySelector('.preset').click();
      assert(!loginOverlay.hidden, 'logged-out preset opens login dialog');
      document.querySelector('#login-uid').click();
      assert(document.querySelector('#login-status').textContent.includes('尚未接入'), 'login does not claim success');
      document.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true }));
      assert(loginOverlay.hidden && !document.querySelector('main').inert, 'escape closes dialog only');
      for (const next of ['atlas', 'synthesis', 'rooms', 'settings']) {
        showPage(next); assert(!document.querySelector('#placeholder-page').hidden, `placeholder ${next}`);
      }
      showPage('bag');
      document.querySelector('[data-filter=character_skin]').click();
      assert(document.querySelectorAll('.card').length === 2, 'character filter');
      typeTabs.hover = null;
      typeTabs.move();
      await new Promise(resolve => setTimeout(resolve, 850));
      assert(!typeTabs.motion, 'slider animation settles');
      const target = typeTabs.buttons[typeTabs.selected];
      assert(Math.abs(typeTabs.center - target.offsetLeft - target.offsetWidth / 2) < 0.5, 'slider reaches selected tab');
      typeTabs.buttons[3].dispatchEvent(new MouseEvent('mouseenter'));
      assert(filter === 'character_skin' && typeTabs.hover === 3, 'hover previews without filtering');
      typeTabs.leave();
      document.querySelectorAll('.card')[1].click();
      assert(character.id === data.items[1].id, 'character preview');
      document.querySelector('[data-filter=accessory]').click();
      assert(document.querySelectorAll('.card').length === 1, 'accessory filter');
      document.querySelector('[data-filter=emote]').click();
      assert(document.querySelectorAll('.card').length === 9, 'emote filter');
      document.querySelector('[data-filter=all]').click();
      character = data.items[0]; preview(); renderItems();
      typeTabs.hover = null; typeTabs.move(true); typeTabs.labels();
      await Promise.all([...document.images].filter(img => img.getAttribute('src')).map(img => img.decode()));
      assert([...document.images].filter(img => img.getAttribute('src')).every(img => img.complete && img.naturalWidth > 0), 'loaded images');
      return 'PASS: login dialog and escape, original slider travel/settle/hover, navigation, filters, images';
    },
    showLogin() { openLogin(); }
  };
  updateNav(); preview(); renderItems(); resize();
})();
