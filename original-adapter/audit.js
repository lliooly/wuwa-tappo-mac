window.__ORIGINAL_AUDIT_PAGE__ = async function(key) {
  const wait = ms => new Promise(resolve => setTimeout(resolve, ms));
  const icon = document.querySelector(`.tab-btn__icon--${key}`);
  if (!icon) throw Error(`Missing original page entry: ${key}`);
  icon.closest('button').click();
  await wait(key === 'atlas' ? 1200 : 350);
  for (let n=0; n<60 && document.visibilityState !== 'visible'; n++) await wait(50);
  if (document.visibilityState !== 'visible') throw Error('Original panel is hidden; foreground window required for UI audit');
  await document.fonts.ready;
  const section = document.querySelector('.module-content');
  const names = {bag:'我的预设', atlas:'全部', exchange:'合成', room:'房间', setting:'设置'};
  const text = section?.innerText || '';
  const classes = [...section.querySelectorAll('[class]')].map(el => el.className).filter(name => typeof name === 'string');
  const expectedClass = {bag:'.role-panel', atlas:'.atlas-module', exchange:'.synthesis-panel', room:'.room-module', setting:'.settings-module'}[key];
  if (!section.querySelector(expectedClass)) throw Error(`Original page failed to render: ${key}: ${text}`);
  await Promise.all([...section.querySelectorAll('img')].map(img => img.decode().catch(() => {})));
  const broken = [...section.querySelectorAll('img')].filter(img => img.getAttribute('src') && (!img.complete || !img.naturalWidth)).map(img => img.src);
  if (broken.length) throw Error(`Broken original images: ${broken.slice(0,3).join(',')}`);
  const localSettings = [];
  let nativeErrorCodes;
  let synthesisModes;
  if (key === 'exchange') {
    if (window.__ORIGINAL_DIAGNOSTICS__.panelState?.isLoggedIn) throw Error('Synthesis audit must stay unauthenticated');
    const tabs = [...section.querySelectorAll('.atlas-tab-item')];
    if (tabs.length !== 2) throw Error('Missing original synthesis modes');
    const slots = [];
    try {
      for (const [index, expected] of [[0,10],[1,5]]) {
        tabs[index].click(); await wait(100);
        const count = section.querySelectorAll('.synthesis-item').length;
        if (count !== expected || section.querySelector('.synthesis-item--filled')) throw Error('Original unauthenticated synthesis slots incorrect');
        if (!section.querySelector('.common-btn--disabled')) throw Error('Empty synthesis submission was enabled');
        slots.push(count);
      }
      synthesisModes = {slots, emptySubmissionDisabled:true};
    } finally { tabs[0].click(); await wait(100); }
  }
  let roomInput;
  if (key === 'room') {
    const panelModule = await import('wuwa://app/assets/index-CiT_jZa7.js');
    if (!panelModule.default.setup.toString().includes('roomIdInput:x')) throw Error('Running panel module lacks the current local input echo patch');
    window.__ORIGINAL_DIAGNOSTICS__.roomTrace = [];
    const input = section.querySelector('input');
    if (!input) throw Error('Missing original room ID input');
    const before = input.value;
    const set = value => { input.value = value; input.dispatchEvent(new Event('input',{bubbles:true})); };
    const acknowledged = async expected => {
      for (let n=0; n<60; n++) {
        if (window.__ORIGINAL_DIAGNOSTICS__.authoritativeRoomInput === expected && window.__ORIGINAL_DIAGNOSTICS__.pendingRoomInput === undefined) return;
        await wait(25);
      }
      throw Error('Room input not acknowledged: '+JSON.stringify({expected, authoritative:window.__ORIGINAL_DIAGNOSTICS__.authoritativeRoomInput,
        pending:window.__ORIGINAL_DIAGNOSTICS__.pendingRoomInput, dom:input.value,
        snapshot:window.__ORIGINAL_DIAGNOSTICS__.panelState?.roomIdInput, trace:window.__ORIGINAL_DIAGNOSTICS__.roomTrace}));
    };
    const cadences = [0,5,15,40];
    try {
      for (const delay of cadences) {
        set(''); await acknowledged('');
        for (const character of '123456') {
          const value = input.value+character; set(value); await wait(delay);
          window.__ORIGINAL_DIAGNOSTICS__.roomTrace.push({kind:'typed', value, dom:input.value});
        }
        await acknowledged('123456');
        if (input.value !== '123456') throw Error(`Original room input lost characters at ${delay}ms cadence`);
      }
      roomInput = {typingCadencesMs:cadences, authoritativeAcknowledgement:true};
    } finally { set(before); await acknowledged(before); }
  }
  let categoryTabs;
  if (key === 'bag') {
    const tabs = [...section.querySelectorAll('.atlas-tab-item')];
    const slider = section.querySelector('.atlas-tab-slider');
    if (tabs.length !== 4 || !slider) throw Error('Missing original bag category controls');
    const frames = [slider.style.transform];
    tabs[0].parentElement.dispatchEvent(new MouseEvent('mouseleave'));
    tabs[1].click();
    const started = performance.now();
    let rafTicks = 0, raf;
    const tick = () => { rafTicks++; raf = requestAnimationFrame(tick); };
    raf = requestAnimationFrame(tick);
    // Native mouseleave/blur legitimately cancels a hover. Exercise the selected
    // category instead, and allow rAF throttling without accepting a static jump.
    while (new Set(frames).size < 3 && performance.now()-started < 2500) {
      await wait(16); frames.push(slider.style.transform);
    }
    cancelAnimationFrame(raf);
    if (new Set(frames).size < 3) throw Error('Original category capsule did not animate: '+JSON.stringify({
      frames:[...new Set(frames)],rafTicks,visibility:document.visibilityState,focus:document.hasFocus(),
      connected:slider.isConnected,currentSliderIsSame:document.querySelector('.atlas-tab-slider')===slider,
      rootClass:slider.parentElement.className,width:slider.parentElement.clientWidth,
      tabs:tabs.map(tab=>({left:tab.offsetLeft,width:tab.offsetWidth}))}));
    const counts = [];
    for (const tab of tabs) {
      tab.click(); await wait(100);
      counts.push(section.querySelectorAll('.atlas-item').length);
    }
    tabs[0].click();
    tabs[0].parentElement.dispatchEvent(new MouseEvent('mouseleave'));
    await wait(500);
    if (!counts.slice(1).every(count => count > 0) || counts.slice(1).reduce((sum, count) => sum + count, 0) !== counts[0]) {
      throw Error(`Original bag category filtering failed: ${counts}`);
    }
    categoryTabs = {animatedFrames: new Set(frames).size, counts, restored: true};
  }
  if (key === 'setting') {
    const settings = window.__WUWA_ORIGINAL__;
    const ipc = window.__TAURI_INTERNALS__;
    const shortcuts = await ipc.invoke('get_app_shortcuts');
    const duplicate = {...shortcuts, togglePet:{key:120,modifiers:0}, gameMode:{key:120,modifiers:0}};
    let rejected;
    try { await ipc.invoke('set_app_shortcuts', {config:duplicate}); } catch (error) { rejected = error; }
    if (rejected !== 'duplicate') throw Error('Native shortcut error lost original primitive-string contract');
    nativeErrorCodes = {duplicate:rejected};
    // Exercise only reversible local display options, never autostart or account actions.
    for (const [name, field] of [['禁用拖动','windowPassthrough'], ['鼠标悬停','hoverAutoHide'], ['总是展示宝箱','alwaysShowChest']]) {
      const row = [...section.querySelectorAll('.setting-item')].find(row => row.querySelector('.setting-title')?.textContent.includes(name));
      const input = row?.querySelector('input[type=checkbox]');
      if (!input) throw Error(`Missing original display setting: ${name}`);
      const before = settings.loadDesktopCatSettings()[field];
      input.click(); await wait(100);
      if (settings.loadDesktopCatSettings()[field] === before) throw Error(`Original setting not persisted: ${field}`);
      input.click(); await wait(100);
      if (settings.loadDesktopCatSettings()[field] !== before) throw Error(`Original setting not restored: ${field}`);
      localSettings.push(field);
    }
    for (const [index, field, value] of [[0,'windowOpacity',73],[1,'petScale',125]]) {
      const input = section.querySelectorAll('input[type=range]')[index];
      if (!input) throw Error(`Missing original slider: ${field}`);
      const before = Number(input.value);
      input.value = value; input.dispatchEvent(new Event('input', {bubbles:true})); await wait(250);
      if (settings.loadDesktopCatSettings()[field] !== value) throw Error(`Original slider not persisted: ${field}`);
      input.value = before; input.dispatchEvent(new Event('input', {bubbles:true})); await wait(300);
      if (settings.loadDesktopCatSettings()[field] !== before) throw Error(`Original slider not restored: ${field}`);
      localSettings.push(field);
    }
  }
  return {key,text,classes,cardCount:section.querySelectorAll('.atlas-item').length,
    localSettings, categoryTabs, roomInput, nativeErrorCodes, synthesisModes,
    checkboxes:section.querySelectorAll('input[type=checkbox]').length,
    ranges:section.querySelectorAll('input[type=range]').length,
    errors:[...window.__ORIGINAL_DIAGNOSTICS__.errors],
    blockedRequests:[...window.__ORIGINAL_DIAGNOSTICS__.blockedNetwork]};
};

window.__ORIGINAL_AUDIT_MAIN__ = async function() {
  const wait = ms => new Promise(resolve => setTimeout(resolve, ms));
  const assert = (condition, message) => { if (!condition) throw Error(message); };
  const store = window.__WUWA_ORIGINAL__.globalStore;
  const before = store.localClickCount;
  const frame = () => document.querySelector('.cat-stack__base')?.src;
  const snapshot = window.__ORIGINAL_DIAGNOSTICS__.panelState;
  assert(snapshot && !snapshot.isLoggedIn, 'Layer audit requires unauthenticated state');
  const roles = snapshot.bagList.filter(item => item.asset_type === 'character_skin');
  const originalRole = roles.find(item => item.asset_name.replace(/\.png$/, '') === snapshot.selectedRoleId);
  const otherRole = roles.find(item => item !== originalRole);
  assert(originalRole && otherRole, 'Initial stock requires two original role choices');
  const api = await import('wuwa://app/assets/index-CuzHFfJW.js');
  let restoreRole = false;
  const selectRole = async item => {
    const role = item.asset_name.replace(/\.png$/, '');
    await api.cV('cat-panel-action', {type:'select-appearance', item});
    const started = performance.now();
    while (performance.now()-started < 3000) {
      const head = document.querySelector('.cat-stack__face'), body = document.querySelector('.cat-stack__base');
      if (head?.src.includes(role) && body?.src.includes(role) && head.complete && body.complete && head.naturalWidth && body.naturalWidth) {
        const h = head.getBoundingClientRect(), b = body.getBoundingClientRect();
        assert(h.width > 0 && ['x','y','width','height'].every(key => Math.abs(h[key]-b[key])<.5), 'Head/body canvases are not aligned');
        return {role, head:head.src, body:body.src, headPixels:[head.naturalWidth,head.naturalHeight], bodyPixels:[body.naturalWidth,body.naturalHeight]};
      }
      await wait(25);
    }
    throw Error(`Role layers did not load together: ${role}`);
  };
  try {
    restoreRole = true;
    const switched = await selectRole(otherRole);
    const restored = await selectRole(originalRole);
    restoreRole = false;
    const initial = frame(); assert(initial, 'original body exists');
    window.__ORIGINAL_RECEIVE__('key-press', 'audit-key'); await wait(40);
    const first = frame(); assert(first !== initial, 'press changes original body');
    window.__ORIGINAL_RECEIVE__('key-press', 'audit-key'); await wait(40);
    assert(frame() === first, 'original key-repeat filtering');
    window.__ORIGINAL_RECEIVE__('key-release', 'audit-key'); await wait(30);
    assert(frame() === initial, 'release returns original idle body');
    assert(store.localClickCount === before + 1, 'original release counting');
    window.__ORIGINAL_RECEIVE__('key-press', 'audit-key'); await wait(30);
    assert(frame() !== initial && frame() !== first, 'original alternating hand');
    await wait(230); assert(frame() === initial, 'original 220ms timeout');
    window.__ORIGINAL_RECEIVE__('key-release', 'audit-key');
    const faces = new Set(), accessories = new Set(), changes = [];
    const started = performance.now(); let previous;
    while (performance.now()-started < 6000) {
      const face = document.querySelector('.cat-stack__face')?.src;
      assert(face, 'original head layer exists');
      faces.add(face); accessories.add(document.querySelector('.cat-stack__layer')?.src || '');
      if (face !== previous) { changes.push(performance.now()); previous = face; }
      await wait(20);
    }
    const phases = changes.slice(1).map((time,index) => Math.round(time-changes[index]));
    assert(faces.size === 2 && phases.some(ms => ms >= 180 && ms <= 400), 'original timed blink closes briefly and reopens');
    assert(accessories.size === 1, 'accessory remains an independent static layer during head blink');
    return { bodyFrames: true, repeatFiltering: true, alternating: true, timeout: true, countOnRelease: true,
      roleLayers:{loadedAndAligned:true, samples:[switched,restored]},
      blink: {headFrames:faces.size, measuredPhasesMs:phases, staticAccessory:true} };
  } finally {
    try { if (restoreRole) await selectRole(originalRole); }
    finally { store.setLocalClickCount(before); }
  }
};

window.__ORIGINAL_AUDIT_BUSINESS__ = async function() {
  const wait = ms => new Promise(resolve => setTimeout(resolve, ms));
  const state = () => window.__ORIGINAL_DIAGNOSTICS__.panelState;
  const assert = (condition, message) => { if (!condition) throw Error(message); };
  const until = async (condition, message) => {
    for (let n=0; n<60; n++) { if (condition()) return; await wait(50); }
    throw Error(message);
  };
  const api = await import('wuwa://app/assets/index-CuzHFfJW.js');
  const action = value => api.cV('cat-panel-action', value);
  document.querySelector('.tab-btn__icon--bag').closest('button').click();
  await until(() => state()?.activeTab === 'bag', 'Bag snapshot did not synchronize');
  assert(!state().isLoggedIn, 'Business audit requires original unauthenticated state');
  const before = {role: state().selectedRoleId, part:state().selectedPartId, emotes:[...state().selectedEmoteAssetIds]};
  const bag = state().bagList;
  const emotes = bag.filter(item => item.asset_type === 'emote');
  const click = async item => {
    const needle = item.asset_name.replace(/\.png$/, '');
    const image = [...document.querySelectorAll('.atlas-item img')].find(img => decodeURI(img.src).includes(needle));
    assert(image, `Missing original bag card: ${needle}`);
    image.closest('.atlas-item').click(); await wait(120);
  };
  const same = (a,b) => JSON.stringify(a) === JSON.stringify(b);
  const setEmotes = async target => {
    for (const id of [...state().selectedEmoteAssetIds]) if (!target.includes(id)) await click(emotes.find(item => item.asset_id === id));
    for (const id of target) if (!state().selectedEmoteAssetIds.includes(id)) await click(emotes.find(item => item.asset_id === id));
    await action({type:'reorder-emotes', emoteAssetIds:target});
    await until(() => same(state().selectedEmoteAssetIds, target), 'Emote selection/order did not synchronize');
  };
  const role = bag.find(item => item.asset_type === 'character_skin' && !item.asset_name.startsWith(before.role));
  const originalRole = bag.find(item => item.asset_type === 'character_skin' && item.asset_name.startsWith(before.role));
  const accessory = bag.find(item => item.asset_type === 'accessory');
  try {
    assert(role && originalRole && accessory && emotes.length > 5, 'Initial stock missing expected offline choices');
    await click(role);
    await until(() => state().selectedRoleId === role.asset_name.replace(/\.png$/, ''), 'Original role card did not change desktop appearance');
    await click(originalRole);
    await until(() => state().selectedRoleId === before.role, 'Role did not restore');
    await click(accessory);
    await until(() => state().selectedPartId !== before.part, 'Original accessory card did not toggle');
    await click(accessory);
    await until(() => state().selectedPartId === before.part, 'Accessory did not restore');
    const five = emotes.slice(0,5).map(item => item.asset_id);
    await setEmotes(five);
    await click(emotes[5]);
    assert(same(state().selectedEmoteAssetIds, five), 'Sixth emote bypassed five-slot limit');
    await click(emotes[0]);
    await until(() => state().selectedEmoteAssetIds.length === 4, 'Selected emote did not unequip');
    await click(emotes[5]);
    await until(() => state().selectedEmoteAssetIds.includes(emotes[5].asset_id), 'Vacant emote slot did not equip');
    const reversed = [...state().selectedEmoteAssetIds].reverse();
    await action({type:'reorder-emotes', emoteAssetIds:reversed});
    await until(() => same(state().selectedEmoteAssetIds, reversed), 'Emote reorder did not synchronize');
    await action({type:'reorder-emotes', emoteAssetIds:[reversed[0],reversed[0],...reversed.slice(2)]});
    await wait(150);
    assert(same(state().selectedEmoteAssetIds, reversed), 'Invalid emote reorder was accepted');
    return {roleCard:true, accessoryToggle:true, fiveSlotLimit:true, unequip:true, equip:true, reorder:true, invalidReorderRejected:true};
  } finally {
    if (state().selectedRoleId !== before.role) await click(originalRole);
    if (state().selectedPartId !== before.part) await click(accessory);
    await setEmotes(before.emotes);
    await action({type:'emote-preview-active', active:false});
  }
};

window.__ORIGINAL_AUDIT_EMOTE__ = async function() {
  const wait = ms => new Promise(resolve => setTimeout(resolve, ms));
  const api = await import('wuwa://app/assets/index-CuzHFfJW.js');
  await api.cV('cat-panel-action', {type:'emote-preview-active', active:true});
  try {
    for (let n=0; n<40 && !document.querySelector('.emotion-dot'); n++) await wait(50);
    const buttons = [...document.querySelectorAll('.emotion-dot')];
    if (!buttons.length) throw Error('Original emote fan did not render');
    buttons[0].click(); await wait(50);
    const bubble = document.querySelector('.local-emotion-bubble');
    if (!bubble) throw Error('Original emote button did not create floating bubble');
    const image = bubble.querySelector('img'); await image.decode();
    const initial = getComputedStyle(bubble).transform;
    await wait(250);
    if (getComputedStyle(bubble).transform === initial) throw Error('Original emote bubble did not animate');
    await wait(1000);
    if (document.querySelector('.local-emotion-bubble')) throw Error('Original emote bubble was not removed after animation');
    return {fanButtons:buttons.length, bubbleImageLoaded:true, floatAnimation:true, animationCleanup:true};
  } finally { await api.cV('cat-panel-action', {type:'emote-preview-active', active:false}); }
};
