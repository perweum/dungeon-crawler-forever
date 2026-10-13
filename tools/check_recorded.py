#!/usr/bin/env python3
"""Fail if positions, portraits or floor markers recorded in game (WTF SavedVariables) are not yet in data/manual/*.csv.

Recorded data only exists on the maintainer's machine (DungeonMapDB.manual / portraits / markers); players get only what was
imported with tools/import_manual.py. Run by tools/package.py before building the zip. Exit code 1 = something would be missing.
Run with the venv python (needs lupa): tools/.venv/bin/python tools/check_recorded.py
"""
import csv, glob, os, sys
from lupa import LuaRuntime
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from floors_util import overview_floors, floor_ok

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WTF = "/Applications/World of Warcraft/_classic_beta_/WTF/Account/*/SavedVariables/DungeonCrawlerForever.lua"
TOL = 0.002
KIND_ALIAS = {"arrow_up": "up", "arrow_down": "down", "arrow_left": "left", "arrow_right": "right"}  # marker names of earlier builds

def main():
    files = glob.glob(WTF)
    if not files:
        print("check_recorded: no saved variables found, skipping (nothing recorded on this machine)")
        return 0
    shipped = {(r["instanceMapID"], r["name"]): (r["uiMapID"], float(r["x"]), float(r["y"]))
               for r in csv.DictReader(open(os.path.join(ROOT, "data/manual/bosses.csv"), encoding="utf-8"))}
    ship_disp = {(r["instanceMapID"], r["name"]): r["displayID"]
                 for r in csv.DictReader(open(os.path.join(ROOT, "data/manual/boss_display.csv"), encoding="utf-8"))}
    ship_mk = []  # (instance, floor, kind, x, y); compared by distance, since coordinates are rounded when imported
    for r in csv.DictReader(open(os.path.join(ROOT, "data/manual/markers.csv"), encoding="utf-8")):
        ship_mk.append((r["instanceMapID"], r["uiMapID"], r["kind"], float(r["x"]), float(r["y"])))
    problems = []
    ov = overview_floors()  # dungeons shown as one overview map: positions on their old game floors are ignored
    for f in files:
        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.execute(open(f, encoding="utf-8").read())
        db = lua.globals().DungeonMapDB
        if not db:
            continue
        for inst, bosses in (db["manual"] or {}).items():
            for name, m in bosses.items():
                if not floor_ok(ov, inst, m["floor"]):
                    continue
                key = (str(int(inst)), name)
                got = shipped.get(key)
                if got is None:
                    problems.append(f"position not shipped: instance {int(inst)} / {name}")
                elif got[0] != str(int(m["floor"])) or abs(got[1] - m["x"]) > TOL or abs(got[2] - m["y"]) > TOL:
                    problems.append(f"position differs from shipped: instance {int(inst)} / {name}")
        for inst, bosses in (db["portraits"] or {}).items():
            for name, did in bosses.items():
                if ship_disp.get((str(int(inst)), name)) != str(int(did)):
                    problems.append(f"portrait not shipped: instance {int(inst)} / {name}")
        for inst, floors in (db["markers"] or {}).items():
            for fl, lst in floors.items():
                if not floor_ok(ov, inst, fl):
                    continue
                for _, m in lst.items():
                    if not any(k[:3] == (str(int(inst)), str(int(fl)), KIND_ALIAS.get(m["kind"], m["kind"])) and abs(k[3] - m["x"]) <= TOL and abs(k[4] - m["y"]) <= TOL
                               for k in ship_mk):
                        problems.append(f"floor marker not shipped: instance {int(inst)} floor {int(fl)} {m['kind']}")
    for f in files:
        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.execute(open(f, encoding="utf-8").read())
        db = lua.globals().DungeonMapDB
        for r in ((db["markerRemovals"] or {}).values() if db else []):
            for k in ship_mk:
                if k[:3] == (str(int(r["instance"])), str(int(r["floor"])), r["kind"]) and abs(k[3] - r["x"]) <= 0.004 and abs(k[4] - r["y"]) <= 0.004:
                    problems.append(f"marker removed in game but still shipped: instance {int(r['instance'])} floor {int(r['floor'])} {r['kind']}")
    ship_links = []
    lp = os.path.join(ROOT, "data/manual/marker_links.csv")
    if os.path.exists(lp):
        for r in csv.DictReader(open(lp, encoding="utf-8")):
            ship_links.append((r["instanceMapID"], r["floorA"], float(r["xA"]), float(r["yA"]), r["floorB"], float(r["xB"]), float(r["yB"])))
    def near(f1, x1, y1, f2, x2, y2): return f1 == f2 and abs(x1 - x2) <= 0.006 and abs(y1 - y2) <= 0.006
    def has_link(inst, fa, xa, ya, fb, xb, yb):
        return any(k[0] == inst and ((near(k[1], k[2], k[3], fa, xa, ya) and near(k[4], k[5], k[6], fb, xb, yb))
                   or (near(k[1], k[2], k[3], fb, xb, yb) and near(k[4], k[5], k[6], fa, xa, ya))) for k in ship_links)
    for f in files:
        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.execute(open(f, encoding="utf-8").read())
        db = lua.globals().DungeonMapDB
        if not db:
            continue
        for inst, lst in (db["markerLinks"] or {}).items():
            for _, l in lst.items():
                if not (floor_ok(ov, inst, l["fa"]) and floor_ok(ov, inst, l["fb"])):
                    continue
                if not has_link(str(int(inst)), str(int(l["fa"])), l["xa"], l["ya"], str(int(l["fb"])), l["xb"], l["yb"]):
                    problems.append(f"floor link not shipped: instance {int(inst)} floors {int(l['fa'])} - {int(l['fb'])}")
        for r in (db["linkRemovals"] or {}).values():
            if has_link(str(int(r["instance"])), str(int(r["fa"])), r["xa"], r["ya"], str(int(r["fb"])), r["xb"], r["yb"]):
                problems.append(f"floor link removed in game but still shipped: instance {int(r['instance'])} floors {int(r['fa'])} - {int(r['fb'])}")
    if problems:
        print("check_recorded: data recorded in game is NOT in data/manual yet:")
        for p in sorted(set(problems)):
            print("  -", p)
        print("Run tools/.venv/bin/python tools/import_manual.py, review, commit, then package again.")
        return 1
    print("check_recorded: everything recorded in game is in the shipped data")
    return 0

if __name__ == "__main__":
    sys.exit(main())
