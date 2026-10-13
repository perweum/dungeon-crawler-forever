#!/usr/bin/env python3
"""Import boss positions recorded in-game (/dm edit) into data/manual/bosses.csv, then regenerate Data/Dungeons.lua.

Reads DungeonMapDB.manual from WTF/Account/*/SavedVariables/DungeonCrawlerForever.lua (written on /reload or logout):
  manual[instanceMapID][bossName] = { floor = <uiMapID>, x = 0..1, y = 0..1 }
Newest import wins per (instance, boss). Usage: tools/import_manual.py [--no-gen]
"""
import csv, glob, os, subprocess, sys
from lupa import LuaRuntime
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from floors_util import overview_floors, floor_ok

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
    ov = overview_floors()  # dungeons shown as one overview map: positions on their old game floors are not imported
    skipped = 0
    manual = db["manual"] if db else None
    if manual:
        for inst, bosses in manual.items():
            for name, m in bosses.items():
                if not floor_ok(ov, inst, m["floor"]):
                    skipped += 1
                    continue
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
                if not floor_ok(ov, inst, fl):
                    skipped += len(lst)
                    continue
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
    # floor links (DungeonMapDB.markerLinks, linkRemovals) -> data/manual/marker_links.csv
    lout = os.path.join(ROOT, "data/manual/marker_links.csv")
    LF = ["instanceMapID", "floorA", "xA", "yA", "floorB", "xB", "yB"]
    lrows = []
    if os.path.exists(lout):
        lrows = [{k: r[k] for k in LF} for r in csv.DictReader(open(lout, encoding="utf-8"))]
    def same_link(r, inst, fa, xa, ya, fb, xb, yb, tol=0.006):
        def near(f1, x1, y1, f2, x2, y2): return f1 == f2 and abs(x1 - x2) <= tol and abs(y1 - y2) <= tol
        a = (r["floorA"], float(r["xA"]), float(r["yA"])); b = (r["floorB"], float(r["xB"]), float(r["yB"]))
        if r["instanceMapID"] != inst: return False
        return (near(*a, fa, xa, ya) and near(*b, fb, xb, yb)) or (near(*a, fb, xb, yb) and near(*b, fa, xa, ya))
    ldb = db["markerLinks"] if db else None
    added = 0
    if ldb:
        for inst, lst in ldb.items():
            for _, l in lst.items():
                if not (floor_ok(ov, inst, l["fa"]) and floor_ok(ov, inst, l["fb"])):
                    skipped += 1
                    continue
                args = (str(int(inst)), str(int(l["fa"])), l["xa"], l["ya"], str(int(l["fb"])), l["xb"], l["yb"])
                if not any(same_link(r, *args) for r in lrows):
                    lrows.append({"instanceMapID": args[0], "floorA": args[1], "xA": f"{args[2]:.4f}", "yA": f"{args[3]:.4f}",
                                  "floorB": args[4], "xB": f"{args[5]:.4f}", "yB": f"{args[6]:.4f}"})
                    added += 1
    lremoved = 0
    for r in ((db["linkRemovals"] or {}).values() if db else []):
        args = (str(int(r["instance"])), str(int(r["fa"])), r["xa"], r["ya"], str(int(r["fb"])), r["xb"], r["yb"])
        keep = [x for x in lrows if not same_link(x, *args)]
        lremoved += len(lrows) - len(keep)
        lrows = keep
    with open(lout, "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=LF)
        w.writeheader()
        for r in lrows: w.writerow(r)  # keep the order links were made in: the link letters (A, B, C ...) follow it
    print(f"{len(lrows)} floor links in {lout} ({added} new, {lremoved} removed)")
    if skipped:
        print(f"{skipped} recorded positions / markers / links on floors that an overview map replaced were ignored")
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
