#!/usr/bin/env python3
"""Activate staged display IDs: merge data/draft/boss_display_cmangos.csv into data/manual/boss_display.csv
(existing manual entries win), then regenerate the data. Run after confirming portraits render in-game."""
import csv, os, subprocess, sys
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
live, staged = (os.path.join(ROOT, p) for p in ("data/manual/boss_display.csv", "data/draft/boss_display_cmangos.csv"))
rows = {}
for p in (staged, live):  # live last so it wins
    if os.path.exists(p):
        for r in csv.DictReader(open(p, encoding="utf-8")):
            rows[(r["instanceMapID"], r["name"])] = r
with open(live, "w", newline="", encoding="utf-8") as f:
    w = csv.DictWriter(f, fieldnames=["instanceMapID", "name", "displayID"])
    w.writeheader()
    for k in sorted(rows, key=lambda k: (int(k[0]), k[1])): w.writerow(rows[k])
print(len(rows), "display IDs active")
subprocess.run([sys.executable, os.path.join(ROOT, "tools/gen_dungeons.py")], check=True)
