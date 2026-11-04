#!/usr/bin/env python3
"""Verify the special package and run its UI outside the checkout twice."""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import uuid
import zipfile

ROOT = Path(__file__).resolve().parents[1]
APP = ROOT / 'dist/Wuwa Tappo Offline.app'
RESOURCES = APP / 'Contents/Resources'
REPORT = ROOT / 'build/offline-validation.json'


def run(*args, **kwargs):
    subprocess.run(args, check=True, **kwargs)


def mac_name(info):
    if info.flag_bits & 0x800:
        return info.filename
    # Match the existing package verifier: ditto omits the UTF-8 flag.
    try:
        return info.filename.encode('cp437').decode('utf-8')
    except UnicodeError:
        return info.filename


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--ui', action='store_true')
    args = parser.parse_args()
    plist = plistlib.loads((APP / 'Contents/Info.plist').read_bytes())
    assert plist['CFBundleIdentifier'] == 'io.lliooly.wuwa-tappo.mac.offline-full-atlas'
    assert plist['CFBundleExecutable'] == 'WuwaTappoOffline'
    assert plist['WuwaDistributionVariant'] == 'offline-full-atlas'
    run('codesign', '--verify', '--strict', str(APP))
    archive = ROOT / 'dist/Wuwa-Tappo-mac-offline-full-atlas-arm64.zip'
    with zipfile.ZipFile(archive) as zipped:
        files = {APP.name + '/' + str(path.relative_to(APP)): path for path in APP.rglob('*') if path.is_file()}
        members = {mac_name(info): info for info in zipped.infolist()
                   if mac_name(info).startswith(APP.name + '/') and not info.is_dir()}
        assert files.keys() == members.keys(), 'ZIP file inventory differs from app'
        for name, path in files.items():
            assert hashlib.sha256(zipped.read(members[name])).digest() == hashlib.sha256(path.read_bytes()).digest(), path
        assert (members[APP.name + '/Contents/MacOS/WuwaTappoOffline'].external_attr >> 16) & 0o111
    inventory = RESOURCES / 'original/public/offline-inventory.json'
    rows = json.loads(inventory.read_text())
    assert len(rows) == len({row['asset_id'] for row in rows}) == 899
    catalog = json.loads((ROOT.parent / 'wuwa-tappo-assets/data/catalog.json').read_text())['items']
    assert {(row['asset_type'], row['asset_id']) for row in rows} == {(item['type'], item['assetId']) for item in catalog}
    for item in catalog:
        for file in item['files'].values():
            path = RESOURCES / 'original/library' / file['path']
            assert hashlib.sha256(path.read_bytes()).hexdigest() == file['sha256'], path
    assert all(row['asset_id'] < 1_000_000_000 for row in rows), 'Synthetic default ID in full inventory'
    html = (RESOURCES / 'original/index.html').read_text()
    assert 'connect-src \'self\' wuwa:;' in html
    for path in (RESOURCES / 'original').glob('**/*.js'):
        run('node', '--check', str(path), stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
    with tempfile.TemporaryDirectory(prefix='wuwa-offline-store-') as directory:
        executable = Path(directory) / 'tests'
        run('xcrun', 'swiftc', '-swift-version', '5', '-module-cache-path', str(ROOT / 'build/module-cache'),
            str(ROOT / 'native/OfflineAtlasStore.swift'), str(ROOT / 'tests/OfflineAtlasStoreTests.swift'), '-o', str(executable))
        run(str(executable), str(inventory))
    print('PASS: special edition metadata, signature, ZIP, inventory, JS syntax and native store')
    if not args.ui:
        return
    directory = Path(tempfile.mkdtemp(prefix='wuwa-offline-validation-'))
    copied = directory / APP.name
    shutil.copytree(APP, copied)
    hashes = lambda root: {str(p.relative_to(root)): hashlib.sha256(p.read_bytes()).hexdigest()
                           for p in root.rglob('*') if p.is_file()}
    assert hashes(APP) == hashes(copied)
    validation_id = plist['CFBundleIdentifier'] + '.validation.' + uuid.uuid4().hex
    plist['CFBundleIdentifier'] = validation_id
    (copied / 'Contents/Info.plist').write_bytes(plistlib.dumps(plist))
    run('codesign', '--force', '--sign', '-', '--identifier', validation_id, str(copied))
    REPORT.unlink(missing_ok=True)
    for restore in [False, True]:
        run('open', '-n', '-W', str(copied), '--args', '--offline-atlas-check', str(REPORT),
            *(['--offline-atlas-restore'] if restore else []), cwd='/private/tmp', timeout=90)
        report = json.loads(REPORT.read_text())
        assert report['status'] == 'passed', report.get('error', 'UI audit failed; see ' + str(REPORT))
        assert report['offline'] and not report['main']['blocked'], 'Remote fetch attempted; see ' + str(REPORT)
        assert not report['runtimeErrors'], report['runtimeErrors']
        assert not report['main']['errors'], report['main']['errors']
        assert len(report['main']['images']) >= 2 and all(image['width'] > 0 for image in report['main']['images']), 'Pet layers failed to load'
        assert report['main']['user']['character']['id'] == report['expected']['character']
        if restore:
            assert report['restored']
        else:
            (ROOT / 'build/offline-first-launch.json').write_text(json.dumps(report, ensure_ascii=False, indent=2))
    print('PASS: fresh isolated bundle outside repository, original UI actions, cross-window state and restart restore')


if __name__ == '__main__':
    main()
