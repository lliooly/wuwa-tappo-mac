#!/usr/bin/env python3
"""Create human-readable names and a cross-referenced public atlas catalog."""

from __future__ import annotations

import json
import re
import urllib.parse
from collections import Counter
from pathlib import Path, PurePosixPath


ROOT = Path(__file__).resolve().parents[1] / "recovered/wuwa-tappo-cn-1.0.2/art-assets/remote"


def main() -> None:
    metadata = ROOT / "metadata"
    assets = json.loads((metadata / "appearance_asset.json").read_text())
    atlas = json.loads((metadata / "atlas.json").read_text())["data"]
    names = json.loads((metadata / "dict-zh.json").read_text())
    main_bundle = ROOT.parents[1] / "frontend/assets/index-CuzHFfJW.js"
    bundled_series = dict(re.findall(r'select_series_(\d+)\$9="([^"]+)"', main_bundle.read_text()))
    series_names = {**bundled_series, **names["series"]}
    manifest = json.loads((ROOT / "manifest.json").read_text())
    if manifest["successCount"] != manifest["fileCount"]:
        raise ValueError("The image download is incomplete")
    files = {x["url"]: x for x in manifest["files"] if x["status"] == "ok"}
    aliases = {}
    catalog = []

    def image_path(folder: str, filename: str, relative_url: str) -> str:
        if not re.fullmatch(r"[A-Za-z0-9_-]+\.png", filename):
            raise ValueError(f"Unsafe filename: {filename}")
        url = urllib.parse.urljoin("https://mc-wuwatappo.kurogames-global.com/", relative_url)
        item = files[url]
        target = ROOT / PurePosixPath(item["path"])
        if not target.is_file():
            raise ValueError(f"Missing target: {target}")
        key = str(PurePosixPath("by-name") / folder / filename)
        aliases[key] = item["path"]
        return item["path"]

    categories = {"character_skin_atlas": ("character_skin", "character"),
                  "accessory_atlas": ("accessory", "accessory"),
                  "emote_atlas": ("emote", "emote")}
    for entry in atlas:
        kind, folder = categories[entry["asset_type"]]
        filename = entry["asset_name"]
        atlas_meta = assets[entry["asset_type"]][str(entry["asset_id"])]
        asset_id = str(atlas_meta["height_light_id"])
        asset = assets[kind][asset_id]
        links = {"atlas": image_path(folder + "_atlas", filename, atlas_meta["url"]),
                 "image": image_path(folder, filename, asset["url"])}
        if kind == "character_skin":
            for field, suffix in [("body1", "body_1"), ("body2", "body_2"), ("body3", "body_3"),
                                  ("head1", "head_1"), ("head2", "head_2")]:
                layer_name = filename[:-4] + "_" + suffix + ".png"
                links[field] = image_path(folder, layer_name, asset[field]["url"])
            match = re.fullmatch(r"role_(\d+)_(\d+)\.png", filename)
            if not match:
                raise ValueError(f"Unexpected character name: {filename}")
            role, series = match.groups()
            label = names["character"].get(role, role) + " · " + series_names.get(series, series)
        elif kind == "accessory":
            code = re.fullmatch(r"accessory_(\d+)\.png", filename)
            label = names["accessory"].get(code.group(1), filename) if code else filename
        else:
            match = re.fullmatch(r"emote_(\d+)_([A-Za-z0-9_-]+)\.png", filename)
            if match:
                role, expression = match.groups()
                label = names["character"].get(role, role) + " · " + names["emote"].get(expression, expression)
            else:
                label = names["emote"].get(filename, filename)
        catalog.append({"nameZh": label, "type": kind, "atlasAssetId": entry["asset_id"],
                        "assetId": int(asset_id), "officialFilename": filename,
                        "rarity": entry.get("rarity", ""), "links": links,
                        "atlasEntry": entry, "assetMetadata": asset, "atlasMetadata": atlas_meta})

    if len(aliases) != len(files) or len(catalog) != len(atlas):
        raise ValueError(f"Index coverage mismatch: {len(aliases)} aliases, {len(files)} files, {len(catalog)} items")
    catalog.sort(key=lambda x: (x["type"], x["officialFilename"]))
    snapshot = json.loads((metadata / "snapshot.json").read_text())
    output = {"capturedAtUtc": snapshot["capturedAtUtc"], "itemCount": len(catalog),
              "counts": dict(Counter(x["type"] for x in catalog)), "items": catalog}
    (ROOT / "catalog.json").write_text(json.dumps(output, ensure_ascii=False, indent=2) + "\n")
    (ROOT / "aliases.json").write_text(json.dumps(aliases, ensure_ascii=False, indent=2, sort_keys=True) + "\n")
    lines = ["# 原版公开图鉴素材目录", "", f"索引快照：{snapshot['capturedAtUtc']}。共 {len(catalog)} 个图鉴条目。",
             "", "这些条目来自无需登录的公开图鉴，包含账号尚未解锁的素材；是否已解锁取决于个人账号，本目录不作判断。",
             "", "图鉴图与素材图是官方提供的独立文件；角色另有三张身体和两张头部动作分层。名称链接指向本地文件。", ""]
    for kind, title in [("character_skin", "角色外观"), ("accessory", "配件"), ("emote", "表情")]:
        lines += [f"## {title}", "", "| 名称 | 官方文件名 | 稀有度 | 图鉴图 | 素材图 | 角色分层 |",
                  "| --- | --- | --- | --- | --- | --- |"]
        for item in (x for x in catalog if x["type"] == kind):
            links = item["links"]
            layer_names = [("body1", "身体1"), ("body2", "身体2"), ("body3", "身体3"),
                           ("head1", "头部1"), ("head2", "头部2")]
            layers = " · ".join(f"[{label}]({links[key]})" for key, label in layer_names if key in links) or "—"
            name = item["nameZh"].replace("|", "\\|")
            lines.append(f"| {name} | {item['officialFilename']} | {item['rarity']} | "
                         f"[图鉴]({links['atlas']}) | [素材]({links['image']}) | {layers} |")
        lines.append("")
    (ROOT / "CATALOG.md").write_text("\n".join(lines))
    print(f"Indexed {len(catalog)} atlas entries and {len(aliases)} categorized image paths")


if __name__ == "__main__":
    main()
