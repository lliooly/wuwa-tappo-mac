#!/usr/bin/env python3
"""Independently check the recovered image archive and its source coverage."""

from __future__ import annotations

import base64
import hashlib
import json
import re
import struct
import urllib.parse
import xml.etree.ElementTree as ET
import zlib
from pathlib import Path

from PIL import Image


PROJECT = Path(__file__).resolve().parents[1]
RECOVERED = PROJECT / "recovered/wuwa-tappo-cn-1.0.2"
ART = RECOVERED / "art-assets"
DATA_URI = re.compile(r"data:image/([^;\s,\"')]+);base64,([A-Za-z0-9+/=]+)")


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def scan_raw_pngs(data: bytes, known_hashes: set[str]) -> dict:
    signature = b"\x89PNG\r\n\x1a\n"
    position = 0
    signatures = valid = 0
    while True:
        start = data.find(signature, position)
        if start < 0:
            break
        position = start + 1
        signatures += 1
        offset = start + len(signature)
        while offset + 12 <= len(data):
            length = struct.unpack_from(">I", data, offset)[0]
            if length > 16 * 1024 * 1024 or offset + 12 + length > len(data):
                break
            chunk = data[offset + 4:offset + 8 + length]
            crc = struct.unpack_from(">I", data, offset + 8 + length)[0]
            if zlib.crc32(chunk) & 0xFFFFFFFF != crc:
                break
            offset += 12 + length
            if chunk[:4] == b"IEND":
                valid += 1
                if hashlib.sha256(data[start:offset]).hexdigest() not in known_hashes:
                    raise ValueError(f"Unmapped complete PNG at offset {start:#x}")
                break
    return {"signatures": signatures, "completePngs": valid, "unmapped": 0}


def main() -> None:
    original = json.loads((RECOVERED / "manifest.json").read_text())
    for item in original["resources"]:
        path = RECOVERED / "frontend" / item["path"].lstrip("/")
        if not path.is_file() or path.stat().st_size != item["size"] or digest(path) != item["sha256"]:
            raise ValueError(f"Frontend resource differs: {path}")

    bundled = json.loads((ART / "bundled/manifest.json").read_text())
    for item in bundled["files"]:
        path = ART / "bundled" / item["path"]
        if not path.is_file() or path.stat().st_size != item["size"] or digest(path) != item["sha256"]:
            raise ValueError(f"Bundled image differs: {path}")
    known = {x["sha256"] for x in bundled["files"]}
    inline_checks = {}
    for build, folder in [("app", RECOVERED / "frontend"),
                          ("installer", ART / "other-builds/installer/frontend"),
                          ("uninstaller", ART / "other-builds/uninstaller/frontend")]:
        hashes, count = set(), 0
        for path in folder.rglob("*"):
            if not path.is_file() or path.suffix not in {".js", ".css", ".html", ".svg"}:
                continue
            for match in DATA_URI.finditer(path.read_text(errors="replace")):
                content = base64.b64decode(match.group(2), validate=True)
                hashes.add(hashlib.sha256(content).hexdigest())
                count += 1
        if hashes - known:
            raise ValueError(f"Unmapped inline images in {build}: {hashes - known}")
        inline_checks[build] = {"occurrences": count, "unique": len(hashes)}

    original_exe = (PROJECT / original["source"]).read_bytes()
    baseline_images = {x["path"] for x in original["resources"]
                       if Path(x["path"]).suffix.lower() in {".png", ".jpg", ".jpeg", ".svg", ".webp", ".gif"}}
    image_path_pattern = re.compile(
        rb"/(?:assets/[A-Za-z0-9_.-]+\.(?:png|jpe?g|svg|webp|gif)|(?:favicon|app-icon)\.png|vite\.svg|tauri\.svg)"
    )
    other_build_checks = {}
    for build in ("installer", "uninstaller"):
        folder = ART / "other-builds" / build
        build_manifest = json.loads((folder / "manifest.json").read_text())
        for item in build_manifest["resources"]:
            path = folder / "frontend" / item["path"].lstrip("/")
            if not path.is_file() or path.stat().st_size != item["size"] or digest(path) != item["sha256"]:
                raise ValueError(f"Other build resource differs: {path}")
        binary = (PROJECT / build_manifest["source"]).read_bytes()
        image_paths = {m.group().decode() for m in image_path_pattern.finditer(binary)}
        if image_paths - baseline_images:
            raise ValueError(f"Additional standalone image paths in {build}: {image_paths - baseline_images}")
        shared = 0
        for item in original["resources"]:
            if item["path"] == "/index.html":
                continue  # Each build has its own HTML entry point.
            key = item["path"].encode()
            pos = binary.find(key)
            if pos < 0:
                continue
            start = pos + len(key)
            original_start = int(item["compressedOffset"], 16)
            size = item["compressedSize"]
            if binary[start:start + size] != original_exe[original_start:original_start + size]:
                raise ValueError(f"Shared resource differs in {build}: {item['path']}")
            shared += 1
        other_build_checks[build] = {"distinctCodeResourcesChecked": len(build_manifest["resources"]),
                                     "sharedCompressedResourcesChecked": shared,
                                     "additionalStandaloneImagePaths": 0}

    native = ART / "bundled/native-icons"
    native_manifest = json.loads((native / "manifest.json").read_text())
    for item in native_manifest["icons"] + [native_manifest["ico"]]:
        path = native / item["path"]
        if path.stat().st_size != item["size"] or digest(path) != item["sha256"]:
            raise ValueError(f"Native icon differs: {path}")
        with Image.open(path) as image:
            image.load()
    known_pngs = known | {x["sha256"] for x in native_manifest["icons"]} | {
        x["sha256"] for x in original["resources"] if x["path"].lower().endswith(".png")
    }
    raw_png_checks = {"app": scan_raw_pngs(original_exe, known_pngs)}
    for build in ("installer", "uninstaller"):
        build_manifest = json.loads((ART / "other-builds" / build / "manifest.json").read_text())
        raw_png_checks[build] = scan_raw_pngs((PROJECT / build_manifest["source"]).read_bytes(), known_pngs)

    sdk = ART / "sdk"
    sdk_manifest = json.loads((sdk / "manifest.json").read_text())
    sdk_hashes = set()
    for item in sdk_manifest["images"]:
        path = sdk / item["path"]
        if path.stat().st_size != item["size"] or digest(path) != item["sha256"]:
            raise ValueError(f"SDK image differs: {path}")
        if item["mime"] == "svg+xml":
            if ET.parse(path).getroot().tag != "{http://www.w3.org/2000/svg}svg":
                raise ValueError(f"Invalid SDK SVG: {path}")
        else:
            with Image.open(path) as image:
                image.load()
                if list(image.size) != item["dimensions"]:
                    raise ValueError(f"Invalid SDK PNG dimensions: {path}")
        sdk_hashes.add(item["sha256"])
    sdk_occurrences = 0
    for source in sdk_manifest["sources"]:
        path = sdk / source["path"]
        if path.stat().st_size != source["size"] or digest(path) != source["sha256"]:
            raise ValueError(f"SDK source differs: {path}")
        for match in DATA_URI.finditer(path.read_text()):
            if hashlib.sha256(base64.b64decode(match.group(2), validate=True)).hexdigest() not in sdk_hashes:
                raise ValueError(f"Unmapped SDK image in {path}")
            sdk_occurrences += 1
    if sdk_occurrences != sdk_manifest["inlineOccurrences"] or len(sdk_hashes) != sdk_manifest["uniqueImageContents"]:
        raise ValueError("SDK inline image coverage differs")

    remote = ART / "remote"
    remote_manifest = json.loads((remote / "manifest.json").read_text())
    metadata = json.loads((remote / "metadata/appearance_asset.json").read_text())
    urls = set()

    def collect(obj: object) -> None:
        if isinstance(obj, dict):
            for key, value in obj.items():
                if key == "url" and isinstance(value, str) and value.strip():
                    urls.add(urllib.parse.urljoin("https://mc-wuwatappo.kurogames-global.com/", value.strip()))
                else:
                    collect(value)
        elif isinstance(obj, list):
            for value in obj:
                collect(value)

    collect(metadata)
    recorded = {item["url"] for item in remote_manifest["files"]}
    if urls != recorded or len(recorded) != remote_manifest["fileCount"]:
        raise ValueError("Catalog URLs and manifest do not match")
    for item in remote_manifest["files"]:
        path = remote / item["path"]
        if item["status"] != "ok" or not path.is_file() or path.stat().st_size != item["size"] or digest(path) != item["sha256"]:
            raise ValueError(f"Remote image differs: {path}")
        with Image.open(path) as image:
            image.verify()
        with Image.open(path) as image:
            image.load()
            if list(image.size) != item["dimensions"]:
                raise ValueError(f"Unexpected dimensions: {path}")
    aliases = json.loads((remote / "aliases.json").read_text())
    if len(aliases) != len(recorded):
        raise ValueError("Incomplete named paths")
    permitted_asset_roots = [(PROJECT / "assets").resolve(),
                             (PROJECT.parent / "wuwa-tappo-assets/assets").resolve()]
    for alias, target in aliases.items():
        path = (remote / target).resolve(strict=True)
        if not path.is_file() or not any(path.is_relative_to(root) for root in permitted_asset_roots):
            raise ValueError(f"Broken or incorrect categorized path: {alias}")
    catalog = json.loads((remote / "catalog.json").read_text())
    atlas = json.loads((remote / "metadata/atlas.json").read_text())["data"]
    if {(x["atlasAssetId"], x["type"] + "_atlas") for x in catalog["items"]} != {
        (x["asset_id"], x["asset_type"]) for x in atlas
    }:
        raise ValueError("Atlas entries and named catalog do not match")
    if {link for item in catalog["items"] for link in item["links"].values()} != set(aliases.values()):
        raise ValueError("Named catalog and aliases do not match")

    report = {"frontendResourcesChecked": len(original["resources"]),
              "bundledSourcePathsChecked": len(bundled["files"]),
              "inlineImages": inline_checks, "otherBuilds": other_build_checks,
              "nativePngIconsChecked": len(native_manifest["icons"]), "rawPngScan": raw_png_checks,
              "sdkNamedImagesChecked": len(sdk_manifest["images"]), "sdkInlineOccurrencesChecked": sdk_occurrences,
              "remoteIndexedUrls": len(urls), "remotePngsChecked": len(recorded),
              "namedPathsChecked": len(aliases), "atlasEntriesChecked": len(atlas),
              "allChecksPassed": True}
    (ART / "verification.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps(report, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
