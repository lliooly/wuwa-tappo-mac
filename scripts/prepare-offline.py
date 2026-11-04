#!/usr/bin/env python3
"""Apply declared full-atlas patches to the staged frontend, never the archive."""
import json
from pathlib import Path
import shutil
from urllib.parse import quote

ROOT = Path(__file__).resolve().parents[1]


def prepare(resources):
    target = resources / 'original'
    catalog = json.loads((ROOT.parent / 'wuwa-tappo-assets/data/catalog.json').read_text())['items']
    inventory = []
    appearance = {key: {} for key in ['character_skin', 'accessory', 'emote',
                                     'character_skin_atlas', 'accessory_atlas', 'emote_atlas']}
    asset_map_file = target / 'offline-assets.js'
    asset_map = json.loads(asset_map_file.read_text().split('=', 1)[1].removesuffix(';'))
    for item in catalog:
        kind, identifier = item['type'], item['assetId']
        required = ['atlas', 'image'] + (['head1', 'head2', 'body1', 'body2', 'body3'] if kind == 'character_skin' else [])
        if any(not item['files'].get(field) for field in required):
            raise ValueError(f'Incomplete offline item: {kind}/{identifier}')
        meta = dict(item.get('assetMetadata') or {})
        folder = {'character_skin': 'character', 'accessory': 'accessory', 'emote': 'emote'}[kind]
        # Relative resource paths work in the original URL resolvers and retain full canvases.
        for field in required:
            file = item['files'][field]
            rel = 'library/' + quote(file['path'])
            if not (target / 'library' / file['path']).is_file():
                raise ValueError(f'Missing offline resource: {file["path"]}')
            if field == 'image':
                meta['url'] = rel
            elif field != 'atlas':
                original_layer = meta.get(field) or {}
                meta[field] = {**original_layer, 'url': rel}
                key = item['officialFilename'].removesuffix('.png') + '_' + field[:-1] + '_' + field[-1] + '.png'
                asset_map[f'{folder}/{key}'] = 'wuwa://app/' + rel
        appearance[kind][str(identifier)] = meta
        appearance[kind + '_atlas'][str(item['atlasAssetId'])] = {
            **(item.get('atlasMetadata') or {}), 'height_light_id': identifier,
            'url': 'library/' + quote(item['files']['atlas']['path'])}
        inventory.append({**item['atlasEntry'], 'asset_id': identifier, 'asset_type': kind,
                          'rarity': item['rarity'], 'role_id': str(meta.get('game_role_id') or 0),
                          'metadata': meta})
    # Stable default; never substitute a different character for a missing asset.
    inventory.sort(key=lambda row: (row['asset_name'] != 'role_1501_1001.png', row['asset_id']))
    (target / 'public/offline-inventory.json').write_text(json.dumps(inventory, ensure_ascii=False))
    asset_map_file.write_text('window.__ORIGINAL_ASSET_MAP__=' + json.dumps(asset_map, ensure_ascii=False) + ';')
    (target / 'offline-catalog.js').write_text('window.__OFFLINE_CATALOG__=' + json.dumps(appearance, ensure_ascii=False) + ';')
    shutil.copy2(ROOT / 'original-adapter/offline-full-atlas.js', target / 'offline-full-atlas.js')
    with (target / 'audit.js').open('a') as output:
        output.write('\n' + (ROOT / 'original-adapter/offline-audit.js').read_text())
    manifest_path = target / 'adapter-manifest.json'
    manifest = json.loads(manifest_path.read_text())

    def patch(file, before, after, reason):
        path = target / file
        text = path.read_text()
        if text.count(before) != 1:
            raise ValueError(f'Offline patch drift: {reason} ({text.count(before)})')
        path.write_text(text.replace(before, after))
        manifest['entryPatches'].append({'file': file, 'before': before, 'after': after, 'reason': reason})

    entry = 'assets/index-CuzHFfJW.js'
    api = 'window.__OFFLINE_FULL_ATLAS__.api'
    for function, args, action, values in [
        ('getBagList', '', 'bag', '{}'), ('userInfo', '', 'user', '{}'),
        ('getPresetList', '', 'presets', '{}'), ('updateUserAppearance', 'e', 'appearance', 'e'),
        ('createPreset', 'e', 'create-preset', 'e'), ('deletePreset', 'e', 'delete-preset', '{preset_id:e}'),
        ('favoriteAsset', 'e', 'favorite', '{asset_id:e,enabled:true}'),
        ('unfavoriteAsset', 'e', 'favorite', '{asset_id:e,enabled:false}')
    ]:
        anchor = f'function {function}({args})' + '{'
        patch(entry, anchor, anchor + f'return {api}("{action}",{values});', f'Local {function}')
    for function, args in [('createRoom', ''), ('joinRoom', 'e'), ('openChest', 'e'),
                           ('synthesisAtlas', 'e'), ('synthesisAtlasSame', 'e'), ('redeemUse', 'e'),
                           ('userLogout', 'e')]:
        anchor = f'function {function}({args})' + '{'
        patch(entry, anchor, anchor + 'return Promise.reject(new Error("全解锁离线版不提供该在线功能"));', f'Disable {function}')
    patch(entry, 'async function bootstrap(){', '''async function bootstrap(){
      applyCatalog(buildCatalogMaps(window.__OFFLINE_CATALOG__),"wuwa://app",1);
      await window.__OFFLINE_FULL_ATLAS__.initialize(globalStore);
      ''', 'Initialize local catalog and appearance before mounting')
    patch(entry, 'function buildAssetUrl(e,t){',
          'function buildAssetUrl(e,t){const offline=window.__ORIGINAL_ASSET_MAP__?.[t.replace(/^\\//,"").split("?")[0]];if(offline)return offline;',
          'Always use one public-snapshot source for offline layers including default characters')
    # Catalog already installed synchronously. Never fetch or cache a remote appearance directory.
    patch(entry, 'async function ensureAppearanceAssetCatalog(e){',
          'async function ensureAppearanceAssetCatalog(e){return true;', 'Keep bundled appearance catalog')

    main = 'assets/index-pp8VWaUF.js'
    patch(main, 'async function Xo(e){', '''async function Xo(e){
      L.value="wuwa://app";lc();uc();Ge.value=true;it();return;
      ''', 'Use local assets without activity configuration requests')
    patch(main, 'async function pn(_="unknown"){', 'async function pn(_="unknown"){return;', 'Disable socket connection initialization')
    patch(main, 'async function Zt(_){', 'async function Zt(_){return;', 'Disable waiting for account socket authentication')
    # Main window remains owner of original panel lists; native changes trigger a refresh.
    patch(main, 'function it(){ge.value&&Au(hc())}', '''function it(){ge.value&&Au(hc())}
      window.addEventListener("offline-atlas-changed",()=>{lc();uc();Promise.all([G(),Ot({force:true})]).then(it)});
      ''', 'Refresh appearance, inventory and presets across windows')
    panel = 'assets/index-CiT_jZa7.js'
    patch('assets/switchDisplayMonitor-B50jXMGD.js',
          '{key:"exchange",labelKey:"nav_synthesis"},{key:"room",labelKey:"nav_rooms"},',
          '', 'Remove synthesis and room navigation from offline panels')
    patch(panel, 'Ja={class:"setting-item"}', 'Ja={class:"setting-item offline-unavailable"}',
          'Remove server chest setting')
    # Add semantic attributes at the original handlers so CSS hides exactly these entries.
    for handler in ['Ns', 'Us', 'Ps', 'Vt']:
        anchor = 'onClick:R(' + handler + ',["stop"])'
        patch(panel, anchor, '"data-offline-unavailable":"",' + anchor, 'Hide online settings action ' + handler)
    import re
    # Offline stylesheet and DOM decoration cover lazy-loaded original components.
    css = '''
      .reward-btn,.reward-countdown,.btn-login,.btn-logout,[data-offline-unavailable],
      .offline-unavailable { display:none!important; }
      .offline-edition-label { position:fixed;left:12px;bottom:8px;z-index:10000;
        font:12px sans-serif;color:#ffe3aa;pointer-events:none; }
    '''
    (target / 'offline-full-atlas.css').write_text(css)
    # Inspect semantic image names and original controls as panels mount or locale changes.
    with (target / 'offline-full-atlas.js').open('a') as output:
        output.write('''
document.addEventListener('DOMContentLoaded',()=>{
  const label=document.createElement('div');label.className='offline-edition-label';
  if(window.__ORIGINAL_NATIVE_LABEL__==='panel'){label.textContent='全解锁离线版 · 装扮仅保存在本机';document.body.append(label);}
  const decorate=()=>{
    document.querySelectorAll('[data-offline-unavailable]').forEach(el=>{
      if(el.tagName==='BUTTON'&&el.querySelector('input'))return;
      if(el.closest('.setting-item'))el.closest('.setting-item').classList.add('offline-unavailable');
    });
  };
  new MutationObserver(decorate).observe(document.getElementById('app'),{childList:true,subtree:true});decorate();
});
''')
    html = (target / 'index.html').read_text()
    html = html.replace('<script src="./offline-assets.js"></script>',
                        '<script src="./offline-assets.js"></script><script src="./offline-catalog.js"></script>'
                        '<script src="./offline-full-atlas.js"></script><link rel="stylesheet" href="./offline-full-atlas.css">')
    # Remote sources removed from CSP in addition to native request blocking.
    html = re.sub(r'<meta http-equiv="Content-Security-Policy"[^>]+>',
                  '''<meta http-equiv="Content-Security-Policy" content="default-src 'self' wuwa: data: blob:; script-src 'self' wuwa: 'unsafe-inline' 'unsafe-eval'; style-src 'self' wuwa: 'unsafe-inline'; connect-src 'self' wuwa:; img-src 'self' wuwa: data: blob:; frame-src 'none'; object-src 'none'; base-uri 'self'">''', html)
    (target / 'index.html').write_text(html)
    manifest['variant'] = 'offline-full-atlas'
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2))
