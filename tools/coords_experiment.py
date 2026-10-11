#!/usr/bin/env python3
"""EXPERIMENT (not wired into the build): estimate boss map coords for bosses lacking them.

Sources, in priority order:
  M  MoP-Classic 5.5.4 JournalEncounter Map_0/Map_1 (+UiMapID)  -- Blizzard-authored pins, same space as ours (exact)
  S  CMaNGOS classic-db creature spawn (map,x,y,z) -> uiMap normalized via retail UiMapAssignment Region_* bounds
Conversion (validated):  u = (R4 - worldY)/(R4 - R1),  v = (R3 - worldX)/(R3 - R0)
  where R0,R1,R2 = min x,y,z and R3,R4,R5 = max x,y,z of the UiMapAssignment row; floor chosen by bounds + z in [R2,R5).
Usage: coords_experiment.py <scratch_dir>   (needs in scratch: cdb.sql, live_UiMapAssignment.csv,
       c_JournalEncounter_5.5.4.70032.csv, c_JournalInstance_5.5.4.70032.csv)
Writes <scratch_dir>/coords_candidates.csv and prints validation + coverage.
"""
import csv, re, sys, os, math, collections

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
S = sys.argv[1] if len(sys.argv) > 1 else "."
norm = lambda s: re.sub(r"[^a-z0-9]", "", s.lower())
ALIAS = {"geilhast": "gelihast", "rasfrostwhisperer": "rasfrostwhisper", "jammalanandogom": "jammalantheprophet"}

def sql_rows(line):
    s = line[line.index("VALUES") + 6:].strip().rstrip(";"); i = 0; n = len(s); out = []; row = []
    while i < n:
        c = s[i]
        if c == "(": row = []; i += 1
        elif c == ")": out.append(row); i += 1
        elif c in ", ": i += 1
        elif c == "'":
            j = i + 1; buf = []
            while True:
                if s[j] == "\\": buf.append(s[j + 1]); j += 2; continue
                if s[j] == "'":
                    if j + 1 < n and s[j + 1] == "'": buf.append("'"); j += 2; continue
                    break
                buf.append(s[j]); j += 1
            row.append("".join(buf)); i = j + 1
        else:
            j = i
            while s[j] not in ",)": j += 1
            row.append(s[i:j]); i = j
    return out

def load_dungeons():
    t = open(os.path.join(ROOT, "addon/DungeonCrawlerForever/Data/Dungeons.lua"), encoding="utf-8").read(); cur = None; res = []
    for l in t.split("\n"):
        m = re.match(r'\s*\[(\d+)\] = \{ name = "([^"]*)"', l)
        if m: cur = (m.group(1), m.group(2)); continue
        if "id =" in l and cur:
            f = re.search(r"floor = (\d+), x = ([\d.]+), y = ([\d.]+)", l)
            res.append(dict(map=cur[0], mapname=cur[1], name=re.search(r'name = "([^"]*)"', l).group(1),
                            diff=int(re.search(r"diff = (\d+)", l).group(1)),
                            floor=f and f.group(1), x=f and float(f.group(2)), y=f and float(f.group(3))))
    return res

def load_floors():
    art = open(os.path.join(ROOT, "addon/DungeonCrawlerForever/Data/Art.lua"), encoding="utf-8").read(); fl = {}
    for m in re.finditer(r"\[(\d+)\] = \{ -- [^\n]*\n((?:    \{[^\n]*\n)+)", art):
        fl[m.group(1)] = re.findall(r"uiMapID = (\d+)", m.group(2))
    return fl

def main():
    D, F = load_dungeons(), load_floors()
    A = collections.defaultdict(set)
    for r in csv.DictReader(open(os.path.join(S, "live_UiMapAssignment.csv"))):
        A[r["UiMapID"]].add(tuple(float(r[k]) for k in ("Region_0", "Region_1", "Region_2", "Region_3", "Region_4", "Region_5")))
    names, spawns = {}, collections.defaultdict(list)
    for line in open(os.path.join(S, "cdb.sql"), encoding="utf-8", errors="replace"):
        if line.startswith("INSERT INTO `creature_template` "):
            for r in sql_rows(line): names[int(r[0])] = r[1]
        elif line.startswith("INSERT INTO `creature` "):
            for r in sql_rows(line): spawns[(int(r[1]), int(r[2]))].append((float(r[4]), float(r[5]), float(r[6])))
    byname = collections.defaultdict(set)
    for e, n in names.items(): byname[norm(n)].add(e)

    def locate(mid, x, y, z):
        c = []
        for f in F.get(mid, []):
            for (R0, R1, R2, R3, R4, R5) in A[f]:
                if R0 <= x <= R3 and R1 <= y <= R4 and R2 <= z < R5:
                    c.append((f, (R4 - y) / (R4 - R1), (R3 - x) / (R3 - R0), R2))
        return max(c, key=lambda t: t[3]) if c else None

    def spawn_pts(mid, name):
        n = norm(name); n = ALIAS.get(n, n)
        return [s for e in byname.get(n, ()) for s in spawns.get((e, int(mid)), [])]

    # validation: bosses we already have
    errs = []; wrong_floor = 0
    for d in D:
        if not d["floor"] or d["diff"] != 0: continue
        best = None
        for (x, y, z) in spawn_pts(d["map"], d["name"]):
            b = locate(d["map"], x, y, z)
            if not b: continue
            same = b[0] == d["floor"]; err = math.hypot(b[1] - d["x"], b[2] - d["y"]) if same else 9
            if best is None or err < best[0]: best = (err, same)
        if best:
            if best[1]: errs.append(best[0])
            else: wrong_floor += 1
    errs.sort(); q = lambda p: errs[int(p * (len(errs) - 1))]
    print(f"VALIDATION S-source vs existing coords: n={len(errs)+wrong_floor} floor_wrong={wrong_floor} "
          f"median_err={q(.5):.3f} p75={q(.75):.3f} p90={q(.9):.3f} (normalized map units)")

    mop = {}
    ji = {r["ID"]: r for r in csv.DictReader(open(os.path.join(S, "c_JournalInstance_5.5.4.70032.csv")))}
    for e in csv.DictReader(open(os.path.join(S, "c_JournalEncounter_5.5.4.70032.csv"))):
        if float(e["Map_0"] or 0): mop[(ji.get(e["JournalInstanceID"], {}).get("MapID"), norm(e["Name_lang"]))] = e

    out = []; seen = set(); stat = collections.Counter()
    for d in D:
        k = (d["map"], norm(d["name"]))
        if d["floor"] or k in seen: continue
        seen.add(k); stat["missing_unique"] += 1
        placeable = bool(F.get(d["map"])); row = dict(map=d["map"], dungeon=d["mapname"], boss=d["name"], src="", floor="", x="", y="", note="")
        m = mop.get(k)
        if m and m["UiMapID"] in F.get(d["map"], []):
            row.update(src="M", floor=m["UiMapID"], x=f'{float(m["Map_0"]):.4f}', y=f'{float(m["Map_1"]):.4f}')
        else:
            pts = spawn_pts(d["map"], d["name"]); locs = [l for l in (locate(d["map"], *p) for p in pts) if l]
            if locs:
                l = locs[0]; nf = len(F[d["map"]])
                row.update(src="S", floor=l[0], x=f"{l[1]:.4f}", y=f"{l[2]:.4f}",
                           note=("single-floor" if nf == 1 else "multi-floor(z-guess)") + (f"; {len(locs)} spawns" if len(locs) > 1 else ""))
        if not placeable: row["note"] = ("no art floors in Art.lua; " + (f"MoP pin exists on uiMap {m['UiMapID']}" if m else "")).strip()
        stat[row["src"] or ("noart" if not placeable else "none")] += 1
        out.append(row)
    p = os.path.join(S, "coords_candidates.csv")
    with open(p, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(out[0])); w.writeheader(); w.writerows(out)
    print("COVERAGE (unique missing bosses):", dict(stat)); print("wrote", p)

main()
