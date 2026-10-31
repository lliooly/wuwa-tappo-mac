#!/usr/bin/env python3
"""Verify evidence boundaries: recovery unchanged; staged edits are declared."""
from pathlib import Path
import hashlib
import json
import subprocess

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'recovered/wuwa-tappo-cn-1.0.3/frontend'
STAGED = ROOT / 'dist/Wuwa Tappo.app/Contents/Resources/original'
manifest = json.loads((STAGED / 'adapter-manifest.json').read_text())
recovery = json.loads((SOURCE.parent / 'manifest.json').read_text())
archived = {item['path'].lstrip('/'): item['sha256'] for item in recovery['resources']}
assert {entry['path']: entry['sha256'] for entry in manifest['sourceFiles']} == archived, 'Build manifest differs from extraction evidence'
assert {str(path.relative_to(SOURCE)) for path in SOURCE.rglob('*') if path.is_file()} == set(archived), 'Recovered file inventory changed'
# Verify the independent extraction evidence still belongs to the archived executable.
executable = ROOT / recovery['source']
if executable.exists():
    with executable.open('rb') as stream:
        digest = hashlib.sha256()
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(chunk)
    assert digest.hexdigest() == recovery['sourceSha256'], 'Archived Windows source executable changed'
allowed = {'index.html', 'assets/index-CuzHFfJW.js', 'assets/index-pp8VWaUF.js', 'assets/index-CiT_jZa7.js', 'assets/login-B1hThJN-.js'}
changed = []
for entry in manifest['sourceFiles']:
    path = entry['path']
    assert hashlib.sha256((SOURCE / path).read_bytes()).hexdigest() == entry['sha256'], f'Recovery was modified: {path}'
    copied = hashlib.sha256((STAGED / path).read_bytes()).hexdigest()
    if copied != entry['sha256']:
        assert path in allowed, f'Undeclared release modification: {path}'
        changed.append(path)
assert set(changed) == allowed
for path in sorted((STAGED / 'assets').glob('*.js')):
    subprocess.run(['node', '--check', str(path)], check=True, capture_output=True)
subprocess.run(['node', '--check', str(STAGED / 'tauri-adapter.js')], check=True, capture_output=True)
asset_map = (STAGED / 'offline-assets.js').read_text()
asset_map = json.loads(asset_map.split('=', 1)[1].removesuffix(';'))
from urllib.parse import unquote, urlsplit
for url in asset_map.values():
    assert (STAGED / unquote(urlsplit(url).path).lstrip('/')).is_file(), url
assert len(json.loads((STAGED / 'public/atlas.json').read_text())['data']) == 899
print(f'PASS: {len(archived)} recovered files match extraction manifest; only {len(changed)} staged files patched')
print(f'PASS: release JS syntax, {len(asset_map)} explicit local asset mappings, 899 public gallery entries')
