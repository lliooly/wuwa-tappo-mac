#!/usr/bin/env python3
"""Restore original Vite source paths, including images inlined in JS/CSS."""

from __future__ import annotations

import base64
import hashlib
import io
import json
import re
from pathlib import Path, PurePosixPath

from PIL import Image


ROOT = Path(__file__).resolve().parents[1] / "recovered/wuwa-tappo-cn-1.0.3"
FRONTEND = ROOT / "frontend"
OUTPUT = ROOT / "art-assets/bundled"
MAIN_JS = FRONTEND / "assets/index-CuzHFfJW.js"
DATA_URI = re.compile(r"data:image/([^;\s,\"')]+);base64,([A-Za-z0-9+/=]+)")


def main() -> None:
    source = MAIN_JS.read_text()
    pairs = re.findall(r'"(/src/assets/(?:img|role)/[^"\n]+)":(__vite_glob_0_\d+(?:\$1)?)', source)
    if not pairs or len(pairs) != len({path for path, _ in pairs}):
        raise ValueError("Missing or duplicate Vite source paths")
    records = []
    mapped_hashes = set()
    for source_path, variable in pairs:
        pattern = (r"(?<![\w$])" + re.escape(variable)
                   + r'=(?:""\+new URL\("([^"]+)",import\.meta\.url\)\.href|"([^"]+)")')
        match = re.search(pattern, source)
        if not match:
            raise ValueError(f"No binding for {source_path}: {variable}")
        if match.group(1):
            emitted = match.group(1)
            if PurePosixPath(emitted).name != emitted:
                raise ValueError(f"Unexpected emitted path: {emitted}")
            content = (FRONTEND / "assets" / emitted).read_bytes()
            origin = "frontend/assets/" + emitted
        else:
            data_uri = DATA_URI.fullmatch(match.group(2))
            if not data_uri:
                raise ValueError(f"Unexpected inline image: {source_path}")
            content = base64.b64decode(data_uri.group(2), validate=True)
            origin = "frontend/assets/" + MAIN_JS.name + "#" + variable
        digest = hashlib.sha256(content).hexdigest()
        mapped_hashes.add(digest)
        relative = PurePosixPath(source_path.removeprefix("/src/assets/"))
        if relative.is_absolute() or ".." in relative.parts:
            raise ValueError(f"Unexpected source path: {source_path}")
        destination = OUTPUT / "source-tree" / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_bytes(content)
        with Image.open(io.BytesIO(content)) as image:
            image.load()
            dimensions, format_name = list(image.size), image.format
        records.append({"sourcePath": source_path, "path": "source-tree/" + str(relative),
                        "origin": origin, "size": len(content), "sha256": digest,
                        "dimensions": dimensions, "format": format_name})

    inline_occurrences = []
    for path in FRONTEND.rglob("*"):
        if not path.is_file() or path.suffix not in {".js", ".css", ".html", ".svg"}:
            continue
        text = path.read_text(errors="replace")
        for match in DATA_URI.finditer(text):
            content = base64.b64decode(match.group(2), validate=True)
            digest = hashlib.sha256(content).hexdigest()
            inline_occurrences.append({"file": str(path.relative_to(ROOT)), "offset": match.start(), "sha256": digest})
            if digest not in mapped_hashes:
                raise ValueError(f"Unmapped embedded image: {path} at {match.start()}")
    manifest = {"source": str(MAIN_JS.relative_to(ROOT)), "fileCount": len(records),
                "inlineOccurrencesChecked": len(inline_occurrences),
                "uniqueInlineImagesChecked": len({x['sha256'] for x in inline_occurrences}),
                "unmappedInlineImages": 0, "files": records, "inlineOccurrences": inline_occurrences}
    (OUTPUT / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")
    print(f"Restored {len(records)} named source paths; verified {len(inline_occurrences)} inline occurrences "
          f"({manifest['uniqueInlineImagesChecked']} unique images)")


if __name__ == "__main__":
    main()
