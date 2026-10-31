#!/usr/bin/env python3
"""Exercise a unique disposable Keychain service, never the app's session."""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='wuwa-session-store-') as directory:
    executable = Path(directory) / 'session-store-tests'
    subprocess.run([
        'xcrun', 'swiftc', '-swift-version', '5',
        '-module-cache-path', str(ROOT / 'build/module-cache'),
        str(ROOT / 'native/OriginalSessionStore.swift'),
        str(ROOT / 'native/OriginalLogPrivacy.swift'),
        str(ROOT / 'tests/OriginalSessionStoreTests.swift'), '-o', str(executable)
    ], check=True)
    subprocess.run([str(executable)], check=True)
