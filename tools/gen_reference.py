#!/usr/bin/env python3
"""Generate addon/DungeonCrawlerForever/Data/Reference.lua: developer reference landmarks plotted on each dungeon floor.

Shown by the maintainer while recording stairs / door markers in edit mode: bosses, rare elites, vendors / quest givers / trainers
and gameobjects (doors, buttons, lifts / transports, chests) at their (approximate) CMaNGOS spawn positions.

Sources
  * CMaNGOS classic-db (GPL-3.0) SQL dump: creature, creature_template, gameobject, gameobject_template.
  * retail UiMapAssignment (data/raw/live) world bounds per floor UiMap; floors from Data/Art.lua; boss list + recorded boss positions
    from Data/Dungeons.lua (which already merges data/manual/bosses.csv).
Projection (same as gen_entrances.py / coords_experiment.py): u = (R4 - y) / (R4 - R1) horizontal, v = (R3 - x) / (R3 - R0) vertical,
  R0..R2 = min x,y,z and R3..R5 = max x,y,z of the assignment row.
Floor choice: floors of an instance often share the same bounds (Blackrock Spire ...), so z decides: each floor's z band is calibrated
  from the recorded bosses of that floor (the CMaNGOS spawn of the boss nearest to the recorded x,y gives z). A spawn goes to the
  containing floor with the nearest z band. Floors without a recorded boss are never used when another floor competes for the point.
Validation: every recorded boss with a CMaNGOS spawn is projected onto its floor and compared with the recorded x,y; instances with a
  median error > MAX_MEDIAN are skipped. Instances / floors that use custom or Forever-made art (ArtCustom.lua, ArtForever.lua) are skipped.
Usage: tools/gen_reference.py <path/to/classic-db.sql>
"""
import collections, csv, math, os, re, statistics, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA = os.path.join(ROOT, "addon/DungeonCrawlerForever/Data")
OUT = os.path.join(DATA, "Reference.lua")
LIVE = os.path.join(ROOT, "data/raw/live/UiMapAssignment.csv")
MAX_MEDIAN = 0.08      # skip an instance whose recorded-boss validation median error is larger
MAX_PER_FLOOR_INSTANCE = 120
DEDUP = 0.015          # same name closer than this (map fraction) = duplicate
MAX_DZ = 40.0          # yards outside a floor's calibrated z band before a spawn is dropped (multi-floor instances only)
KIND_CAP = {"chest": 25, "door": 50}   # per instance; chests / doors are numerous and generic
MAX_DZ_CUSTOM = 5.0    # instances that also have custom-art floors (BRS: upper spire is z>95, same bounds): stay tight to the calibrated bands
PRIO = ["boss", "rare", "lift", "door", "trainer", "vendor", "quest", "chest", "npc"]

def sql_rows(line):
    s = line[line.index("VALUES") + 6:].strip().rstrip(";")
    i, n, row, out = 0, len(s), [], []
    while i < n:
        c = s[i]
        if c == "(":
            row = []; i += 1; continue
        if c == ")":
            out.append(row); i += 1; continue
        if c in ", ":
            i += 1; continue
        if c == "'":
            j, buf = i + 1, []
            while True:
                if s[j] == "\\":
                    buf.append(s[j + 1]); j += 2; continue
                if s[j] == "'":
                    if j + 1 < n and s[j + 1] == "'":
                        buf.append("'"); j += 2; continue
                    break
                buf.append(s[j]); j += 1
            row.append("".join(buf)); i = j + 1; continue
        j = i
        while s[j] not in ",)":
            j += 1
        v = s[i:j]
        row.append(None if v == "NULL" else v)
        i = j
    return out

TABLES = ("creature", "creature_template", "gameobject", "gameobject_template", "gameobject_questrelation", "gameobject_involvedrelation", "quest_template", "gameobject_loot_template", "item_template")

def load_sql(path):
    cols, rows, grab = {}, {t: [] for t in TABLES}, None
    for line in open(path, encoding="utf-8", errors="replace"):
        if line.startswith("CREATE TABLE `"):
            t = line.split("`")[1]
            grab = t if t in TABLES else None
            cols[t] = [] if grab else None
            continue
        if grab:
            m = re.match(r"\s+`(\w+)`", line)
            if m:
                cols[grab].append(m.group(1))
            else:
                grab = None
            continue
        m = re.match(r"INSERT INTO `(\w+)`", line)
        if m and m.group(1) in TABLES:
            rows[m.group(1)].extend(sql_rows(line))
    return {t: [dict(zip(cols[t], r)) for r in rows[t]] for t in TABLES}

norm = lambda s: re.sub(r"[^a-z0-9]", "", s.lower())
ALIAS = {"geilhast": "gelihast", "rasfrostwhisperer": "rasfrostwhisper", "jammalanandogom": "jammalantheprophet"}

def lua_str(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", " ").replace("\r", "") + '"'

def load_art():
    """instance -> [floor uiMapID] for client-art floors (Art.lua, excluding legacy 6xxxxx), + set of custom/forever instances."""
    art = open(os.path.join(DATA, "Art.lua"), encoding="utf-8").read()
    fl, legacy = {}, collections.defaultdict(list)
    for m in re.finditer(r"^  \[(\d+)\] = \{ -- [^\n]*\n((?:    \{[^\n]*\n)+)", art, re.M):
        for line in m.group(2).split("\n"):
            u = re.search(r"uiMapID = (\d+)", line)
            if not u:
                continue
            (legacy[int(m.group(1))] if "legacy = true" in line else fl.setdefault(int(m.group(1)), [])).append(int(u.group(1)))
    custom = set()
    for fn in ("ArtCustom.lua", "ArtForever.lua"):
        custom |= {int(x) for x in re.findall(r"^  \[(\d+)\] = \{", open(os.path.join(DATA, fn), encoding="utf-8").read(), re.M)}
    return fl, legacy, custom

def load_dungeons():
    t = open(os.path.join(DATA, "Dungeons.lua"), encoding="utf-8").read()
    res, cur = collections.OrderedDict(), None
    for l in t.split("\n"):
        m = re.match(r'\s*\[(\d+)\] = \{ name = "([^"]*)", raid = (\w+)', l)
        if m:
            cur = int(m.group(1)); res[cur] = dict(name=m.group(2), raid=m.group(3) == "true", bosses=[]); continue
        if cur is not None and " id = " in l:
            f = re.search(r"floor = (\d+), x = ([\d.]+), y = ([\d.]+)", l)
            res[cur]["bosses"].append(dict(name=re.search(r'name = "([^"]*)"', l).group(1), diff=int(re.search(r"diff = (\d+)", l).group(1)),
                                           floor=int(f.group(1)) if f else None, x=float(f.group(2)) if f else None,
                                           y=float(f.group(3)) if f else None))
    return res

def main():
    if len(sys.argv) < 2 or not os.path.exists(sys.argv[1]):
        sys.exit(__doc__)
    D = load_dungeons()
    ART, LEGACY, CUSTOM = load_art()
    bounds = collections.defaultdict(list)   # floor uiMapID -> distinct (R0,R1,R2,R3,R4,R5)
    for r in csv.DictReader(open(LIVE, encoding="utf-8")):
        b = tuple(round(float(r["Region_%d" % i]), 3) for i in range(6))
        if b not in bounds[int(r["UiMapID"])]:
            bounds[int(r["UiMapID"])].append(b)
    S = load_sql(sys.argv[1])
    tpl = {int(r["Entry"]): r for r in S["creature_template"]}
    gtpl = {int(r["entry"]): r for r in S["gameobject_template"]}
    cspawn = collections.defaultdict(list)   # map -> [(entry, x, y, z)]
    for r in S["creature"]:
        cspawn[int(r["map"])].append((int(r["id"]), float(r["position_x"]), float(r["position_y"]), float(r["position_z"])))
    gspawn = collections.defaultdict(list)
    for r in S["gameobject"]:
        gspawn[int(r["map"])].append((int(r["id"]), float(r["position_x"]), float(r["position_y"]), float(r["position_z"])))
    ourq = {int(m) for m in re.findall(r"\{ id = (\d+),", open(os.path.join(DATA, "Quests.lua"), encoding="utf-8").read())}  # only quests the addon lists
    questobj = {int(x["id"]) for t in ("gameobject_questrelation", "gameobject_involvedrelation") for x in S[t] if int(x["quest"]) in ourq}
    # objects whose loot holds an item a quest asks for (the book in the library, the relic in the last room): item name per object entry
    reqitems = {int(q["ReqItemId%d" % i]) for q in S["quest_template"] if int(q["entry"]) in ourq for i in range(1, 5) if int(q.get("ReqItemId%d" % i) or 0)}
    iname = {int(x["entry"]): x["name"] for x in S["item_template"] if int(x["entry"]) in reqitems}
    lootitems = collections.defaultdict(set)
    for x in S["gameobject_loot_template"]:
        if int(x["item"]) in iname and float(x["ChanceOrQuestChance"] or 0) < 0:  # a quest-only drop (negative chance)
            lootitems[int(x["entry"])].add(iname[int(x["item"])])
    objitem = {e: sorted(lootitems[int(t["data1"] or 0)]) for e, t in gtpl.items() if int(t["type"] or -1) == 3 and lootitems.get(int(t["data1"] or 0))}
    by_name = collections.defaultdict(set)
    for e, t in tpl.items():
        by_name[norm(t["Name"])].add(e)

    def contains(floor, x, y):
        for (R0, R1, R2, R3, R4, R5) in bounds.get(floor, ()):
            if R0 <= x <= R3 and R1 <= y <= R4:
                return ((R4 - y) / (R4 - R1), (R3 - x) / (R3 - R0))
        return None

    out, report, skipped = {}, [], []
    for inst, d in D.items():
        floors = ART.get(inst, [])
        if inst in CUSTOM and not floors:
            skipped.append(f"{inst} {d['name']}: custom / Forever-made art (ArtCustom / ArtForever)"); continue
        if not floors:
            skipped.append(f"{inst} {d['name']}: no client-art floors in Art.lua" + (" (legacy art only)" if inst in LEGACY else "")); continue
        if inst not in cspawn and inst not in gspawn:
            skipped.append(f"{inst} {d['name']}: no CMaNGOS spawns on this map"); continue
        if LEGACY.get(inst):
            skipped.append(f"{inst} {d['name']}: legacy-art floors skipped (no world bounds): {len(LEGACY[inst])}")
        # --- calibration + validation from recorded bosses
        zs = collections.defaultdict(list)       # floor -> [z]
        errs, unmatched, wrongfloor = [], [], 0
        for b in d["bosses"]:
            if b["floor"] is None or b["diff"] != 0 or b["floor"] not in floors:
                continue
            n = norm(b["name"]); n = ALIAS.get(n, n)
            ents = by_name.get(n, set())
            best = None
            for (e, x, y, z) in cspawn[inst]:
                if e in ents:
                    p = contains(b["floor"], x, y)
                    if p:
                        err = math.hypot(p[0] - b["x"], p[1] - b["y"])
                        if best is None or err < best[0]:
                            best = (err, z)
            if best:
                errs.append(best[0]); zs[b["floor"]].append(best[1])
            else:
                unmatched.append(b["name"])
        med = statistics.median(errs) if errs else None
        if med is None:
            skipped.append(f"{inst} {d['name']}: no recorded boss with a CMaNGOS spawn to validate / calibrate"); continue
        if med > MAX_MEDIAN:
            skipped.append(f"{inst} {d['name']}: projection median error {med:.3f} > {MAX_MEDIAN}"); continue
        band = {f: (min(v), max(v)) for f, v in zs.items()}
        uncal = [f for f in floors if f not in band]

        maxdz = MAX_DZ_CUSTOM if inst in CUSTOM else MAX_DZ

        def pick(x, y, z):
            cand = [(f, contains(f, x, y)) for f in floors]
            cand = [(f, p) for f, p in cand if p]
            if not cand:
                return None
            if len(cand) == 1:
                f, p = cand[0]
                if len(floors) > 1 and f in band and not (band[f][0] - maxdz <= z <= band[f][1] + maxdz):
                    return None
                return f, p
            cal = [(f, p) for f, p in cand if f in band]
            if not cal:
                return None
            def dz(fp):
                lo, hi = band[fp[0]]
                return 0.0 if lo <= z <= hi else min(abs(z - lo), abs(z - hi))
            f, p = min(cal, key=lambda fp: (dz(fp), abs(z - sum(band[fp[0]]) / 2), fp[0]))
            return None if dz((f, p)) > maxdz else (f, p)

        rows = []   # (prio, floor, x, y, name, t, level)
        seen_boss = set()
        # bosses: recorded position wins; else project the spawn
        for b in d["bosses"]:
            if b["diff"] != 0 and not d["raid"]:
                pass
            key = norm(b["name"])
            if key in seen_boss:
                continue
            n = ALIAS.get(key, key)
            ents = by_name.get(n, set())
            lvl = max([int(tpl[e]["MaxLevel"] or 0) for e in ents] or [0]) or None
            if b["floor"] is not None and b["floor"] in floors:
                rows.append((0, b["floor"], b["x"], b["y"], b["name"], "boss", lvl)); seen_boss.add(key)
            elif b["floor"] is None and inst not in CUSTOM:   # custom-art instance (BRS): unplaced bosses live on the custom floors
                for (e, x, y, z) in cspawn[inst]:
                    if e in ents:
                        r = pick(x, y, z)
                        if r:
                            rows.append((0, r[0], r[1][0], r[1][1], b["name"], "boss", lvl)); seen_boss.add(key); break
        bossents = {e for b in d["bosses"] for e in by_name.get(ALIAS.get(norm(b["name"]), norm(b["name"])), ())}
        cnt = collections.Counter(e for (e, _, _, _) in cspawn[inst])
        for (e, x, y, z) in cspawn[inst]:
            t = tpl.get(e)
            if not t or e in bossents or not (t["Name"] or "").strip():
                continue
            fl = int(t["NpcFlags"] or 0)
            kind = None
            if int(t["Rank"] or 0) in (2, 4) and cnt[e] == 1:
                kind = "rare"
            elif fl & 16:
                kind = "trainer"
            elif fl & (128 | 4096):
                kind = "vendor"
            elif fl & 2:
                kind = "quest"
            elif fl & (8192 | 65536):
                kind = "npc"
            if not kind:
                continue
            r = pick(x, y, z)
            if r:
                rows.append((PRIO.index(kind), r[0], r[1][0], r[1][1], t["Name"], kind, int(t["MaxLevel"] or 0) or None))
        for (e, x, y, z) in gspawn[inst]:
            t = gtpl.get(e)
            if not t or not (t["name"] or "").strip():
                continue
            ty = int(t["type"] or -1)
            kind = {0: "door", 1: "door", 11: "lift", 15: "lift", 3: "chest"}.get(ty)
            if e in questobj:
                kind = "quest"  # a book, remains or tablet that starts or ends a quest
            qitems = objitem.get(e)
            if qitems:
                kind = "quest"  # an object that holds a quest item
            if not kind:
                continue
            r = pick(x, y, z)
            if r:
                rows.append((PRIO.index(kind), r[0], r[1][0], r[1][1], t["name"], kind, None, "; ".join(qitems) if qitems else None))
        # dedup (same name within DEDUP on the same floor; higher priority first), then cap
        rows.sort(key=lambda r: (r[0], r[4], r[1], round(r[2], 4), round(r[3], 4)))
        kept = []
        for r in rows:
            if any(k[1] == r[1] and k[4] == r[4] and math.hypot(k[2] - r[2], k[3] - r[3]) < DEDUP for k in kept):
                continue
            if r[5] in KIND_CAP and sum(1 for k in kept if k[5] == r[5]) >= KIND_CAP[r[5]]:
                continue
            kept.append(r)
        capped = max(0, len(kept) - MAX_PER_FLOOR_INSTANCE)
        kept = kept[:MAX_PER_FLOOR_INSTANCE]
        out[inst] = kept
        c = collections.Counter(r[5] for r in kept)
        report.append((inst, d["name"], len(kept), capped, dict(c), len(errs), med, max(errs), unmatched, uncal))

    # --- custom "all floors" maps (Shadowfang Keep, Wailing Caverns, Gnomeregan, Sunken Temple): one flat picture of the whole dungeon, no client bounds.
    # The recorded boss positions on it against the bosses' CMaNGOS spawns give an affine map (world x, y -> picture fractions) by least squares; the
    # quest givers, quest objects and quest-item objects are projected with it. Only a fit with a small error is used.
    def solve3(A, bvec):   # least squares for u = p*x + q*y + r (normal equations, 3x3)
        n = len(A)
        M = [[sum(A[k][i] * A[k][j] for k in range(n)) for j in range(3)] + [sum(A[k][i] * bvec[k] for k in range(n))] for i in range(3)]
        for i in range(3):
            piv = max(range(i, 3), key=lambda r: abs(M[r][i]))
            if abs(M[piv][i]) < 1e-9:
                return None
            M[i], M[piv] = M[piv], M[i]
            for r in range(3):
                if r != i:
                    f = M[r][i] / M[i][i]
                    M[r] = [M[r][c] - f * M[i][c] for c in range(4)]
        return [M[i][3] / M[i][i] for i in range(3)]
    for inst, d in D.items():
        if inst in out or inst not in cspawn:
            continue
        bfloors = {b["floor"] for b in d["bosses"] if b["floor"] and b["diff"] == 0}
        if len(bfloors) != 1 or next(iter(bfloors)) < 800000:
            continue
        fl = next(iter(bfloors))
        pairs = []
        for b in d["bosses"]:
            if b["floor"] != fl or b["diff"] != 0:
                continue
            n = norm(b["name"]); n = ALIAS.get(n, n)
            sp = [(x, y) for (e, x, y, z) in cspawn[inst] if e in by_name.get(n, ())]
            if sp:
                pairs.append((sp[0][0], sp[0][1], b["x"], b["y"]))
        if len(pairs) < 4:
            skipped.append(f"{inst} {d['name']}: custom map, only {len(pairs)} bosses to fit (need 4)"); continue
        pu = solve3([(x, y, 1.0) for x, y, u, v in pairs], [u for x, y, u, v in pairs])
        pv = solve3([(x, y, 1.0) for x, y, u, v in pairs], [v for x, y, u, v in pairs])
        if not (pu and pv):
            skipped.append(f"{inst} {d['name']}: custom map, the bosses do not fit a map (collinear)"); continue
        proj = lambda x, y: (pu[0] * x + pu[1] * y + pu[2], pv[0] * x + pv[1] * y + pv[2])
        errs = [math.hypot(proj(x, y)[0] - u, proj(x, y)[1] - v) for x, y, u, v in pairs]
        med = statistics.median(errs)
        if med > MAX_MEDIAN:
            skipped.append(f"{inst} {d['name']}: custom map, fit median error {med:.3f} > {MAX_MEDIAN}"); continue
        rows = [(0, fl, b["x"], b["y"], b["name"], "boss", None) for b in d["bosses"] if b["floor"] == fl and b["diff"] == 0]
        for (e, x, y, z) in cspawn[inst]:
            t = tpl.get(e)
            if not t or not (t["Name"] or "").strip() or not (int(t["NpcFlags"] or 0) & 2):
                continue
            u, v = proj(x, y)
            if -0.02 <= u <= 1.02 and -0.02 <= v <= 1.02:
                rows.append((PRIO.index("quest"), fl, u, v, t["Name"], "quest", int(t["MaxLevel"] or 0) or None))
        for (e, x, y, z) in gspawn[inst]:
            t = gtpl.get(e)
            if not t or not (e in questobj or objitem.get(e)):
                continue
            u, v = proj(x, y)
            if -0.02 <= u <= 1.02 and -0.02 <= v <= 1.02:
                qi = objitem.get(e)
                rows.append((PRIO.index("quest"), fl, u, v, t["name"], "quest", None, "; ".join(qi) if qi else None))
        rows.sort(key=lambda r: (r[0], r[4], r[2], r[3]))
        kept = []
        for r in rows:
            if any(k[4] == r[4] and math.hypot(k[2] - r[2], k[3] - r[3]) < DEDUP for k in kept):
                continue
            kept.append(r)
        out[inst] = kept
        report.append((inst, d["name"], len(kept), 0, dict(collections.Counter(r[5] for r in kept)), len(errs), med, max(errs), [], []))

    lines = ["-- GENERATED by tools/gen_reference.py from CMaNGOS classic-db spawns (GPL-3.0) + retail UiMapAssignment bounds. Do not edit.",
             "-- Developer reference landmarks (approximate): [instanceMapID] = { [floorUiMapID] = { { x, y, n = name, t = kind, l = level, i = quest item held }, ... } }",
             "local _, ns = ...", "ns.Reference = {"]
    for inst in sorted(out):
        byf = collections.defaultdict(list)
        for r in out[inst]:
            byf[r[1]].append(r)
        if not byf:
            continue
        lines.append(f"  [{inst}] = {{ -- {D[inst]['name']}")
        for f in sorted(byf):
            lines.append(f"    [{f}] = {{")
            for r in sorted(byf[f], key=lambda r: (r[0], r[4], r[2], r[3])):
                lv = f", l = {r[6]}" if r[6] else ""
                if len(r) > 7 and r[7]:
                    lv += f", i = {lua_str(r[7])}"  # the quest item(s) this object holds
                lines.append(f"      {{ x = {r[2]:.4f}, y = {r[3]:.4f}, n = {lua_str(r[4])}, t = \"{r[5]}\"{lv} }},")
            lines.append("    },")
        lines.append("  },")
    lines.append("}")
    text = "\n".join(lines) + "\n"
    with open(OUT, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)
    print(f"wrote {OUT}: {len(text.encode('utf-8'))} bytes")
    for inst, name, n, capped, c, ne, med, mx, unm, uncal in report:
        print(f"  {inst:4} {name:24} rows {n:3} (capped {capped}) {c} | validated {ne}, median err {med:.3f} max {mx:.3f}"
              + (f" | no spawn match: {unm}" if unm else "") + (f" | uncalibrated floors: {uncal}" if uncal else ""))
    for s in skipped:
        print("  SKIPPED", s)

main()
