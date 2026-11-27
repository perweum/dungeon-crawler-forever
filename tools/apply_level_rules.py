#!/usr/bin/env python3
"""Apply the level rules (D-081) to data/manual/dungeon_info.csv (recMinLevel / recMaxLevel) and data/manual/wings.csv (recMin / recMax).

The game only knows ONE level per dungeon (its Dungeon Finder level, data/manual/avail_levels.csv, read in game with `/dm probe lfg`): "Available".
The "Recommended" range is ours:
  * low  = max(Available, the highest boss level of the dungeon or wing - 5): a boss more than 5 levels above you is one you cannot hit.
  * high = the current upper bound (from foreverdb.net), never above the highest player level at which the LOWEST boss is still not grey
           (grey: level <= player - 5 below 40 ... see gray_level), and never below the low.
  * The nine new Forever dungeons keep Blizzard's official ranges; only a low below Available is raised to it.
  * EXEMPT dungeons keep their range (only raised to Available): Uldaman (maintainer, 2026-11-27).
Boss levels come from addon/.../Data/BossLevels.lua and the wing boss lists from Data/Wings.lua (both generated). Idempotent: run it again and nothing changes.
Usage: tools/.venv/bin/python tools/apply_level_rules.py   (then tools/gen_dungeons.py and tools/gen_loot.py)
"""
import csv, os
from lupa import LuaRuntime

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA = os.path.join(ROOT, "addon/DungeonCrawlerForever/Data")
NEW = {3065, 2999, 2998, 2959, 2970, 3039, 2994, 2974, 3001}   # the nine new Forever dungeons: official ranges
EXEMPT = {70}                                                    # Uldaman: the existing recommended range stays
HIT = 5                                                          # a boss more than this many levels above you cannot be hit

def gray_level(p):
    """The highest mob level that is grey for a player of level p (the game's formula)."""
    if p <= 5: return 0
    if p <= 39: return p - p // 10 - 5
    if p <= 59: return p - p // 5 - 1
    return p - 9

def cap_for(lowest_boss):
    """The highest player level at which a boss of this level is not grey yet."""
    cap = 60
    for p in range(1, 61):
        if lowest_boss <= gray_level(p):
            cap = p - 1
            break
    return cap

def load_lua():
    L = LuaRuntime(unpack_returned_tuples=True)
    ns = L.eval("{}")
    run = L.eval("function(src, ns) local f = assert(load(src, '=x')) return f('DCF', ns) end")
    for f in ("Dungeons.lua", "BossLevels.lua", "Wings.lua"):
        run(open(os.path.join(DATA, f), encoding="utf-8").read(), ns)
    return ns

def levels(bosslv, names):
    out = []
    for n, v in bosslv.items():
        if names is not None and n not in names: continue
        try:
            if isinstance(v, (int, float)): out.append(int(v))
            else: out += [int(v[1]), int(v[2])]
        except Exception:
            pass
    return [x for x in out if x < 900]   # 999 = the skull ("??")

def rule(avail, lo_boss, hi_boss, cur_lo, cur_hi, new, exempt):
    if new or exempt:
        low = max(cur_lo, avail)
        return low, max(low, cur_hi)
    low = max(avail, hi_boss - HIT)
    high = min(cur_hi, cap_for(lo_boss), 60)
    return low, max(low, high)

def main():
    ns = load_lua()
    avail = {int(r["instanceMapID"]): int(r["level"]) for r in csv.DictReader(open(os.path.join(ROOT, "data/manual/avail_levels.csv"), encoding="utf-8"))}
    ip = os.path.join(ROOT, "data/manual/dungeon_info.csv")
    irows = list(csv.DictReader(open(ip, encoding="utf-8")))
    ifields = list(irows[0].keys())
    wp = os.path.join(ROOT, "data/manual/wings.csv")
    wrows = list(csv.DictReader(open(wp, encoding="utf-8")))
    wfields = list(wrows[0].keys())
    changes = []
    wing_lows = {}
    wing_instances = {int(r["instanceMapID"]) for r in wrows}
    for r in wrows:
        inst = int(r["instanceMapID"])
        a = avail.get(inst)
        if a is None or not r["recMin"]: continue
        bl = ns.BossLevels[inst]
        w = next((w for _, w in ns.Wings[inst].items() if int(w.wing) == int(r["wing"])), None) if ns.Wings[inst] else None
        names = {k for k in w.bosses.keys() if not k.startswith("Trash")} if w else None
        lv = levels(bl, names) if bl else []
        if not lv: continue
        lo, hi = rule(a, min(lv), max(lv), int(float(r["recMin"])), int(float(r["recMax"])), inst in NEW, inst in EXEMPT)
        if (str(lo), str(hi)) != (r["recMin"], r["recMax"]):
            changes.append((r["name"], f"{r['recMin']}-{r['recMax']}", f"{lo}-{hi}"))
        r["recMin"], r["recMax"] = str(lo), str(hi)
        wing_lows.setdefault(inst, []).append(lo)
    by_name = {d.name: int(i) for i, d in ns.Dungeons.items()}   # (the rows of the new dungeons have no map id in dungeon_info.csv: they are found by name)
    for r in irows:
        inst = int(r["instanceMapID"]) if r["instanceMapID"] else by_name.get(r["name"])
        if inst is None: continue
        a = avail.get(inst)
        if a is None or not r["recMinLevel"]: continue
        cur_lo, cur_hi = int(float(r["recMinLevel"])), int(float(r["recMaxLevel"]))
        if inst in wing_instances:     # the instance row of a dungeon with wings: the lowest wing low, the upper bound stays
            lo, hi = min(wing_lows.get(inst, [cur_lo])), cur_hi
        else:
            bl = ns.BossLevels[inst]
            lv = levels(bl, None) if bl else []
            if not lv: continue
            lo, hi = rule(a, min(lv), max(lv), cur_lo, cur_hi, inst in NEW, inst in EXEMPT)
        if (lo, hi) != (cur_lo, cur_hi):
            changes.append((r["name"], f"{cur_lo}-{cur_hi}", f"{lo}-{hi}"))
        r["recMinLevel"], r["recMaxLevel"] = str(lo), str(hi)
    for path, fields, rows in ((ip, ifields, irows), (wp, wfields, wrows)):
        with open(path, "w", newline="", encoding="utf-8") as f:
            w = csv.DictWriter(f, fieldnames=fields, lineterminator="\n")
            w.writeheader()
            w.writerows(rows)
    for n, a, b in changes:
        print(f"{n:34} {a:>8} -> {b}")
    print(f"{len(changes)} ranges changed")

if __name__ == "__main__":
    main()
