#!/usr/bin/env python3
"""Compile the production storage implementation against isolated preferences."""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='wuwa-click-store-') as directory:
    executable = Path(directory) / 'click-store-tests'
    subprocess.run([
        'xcrun', 'swiftc', '-swift-version', '5',
        '-module-cache-path', str(ROOT / 'build/module-cache'),
        str(ROOT / 'native/OriginalClickStore.swift'),
        str(ROOT / 'tests/OriginalClickStoreTests.swift'), '-o', str(executable)
    ], check=True)
    subprocess.run([str(executable)], check=True)
