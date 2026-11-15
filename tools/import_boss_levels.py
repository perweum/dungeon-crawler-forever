#!/usr/bin/env python3
"""Compare the boss levels recorded in game (addon/DungeonMapProbe/BossLevels.lua, /dmlevels) with the levels we ship, and optionally apply them.

Reads DungeonMapBossLevelsDB from WTF/Account/*/SavedVariables/DungeonMapProbe.lua (written on /reload or logout):
  seen[instanceMapID][unitName] = { levels = { [level] = sightings }, class, npc, n }      level -1 = the skull (??)
Matches each recorded name to one of our bosses (Data/Dungeons.lua) by name, through data/manual/boss_names.csv (client name -> display name) and
through the parts of a combined name ("Izha'Rel and Tor'Rel", "Jammal'an and Ogom"). The level seen most often wins.

Usage: tools/import_boss_levels.py [--apply] [--min N] [--file <copied DungeonMapProbe.lua>]
  default: only a report (new levels, changes, bosses that agree, recorded names that are not bosses of ours: rares we do not list yet)
  --apply  write the new and changed levels to data/manual/boss_levels.csv (replacing a row of the same boss), then run tools/gen_loot.py
  --min N  ignore a level seen fewer than N times (default 1)
Run with the venv python (lupa): tools/.venv/bin/python tools/import_boss_levels.py
"""
import csv, glob, os, re, subprocess, sys, time, unicodedata
from lupa import LuaRuntime

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WOW_DIR = os.environ.get("WOW_DIR", "/Applications/World of Warcraft/_forever_")
SV = WOW_DIR + "/WTF/Account/*/SavedVariables/DungeonMapProbe.lua"
CSV_OUT = os.path.join(ROOT, "data/manual/boss_levels.csv")
FIELDS = ["instanceMapID", "name", "level", "source"]


def norm(s):
    s = unicodedata.normalize("NFKD", s).encode("ascii", "ignore").decode().lower()
    s = re.sub(r"[^a-z0-9 ]", " ", s)
    return re.sub(r"\s+", " ", re.sub(r"\b(the)\b", " ", s)).strip()


def our_bosses():
    s = open(os.path.join(ROOT, "addon/DungeonCrawlerForever/Data/Dungeons.lua"), encoding="utf-8").read()
    out = {}
    for m in re.finditer(r'\[(\d+)\] = \{ name = "([^"]+)", raid = (true|false)[^\n]*\n((?:    \{[^\n]*\n)+)', s):
        out[int(m.group(1))] = (m.group(2), [re.search(r'name = "([^"]+)"', l).group(1) for l in m.group(4).splitlines() if "trash = true" not in l])
    return out


def renames():
    out = {}
    p = os.path.join(ROOT, "data/manual/boss_names.csv")
    if os.path.exists(p):
        for r in csv.DictReader(open(p, encoding="utf-8")):
            out[(int(r["instanceMapID"]), norm(r["displayName"]))] = r["clientName"]
    return out


def current_levels():
    s = open(os.path.join(ROOT, "addon/DungeonCrawlerForever/Data/BossLevels.lua"), encoding="utf-8").read()
    out = {}
    for m in re.finditer(r"\[(\d+)\] = \{ (.*) \},\n", s):
        d = {}
        for k, v in re.findall(r'\["([^"]+)"\] = (\{[^}]*\}|\d+)', m.group(2)):
            d[k] = tuple(int(x) for x in re.findall(r"\d+", v)) if v.startswith("{") else (int(v),)
        out[int(m.group(1))] = d
    return out


def lua_dict(t):
    return {k: lua_dict(v) if hasattr(v, "items") else v for k, v in t.items()}


def show(t):
    if t is None:
        return "none"
    return "??" if t[0] >= 900 else (str(t[0]) if len(t) == 1 or t[0] == t[1] else f"{t[0]}-{t[1]}")


def csvval(t):
    return "??" if t[0] >= 900 else (str(t[0]) if len(t) == 1 or t[0] == t[1] else f"{t[0]}-{t[1]}")


def main():
    argv = sys.argv[1:]
    arg = lambda n, d=None: argv[argv.index(n) + 1] if n in argv and argv.index(n) + 1 < len(argv) else d
    minseen = int(arg("--min", "1"))
    files = [arg("--file")] if arg("--file") else sorted(glob.glob(SV), key=os.path.getmtime, reverse=True)
    if not files or not os.path.exists(files[0]):
        sys.exit("no DungeonMapProbe.lua saved variables found (set WOW_DIR, or /reload in game first)")
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(open(files[0], encoding="utf-8").read())
    db = lua.globals().DungeonMapBossLevelsDB
    if not db or not db["seen"]:
        sys.exit(f"no boss levels recorded in {files[0]}: update the probe addon (restart the game), target bosses inside a dungeon, then /reload")
    seen = lua_dict(db["seen"])
    ours, ren, cur = our_bosses(), renames(), current_levels()
    new, change, same, notours = [], [], [], []
    for inst, byname in sorted(seen.items()):
        inst = int(inst)
        if inst not in ours:
            for name, e in byname.items():
                notours.append((f"instance {inst}", name, e))
            continue
        dn, names = ours[inst]
        keys = {}
        for n in names:
            parts = {norm(n)} | {norm(p) for p in re.split(r"\s+and\s+|\s*&\s*|\s*/\s*", n)}
            if (inst, norm(n)) in ren:
                parts.add(norm(ren[(inst, norm(n))]))
            for k in parts:
                keys.setdefault(k, []).append(n)
        for name, e in byname.items():
            lv = {int(l): int(c) for l, c in e["levels"].items() if int(c) >= minseen}
            hit = keys.get(norm(name))
            if not lv or not hit:
                if lv:
                    notours.append((dn, name, e))
                continue
            top = max(lv.items(), key=lambda kv: (kv[1], kv[0]))[0]
            level = (999,) if top < 0 else (top,)
            for n in hit:
                c = cur.get(inst, {}).get(n)
                row = (inst, n, dn, name, level, lv, c)
                if c is None:
                    new.append(row)
                elif tuple(c) == level or (len(c) == 2 and c[0] == c[1] == level[0]):
                    same.append(row)
                else:
                    change.append(row)

    def fmt(r):
        inst, n, dn, seen_name, level, lv, c = r
        many = "  (seen at " + ", ".join(f"{'??' if l < 0 else l} x{k}" for l, k in sorted(lv.items())) + ")" if len(lv) > 1 else ""
        return f"  {dn}: {n}" + (f" (as {seen_name})" if seen_name != n else "") + f"  {show(c)} -> {show(level)}{many}"

    print(f"{sum(len(v) for v in seen.values())} recorded names in {files[0]}; recorder skipped {db['secret'] or 0} hidden sightings")
    print(f"\nNEW levels ({len(new)}):")
    for r in new: print(fmt(r))
    print(f"\nCHANGED levels ({len(change)}):")
    for r in change: print(fmt(r))
    print(f"\nagree with what we ship: {len(same)}")
    print(f"\nrecorded elites / rares / bosses that are NOT bosses of ours ({len(notours)}):")
    for dn, name, e in notours:
        ls = ", ".join(f"{'??' if int(l) < 0 else l}" for l in sorted(e['levels'].keys(), key=int))
        print(f"  {dn}: {name} ({e['class'] if 'class' in e else '?'}) level {ls}")
    if "--apply" in argv and (new or change):
        rows = list(csv.DictReader(open(CSV_OUT, encoding="utf-8"))) if os.path.exists(CSV_OUT) else []
        idx = {(r["instanceMapID"], r["name"]): i for i, r in enumerate(rows)}
        stamp = time.strftime("%Y-%m-%d")
        for inst, n, dn, seen_name, level, lv, c in new + change:
            r = {"instanceMapID": str(inst), "name": n, "level": csvval(level),
                 "source": f"recorded in game {stamp} (tools/import_boss_levels.py, {sum(lv.values())} sightings)"}
            if (str(inst), n) in idx:
                rows[idx[(str(inst), n)]] = r
            else:
                rows.append(r)
        raw = open(CSV_OUT, "rb").read() if os.path.exists(CSV_OUT) else b""
        nl = "\r\n" if b"\r\n" in raw else "\n"
        with open(CSV_OUT, "w", newline="", encoding="utf-8") as f:
            w = csv.DictWriter(f, fieldnames=FIELDS, lineterminator=nl)
            w.writeheader()
            w.writerows(rows)
        print(f"\nwrote {len(new) + len(change)} levels to {CSV_OUT}; regenerating:")
        subprocess.run([sys.executable, "-I", os.path.join(ROOT, "tools/gen_loot.py")], cwd=ROOT)


if __name__ == "__main__":
    main()
