#!/usr/bin/env python3
"""Stage recovered release assets without modifying the recovery archive."""
import hashlib
import json
from pathlib import Path
import re
import shutil

ROOT = Path(__file__).resolve().parents[1]


def prepare(resources):
    source = ROOT / 'recovered/wuwa-tappo-cn-1.0.4/frontend'
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
    entry = target / 'assets/index-CM6qA69G.js'
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
    main_file = target / 'assets/index-BFg5ADH5.js'
    main_text = main_file.read_text()
    mouse_before = 'async function Jc(e,t,o,l,f){'
    if main_text.count(mouse_before) != 1:
        raise ValueError('Original pointer dispatch patch drift')
    main_text = main_text.replace(mouse_before, mouse_before + 'if(window.__MACOS_DIRECT_MOUSE__){const hit=Wt(o,l);if(!hit||!document.elementFromPoint(hit.x,hit.y)?.closest("[data-room-cat-id]"))return;}')
    reset_before = 'const Yr=new Set,ka=new Set;'
    if main_text.count(reset_before) != 1:
        raise ValueError('Original key-state reset patch drift')
    main_text = main_text.replace(reset_before, reset_before + 'window.__MACOS_RESET_INPUT__=()=>{Yr.clear();ka.clear();oh()};')
    game_mode_start = main_text.index('function $a(e){')
    game_mode_end = main_text.index('async function Xc(){', game_mode_start)
    game_mode_before = main_text[game_mode_start:game_mode_end]
    game_mode_after = """let followSystemGameMode=window.__MACOS_FOLLOW_SYSTEM_GAME_MODE__===true,systemGameModeActive=null;
    function updateSystemGameMode(state){
        if(!followSystemGameMode)systemGameModeActive=null;
        followSystemGameMode=state.enabled===true;
        if(typeof state.active==="boolean")systemGameModeActive=state.active;
        if(!followSystemGameMode){
            void kt("set_macos_effective_game_mode",{enabled:null}).catch(()=>{});
            return;
        }
        if(systemGameModeActive===null)return;
        const value=systemGameModeActive;
        sr({gameMode:value});
        tn.value=value;
        void kt("set_macos_effective_game_mode",{enabled:value}).catch(()=>{});
        jm(value);
    }
    function receiveSystemGameMode(event){updateSystemGameMode(event.detail)}
    function $a(e){
        if(followSystemGameMode)return;
        sr({gameMode:e});
        tn.value=e;
        vu("game_mode",e);
        jm(e);
    }
    function Op(e){
        if(followSystemGameMode||!Et().autoGameModeOnFullscreen){_a=false;return}
        if(e!==_a){_a=e;if(tn.value!==e)$a(e)}
    }
    function Fp(){$a(!tn.value)}
    """
    for before, after, reason in [
        (game_mode_before, game_mode_after, 'Synchronize Tappo with both system Game Mode states'),
        ('ha=await Am(e=>{tn.value=e}),', '''ha=await Am(e=>{if(!followSystemGameMode)tn.value=e}),
         window.addEventListener("macos-system-game-mode",receiveSystemGameMode),
         await kt("get_macos_game_mode").then(updateSystemGameMode).catch(()=>{}),''',
         'Ignore manual mode events while following the system'),
        ('window.removeEventListener("pet-toast-geometry-changed",Zc),',
         'window.removeEventListener("macos-system-game-mode",receiveSystemGameMode),window.removeEventListener("pet-toast-geometry-changed",Zc),',
         'Remove the system state listener when the desktop view unmounts'),
        ('"tray-toggle-game-mode",()=>{Pe()||$a(!Et().gameMode)}',
         '"tray-toggle-game-mode",()=>{Pe()||Fp()}', 'Toggle the effective mode from the tray'),
    ]:
        if main_text.count(before) != 1:
            raise ValueError(f'Original game mode patch drift: {reason}')
        main_text = main_text.replace(before, after)
        patches.append({'file': main_file.name, 'reason': reason, 'before': before, 'after': after})
    main_file.write_text(main_text)
    patches.append({'reason': 'Recover key state after permission loss or sleep without inventing click counts', 'file': main_file.name, 'before': reset_before})
    patches.append({'reason': 'Use actual WK events for local controls and retain native-only remote member gestures', 'file': main_file.name, 'before': mouse_before})
    panel_file = target / 'assets/index-BIzzuO5B.js'
    panel_text = panel_file.read_text()
    input_before = 'set:I=>{re({type:"set-room-id-input",value:I})}'
    input_after = 'set:I=>{p.value&&(p.value={...p.value,roomIdInput:I});re({type:"set-room-id-input",value:I})}'
    if panel_text.count(input_before) != 1:
        raise ValueError('Original room input echo patch drift')
    panel_file.write_text(panel_text.replace(input_before, input_after))
    patches.append({'file': panel_file.name, 'reason': 'Echo room input locally before asynchronous WK snapshot acknowledgement',
                    'before': input_before, 'after': input_after})
    # Reuse the version row and status messages with the macOS Release check.
    panel_text = panel_file.read_text()
    enabled_before = 'X=on(),se=b(!1)'
    enabled_after = 'X=window.__MACOS_ONLINE__===true,se=b(!1)'
    handler_start = panel_text.index('async function Ds(){')
    handler_end = panel_text.index('Je(async()=>', handler_start)
    handler_before = panel_text[handler_start:handler_end]
    handler_after = """async function Ds(){
        if(!X||se.value)return;
        se.value=true;
        oe.value=s("setting_version_checking");
        try{
            const result=await gs("check_mac_release");
            if(result.kind==="available")oe.value=s("setting_version_new_confirm",{version:result.version});
            else if(result.kind==="none")oe.value=s("setting_version_latest",{version:result.currentVersion});
            else if(result.kind==="disabled")oe.value=s("setting_version_disabled");
            else oe.value=s("setting_version_check_failed");
        }catch{
            oe.value=s("setting_version_check_failed");
        }finally{
            se.value=false;
        }
    }"""
    for before, after, reason in [
        (enabled_before, enabled_after, 'Enable the macOS release button only in the online edition'),
        (handler_before, handler_after, 'Check GitHub releases via the native bridge from the settings button'),
    ]:
        if panel_text.count(before) != 1:
            raise ValueError(f'Original update patch drift: {reason}')
        panel_text = panel_text.replace(before, after)
        patches.append({'file': panel_file.name, 'reason': reason, 'before': before, 'after': after})
    follow_row = """systemMode.value?.supported?(l(),y("div",No,[
        e("div",Oo,[
            e("div",Do,String(N.value).startsWith("zh")?"跟随 macOS 游戏模式":"Follow macOS Game Mode",1),
            e("div",Ho,String(N.value).startsWith("zh")?"自动同步系统游戏模式的开启和关闭状态。":"Keep Tappo in sync when macOS Game Mode turns on or off.",1)
        ]),
        e("div",Vo,[e("label",Wo,[
            e("input",{type:"checkbox",checked:systemMode.value.enabled,disabled:systemModeBusy.value,
                "aria-label":String(N.value).startsWith("zh")?"跟随 macOS 游戏模式":"Follow macOS Game Mode",
                onMousedown:R(()=>{},["stop"]),onChange:setSystemMode},null,8,["checked","disabled","aria-label"]),
            e("span",{class:"setting-slider"})
        ])])
    ])):J("",!0),"""
    panel_game_mode = [
        ('const H=An,', """const systemMode=b(null),systemModeBusy=b(false);
        let unlistenEffectiveMode;
        async function setSystemMode(event){
            systemModeBusy.value=true;
            try{systemMode.value=await gs("set_follow_macos_game_mode",{enabled:event.target.checked})}
            catch{event.target.checked=!!systemMode.value?.enabled;Ne(String(N.value).startsWith("zh")?"无法更新游戏模式设置":"Could not update Game Mode settings")}
            finally{systemModeBusy.value=false}
        }
        function reflectEffectiveMode(value){
            const effective=value??Ns().gameMode;
            if(effective!==O.value){pe=true;O.value=effective;ve(()=>{pe=false})}
        }
        const H=An,"""),
        ('gameMode:O.value,autoGameModeOnFullscreen:', 'autoGameModeOnFullscreen:'),
        ('st("game_mode",O.value),Ve(),Un(O.value)', 'st("game_mode",O.value),Cn({gameMode:O.value}),Un(O.value)'),
        ('I=!0,i=!0,await Kt(!1),', """unlistenEffectiveMode=await sa("macos-effective-game-mode",event=>reflectEffectiveMode(event.payload));
        systemMode.value=await gs("get_macos_game_mode").catch(()=>null);
        if(systemMode.value?.effective!=null)reflectEffectiveMode(systemMode.value.effective);
        I=!0,i=!0;await Kt(!1),"""),
        ('dt(()=>{ot(),ge?.()', 'dt(()=>{unlistenEffectiveMode?.();ot(),ge?.()'),
        ('e("div",No,[e("div",Oo,[e("div",Do,L(v(s)("setting_auto_game_mode_fullscreen"))',
         follow_row+'e("div",No,[e("div",Oo,[e("div",Do,L(v(s)("setting_auto_game_mode_fullscreen"))'),
        ('a[10]||(a[10]=x=>O.value=x),type:"checkbox",onMousedown:a[11]||(a[11]=R(()=>{},["stop"]))},null,544)',
         'a[10]||(a[10]=x=>O.value=x),disabled:!!systemMode.value?.enabled,type:"checkbox",onMousedown:a[11]||(a[11]=R(()=>{},["stop"]))},null,552,["disabled"])'),
        ('a[12]||(a[12]=x=>g.value=x),type:"checkbox",onMousedown:a[13]||(a[13]=R(()=>{},["stop"]))},null,544)',
         'a[12]||(a[12]=x=>g.value=x),disabled:!!systemMode.value?.enabled,type:"checkbox",onMousedown:a[13]||(a[13]=R(()=>{},["stop"]))},null,552,["disabled"])'),
    ]
    for before, after in panel_game_mode:
        if panel_text.count(before) != 1:
            raise ValueError(f'Original game mode settings patch drift: {before}')
        panel_text = panel_text.replace(before, after)
        patches.append({'file': panel_file.name, 'reason': 'Expose macOS Game Mode following in settings',
                        'before': before, 'after': after})
    panel_file.write_text(panel_text)
    # Keep the official selection dialog available without loading an account SDK.
    login_file = target / 'assets/login-6yi5hIzI.js'
    login_text = login_file.read_text()
    login_patches = [
        ('Oe({link:[{rel:"stylesheet",href:Ae}],script:[{src:Fe,onload:()=>{y()}}]});',
         'window.__MACOS_ONLINE__&&Oe({link:[{rel:"stylesheet",href:Ae}],script:[{src:Fe,onload:()=>{y()}}]});',
         'Load original authentication SDK only online'),
        ('if(i==="online"){if(x(L)){ze().then', 'if(window.__MACOS_ONLINE__&&i==="online"){if(x(L)){ze().then',
         'Keep SDK initialization and recovery offline during audit'),
        ('window.addEventListener("cat-pass-login-overlay",V),e()});',
         'window.addEventListener("cat-pass-login-overlay",V),e()||b()});',
         'Open original choice after mounting even if initial native open event preceded listeners'),
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
