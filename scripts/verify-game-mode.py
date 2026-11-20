#!/usr/bin/env python3
"""Compile the Game Mode log cursor and state parser against isolated tests."""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='wuwa-game-mode-') as directory:
    executable = Path(directory) / 'game-mode-tests'
    subprocess.run([
        'xcrun', 'swiftc', '-swift-version', '5',
        '-module-cache-path', str(Path(directory) / 'module-cache'),
        str(ROOT / 'native/SystemGameModeMonitor.swift'),
        str(ROOT / 'tests/SystemGameModeMonitorTests.swift'), '-o', str(executable)
    ], check=True)
    subprocess.run([str(executable)], check=True)
