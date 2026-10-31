#!/usr/bin/env python3
"""Archive the public appearance catalog and its exact referenced PNG files."""

from __future__ import annotations

import concurrent.futures
import argparse
import hashlib
import json
import os
import random
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from collections import defaultdict
from datetime import datetime, timezone
from pathlib import Path, PurePosixPath

from PIL import Image


ROOT = Path(__file__).resolve().parents[1] / "recovered/wuwa-tappo-cn-1.0.3/art-assets/remote"
API = "https://api-mc-wuwatappo.kurogames-global.com"
HOST = "https://mc-wuwatappo.kurogames-global.com"
HOSTNAME = urllib.parse.urlsplit(HOST).hostname
USER_AGENT = "WuwaTappo-asset-archive/1.0"


def read_url(url: str) -> bytes:
    parsed = urllib.parse.urlsplit(url)
    if parsed.scheme != "https" or parsed.hostname not in {HOSTNAME, urllib.parse.urlsplit(API).hostname}:
        raise ValueError(f"Unexpected host: {url}")
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(request, timeout=30) as response:
        final = urllib.parse.urlsplit(response.geturl())
        if final.scheme != "https" or final.hostname not in {HOSTNAME, urllib.parse.urlsplit(API).hostname}:
            raise ValueError(f"Unexpected redirect: {response.geturl()}")
        data = response.read(16 * 1024 * 1024 + 1)
        if len(data) > 16 * 1024 * 1024:
            raise ValueError(f"Response too large: {url}")
        return data


def save_bytes(path: Path, data: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(path.name + ".part")
    tmp.write_bytes(data)
    os.replace(tmp, path)


def get_json(url: str, filename: str) -> object:
    raw = read_url(url)
    data = json.loads(raw)
    save_bytes(ROOT / "metadata" / filename, raw)
    return data


def snapshot() -> None:
    config = get_json(API + "/api/common/activity-config", "activity-config.json")
    if config.get("code") != 0 or config.get("data", {}).get("assets_host", "").rstrip("/") != HOST:
        raise ValueError("Unexpected activity configuration")
    host = get_json(HOST + "/app/json-host/appearance_asset_host.json", "appearance_asset_host.json")
    catalog_url = host["url"]
    catalog = get_json(catalog_url, "appearance_asset.json")
    required = {"character_skin", "accessory", "emote", "character_skin_atlas", "accessory_atlas", "emote_atlas"}
    if not isinstance(catalog, dict) or not all(isinstance(catalog.get(k), dict) for k in required):
        raise ValueError("Unexpected appearance catalog")
    atlas = get_json(API + "/api/common/atlas", "atlas.json")
    if atlas.get("code") != 0 or not isinstance(atlas.get("data"), list):
        raise ValueError("Unexpected atlas response")
    languages = get_json(HOST + "/app/json-host/dict_host.json", "dict_host.json")
    for lang, url in sorted(languages["url"].items()):
        if not lang.replace("_", "").isalnum():
            raise ValueError(f"Unexpected language key: {lang}")
        get_json(url, f"dict-{lang}.json")
    metadata = {
        "capturedAtUtc": datetime.now(timezone.utc).isoformat(),
        "activityConfig": API + "/api/common/activity-config",
        "atlas": API + "/api/common/atlas",
        "appearanceHostIndex": HOST + "/app/json-host/appearance_asset_host.json",
        "appearanceCatalog": catalog_url,
        "dictionaryHostIndex": HOST + "/app/json-host/dict_host.json",
        "assetsHost": HOST,
        "assetsJsonTimestamp": config["data"].get("assets_json_ts"),
    }
    save_bytes(ROOT / "metadata" / "snapshot.json", (json.dumps(metadata, ensure_ascii=False, indent=2) + "\n").encode())
    print("Snapshot saved:", {k: len(catalog[k]) for k in sorted(required)}, flush=True)


def collect_references(catalog: dict) -> dict:
    references = defaultdict(list)

    def walk(obj: object, kind: str, asset_id: str, fields: list[str]) -> None:
        if not isinstance(obj, dict):
            return
        for key, value in obj.items():
            if key == "url" and isinstance(value, str) and value.strip():
                url = urllib.parse.urljoin(HOST + "/", value.strip())
                parsed = urllib.parse.urlsplit(url)
                path = PurePosixPath(urllib.parse.unquote(parsed.path.lstrip("/")))
                if (parsed.scheme != "https" or parsed.hostname != HOSTNAME or len(path.parts) != 2
                        or path.parts[0] not in {"character", "character_atlas", "accessory", "accessory_atlas", "emote", "emote_atlas"}
                        or path.suffix.lower() != ".png" or any(part in {".", ".."} for part in path.parts)):
                    raise ValueError(f"Unexpected asset URL: {url}")
                references[(str(path), url)].append({"type": kind, "assetId": asset_id, "field": ".".join(fields + [key])})
            elif isinstance(value, dict):
                walk(value, kind, asset_id, fields + [key])

    for kind, entries in catalog.items():
        if isinstance(entries, dict):
            for asset_id, entry in entries.items():
                walk(entry, kind, str(asset_id), [])
    paths = defaultdict(set)
    for path, url in references:
        paths[path].add(url)
    collisions = [path for path, urls in paths.items() if len(urls) > 1]
    if collisions:
        raise ValueError(f"Different URLs resolve to the same local path: {collisions[:5]}")
    return references


def image_info(path: Path) -> tuple[int, str, list[int]]:
    raw = path.read_bytes()
    if not raw.startswith(b"\x89PNG\r\n\x1a\n"):
        raise ValueError("Not a PNG")
    with Image.open(path) as image:
        image.verify()
    with Image.open(path) as image:
        image.load()
        size = list(image.size)
    return len(raw), hashlib.sha256(raw).hexdigest(), size


def download_one(item: tuple) -> dict:
    (relative_path, url), refs, previous = item
    path = ROOT / "files" / relative_path
    if (previous and previous.get("status") == "ok" and previous.get("url") == url
            and path.exists()):
        try:
            size, digest, dimensions = image_info(path)
            if size == previous.get("size") and digest == previous.get("sha256"):
                return {"path": "files/" + relative_path, "url": url, "size": size, "sha256": digest,
                        "dimensions": dimensions, "references": refs, "status": "ok"}
        except Exception:
            pass
    error = ""
    temporary = path.with_name(path.name + ".download")
    for attempt in range(4):
        try:
            raw = read_url(url)
            save_bytes(temporary, raw)
            size, digest, dimensions = image_info(temporary)
            os.replace(temporary, path)
            return {"path": "files/" + relative_path, "url": url, "size": size, "sha256": digest,
                    "dimensions": dimensions, "references": refs, "status": "ok"}
        except Exception as exc:
            error = f"{type(exc).__name__}: {exc}"
            if temporary.exists():
                temporary.unlink()
            if isinstance(exc, urllib.error.HTTPError) and exc.code in {401, 403, 404, 410}:
                break
            time.sleep(min(2 ** attempt, 8) + random.random() * 0.3)
    return {"path": "files/" + relative_path, "url": url, "references": refs, "status": "failed", "error": error}


def download() -> None:
    catalog = json.loads((ROOT / "metadata/appearance_asset.json").read_text())
    references = collect_references(catalog)
    previous_path = ROOT / "manifest.json"
    previous = {}
    if previous_path.exists():
        previous = {x["path"]: x for x in json.loads(previous_path.read_text()).get("files", [])}
    print(f"Downloading {len(references)} indexed PNG files, at most 6 simultaneous requests", flush=True)
    results = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=6) as pool:
        futures = [pool.submit(download_one, (key, refs, previous.get("files/" + key[0])))
                   for key, refs in sorted(references.items())]
        for future in concurrent.futures.as_completed(futures):
            result = future.result()
            results.append(result)
            if result["status"] != "ok":
                print("FAILED", result["path"], result["error"], flush=True)
            if len(results) % 100 == 0 or len(results) == len(futures):
                failed = sum(x["status"] != "ok" for x in results)
                print(f"{len(results)}/{len(futures)} complete; {failed} failed", flush=True)
    results.sort(key=lambda x: x["path"])
    manifest = {"catalog": "metadata/appearance_asset.json", "fileCount": len(results),
                "successCount": sum(x["status"] == "ok" for x in results), "files": results}
    save_bytes(ROOT / "manifest.json", (json.dumps(manifest, ensure_ascii=False, indent=2) + "\n").encode())
    if manifest["successCount"] != manifest["fileCount"]:
        sys.exit(1)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="保存官方公开的素材索引和图片")
    parser.add_argument("action", choices=("snapshot", "download"))
    parser.add_argument("--output", type=Path, help="下载暂存目录；已分类的素材目录不会被覆盖")
    args = parser.parse_args()
    if args.output is not None:
        ROOT = args.output.expanduser().resolve()
    if (ROOT / ".categorized").exists():
        raise SystemExit("素材归档已分类整理；请用 --output 指定独立的暂存目录，避免覆盖现有索引。")
    if args.action == "snapshot":
        snapshot()
    else:
        download()
