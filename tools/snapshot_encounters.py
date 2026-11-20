#!/usr/bin/env python3
"""Refresh tools/test/fixtures/encounters.csv from the game's DungeonEncounter list (data/raw/<data/BUILD>/DungeonEncounter.csv).
The route-consistency test in tools/test/smoke.lua reads it (data/raw is git-ignored, so CI needs this committed copy). Run after every client build update."""
import csv, os
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
build = open(os.path.join(ROOT, "data/BUILD")).read().strip()
src = os.path.join(ROOT, "data/raw", build, "DungeonEncounter.csv")
rows = list(csv.DictReader(open(src, encoding="utf-8")))
out = os.path.join(ROOT, "tools/test/fixtures/encounters.csv")
with open(out, "w", newline="", encoding="utf-8") as f:
    w = csv.writer(f); w.writerow(["map", "difficulty", "id", "name"])
    for r in sorted(rows, key=lambda r: (int(r["MapID"]), int(r["ID"]))):
        w.writerow([r["MapID"], r["DifficultyID"], r["ID"], r["Name_lang"]])
print(f"{len(rows)} encounters from build {build} -> {out}")
