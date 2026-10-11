#!/usr/bin/env python3
"""Build dist/DungeonCrawlerForever-<version>.zip from addon/DungeonCrawlerForever (version from the TOC). Run: python3 tools/package.py"""
import os, re, zipfile
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "addon/DungeonCrawlerForever")
toc = open(os.path.join(SRC, "DungeonCrawlerForever.toc"), encoding="utf-8").read()
version = re.search(r"^## Version: (\S+)", toc, re.M).group(1)
os.makedirs(os.path.join(ROOT, "dist"), exist_ok=True)
out = os.path.join(ROOT, "dist", f"DungeonCrawlerForever-{version}.zip")
n = 0
with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
    for dirpath, dirs, files in os.walk(SRC):
        dirs[:] = [d for d in dirs if not d.startswith(".")]
        for f in sorted(files):
            if f.startswith(".") or f == "Thumbs.db":
                continue
            full = os.path.join(dirpath, f)
            z.write(full, os.path.join("DungeonCrawlerForever", os.path.relpath(full, SRC)))
            n += 1
print(f"{out}: {n} files, {os.path.getsize(out) // 1024} KB")
