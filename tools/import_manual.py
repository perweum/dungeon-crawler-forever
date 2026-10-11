#!/usr/bin/env python3
"""Import boss positions recorded in-game (/dm edit) into data/manual/bosses.csv, then regenerate Data/Dungeons.lua.

Reads DungeonMapDB.manual from WTF/Account/*/SavedVariables/DungeonCrawlerForever.lua (written on /reload or logout):
  manual[instanceMapID][bossName] = { floor = <uiMapID>, x = 0..1, y = 0..1 }
Newest import wins per (instance, boss). Usage: tools/import_manual.py [--no-gen]
"""
import csv, glob, os, subprocess, sys
from lupa import LuaRuntime

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WTF = "/Applications/World of Warcraft/_classic_beta_/WTF/Account/*/SavedVariables/DungeonCrawlerForever.lua"
OUT = os.path.join(ROOT, "data/manual/bosses.csv")

KIND_ALIAS = {"arrow_up": "up", "arrow_down": "down", "arrow_left": "left", "arrow_right": "right"}  # marker names of earlier builds

def main():
    files = glob.glob(WTF)
    if not files:
        sys.exit("no DungeonMap.lua SavedVariables found (/reload in game first)")
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(open(files[0], encoding="utf-8").read())
    db = lua.globals().DungeonMapDB
    rows = {}
    if os.path.exists(OUT):
        for r in csv.DictReader(open(OUT, encoding="utf-8")):
            rows[(r["instanceMapID"], r["name"])] = r
    new = 0
    manual = db["manual"] if db else None
    if manual:
        for inst, bosses in manual.items():
            for name, m in bosses.items():
                key = (str(int(inst)), name)
                row = {"instanceMapID": key[0], "uiMapID": str(int(m["floor"])), "name": name,
                       "x": f"{m['x']:.4f}", "y": f"{m['y']:.4f}"}
                if rows.get(key) != row:
                    new += 1
                rows[key] = row
    # creature display IDs recorded with /dm portrait -> data/manual/boss_display.csv
    dout = os.path.join(ROOT, "data/manual/boss_display.csv")
    drows = {}
    if os.path.exists(dout):
        for r in csv.DictReader(open(dout, encoding="utf-8")):
            drows[(r["instanceMapID"], r["name"])] = r
    pdb = db["portraits"] if db else None
    if pdb:
        for inst, bosses in pdb.items():
            for name, did in bosses.items():
                drows[(str(int(inst)), name)] = {"instanceMapID": str(int(inst)), "name": name, "displayID": str(int(did))}
    with open(dout, "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=["instanceMapID", "name", "displayID"])
        w.writeheader()
        for k in sorted(drows, key=lambda k: (int(k[0]), k[1])):
            w.writerow(drows[k])
    print(f"{len(drows)} recorded portraits in {dout}")
    # floor markers recorded with /dm edit (Placing: Entrance / Exit / Stairs / Portal) -> data/manual/markers.csv
    mout = os.path.join(ROOT, "data/manual/markers.csv")
    mrows = {}
    if os.path.exists(mout):
        for r in csv.DictReader(open(mout, encoding="utf-8")):
            mrows[(r["instanceMapID"], r["uiMapID"], r["kind"], f"{float(r['x']):.3f}", f"{float(r['y']):.3f}")] = r
    mdb = db["markers"] if db else None
    if mdb:
        for inst, floors in mdb.items():
            for fl, lst in floors.items():
                for _, m in lst.items():
                    key = (str(int(inst)), str(int(fl)), KIND_ALIAS.get(m["kind"], m["kind"]), f"{m['x']:.3f}", f"{m['y']:.3f}")
                    # an already imported marker of the same kind within 0.002 is the same marker (coordinates were rounded): replace it
                    for old in [k for k, r in mrows.items() if k[:3] == key[:3] and abs(float(r["x"]) - m["x"]) <= 0.002 and abs(float(r["y"]) - m["y"]) <= 0.002]:
                        del mrows[old]
                    mrows[key] = {"instanceMapID": key[0], "uiMapID": key[1], "kind": key[2], "x": f"{m['x']:.4f}", "y": f"{m['y']:.4f}"}
    # markers removed in game (DungeonMapDB.markerRemovals) are deleted from the shipped data
    removed = 0
    for r in ((db["markerRemovals"] or {}).values() if db else []):
        for k in [k for k, row in mrows.items() if k[:3] == (str(int(r["instance"])), str(int(r["floor"])), r["kind"])
                  and abs(float(row["x"]) - r["x"]) <= 0.004 and abs(float(row["y"]) - r["y"]) <= 0.004]:
            del mrows[k]
            removed += 1
    if removed:
        print(f"{removed} floor markers removed (removed in game)")
    with open(mout, "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=["instanceMapID", "uiMapID", "kind", "x", "y"])
        w.writeheader()
        for k in sorted(mrows, key=lambda k: (int(k[0]), int(k[1]), k[2], k[3], k[4])): w.writerow(mrows[k])
    print(f"{len(mrows)} floor markers in {mout}")
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=["instanceMapID", "uiMapID", "name", "x", "y"])
        w.writeheader()
        for k in sorted(rows, key=lambda k: (int(k[0]), k[1])):
            w.writerow(rows[k])
    print(f"{len(rows)} recorded positions in {OUT} ({new} new/changed)")
    if "--no-gen" not in sys.argv:
        subprocess.run([sys.executable, os.path.join(ROOT, "tools/gen_dungeons.py")], check=True)

main()
