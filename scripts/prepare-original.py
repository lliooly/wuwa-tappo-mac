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
    # No cross-origin endpoints, JSONP, telemetry, accounts or server mutations in this phase.
    html = html.replace('<meta charset="UTF-8" />', '''<meta charset="UTF-8" />
    <meta http-equiv="Content-Security-Policy" content="default-src 'self' wuwa: data: blob:; script-src 'self' wuwa: 'unsafe-inline' 'unsafe-eval'; style-src 'self' wuwa: 'unsafe-inline'; connect-src 'self' wuwa:; img-src 'self' wuwa: data: blob:; object-src 'none'; base-uri 'self'">''')
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
    replace('function getDictionaryAssetsHost(){const e=normalizeAssetsHost(readStoredDictionaryAssetsHost());return e&&e!==dictionaryAssetsHost&&(dictionaryAssetsHost=e),dictionaryAssetsHost}',
            'function getDictionaryAssetsHost(){return "wuwa://app/public"}', 'Use archived public dictionaries')
    replace('function shouldDeferRemoteDictionary(){return networkSnapshot.value.status==="offline"||networkSnapshot.value.status==="reconnecting"||networkSnapshot.value.status==="degraded"}',
            'function shouldDeferRemoteDictionary(){return false}', 'Archived local dictionaries do not require internet')
    replace('function atlas(){const e={loading:!0,reload:!0};return jsonpClient.get("api/common/atlas",{},e)}',
            'function atlas(){return fetch("wuwa://app/public/atlas.json").then(r=>r.json())}', 'Load unmodified public atlas snapshot without account service')
    network_start = staged[staged.index('function startNetworkMonitoring(){'):staged.index('function stopNetworkMonitoring(){')]
    replace(network_start, 'function startNetworkMonitoring(){if(!started){started=true;setSnapshot({status:"offline",reason:"macos-local-only",retryAttempt:0})}}',
            'Keep account connectivity explicitly offline without retrying excluded services')
    replace('function isAppUpdaterEnabled(){if(!isTauriRuntime())return!1;const e="true".toLowerCase();return e!=="false"&&e!=="0"}',
            'function isAppUpdaterEnabled(){return false}', 'Windows updater cannot install into the macOS bundle; do not claim an update check succeeded')
    replace('function buildAssetUrl(e,t){const n=',
            'function buildAssetUrl(e,t){const local=window.__ORIGINAL_ASSET_MAP__?.[t.replace(/^\\//,"").split("?")[0]];if(local&&!(isLocalRoleAssetsHost(e)&&resolveLocalRoleAssetUrl(t)))return local;const n=',
            'Resolve archived assets by explicit catalog mapping before original local fallback')
    # Expose original state and router only for native integration checks, no duplicated Vue implementation.
    replace('bootstrap();export{',
            'window.__WUWA_ORIGINAL__={router,globalStore,loadDesktopCatSettings,persistDesktopCatSettings,showToast};bootstrap();export{',
            'Expose actual original router/store for integration verification')
    entry.write_text(staged)
    main_file = target / 'assets/index-pp8VWaUF.js'
    main_text = main_file.read_text()
    mouse_before = 'async function Xc(e,t,o,l,f){'
    if main_text.count(mouse_before) != 1:
        raise ValueError('Original pointer dispatch patch drift')
    main_text = main_text.replace(mouse_before, mouse_before + 'if(window.__MACOS_DIRECT_MOUSE__)return;')
    reset_before = 'const qr=new Set,va=new Set;'
    if main_text.count(reset_before) != 1:
        raise ValueError('Original key-state reset patch drift')
    main_text = main_text.replace(reset_before, reset_before + 'window.__MACOS_RESET_INPUT__=()=>{qr.clear();va.clear();Zd()};')
    main_file.write_text(main_text)
    patches.append({'reason': 'Recover key state after permission loss or sleep without inventing click counts', 'file': main_file.name, 'before': reset_before})
    patches.append({'reason': 'Use actual WK mouse events inside native hit regions, avoid duplicate synthetic clicks', 'file': main_file.name, 'before': mouse_before})
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
    login_open = login_text[login_text.index('async function n(){if(!m){'):login_text.index('function e(){b&&clearTimeout(b)')]
    login_patches = [
        (login_open, 'async function n(){p()}', 'Open original login choice without waiting for SDK'),
        ('Re({link:[{rel:"stylesheet",href:Pe}],script:[{src:Ae,onload:()=>{_(),u&&(u=!1,n())}}]});', '', 'Do not load remote authentication SDK'),
        ('window.addEventListener("cat-pass-login-overlay",F),K()});', 'window.addEventListener("cat-pass-login-overlay",F),p()});', 'Present choice on first native window mount'),
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
