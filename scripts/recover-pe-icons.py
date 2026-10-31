#!/usr/bin/env python3
"""Recover PNG icon resources from the installer, app, and uninstaller PE files."""

from __future__ import annotations

import hashlib
import io
import json
import struct
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
SAMPLES = ["WuwaTappo-cn_1.0.2_x64-setup.exe", "WuwaTappo/WuwaTappo.exe", "WuwaTappo/uninstall.exe"]
OUTPUT = ROOT / "recovered/wuwa-tappo-cn-1.0.3/art-assets/bundled/native-icons"


def resources(path: Path) -> list[dict]:
    data = path.read_bytes()
    pe = struct.unpack_from("<I", data, 0x3C)[0]
    count, optional_size = struct.unpack_from("<H", data, pe + 6)[0], struct.unpack_from("<H", data, pe + 20)[0]
    table = pe + 24 + optional_size
    sections = []
    for i in range(count):
        offset = table + 40 * i
        name = data[offset:offset + 8].split(b"\0")[0].decode()
        size, va, raw_size, raw_offset = struct.unpack_from("<IIII", data, offset + 8)
        sections.append((name, va, max(size, raw_size), raw_offset))

    def file_offset(rva: int) -> int:
        for _, va, size, offset in sections:
            if va <= rva < va + size:
                return offset + rva - va
        raise ValueError(f"Unmapped RVA: {rva:x}")

    base = next(item[3] for item in sections if item[0] == ".rsrc")
    found = []

    def walk(offset: int, keys: list[int]) -> None:
        named, ids = struct.unpack_from("<HH", data, offset + 12)
        for i in range(named + ids):
            key, target = struct.unpack_from("<II", data, offset + 16 + 8 * i)
            if key & 0x80000000:
                raise ValueError("Unexpected named resource")
            if target & 0x80000000:
                walk(base + (target & 0x7FFFFFFF), keys + [key])
            else:
                address, size, _, _ = struct.unpack_from("<IIII", data, base + target)
                pos = file_offset(address)
                found.append({"keys": keys + [key], "offset": pos, "bytes": data[pos:pos + size]})

    walk(base, [])
    return found


def main() -> None:
    samples = {name: resources(ROOT / name) for name in SAMPLES}
    first = samples[SAMPLES[0]]
    icons = {x["keys"][1]: x["bytes"] for x in first if x["keys"][0] == 3}
    groups = [x for x in first if x["keys"][0] == 14]
    if len(icons) != 6 or len(groups) != 1:
        raise ValueError("Unexpected icon resources")
    OUTPUT.mkdir(parents=True, exist_ok=True)
    entries = []
    for icon_id, content in sorted(icons.items()):
        with Image.open(io.BytesIO(content)) as image:
            image.load()
            width, height = image.size
        matches = []
        for filename, sample in samples.items():
            match = [x for x in sample if x["keys"][:2] == [3, icon_id]]
            if len(match) != 1 or match[0]["bytes"] != content:
                raise ValueError(f"Icon differs in {filename}: {icon_id}")
            matches.append({"source": filename, "resourceId": icon_id, "languageId": match[0]["keys"][2],
                            "fileOffset": hex(match[0]["offset"])})
        name = f"icon-{icon_id}-{width}x{height}.png"
        (OUTPUT / name).write_bytes(content)
        entries.append({"path": name, "size": len(content), "sha256": hashlib.sha256(content).hexdigest(),
                        "dimensions": [width, height], "sources": matches})

    group = groups[0]["bytes"]
    reserved, icon_type, count = struct.unpack_from("<HHH", group)
    if reserved != 0 or icon_type != 1 or count != len(icons):
        raise ValueError("Invalid group icon")
    header = bytearray(struct.pack("<HHH", 0, 1, count))
    payload = bytearray()
    for i in range(count):
        entry = group[6 + 14 * i:6 + 14 * (i + 1)]
        resource_id = struct.unpack_from("<H", entry, 12)[0]
        content = icons[resource_id]
        if struct.unpack_from("<I", entry, 8)[0] != len(content):
            raise ValueError("Icon size mismatch")
        header.extend(entry[:12])
        header.extend(struct.pack("<I", 6 + 16 * count + len(payload)))
        payload.extend(content)
    ico = bytes(header + payload)
    (OUTPUT / "app.ico").write_bytes(ico)
    (OUTPUT / "manifest.json").write_text(json.dumps({"icons": entries, "ico": {"path": "app.ico",
        "size": len(ico), "sha256": hashlib.sha256(ico).hexdigest()}}, ensure_ascii=False, indent=2) + "\n")
    print(f"Recovered {len(entries)} identical PNG icon resources from each of the three PE files")


if __name__ == "__main__":
    main()
