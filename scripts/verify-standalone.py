#!/usr/bin/env python3
"""Run the shipped code/resources outside the repo with isolated macOS preferences."""
import hashlib
import json
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import uuid

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'dist/Wuwa Tappo.app'
PREFIX = ROOT / 'build/standalone-pages'
EVIDENCE = ROOT / 'build/standalone-validation.json'


def hashes(root, resources_only=False):
    return {str(path.relative_to(root)): hashlib.sha256(path.read_bytes()).hexdigest()
            for path in root.rglob('*') if path.is_file()
            and '_CodeSignature' not in path.parts
            and str(path.relative_to(root)) != 'Contents/Info.plist'
            and not (resources_only and str(path.relative_to(root)) == 'Contents/MacOS/WuwaTappo')}


def unsigned_hash(executable, destination):
    shutil.copy2(executable, destination)
    subprocess.run(['codesign', '--remove-signature', str(destination)], check=True, capture_output=True)
    return hashlib.sha256(destination.read_bytes()).hexdigest()


def main():
    EVIDENCE.write_text(json.dumps({'status': 'running'}))
    app = Path(tempfile.mkdtemp(prefix='wuwa-tappo-validation-')) / SOURCE.name
    subprocess.run(['ditto', str(SOURCE), str(app)], check=True)
    expected = hashes(SOURCE)
    assert hashes(app) == expected, 'Copied code/resources differ from shipped app'
    plist_path = app / 'Contents/Info.plist'
    with plist_path.open('rb') as stream:
        plist = plistlib.load(stream)
    original_id = plist['CFBundleIdentifier']
    # Real input may run concurrently in the user's app. Never share its defaults
    # or WebKit storage with a suite that temporarily changes counters/settings.
    validation_id = original_id + '.validation.' + uuid.uuid4().hex
    plist['CFBundleIdentifier'] = validation_id
    with plist_path.open('wb') as stream:
        plistlib.dump(plist, stream)
    subprocess.run(['codesign', '--force', '--sign', '-', '--identifier', validation_id, str(app)], check=True)
    subprocess.run(['codesign', '--verify', '--strict', str(app)], check=True)
    assert hashes(app, resources_only=True) == hashes(SOURCE, resources_only=True), 'Validation resources changed'
    # Re-signing necessarily changes the Mach-O signature. Compare canonical
    # unsigned copies using Apple's signer instead of ignoring executable drift.
    code_hash = unsigned_hash(SOURCE / 'Contents/MacOS/WuwaTappo', app.parent / 'source-unsigned')
    assert code_hash == unsigned_hash(app / 'Contents/MacOS/WuwaTappo', app.parent / 'validation-unsigned'), 'Executable code changed'
    Path(str(PREFIX) + '.audit.json').write_text(json.dumps({'status': 'launching'}))
    subprocess.run(['open', '-n', '-W', str(app), '--args', '--original-ui', '--original-audit',
                    '--original-preview', str(PREFIX)], cwd='/private/tmp', check=True, timeout=120)
    report = json.loads(Path(str(PREFIX) + '.audit.json').read_text())
    assert report.get('status') == 'passed', report.get('failure', 'Audit did not complete')
    evidence = {'status': 'passed', 'app': str(app), 'sourceBundleIdentifier': original_id,
                'validationBundleIdentifier': validation_id, 'codeAndResourcesIdentical': True,
                'comparedFiles': len(expected), 'unsignedExecutableSha256': code_hash,
                'workingDirectory': '/private/tmp',
                'isolatedPreferences': True, 'audit': str(PREFIX) + '.audit.json',
                'finishedAt': report['finishedAt']}
    EVIDENCE.write_text(json.dumps(evidence, ensure_ascii=False, indent=2))
    print('PASS: standalone code/resources, isolated preferences, original UI/behavior suite')


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        EVIDENCE.write_text(json.dumps({'status': 'failed', 'error': str(error)}, ensure_ascii=False, indent=2))
        raise
