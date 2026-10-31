#!/usr/bin/env python3
"""Check the original notice route offline, without interrupting a live room."""
import json
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import uuid

ROOT = Path(__file__).resolve().parents[1]
report = ROOT / 'build/maintenance-check.json'
report.parent.mkdir(exist_ok=True)
report.write_text(json.dumps({'status': 'building'}))
try:
    with tempfile.TemporaryDirectory(prefix='wuwa-maintenance-') as directory:
        app = Path(directory) / 'Wuwa Maintenance Check.app'
        subprocess.run(['ditto', str(ROOT / 'dist/Wuwa Tappo.app'), str(app)], check=True)
        executable = app / 'Contents/MacOS/WuwaTappo'
        executable.unlink()
        subprocess.run([
            'xcrun', 'swiftc', '-swift-version', '5', '-O', '-target', 'arm64-apple-macos13.0',
            '-module-cache-path', str(ROOT / 'build/module-cache'),
            '-framework', 'AppKit', '-framework', 'JavaScriptCore', '-framework', 'WebKit',
            *[str(path) for path in sorted((ROOT / 'native').glob('*.swift'))], '-o', str(executable)
        ], check=True)
        plist_path = app / 'Contents/Info.plist'
        plist = plistlib.loads(plist_path.read_bytes())
        plist['CFBundleIdentifier'] = 'io.lliooly.wuwa-tappo.maintenance.' + uuid.uuid4().hex
        plist_path.write_bytes(plistlib.dumps(plist))
        subprocess.run(['codesign', '--force', '--sign', '-', str(app)], check=True, capture_output=True)
        report.write_text(json.dumps({'status': 'running'}))
        subprocess.run(['open', '-n', '-W', str(app), '--args', '--offline', '--maintenance-check', str(report)], check=True, timeout=40)
        result = json.loads(report.read_text())
        assert result.get('status') == 'passed', result
        assert result.get('unknownCommands') == [], result
        print('PASS: original maintenance overlay, main-window hiding, isolated offline execution')
except Exception as error:
    report.write_text(json.dumps({'status': 'failed', 'error': str(error)}))
    raise
