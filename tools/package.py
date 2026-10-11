#!/usr/bin/env python3
"""Build dist/DungeonCrawlerForever-<version>.zip from addon/DungeonCrawlerForever (version from the TOC). Run: python3 tools/package.py"""
import os, re, subprocess, sys, zipfile
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# Refuse to package while data recorded in game (only on the maintainer's machine) is missing from the shipped data.
# Skip with --skip-recorded-check (CI has no saved variables and passes anyway).
venv_py = os.path.join(ROOT, "tools/.venv/bin/python")
if "--skip-recorded-check" not in sys.argv and os.path.exists(venv_py):
    if subprocess.run([venv_py, os.path.join(ROOT, "tools/check_recorded.py")]).returncode != 0:
        sys.exit("package: not building, see above")
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
