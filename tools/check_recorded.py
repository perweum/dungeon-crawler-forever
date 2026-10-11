#!/usr/bin/env python3
"""Fail if positions, portraits or floor markers recorded in game (WTF SavedVariables) are not yet in data/manual/*.csv.

Recorded data only exists on the maintainer's machine (DungeonMapDB.manual / portraits / markers); players get only what was
imported with tools/import_manual.py. Run by tools/package.py before building the zip. Exit code 1 = something would be missing.
Run with the venv python (needs lupa): tools/.venv/bin/python tools/check_recorded.py
"""
import csv, glob, os, sys
from lupa import LuaRuntime

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WTF = "/Applications/World of Warcraft/_classic_beta_/WTF/Account/*/SavedVariables/DungeonCrawlerForever.lua"
TOL = 0.002

def main():
    files = glob.glob(WTF)
    if not files:
        print("check_recorded: no saved variables found, skipping (nothing recorded on this machine)")
        return 0
    shipped = {(r["instanceMapID"], r["name"]): (r["uiMapID"], float(r["x"]), float(r["y"]))
               for r in csv.DictReader(open(os.path.join(ROOT, "data/manual/bosses.csv"), encoding="utf-8"))}
    ship_disp = {(r["instanceMapID"], r["name"]): r["displayID"]
                 for r in csv.DictReader(open(os.path.join(ROOT, "data/manual/boss_display.csv"), encoding="utf-8"))}
    ship_mk = set()
    for r in csv.DictReader(open(os.path.join(ROOT, "data/manual/markers.csv"), encoding="utf-8")):
        ship_mk.add((r["instanceMapID"], r["uiMapID"], r["kind"], f"{float(r['x']):.3f}", f"{float(r['y']):.3f}"))
    problems = []
    for f in files:
        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.execute(open(f, encoding="utf-8").read())
        db = lua.globals().DungeonMapDB
        if not db:
            continue
        for inst, bosses in (db["manual"] or {}).items():
            for name, m in bosses.items():
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
                for _, m in lst.items():
                    if (str(int(inst)), str(int(fl)), m["kind"], f"{m['x']:.3f}", f"{m['y']:.3f}") not in ship_mk:
                        problems.append(f"floor marker not shipped: instance {int(inst)} floor {int(fl)} {m['kind']}")
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
