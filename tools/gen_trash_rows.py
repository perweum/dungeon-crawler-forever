#!/usr/bin/env python3
"""Write data/manual/boss_trash.csv: one "Trash" entry per dungeon / raid (per wing where a dungeon has wings) that AtlasLoot has a trash
loot table for. The list shows the drops of the regular mobs of the dungeon. Lists with fewer than 2 items are skipped.
Usage: tools/gen_trash_rows.py [path/to/AtlasLootClassic_DungeonsAndRaids]   then tools/gen_dungeons.py && tools/gen_loot.py
(AtlasLoot's trash tables contain no grey (poor quality) items: checked against the classic item database, 2026-10-13.)
"""
import csv, os, re, sys
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ATLAS = sys.argv[1] if len(sys.argv) > 1 else "/Applications/World of Warcraft/_classic_beta_/Interface/AddOns/AtlasLootClassic_DungeonsAndRaids"
KEYS = {"DireMaulEast": 429, "DireMaulWest": 429, "DireMaulNorth": 429}   # AtlasLoot dungeons without an InstanceID
SUFFIX = {"ScarletMonasteryGraveyard": "Graveyard", "ScarletMonasteryLibrary": "Library", "ScarletMonasteryArmory": "Armory",
          "ScarletMonasteryCathedral": "Cathedral", "DireMaulEast": "East", "DireMaulWest": "West", "DireMaulNorth": "North",
          "LowerBlackrockSpire": "Lower", "UpperBlackrockSpire": "Upper"}

def main():
    src = open(os.path.join(ATLAS, "data.lua"), encoding="utf-8").read().replace("\r", "")
    ours = set(re.findall(r"^  \[(\d+)\] = \{ name =", open(os.path.join(ROOT, "addon/DungeonCrawlerForever/Data/Dungeons.lua"), encoding="utf-8").read(), re.M))
    found = []   # (instance, key, items)
    for blk in re.split(r'\n(?=data\["[^"]+"\] = \{)', src):
        m = re.match(r'data\["([^"]+)"\] = \{', blk)
        if not m:
            continue
        key = m.group(1)
        im = re.search(r"^\tInstanceID = (\d+)", blk, re.M)
        inst = im.group(1) if im else (str(KEYS[key]) if key in KEYS else None)
        if not inst or inst not in ours:
            continue
        for bm in re.split(r'\n\t\t\{ ?(?:--[^\n]*)?\n', blk):
            nm = re.search(r'^\t\t\tname = AL\["(Trash(?: Mobs)?)"\]', bm, re.M)
            if nm:
                n = len(re.findall(r"^\s*\{\s*\d+\s*,\s*\d+\s*[,}]", bm, re.M))
                if n >= 2:
                    found.append((inst, key, n))
    per = {}
    for inst, key, n in found:
        per[inst] = per.get(inst, 0) + 1
    rows = []
    for inst, key, n in sorted(found, key=lambda t: (int(t[0]), t[1])):
        name = "Trash" if per[inst] == 1 else "Trash (%s)" % SUFFIX.get(key, key)
        rows.append({"instanceMapID": inst, "name": name, "atlasKey": key, "order": "99000"})
    with open(os.path.join(ROOT, "data/manual/boss_trash.csv"), "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=["instanceMapID", "name", "atlasKey", "order"])
        w.writeheader()
        w.writerows(rows)
    print(f"{len(rows)} trash entries in {len(set(r['instanceMapID'] for r in rows))} instances")

main()
