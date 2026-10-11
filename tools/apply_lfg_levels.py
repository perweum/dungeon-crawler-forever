#!/usr/bin/env python3
"""Apply the game's own dungeon-finder levels (data/manual/lfg_levels.csv, read in game with `/dmprobe lfg`, GetLFGDungeonInfo)
to data/manual/dungeon_info.csv and data/manual/wings.csv.

The game gives ONE level per classic dungeon (its recommended / entry level), no range. We keep the width of the range from
foreverdb.net and move the range so it starts at the game's level (a range that ends at 60 stays capped at 60). The wings of an
instance (Scarlet Monastery, Lower/Upper Blackrock Spire, Dire Maul) are moved by the same amount. Idempotent.
Usage: python3 tools/apply_lfg_levels.py   (then tools/gen_dungeons.py and tools/gen_loot.py)
"""
import csv, os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CAP = 60

def shift(lo, hi, delta):
    lo2 = lo + delta
    hi2 = hi if hi >= CAP else min(CAP, hi + delta)
    return lo2, hi2

def main():
    lfg = {r["instanceMapID"]: int(r["level"]) for r in csv.DictReader(open(os.path.join(ROOT, "data/manual/lfg_levels.csv"), encoding="utf-8"))}
    ip = os.path.join(ROOT, "data/manual/dungeon_info.csv")
    rows = list(csv.DictReader(open(ip, encoding="utf-8")))
    fields = list(rows[0].keys())
    delta = {}
    for r in rows:
        inst = r["instanceMapID"]
        if inst in lfg and r["recMinLevel"]:
            lo, hi = int(float(r["recMinLevel"])), int(float(r["recMaxLevel"]))
            d = lfg[inst] - lo
            delta[inst] = d
            lo2, hi2 = shift(lo, hi, d)
            if (lo2, hi2) != (lo, hi):
                print(f"{r['name']:24} {lo}-{hi} -> {lo2}-{hi2}")
            r["recMinLevel"], r["recMaxLevel"] = str(lo2), str(hi2)
    with open(ip, "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=fields)
        w.writeheader()
        w.writerows(rows)
    wp = os.path.join(ROOT, "data/manual/wings.csv")
    wrows = list(csv.DictReader(open(wp, encoding="utf-8")))
    wfields = list(wrows[0].keys())
    for r in wrows:
        d = delta.get(r["instanceMapID"])
        if d:
            lo, hi = int(r["recMin"]), int(r["recMax"])
            lo2, hi2 = shift(lo, hi, d)
            if (lo2, hi2) != (lo, hi):
                print(f"  wing {r['name']:34} {lo}-{hi} -> {lo2}-{hi2}")
            r["recMin"], r["recMax"] = str(lo2), str(hi2)
    with open(wp, "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=wfields)
        w.writeheader()
        w.writerows(wrows)

if __name__ == "__main__":
    main()
