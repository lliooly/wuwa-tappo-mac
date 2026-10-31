#!/usr/bin/env python3
"""Stage recovered release assets without modifying the recovery archive."""
import hashlib
import json
from pathlib import Path
import re
import shutil

ROOT = Path(__file__).resolve().parents[1]


def prepare(resources):
    source = ROOT / 'recovered/wuwa-tappo-cn-1.0.2/frontend'
    recovery = json.loads((source.parent / 'manifest.json').read_text())
    archived = {item['path'].lstrip('/'): item['sha256'] for item in recovery['resources']}
    actual = {str(path.relative_to(source)): hashlib.sha256(path.read_bytes()).hexdigest()
              for path in source.rglob('*') if path.is_file()}
    if actual != archived:
        raise ValueError('Recovered frontend differs from the original extraction manifest')
    target = resources / 'original'
    shutil.copytree(source, target)
    html = (target / 'index.html').read_text()
    # HTTPS official services are available in normal mode; audit mode stays offline.
    html = html.replace('<meta charset="UTF-8" />', '''<meta charset="UTF-8" />
    <meta http-equiv="Content-Security-Policy" content="default-src 'self' wuwa: data: blob:; script-src 'self' wuwa: 'unsafe-inline' 'unsafe-eval' https://*.kurogame.com https://*.kurogames.com https://*.kurogames-global.com; style-src 'self' wuwa: 'unsafe-inline' https://*.kurogame.com https://*.kurogames.com; connect-src 'self' wuwa: https://*.kurogame.com https://*.kurogames.com https://*.kurogames-global.com wss://api-mc-wuwatappo.kurogames-global.com; img-src 'self' wuwa: data: blob: https:; frame-src https://*.kurogame.com https://*.kurogames.com; object-src 'none'; base-uri 'self'">''')
    html = html.replace('<div id="app"></div>', '<div id="app"></div><script src="./offline-assets.js"></script>')
    (target / 'index.html').write_text(html)
    entry = target / 'assets/index-CuzHFfJW.js'
    original = entry.read_text()
    staged = original
    patches = []

    def replace(before, after, reason):
        nonlocal staged
        if staged.count(before) != 1:
            raise ValueError(f'Original adapter patch drift: {reason}')
        staged = staged.replace(before, after)
        patches.append({'reason': reason, 'before': before, 'after': after})

    replace('loaderModule.init(kurodataConfig);window.kurodata=loaderModule;initTrackCommonProps();initFrontendAlertReporting();',
            'window.kurodata=macOSTracking;', 'Disable external analytics and diagnostics initialization')
    members = ['track', 'setSuperProperties', 'flush', 'getDeviceId']
    for member in members:
        before = 'loaderModule.' + member
        count = staged.count(before)
        if count == 0:
            raise ValueError(f'Telemetry adapter drift: {member}')
        staged = staged.replace(before, 'macOSTracking.' + member)
        patches.append({'reason': 'Disable outbound telemetry member', 'member': member, 'count': count})
    staged = 'const macOSTracking={track(){},setSuperProperties(){},flush(){return Promise.resolve()},getDeviceId(){return ""}};\n' + staged
    replace('isdkSrc="//pro-cdn-sdk.kurogame.com/pro/web-sdk/1.x/kr-sdk.js"',
            'isdkSrc="https://pro-cdn-sdk.kurogame.com/pro/web-sdk/1.x/kr-sdk.js"',
            'Use HTTPS SDK script instead of inheriting custom wuwa scheme')
    replace('isdkCss="//pro-cdn-sdk.kurogame.com/pro/web-sdk/1.x/style.css"',
            'isdkCss="https://pro-cdn-sdk.kurogame.com/pro/web-sdk/1.x/style.css"',
            'Use HTTPS SDK stylesheet instead of inheriting custom wuwa scheme')
    replace('function getDictionaryAssetsHost(){const e=normalizeAssetsHost(readStoredDictionaryAssetsHost());return e&&e!==dictionaryAssetsHost&&(dictionaryAssetsHost=e),dictionaryAssetsHost}',
            'function getDictionaryAssetsHost(){if(!window.__MACOS_ONLINE__)return "wuwa://app/public";const e=normalizeAssetsHost(readStoredDictionaryAssetsHost());return e&&e!==dictionaryAssetsHost&&(dictionaryAssetsHost=e),dictionaryAssetsHost||"wuwa://app/public"}', 'Use live dictionary host with archived startup/offline fallback')
    replace('function shouldDeferRemoteDictionary(){return networkSnapshot.value.status==="offline"||networkSnapshot.value.status==="reconnecting"||networkSnapshot.value.status==="degraded"}',
            'function shouldDeferRemoteDictionary(){return window.__MACOS_ONLINE__&&(networkSnapshot.value.status==="offline"||networkSnapshot.value.status==="reconnecting"||networkSnapshot.value.status==="degraded")}', 'Respect network gate only in online mode')
    replace('function atlas(){const e={loading:!0,reload:!0};return jsonpClient.get("api/common/atlas",{},e)}',
            'function atlas(){const local=()=>fetch("wuwa://app/public/atlas.json").then(r=>r.json());if(!window.__MACOS_ONLINE__)return local();return jsonpClient.get("api/common/atlas",{},{loading:!0,reload:!0}).catch(error=>{if(isNetworkApiError(error))return local();throw error})}', 'Use live public atlas and archived network-error fallback')
    network_start = staged[staged.index('function startNetworkMonitoring(){'):staged.index('function stopNetworkMonitoring(){')]
    replace(network_start, network_start.replace('function startNetworkMonitoring(){', 'function startNetworkMonitoring(){if(!window.__MACOS_ONLINE__){if(!started){started=true;setSnapshot({status:"offline",reason:"macos-local-only",retryAttempt:0})}return}'),
            'Preserve original network monitor with explicit offline audit mode')
    replace('function isAppUpdaterEnabled(){if(!isTauriRuntime())return!1;const e="true".toLowerCase();return e!=="false"&&e!=="0"}',
            'function isAppUpdaterEnabled(){return false}', 'Windows updater cannot install into the macOS bundle; do not claim an update check succeeded')
    replace('function buildAssetUrl(e,t){const n=',
            'function buildAssetUrl(e,t){const local=window.__ORIGINAL_ASSET_MAP__?.[t.replace(/^\\//,"").split("?")[0]];if(local&&!(isLocalRoleAssetsHost(e)&&resolveLocalRoleAssetUrl(t)))return local;const n=',
            'Resolve archived assets by explicit catalog mapping before original local fallback')
    # Expose original state and router only for native integration checks, no duplicated Vue implementation.
    replace('bootstrap();export{',
            'window.__WUWA_ORIGINAL__={router,globalStore,loadDesktopCatSettings,persistDesktopCatSettings,showToast};bootstrap();export{',
            'Expose actual original router/store for integration verification')
    # Preserve the release's synchronous token API, backed by the native Keychain.
    cookie_start = staged.index('getCookie=e=>{const t=`kuro_${e}=`')
    cookie_end = staged.index(',throttle$1=', cookie_start)
    replace(staged[cookie_start:cookie_end],
            'getCookie=e=>window.__MACOS_SESSION__.get(e),setCookie=(e,t,n)=>window.__MACOS_SESSION__.set(e,t,n)',
            'Adapt Secure cookies unsupported by custom WKURLScheme to shared Keychain session')
    replace('applyClickReportSuccess(e){const t=parseClickCount(e);this.userInfo&&(this.userInfo={...this.userInfo,total_click_count:t}),this.setLocalClickCount(0),this.serverClickSpend=0}',
            'applyClickReportSuccess(e){const t=parseClickCount(e),n=this.cumulativeClickCount,s=Math.max(this.serverClickTotal,t);this.userInfo&&(this.userInfo={...this.userInfo,total_click_count:s}),this.setLocalClickCount(isFrozenClickCount(s)?0:Math.max(0,n-s)),this.serverClickSpend=0}',
            'Keep clicks received while a report is in flight and never roll back a newer confirmed total')
    replace('r=o.preset_id??o.id,i=toFiniteNumber(o.character_asset_id)',
            'r=toFiniteNumber(o.preset_id??o.id),i=toFiniteNumber(o.character_asset_id)',
            'Preserve numeric preset IDs encoded as strings instead of replacing them with list positions')
    entry.write_text(staged)
    main_file = target / 'assets/index-pp8VWaUF.js'
    main_text = main_file.read_text()
    mouse_before = 'async function Xc(e,t,o,l,f){'
    if main_text.count(mouse_before) != 1:
        raise ValueError('Original pointer dispatch patch drift')
    main_text = main_text.replace(mouse_before, mouse_before + 'if(window.__MACOS_DIRECT_MOUSE__){const hit=Wt(o,l);if(!hit||!document.elementFromPoint(hit.x,hit.y)?.closest("[data-room-cat-id]"))return;}')
    reset_before = 'const qr=new Set,va=new Set;'
    if main_text.count(reset_before) != 1:
        raise ValueError('Original key-state reset patch drift')
    main_text = main_text.replace(reset_before, reset_before + 'window.__MACOS_RESET_INPUT__=()=>{qr.clear();va.clear();Zd()};')
    main_file.write_text(main_text)
    patches.append({'reason': 'Recover key state after permission loss or sleep without inventing click counts', 'file': main_file.name, 'before': reset_before})
    patches.append({'reason': 'Use actual WK events for local controls and retain native-only remote member gestures', 'file': main_file.name, 'before': mouse_before})
    panel_file = target / 'assets/index-CiT_jZa7.js'
    panel_text = panel_file.read_text()
    input_before = 'set:x=>{ue({type:"set-room-id-input",value:x})}'
    input_after = 'set:x=>{f.value&&(f.value={...f.value,roomIdInput:x});ue({type:"set-room-id-input",value:x})}'
    if panel_text.count(input_before) != 1:
        raise ValueError('Original room input echo patch drift')
    panel_file.write_text(panel_text.replace(input_before, input_after))
    patches.append({'file': panel_file.name, 'reason': 'Echo room input locally before asynchronous WK snapshot acknowledgement',
                    'before': input_before, 'after': input_after})
    # Keep the official selection dialog available without loading an account SDK.
    login_file = target / 'assets/login-B1hThJN-.js'
    login_text = login_file.read_text()
    login_patches = [
        ('async function n(){if(!m){', 'async function n(){if(!window.__MACOS_ONLINE__){p();return}if(!m){', 'Keep offline choice while restoring original SDK initialization online'),
        ('Re({link:[{rel:"stylesheet",href:Pe}],script:[{src:Ae,onload:()=>{_(),u&&(u=!1,n())}}]});', 'window.__MACOS_ONLINE__&&Re({link:[{rel:"stylesheet",href:Pe}],script:[{src:Ae,onload:()=>{_(),u&&(u=!1,n())}}]});', 'Load original authentication SDK only online'),
        ('window.addEventListener("cat-pass-login-overlay",F),K()});', 'window.addEventListener("cat-pass-login-overlay",F),K(),n()});', 'Open original choice after mounting even if initial native open event preceded listeners'),
    ]
    for before, after, reason in login_patches:
        if login_text.count(before) != 1:
            raise ValueError(f'Original login placeholder patch drift: {reason}')
        login_text = login_text.replace(before, after)
        patches.append({'file': login_file.name, 'reason': reason, 'before': before, 'after': after})
    login_file.write_text(login_text)
    # Dictionaries and public gallery are official public snapshots, never simulated user inventory.
    snapshot = ROOT / 'assets/_索引/remote/metadata'
    public = target / 'public'
    public.mkdir()
    for path in snapshot.glob('dict-*.json'):
        shutil.copy2(path, public / path.name)
    shutil.copy2(snapshot / 'atlas.json', public / 'atlas.json')
    hosts = json.loads((snapshot / 'dict_host.json').read_text())
    hosts['url'] = {lang: f'wuwa://app/public/dict-{lang}.json' for lang in hosts['url']}
    (public / 'app/json-host').mkdir(parents=True)
    (public / 'app/json-host/dict_host.json').write_text(json.dumps(hosts))
    library = ROOT.parent / 'wuwa-tappo-assets'
    catalog = json.loads((library / 'data/catalog.json').read_text())
    asset_map = {}
    folders = {'character_skin': 'character', 'accessory': 'accessory', 'emote': 'emote'}
    from urllib.parse import quote, urlsplit
    for item in catalog['items']:
        folder = folders[item['type']]
        for field, file in item['files'].items():
            rel = file['path']
            # Public gallery, role and expression resources retain purpose-specific paths.
            destination = target / 'library' / rel
            if not destination.exists():
                if hashlib.sha256((library / rel).read_bytes()).hexdigest() != file['sha256']:
                    raise ValueError(f'Archived public asset hash mismatch: {rel}')
                destination.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(library / rel, destination)
            url = 'wuwa://app/library/' + quote(rel)
            if field == 'atlas':
                asset_map[f'{folder}_atlas/{item["officialFilename"]}'] = url
            elif field == 'image':
                asset_map[f'{folder}/{item["officialFilename"]}'] = url
            if file.get('sourceUrl'):
                asset_map[urlsplit(file['sourceUrl']).path.lstrip('/')] = url
    (target / 'offline-assets.js').write_text('window.__ORIGINAL_ASSET_MAP__=' + json.dumps(asset_map, ensure_ascii=False) + ';')
    shutil.copy2(ROOT / 'original-adapter/tauri.js', target / 'tauri-adapter.js')
    shutil.copy2(ROOT / 'original-adapter/audit.js', target / 'audit.js')
    shutil.copy2(ROOT / 'original-adapter/session.js', target / 'session-adapter.js')
    shutil.copy2(ROOT / 'original-adapter/socket.js', target / 'socket-adapter.js')
    inventory = []
    for path in sorted(source.rglob('*')):
        if path.is_file():
            inventory.append({'path': str(path.relative_to(source)), 'sha256': hashlib.sha256(path.read_bytes()).hexdigest()})
    (target / 'adapter-manifest.json').write_text(json.dumps({'sourceFiles': inventory, 'entryPatches': patches}, ensure_ascii=False, indent=2))
    # Inventory all literal platform calls for the implementation and completion audit.
    candidates = set()
    plugins = set()
    routes = []
    for path in source.glob('assets/*.js'):
        text = path.read_text()
        plugins.update(re.findall(r'["\x27](plugin:[^"\x27`]+)["\x27]', text))
        for name in re.findall(r'\b\w+\("([a-z][a-z0-9_]+)"(?:,|\))', text):
            if '_' in name:
                candidates.add(name)
    routes = re.findall(r'\{path:"([^"\n]+)",name:"([^"\n]+)"', original)
    (ROOT / 'build').mkdir(exist_ok=True)
    (ROOT / 'build/original-inventory.json').write_text(json.dumps({
        'routes': routes, 'pluginCommands': sorted(plugins), 'candidateCommandsAndTranslationKeys': sorted(candidates)
    }, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    import sys
    prepare(Path(sys.argv[1]))
