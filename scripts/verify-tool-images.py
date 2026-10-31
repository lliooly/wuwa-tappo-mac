#!/usr/bin/env python3
"""Check Pillow compatibility against the archived raster assets."""
import json
from pathlib import Path

from PIL import Image

LIBRARY = Path(__file__).resolve().parents[2] / 'wuwa-tappo-assets'


def main():
    manifest = json.loads((LIBRARY / 'data/files.json').read_text())
    checked = 0
    for item in manifest['files']:
        path = LIBRARY / item['path']
        if path.suffix.lower() not in {'.png', '.jpg', '.jpeg', '.ico', '.webp', '.gif'}:
            continue
        with Image.open(path) as image:
            image.verify()
        with Image.open(path) as image:
            image.load()
            if item.get('dimensions') and list(image.size) != item['dimensions']:
                raise ValueError(f'Image dimensions differ: {item["path"]}')
        checked += 1
    if not checked:
        raise ValueError('No raster assets found')
    print(f'PASS: {checked} raster images decoded')


if __name__ == '__main__':
    main()
