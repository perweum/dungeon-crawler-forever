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
# The test suite (includes the check that every route stop can be produced by a real client encounter) gates the package when lupa is available.
if "--skip-tests" not in sys.argv and os.path.exists(venv_py):
    if subprocess.run([venv_py, "-B", os.path.join(ROOT, "tools/test/run.py")], stdout=subprocess.DEVNULL).returncode != 0:
        sys.exit("package: not building, the tests fail (run tools/.venv/bin/python -B tools/test/run.py)")
SRC = os.path.join(ROOT, "addon/DungeonCrawlerForever")
toc = open(os.path.join(SRC, "DungeonCrawlerForever.toc"), encoding="utf-8").read()
version = re.search(r"^## Version: (\S+)", toc, re.M).group(1)
os.makedirs(os.path.join(ROOT, "dist"), exist_ok=True)
out = os.path.join(ROOT, "dist", f"DungeonCrawlerForever-{version}.zip")
n = 0
# community map tiles (Art/<instance>_<floor>_<row>_<col>.blp) that Data/ArtCustom.lua does not use (a floor parked while the dungeon shows the game's tile map
# instead, data/manual/art_tile_first.csv) stay in the repository but are not shipped
TILE = re.compile(r"^\d+_\d+_\d+_\d+\.(blp|tga)$", re.I)
used_art = open(os.path.join(SRC, "Data/ArtCustom.lua"), encoding="utf-8").read()
skipped = 0
with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
    for dirpath, dirs, files in os.walk(SRC):
        dirs[:] = [d for d in dirs if not d.startswith(".")]
        for f in sorted(files):
            if f.startswith(".") or f == "Thumbs.db":
                continue
            if TILE.match(f) and os.path.basename(dirpath) == "Art" and ("Art\\\\" + os.path.splitext(f)[0] + '"') not in used_art:
                skipped += 1
                continue
            full = os.path.join(dirpath, f)
            z.write(full, os.path.join("DungeonCrawlerForever", os.path.relpath(full, SRC)))
            n += 1
print(f"{out}: {n} files, {os.path.getsize(out) // 1024} KB" + (f" ({skipped} unused map tiles left out)" if skipped else ""))
