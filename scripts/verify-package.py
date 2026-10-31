#!/usr/bin/env python3
"""Verify the signed app and every file in its macOS distribution ZIP."""
import hashlib
import json
from pathlib import Path
import plistlib
import subprocess
import zipfile

ROOT = Path(__file__).resolve().parents[1]
APP = ROOT / 'dist/Wuwa Tappo.app'
ARCHIVE = ROOT / 'dist/Wuwa-Tappo-mac-arm64.zip'
REPORT = ROOT / 'build/package-verification.json'


def mac_name(info):
    if info.flag_bits & 0x800:
        return info.filename
    # ditto stores UTF-8 paths in its macOS ZIP variant without the usual flag.
    # Python 3.9 otherwise interprets these bytes as CP437.
    try:
        return info.filename.encode('cp437').decode('utf-8')
    except UnicodeError:
        return info.filename


def main():
    REPORT.write_text(json.dumps({'status': 'running'}))
    subprocess.run(['codesign', '--verify', '--strict', str(APP)], check=True)
    files = {APP.name + '/' + str(path.relative_to(APP)): path
             for path in APP.rglob('*') if path.is_file()}
    with zipfile.ZipFile(ARCHIVE) as archive:
        members = {mac_name(info): info for info in archive.infolist()
                   if mac_name(info).startswith(APP.name + '/') and not info.is_dir()}
        assert set(files) == set(members), 'Archive inventory differs from application'
        for name, path in files.items():
            assert hashlib.sha256(archive.read(members[name])).digest() == hashlib.sha256(path.read_bytes()).digest(), name
        executable = members[APP.name + '/Contents/MacOS/WuwaTappo']
        assert (executable.external_attr >> 16) & 0o111, 'Archive lost executable permissions'
    plist = plistlib.loads((APP / 'Contents/Info.plist').read_bytes())
    report = {'status': 'passed', 'signedApplication': True, 'archiveMatchesApplication': True,
              'comparedFiles': len(files), 'version': plist['CFBundleShortVersionString'],
              'bundleIdentifier': plist['CFBundleIdentifier'], 'archiveBytes': ARCHIVE.stat().st_size,
              'filenameEncoding': 'UTF-8 (macOS ditto ZIP)'}
    REPORT.write_text(json.dumps(report, indent=2))
    print(f'PASS: signature, {len(files)} archived files, executable permissions')


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        REPORT.write_text(json.dumps({'status': 'failed', 'error': str(error)}, indent=2))
        raise
