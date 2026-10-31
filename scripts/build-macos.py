#!/usr/bin/env python3
"""Build a self-contained native macOS .app using Apple's installed toolchain."""
import hashlib
import base64
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]
LIBRARY = ROOT.parent / 'wuwa-tappo-assets'
APP = ROOT / 'dist/Wuwa Tappo.app'
CONTENTS = APP / 'Contents'
RESOURCES = CONTENTS / 'Resources'


def run(*args):
    subprocess.run(args, check=True, cwd=ROOT)


def main():
    # Only clean generated bundle content, never source or the asset library.
    if APP.exists():
        shutil.rmtree(APP)
    (CONTENTS / 'MacOS').mkdir(parents=True)
    RESOURCES.mkdir()
    shutil.copy2(ROOT / 'assets/macos/menu-bar-template.png', RESOURCES / 'menu-bar-template.png')
    catalog = json.loads((LIBRARY / 'data/catalog.json').read_text())

    def find(kind, name):
        return next(item for item in catalog['items']
                    if item['type'] == kind and item['officialFilename'] == name)

    character = find('character_skin', 'role_1501_1001.png')
    accessory = find('accessory', 'accessory_1000.png')
    files = {}
    for field, item in [(field, character) for field in ['body1', 'body2', 'body3', 'head1', 'head2']] + [('accessory', accessory)]:
        original = item['files']['image' if field == 'accessory' else field]
        source = (LIBRARY / original['path']).resolve()
        if not source.is_relative_to(LIBRARY.resolve()):
            raise ValueError('素材路径越界')
        if hashlib.sha256(source.read_bytes()).hexdigest() != original['sha256']:
            raise ValueError(f'素材哈希不匹配：{source}')
        target = RESOURCES / original['path']
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target)
        files[field] = original['path']
    meta = character.get('assetMetadata') or {}
    ui_path = 'assets/界面/原版/pet-info-setting.png'
    ui_manifest = json.loads((LIBRARY / 'data/files.json').read_text())['files']
    ui_entry = next(entry for entry in ui_manifest if entry['path'] == ui_path)
    ui_source = LIBRARY / ui_path
    if hashlib.sha256(ui_source.read_bytes()).hexdigest() != ui_entry['sha256']:
        raise ValueError('原版信息条素材哈希不匹配')
    ui_target = RESOURCES / ui_path
    ui_target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(ui_source, ui_target)
    files['toolbar'] = ui_path
    for key, filename in {
        'chestBubble': 'reward-btn.png', 'chestBody': 'reward-btn-icon1.png',
        'chestLid': 'reward-btn-icon2.png', 'bubbleBack': 'emotion-dot-light1.png',
        'bubbleFront': 'emotion-dot-light2.png'
    }.items():
        path = 'assets/界面/原版/' + filename
        entry = next(entry for entry in ui_manifest if entry['path'] == path)
        source = LIBRARY / path
        if hashlib.sha256(source.read_bytes()).hexdigest() != entry['sha256']:
            raise ValueError(f'界面素材哈希不匹配：{path}')
        target = RESOURCES / path
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target)
        files[key] = path
    for index, name in enumerate(['idle', 'happy', 'angry', 'surprised', 'pain']):
        item = find('emote', f'emote_{name}.png')
        entry = item['files']['image']
        source = LIBRARY / entry['path']
        if hashlib.sha256(source.read_bytes()).hexdigest() != entry['sha256']:
            raise ValueError(f'表情素材哈希不匹配：{source}')
        target = RESOURCES / entry['path']
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target)
        files[f'emote{index}'] = entry['path']
    (RESOURCES / 'appearance.json').write_text(json.dumps({
        'files': files, 'offsetX': meta.get('offset_x', 0), 'offsetY': meta.get('offset_y', 0)
    }, ensure_ascii=False, indent=2))
    # Independent offline settings panel. Card thumbnails and worn layers retain separate fields.
    panel_dir = RESOURCES / 'panel'
    shutil.copytree(ROOT / 'panel', panel_dir)
    panel_names = [('character_skin', 'role_1501_1001.png'), ('character_skin', 'role_1502_1001.png'),
                   ('accessory', 'accessory_1000.png')]
    panel_names += [('emote', f'emote_{name}.png') for name in
                    ['idle', 'happy', 'angry', 'surprised', 'pain', 'effort', 'stunned', 'threaten', 'triumph']]
    panel_items = []
    for kind, name in panel_names:
        item = find(kind, name)
        keys = ['atlas', 'image'] + (['head1', 'body1'] if kind == 'character_skin' else [])
        item_files = {}
        for field in keys:
            entry = item['files'][field]
            source = LIBRARY / entry['path']
            if hashlib.sha256(source.read_bytes()).hexdigest() != entry['sha256']:
                raise ValueError(f'面板素材哈希不匹配：{source}')
            target = RESOURCES / entry['path']
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, target)
            item_files[field] = entry['path']
        metadata = item.get('assetMetadata') or {}
        panel_items.append({'id': item['assetId'], 'type': kind, 'name': item['nameZh'],
                            'files': item_files, 'offsetX': metadata.get('offset_x', 0),
                            'offsetY': metadata.get('offset_y', 0)})
    for entry in ui_manifest:
        path = entry['path']
        if not (path.startswith('assets/界面/原版/') and len(Path(path).parts) == 4):
            continue
        filename = Path(path).name
        if not (filename.startswith(('nav-', 'module-', 'preview-', 'preset-', 'type-icon-', 'atlas-item-', 'atlas-thumb-'))
                or filename in ['logo.png', 'close.png']):
            continue
        source = LIBRARY / path
        if hashlib.sha256(source.read_bytes()).hexdigest() != entry['sha256']:
            raise ValueError(f'面板界面素材哈希不匹配：{path}')
        target = RESOURCES / path
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target)
    for font in ['975MaruSC-Medium-CqkJPt5f.woff2', '975MaruSC-Bold-iviPgHHc.woff2']:
        path = 'assets/字体/' + font
        entry = next(entry for entry in ui_manifest if entry['path'] == path)
        source = LIBRARY / path
        if hashlib.sha256(source.read_bytes()).hexdigest() != entry['sha256']:
            raise ValueError('字体哈希不匹配')
        target = RESOURCES / path
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target)
    for filename in ['logo.png', 'texture.png', 'close.png', 'passport-button.png', 'uid-button.png']:
        path = 'assets/界面/原版/login-select/' + filename
        entry = next(entry for entry in ui_manifest if entry['path'] == path)
        source = LIBRARY / path
        if hashlib.sha256(source.read_bytes()).hexdigest() != entry['sha256']:
            raise ValueError(f'登录界面素材哈希不匹配：{path}')
        target = RESOURCES / path
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target)
    (panel_dir / 'panel-data.js').write_text('window.PANEL_DATA = ' + json.dumps({'items': panel_items}, ensure_ascii=False) + ';\n')
    # WebKit file origins block file-backed CSS masks. Inline only the original mask bytes.
    css_path = panel_dir / 'panel.css'
    css = css_path.read_text()
    for filename in ['atlas-thumb-1.png', 'preview-main-mask.png']:
        path = 'assets/界面/原版/' + filename
        encoded = base64.b64encode((RESOURCES / path).read_bytes()).decode('ascii')
        css = css.replace("url('../" + path + "')", "url('data:image/png;base64," + encoded + "')")
    css_path.write_text(css)
    # Preserve one animation implementation: adapt ES module exports for JavaScriptCore.
    core = (ROOT / 'src/animation/pet-animation.js').read_text()
    core = core.replace('export const ORIGINAL_TIMING', 'const ORIGINAL_TIMING').replace('export class PetAnimation', 'class PetAnimation')
    (RESOURCES / 'pet-animation.js').write_text(core)
    import importlib.util
    spec = importlib.util.spec_from_file_location('prepare_original', ROOT / 'scripts/prepare-original.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    module.prepare(RESOURCES)
    for name in ['版权与来源.md', '字体授权.md']:
        source = LIBRARY / 'docs' / name
        if source.exists():
            shutil.copy2(source, RESOURCES / name)
    shutil.copy2(LIBRARY / 'LICENSES/OFL-1.1.txt', RESOURCES / 'OFL-1.1.txt')
    shutil.copy2(LIBRARY / 'data/来源快照/font-name-records.json', RESOURCES / 'font-name-records.json')
    # Keep adaptation terms and all known font license texts in future packages.
    shutil.copy2(ROOT / 'LICENSES/Apache-2.0.txt', RESOURCES / 'Apache-2.0.txt')
    for name in ['LICENSE', 'DISCLAIMER.md', 'THIRD_PARTY_NOTICES.md']:
        shutil.copy2(ROOT / name, RESOURCES / name)
    # Build the macOS icon from the archived release icon, never a framework logo.
    icon_path = 'assets/图标/发行包/app-icon.png'
    icon_source = LIBRARY / icon_path
    icon_entry = next(entry for entry in ui_manifest if entry['path'] == icon_path)
    if hashlib.sha256(icon_source.read_bytes()).hexdigest() != icon_entry['sha256']:
        raise ValueError('发行包应用图标哈希不匹配')
    iconset = ROOT / 'build/WuwaTappo.iconset'
    if iconset.exists():
        shutil.rmtree(iconset)
    iconset.mkdir(parents=True)
    for size in [16, 32, 128, 256, 512]:
        for scale in [1, 2]:
            pixels = size * scale
            destination = iconset / f'icon_{size}x{size}{"@2x" if scale == 2 else ""}.png'
            if pixels == 512:
                shutil.copy2(icon_source, destination)
            else:
                subprocess.run(['sips', '-z', str(pixels), str(pixels), str(icon_source), '--out', str(destination)],
                               check=True, capture_output=True)
    run('iconutil', '-c', 'icns', str(iconset), '-o', str(RESOURCES / 'WuwaTappo.icns'))
    with (CONTENTS / 'Info.plist').open('wb') as output:
        plistlib.dump({
            'CFBundleName': 'Wuwa Tappo', 'CFBundleDisplayName': 'Wuwa Tappo',
            'CFBundleIdentifier': 'io.lliooly.wuwa-tappo.mac',
            'CFBundleExecutable': 'WuwaTappo', 'CFBundlePackageType': 'APPL',
            'CFBundleIconFile': 'WuwaTappo.icns',
            'CFBundleShortVersionString': '0.2.0', 'CFBundleVersion': '7',
            'LSMinimumSystemVersion': '13.0', 'LSUIElement': True,
            'NSHighResolutionCapable': True,
            'NSInputMonitoringUsageDescription': '监听键盘和鼠标操作以驱动玩偶动画，不读取或保存输入文本。'
        }, output)
    cache = ROOT / 'build/module-cache'
    cache.mkdir(parents=True, exist_ok=True)
    run('xcrun', 'swiftc', '-swift-version', '5', '-O', '-target', 'arm64-apple-macos13.0',
        '-module-cache-path', str(cache), '-framework', 'AppKit', '-framework', 'JavaScriptCore', '-framework', 'WebKit',
        *[str(p) for p in sorted((ROOT / 'native').glob('*.swift'))],
        '-o', str(CONTENTS / 'MacOS/WuwaTappo'))
    # A developer identity can be supplied to keep a stable identity across local rebuilds.
    identity = os.environ.get('WUWA_SIGN_IDENTITY', '-')
    run('codesign', '--force', '--sign', identity, '--identifier', 'io.lliooly.wuwa-tappo.mac', str(APP))
    run('codesign', '--verify', '--strict', str(APP))
    archive = ROOT / 'dist/Wuwa-Tappo-mac-arm64.zip'
    if archive.exists():
        archive.unlink()
    run('ditto', '-c', '-k', '--sequesterRsrc', '--keepParent', str(APP), str(archive))
    print(f'已生成：{APP}\n压缩包：{archive}', flush=True)


if __name__ == '__main__':
    main()
