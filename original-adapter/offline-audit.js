window.__OFFLINE_ATLAS_AUDIT__ = async function(expected) {
  const wait = ms => new Promise(resolve => setTimeout(resolve, ms));
  const assert = (condition, message) => { if (!condition) throw Error(message); };
  const until = async (condition, message) => {
    for (let i=0;i<120;i++) { if (condition()) return; await wait(50); }
    throw Error(message);
  };
  const local = window.__OFFLINE_FULL_ATLAS__;
  const state = () => window.__ORIGINAL_DIAGNOSTICS__.panelState;
  const action = payload => window.__TAURI_INTERNALS__.invoke('plugin:event|emit', {event:'cat-panel-action', payload});
  await until(() => state()?.bagList?.length > 800, 'Full inventory was not published to the panel');
  const bag = await local.request('bag');
  assert(state().bagList.length === bag.length, 'Panel inventory differs from bundled catalog');
  assert(!document.querySelector('.tab-btn__icon--room,.tab-btn__icon--exchange'), 'Online navigation is present');
  assert(!window.__MACOS_ONLINE__, 'Offline edition enabled online services');
  let user = await local.request('user');
  if (expected) {
    assert(user.character.id === expected.character, 'Character was not restored');
    assert(user.accessory?.id === expected.accessory, 'Accessory was not restored');
    assert(JSON.stringify(user.emote.map(e=>e.id)) === JSON.stringify(expected.emotes), 'Emotes were not restored');
    assert(bag.find(e=>e.asset_id === expected.favorite)?.is_collect === 1, 'Favorite was not restored');
    assert((await local.request('presets')).length === expected.presetCount, 'Presets were not restored');
    return {status:'passed', restored:true, inventory:bag.length, expected};
  }
  const character = bag.find(e=>e.asset_type === 'character_skin' && e.asset_id !== user.character.id);
  const accessory = bag.find(e=>e.asset_type === 'accessory' && e.role_id === '0');
  const emotes = bag.filter(e=>e.asset_type === 'emote' && e.role_id === '0').slice(0,6);
  assert(character && accessory && emotes.length === 6, 'Missing test choices');
  await action({type:'select-appearance',item:character});
  await until(() => state().userInfo?.character?.id === character.asset_id ||
    state().selectedRoleId === character.asset_name.replace(/\.png$/,''), 'Character selection did not reach panel');
  await action({type:'select-appearance',item:accessory});
  await until(() => state().selectedPartId === accessory.asset_name ||
    state().selectedPartId === accessory.asset_name.replace(/\.png$/,''), 'Accessory selection did not reach panel');
  for (const item of emotes.slice(0,5)) {
    await action({type:'select-appearance',item});
    await until(() => state().selectedEmoteAssetIds.includes(item.asset_id), 'Emote did not equip');
  }
  await action({type:'select-appearance',item:emotes[5]});await wait(150);
  assert(!state().selectedEmoteAssetIds.includes(emotes[5].asset_id), 'Sixth emote bypassed original limit');
  const reversed=emotes.slice(0,5).map(e=>e.asset_id).reverse();
  await action({type:'reorder-emotes',emoteAssetIds:reversed});
  await until(() => JSON.stringify(state().selectedEmoteAssetIds) === JSON.stringify(reversed), 'Emote reorder failed');
  await local.api('favorite',{asset_id:character.asset_id,enabled:true});
  await until(() => state().bagList.find(e=>e.asset_id === character.asset_id)?.is_collect === 1, 'Cross-window favorite refresh failed');
  await action({type:'create-preset'});
  await until(() => state().presetList?.length === 1 && state().presetList[0].preset_id > 0 && !state().presetListLoading, 'Preset creation failed');
  // Verify original delete and apply paths as well as native persistence.
  const preset = state().presetList[0];
  await action({type:'select-appearance',item:accessory});
  await until(() => !state().selectedPartId, 'Accessory did not unequip');
  await action({type:'apply-preset',preset});
  await until(() => !!state().selectedPartId && state().selectedEmoteAssetIds.length === 5, 'Preset did not restore accessory and emotes');
  await action({type:'create-preset'});
  await until(() => state().presetList?.length === 2 && state().presetList.every(p=>p.preset_id > 0) && !state().presetListLoading, 'Second preset creation failed');
  await action({type:'delete-preset',presetId:state().presetList[1].preset_id});
  await until(() => state().presetList?.length === 1, 'Preset deletion failed');
  await document.fonts.ready;await wait(500);
  const broken=[...document.querySelectorAll('img')].filter(img=>img.getAttribute('src') && (!img.complete || !img.naturalWidth)).map(img=>img.src);
  assert(!broken.length, 'Broken original images: '+broken.slice(0,3).join(','));
  user = await local.request('user');
  const result = {character:user.character.id,accessory:user.accessory.id,emotes:user.emote.map(e=>e.id),
    favorite:character.asset_id,presetCount:(await local.request('presets')).length};
  assert(result.character === character.asset_id, 'Local state lost character update');
  assert(!window.__ORIGINAL_DIAGNOSTICS__.blockedNetwork.length, 'Remote fetch was attempted');
  const atlasPage = await window.__ORIGINAL_AUDIT_PAGE__('atlas');
  assert(state().atlasList.length === bag.length, 'Full atlas did not render');
  const settingsPage = await window.__ORIGINAL_AUDIT_PAGE__('setting');
  assert([...document.querySelectorAll('[data-offline-unavailable]')].every(el=>!el.getClientRects().length), 'Online settings are visible');
  document.querySelector('.tab-btn__icon--bag').closest('button').click();await wait(400);
  return {status:'passed',inventory:bag.length,expected:result,fullInventory:true,appearance:true,
    fiveEmoteLimit:true,reorder:true,presets:true,favorites:true,images:true,
    atlasCards:atlasPage.cardCount,settings:settingsPage.localSettings};
};
