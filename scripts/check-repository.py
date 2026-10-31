#!/usr/bin/env python3
"""Check source integrity and documentation without requiring a macOS build."""
import ast
import hashlib
from html.parser import HTMLParser
import json
from pathlib import Path
import re
import struct
import subprocess
from urllib.parse import unquote, urlsplit

ROOT = Path(__file__).resolve().parents[1]


def anchors(text):
    return {
        re.sub(r'[^\w\- ]', '', title.strip().lower()).replace(' ', '-')
        for title in re.findall(r'^#{1,6} (.+)$', text, re.MULTILINE)
    }


class References(HTMLParser):
    def __init__(self):
        super().__init__()
        self.urls = []

    def handle_starttag(self, tag, attrs):
        for key, value in attrs:
            if key in {'src', 'href'} and value:
                self.urls.append(value)


def main():
    tracked = subprocess.check_output(
        ['git', 'ls-files', '--cached', '--others', '--exclude-standard', '-z'], cwd=ROOT
    ).decode().split('\0')
    paths = sorted({ROOT / path for path in tracked if path})
    links = [path for path in paths if path.is_symlink()]
    for path in links:
        if not path.exists():
            raise ValueError(f'Broken symlink: {path.relative_to(ROOT)} -> {path.readlink()}')

    archive = ROOT / 'recovered/wuwa-tappo-cn-1.0.3'
    manifest = json.loads((archive / 'manifest.json').read_text())
    package = json.loads((ROOT / 'package.json').read_text())
    if package['version'] != manifest['sourceVersion']:
        raise ValueError('Application version differs from recovered Windows version')
    if not isinstance(package['macosBuild'], int) or package['macosBuild'] < 1:
        raise ValueError('macosBuild must be a positive integer')
    executable = ROOT / manifest['source']
    if executable.exists():
        data = executable.read_bytes()
        if hashlib.sha256(data).hexdigest() != manifest['sourceSha256']:
            raise ValueError('Windows source hash differs from recovery manifest')
        evidence = manifest['versionEvidence']
        info = struct.unpack_from('<6I', data, int(evidence['offset'], 16))
        if info[0] != 0xfeef04bd:
            raise ValueError('Missing Windows VS_FIXEDFILEINFO signature')
        for key, high, low in [('fileVersion', info[2], info[3]),
                               ('productVersion', info[4], info[5])]:
            version = '.'.join(map(str, [high >> 16, high & 0xffff, low >> 16, low & 0xffff]))
            if version != evidence[key] or version.rsplit('.', 1)[0] != package['version']:
                raise ValueError(f'Windows {key} differs from application version')
    for item in manifest['resources']:
        path = archive / 'frontend' / item['path'].lstrip('/')
        content = path.read_bytes()
        if len(content) != item['size'] or hashlib.sha256(content).hexdigest() != item['sha256']:
            raise ValueError(f'Recovery drift: {item["path"]}')

    python_files = [path for path in paths if path.suffix == '.py' and not path.is_symlink()]
    for path in python_files:
        ast.parse(path.read_text(), filename=str(path))
    js_files = [path for path in paths if path.suffix in {'.js', '.mjs'}
                and path.relative_to(ROOT).parts[0] != 'recovered' and not path.is_symlink()]
    for path in js_files:
        subprocess.run(['node', '--check', str(path)], check=True, capture_output=True)

    docs = [path for path in paths if path.is_file() and not path.is_symlink()
            and path.suffix == '.md'
            and (path.parent == ROOT or path.relative_to(ROOT).parts[0] == 'docs')]
    checked = 0
    for path in docs:
        text = path.read_text()
        parser = References()
        parser.feed(text)
        urls = parser.urls + re.findall(r'\[[^\]\n]+\]\(([^)\n]+)\)', text)
        for url in urls:
            target = urlsplit(url)
            if target.scheme or target.netloc:
                continue
            destination = path.parent / unquote(target.path) if target.path else path
            if not destination.exists():
                raise ValueError(f'Missing documentation target: {path.name}: {url}')
            if target.fragment and destination.suffix == '.md':
                if unquote(target.fragment) not in anchors(destination.read_text()):
                    raise ValueError(f'Missing anchor: {path.name}: {url}')
            checked += 1
    print(f'PASS: {len(links)} symlinks, {len(manifest["resources"])} recovered hashes, '
          f'{len(python_files)} Python / {len(js_files)} JS syntax checks, {checked} local links')


if __name__ == '__main__':
    main()
