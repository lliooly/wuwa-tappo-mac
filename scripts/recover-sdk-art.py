#!/usr/bin/env python3
"""Recover inline images from the archived public login SDK snapshot."""

from __future__ import annotations

import base64
import hashlib
import io
import json
import re
import xml.etree.ElementTree as ET
from datetime import datetime, timezone
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1] / "recovered/wuwa-tappo-cn-1.0.3/art-assets/sdk"
DATA = re.compile(r"data:image/([^;\s,\"')]+);base64,([A-Za-z0-9+/=]+)")
SOURCES = {"kr-sdk.js": "https://pro-cdn-sdk.kurogame.com/pro/web-sdk/1.x/kr-sdk.js",
           "style.css": "https://pro-cdn-sdk.kurogame.com/pro/web-sdk/1.x/style.css"}


def main() -> None:
    images = []
    hashes = set()
    source_info = []
    source_text = (ROOT / "source/kr-sdk.js").read_text()
    for match in DATA.finditer(source_text):
        prefix = source_text[max(0, match.start() - 100):match.start()]
        binding = re.search(r"([A-Za-z_$][\w$]*)\s*=\s*[\"']$", prefix)
        if not binding:
            raise ValueError(f"Image has no variable name at character {match.start()}")
        variable = binding.group(1)
        name = variable.replace("$", "_")
        mime = match.group(1)
        extension = {"svg+xml": "svg", "png": "png"}.get(mime)
        if not extension:
            raise ValueError(f"Unexpected image type: {mime}")
        content = base64.b64decode(match.group(2), validate=True)
        if extension == "svg":
            if ET.fromstring(content).tag != "{http://www.w3.org/2000/svg}svg":
                raise ValueError(f"Invalid SVG: {name}")
            dimensions = None
        else:
            with Image.open(io.BytesIO(content)) as image:
                image.load()
                dimensions = list(image.size)
        output = ROOT / "images" / f"{name}.{extension}"
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_bytes(content)
        checksum = hashlib.sha256(content).hexdigest()
        hashes.add(checksum)
        images.append({"variable": variable, "path": str(output.relative_to(ROOT)), "mime": mime,
                       "size": len(content), "sha256": checksum, "dimensions": dimensions,
                       "source": "source/kr-sdk.js", "characterOffset": match.start()})
    occurrences = []
    for filename, url in SOURCES.items():
        path = ROOT / "source" / filename
        raw = path.read_bytes()
        text = raw.decode()
        source_info.append({"path": str(path.relative_to(ROOT)), "url": url, "size": len(raw),
                            "sha256": hashlib.sha256(raw).hexdigest()})
        for match in DATA.finditer(text):
            checksum = hashlib.sha256(base64.b64decode(match.group(2), validate=True)).hexdigest()
            if checksum not in hashes:
                raise ValueError(f"Image not mapped in SDK source: {filename} at {match.start()}")
            occurrences.append({"source": "source/" + filename, "characterOffset": match.start(), "sha256": checksum})
    manifest = {"capturedAtUtc": datetime.now(timezone.utc).isoformat(), "sources": source_info,
                "namedImages": len(images), "uniqueImageContents": len(hashes),
                "inlineOccurrences": len(occurrences), "images": images, "occurrences": occurrences}
    (ROOT / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")
    print(f"Recovered {len(images)} named SDK images ({len(hashes)} unique, {len(occurrences)} occurrences)")


if __name__ == "__main__":
    main()
