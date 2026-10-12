#!/usr/bin/env python3
"""Generate addon/DungeonCrawlerForever/Data/Quests.lua: quests linked to a dungeon (pre-quest chains, attunement, quests done inside).

Sources:
  * classic dungeons: CMaNGOS classic-db (GPL-3.0) SQL dump: quest_template, creature/gameobject_questrelation + involvedrelation, creature +
    gameobject spawns, creature_template, creature_loot_template, item_template. Linking rules: docs/research/dungeon-quests.md
    (quest zone, kill / object objective, quest-only drops, giver or turn-in NPC spawning only in the dungeon, key items).
    Pre-quests: PrevQuestId / NextQuestInChain followed backwards from each linked quest.
  * giver / turn-in position: first CMaNGOS spawn of the NPC (or the gameobject), converted to the zone map with Forever's UiMapAssignment
    (smallest zone-type region on the spawn's map containing it): gx = (R4-y)/(R4-R1), gy = (R3-x)/(R3-R0) in percent = in-game coordinates.
    Spawns in instance maps resolve to nothing. Several zones -> nothing; one zone but spread out -> zone only.
  * filter: quest ids must exist in the Forever client's quest list (data/raw/<build>/QuestV2.csv)
  * data/manual/dungeon_quests.csv: hand-entered Forever-new dungeon quests; manual rows win over generated rows for the same (instance, quest)
  * data/manual/quest_exclude.csv (instanceMapID,questID,reason): removes generated rows
Usage: tools/gen_quests.py <path/to/classic-db.sql>
"""
import collections, csv, os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "addon/DungeonCrawlerForever/Data/Quests.lua")
HORDE = 2 | 16 | 32 | 128          # Orc, Undead, Tauren, Troll
ALLIANCE = 1 | 4 | 8 | 64          # Human, Dwarf, Night Elf, Gnome
KEY_CLASS = 13                     # item class "Key"
KEY_QUESTS = {5505: 289, 5511: 289, 4743: 229}  # attunement quests the automatic key-item rule misses (Scholomance "The Key to Scholomance", UBRS "Seal of Ascension")

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

TABLES = ("quest_template", "creature_questrelation", "creature_involvedrelation", "gameobject_questrelation", "gameobject_involvedrelation",
          "creature", "gameobject", "creature_template", "creature_loot_template", "item_template")

def load(sql_path):
    """Return {table: (colindex, rows)} for the tables we need."""
    cols, rows, grab = {}, {t: [] for t in TABLES}, None
    for line in open(sql_path, encoding="utf-8", errors="replace"):
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
    return {t: ({c: i for i, c in enumerate(cols[t])}, rows[t]) for t in TABLES}

def lua_str(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", " ").replace("\r", "") + '"'

def faction_of(mask):
    mask &= 0xFFFFFFFF
    # classify only when every set bit is a known race on one side (Forever may add races with other bits)
    if mask & HORDE and not mask & ~HORDE:
        return "H"
    if mask & ALLIANCE and not mask & ~ALLIANCE:
        return "A"
    return None

def main():
    if len(sys.argv) < 2 or not os.path.exists(sys.argv[1]):
        sys.exit(__doc__)
    build = open(os.path.join(ROOT, "data/BUILD")).read().strip()
    client = {int(r["ID"]) for r in csv.DictReader(open(os.path.join(ROOT, f"data/raw/{build}/QuestV2.csv"), encoding="utf-8"))}
    dtext = open(os.path.join(ROOT, "addon/DungeonCrawlerForever/Data/Dungeons.lua"), encoding="utf-8").read()
    ours = {int(m.group(1)): m.group(2) for m in re.finditer(r'^  \[(\d+)\] = \{ name = "([^"]+)"', dtext, re.M)}
    DUNGEONS = [36, 33, 34, 43, 47, 48, 70, 90, 109, 129, 189, 209, 229, 230, 289, 329, 349, 389, 429]
    for m in DUNGEONS:
        if m not in ours:
            sys.exit(f"dungeon {m} not in Dungeons.lua")

    T = load(sys.argv[1])
    def tab(t):
        c, r = T[t]
        return c, r
    qc, qr = tab("quest_template")
    Q = {}
    for r in qr:
        e = int(r[qc["entry"]])
        g = lambda k: int(r[qc[k]] or 0)
        Q[e] = dict(title=r[qc["Title"]] or "", min=g("MinLevel"), lvl=g("QuestLevel"), zone=g("ZoneOrSort"), races=g("RequiredRaces"), classes=g("RequiredClasses"),
                    prev=g("PrevQuestId"), chain=g("NextQuestInChain"),
                    kill=[g(f"ReqCreatureOrGOId{i}") for i in range(1, 5)], items=[g(f"ReqItemId{i}") for i in range(1, 5)],
                    rew=[g(f"RewItemId{i}") for i in range(1, 5) if f"RewItemId{i}" in qc], src=g("SrcItemId"))
    cc, cr = tab("creature")
    spawn = collections.defaultdict(set)
    spos = collections.defaultdict(list)    # creature entry -> [(map, x, y)] in dump order
    for r in cr:
        spawn[int(r[cc["id"]])].add(int(r[cc["map"]]))
        spos[int(r[cc["id"]])].append((int(r[cc["map"]]), float(r[cc["position_x"]]), float(r[cc["position_y"]])))
    gc, gr = tab("gameobject")
    gspawn = collections.defaultdict(set)
    gpos = collections.defaultdict(list)
    for r in gr:
        gspawn[int(r[gc["id"]])].add(int(r[gc["map"]]))
        gpos[int(r[gc["id"]])].append((int(r[gc["map"]]), float(r[gc["position_x"]]), float(r[gc["position_y"]])))
    def rel(t):
        c, rows = tab(t)
        d = collections.defaultdict(set)
        for r in rows:
            d[int(r[c["quest"]])].add(int(r[c["id"]]))
        return d
    giverC, endC, giverG, endG = rel("creature_questrelation"), rel("creature_involvedrelation"), rel("gameobject_questrelation"), rel("gameobject_involvedrelation")
    tc, tr = tab("creature_template")
    cname = {int(r[tc["Entry"]]): r[tc["Name"]] or "" for r in tr}
    lootid = {int(r[tc["Entry"]]): int(r[tc["LootId"]] or 0) for r in tr}
    loot2c = collections.defaultdict(set)
    for e, l in lootid.items():
        if l:
            loot2c[l].add(e)
    lc, lr = tab("creature_loot_template")
    qdrop = collections.defaultdict(set)
    for r in lr:
        if float(r[lc["ChanceOrQuestChance"]] or 0) < 0:
            for c in loot2c.get(int(r[lc["entry"]]), ()):
                qdrop[int(r[lc["item"]])].add(c)
    ic, ir = tab("item_template")
    iclass = {int(r[ic["entry"]]): int(r[ic["class"]] or 0) for r in ir if "key" in (r[ic["name"]] or "").lower()}  # key-class items named "... Key"
    areas = collections.defaultdict(set)
    for r in csv.DictReader(open(os.path.join(ROOT, f"data/raw/{build}/AreaTable.csv"), encoding="utf-8")):
        try:
            areas[int(r["ContinentID"])].add(int(r["ID"]))
        except ValueError:
            pass

    uimap = {r["ID"]: r for r in csv.DictReader(open(os.path.join(ROOT, f"data/raw/{build}/UiMap.csv"), encoding="utf-8"))}
    zones = collections.defaultdict(list)   # MapID -> [(area, zone name, R0, R1, R3, R4)], smallest first
    for a in csv.DictReader(open(os.path.join(ROOT, f"data/raw/{build}/UiMapAssignment.csv"), encoding="utf-8")):
        u = uimap.get(a["UiMapID"])
        if u and u["Type"] == "3":
            R = [float(a[f"Region_{i}"]) for i in range(6)]
            zones[int(a["MapID"])].append(((R[3] - R[0]) * (R[4] - R[1]), u["Name_lang"], R[0], R[1], R[3], R[4]))
    for l in zones.values():
        l.sort()
    SPREAD = 3.0   # percent of the zone map: spawns closer than this count as one place
    def locate(plist):
        """[(map, x, y)] -> (zone, gx, gy) / (zone, None, None) / None"""
        res = []
        for mp, x, y in plist:
            cand = []
            for _, name, r0, r1, r3, r4 in zones.get(mp, ()):
                if r0 <= x <= r3 and r1 <= y <= r4:
                    u, v = (r4 - y) / (r4 - r1) * 100, (r3 - x) / (r3 - r0) * 100
                    cand.append((min(u, 100 - u, v, 100 - v), name, round(u, 1), round(v, 1), (r0, r1, r3, r4)))
            if not cand:
                continue
            # zone boxes overlap at their edges: take the one the point is deepest inside, then a sub-region (city) whose whole box lies in it
            best = max(cand)
            sub = [c for c in cand if c is not best and c[0] >= 5 and (c[4][2] - c[4][0]) * (c[4][3] - c[4][1]) < 0.3 * (best[4][2] - best[4][0]) * (best[4][3] - best[4][1]) and c[4][0] >= best[4][0] and c[4][1] >= best[4][1] and c[4][2] <= best[4][2] and c[4][3] <= best[4][3]]
            if sub:
                best = max(sub)
            res.append(best[1:4])
        if not res or len({z for z, _, _ in res}) > 1:
            return None
        z, gx, gy = res[0]
        if all(abs(a - gx) <= SPREAD and abs(b - gy) <= SPREAD for _, a, b in res):
            return z, gx, gy
        return z, None, None
    def place(cs, gos):
        """where the quest NPC (lowest entry of the first name) or, without a creature, the gameobject(s) stand"""
        names = {}
        for c in sorted(cs):
            if cname.get(c):
                names.setdefault(cname[c], c)
        if names:
            return locate(spos.get(names[sorted(names)[0]], []))
        return locate([p for g in sorted(gos) for p in gpos.get(g, [])])

    def inside_only(maps, m):
        return m in maps and maps <= {m}
    def maps_of(cs):
        s = set()
        for c in cs:
            s |= spawn.get(c, set())
        return s

    # direct links: (dungeon, quest) -> set of reasons
    links = collections.defaultdict(set)
    for e, v in Q.items():
        for m in DUNGEONS:
            why = links[(m, e)]
            if v["zone"] > 0 and v["zone"] in areas.get(m, ()):
                why.add("area")
            for c in v["kill"]:
                if c > 0 and inside_only(spawn.get(c, set()), m):
                    why.add("kill")
                if c < 0 and inside_only(gspawn.get(-c, set()), m):
                    why.add("object")
            for it in v["items"]:
                if it and it in qdrop and inside_only(maps_of(qdrop[it]), m):
                    why.add("drop")
            if any(inside_only(spawn.get(c, set()), m) for c in giverC.get(e, ())):
                why.add("giver")
            if any(inside_only(spawn.get(c, set()), m) for c in endC.get(e, ())):
                why.add("turnin")
            if any(inside_only(gspawn.get(g, set()), m) for g in giverG.get(e, set()) | endG.get(e, set())):
                why.add("object-npc")
            if not why:
                del links[(m, e)]
    # attunement: key-class item as requirement, source or reward of a quest that already links to the dungeon
    attune = set()
    for (m, e) in links:
        v = Q[e]
        if any(iclass.get(i, 0) == KEY_CLASS for i in v["items"] + v["rew"] + [v["src"]] if i):
            attune.add((m, e))
    for e, m in KEY_QUESTS.items():
        if e in Q:
            links[(m, e)].add("key"); attune.add((m, e))

    # predecessor map for chains
    pred = {}
    for e, v in Q.items():
        if v["prev"] > 0 and v["prev"] in Q:
            pred[e] = v["prev"]
    nxt = collections.defaultdict(set)
    for e, v in Q.items():
        if v["chain"] in Q:
            nxt[v["chain"]].add(e)
    for e in Q:
        if e not in pred and nxt.get(e):
            pred[e] = min(nxt[e])

    exclude = set()
    ex_path = os.path.join(ROOT, "data/manual/quest_exclude.csv")
    if os.path.exists(ex_path):
        for r in csv.DictReader(open(ex_path, encoding="utf-8")):
            if r["questID"].strip():
                exclude.add((int(r["instanceMapID"]), int(r["questID"])))

    def npc_names(ids):
        return sorted({cname[c] for c in ids if cname.get(c)})
    def row_for(e, m, where):
        v = Q[e]
        r = dict(id=e, name=v["title"], level=v["lvl"], min=v["min"], faction=faction_of(v["races"]), where=where)
        if v["classes"]: r["class"] = v["classes"]  # class bitmask (Warrior 1, Paladin 2, Hunter 4, Rogue 8, Priest 16, Shaman 64, Mage 128, Warlock 256, Druid 1024)
        g, t = npc_names(giverC.get(e, ())), npc_names(endC.get(e, ()))
        if g: r["giver"] = g[0]
        if t: r["turnin"] = t[0]
        for key, cs, gos in (("giver", giverC.get(e, ()), giverG.get(e, ())), ("turnin", endC.get(e, ()), endG.get(e, ()))):
            loc = place(cs, gos) if (cs or gos) else None
            if loc:
                r[key + "Zone"] = loc[0]
                if loc[1] is not None: r[key[0] + "x"], r[key[0] + "y"] = loc[1], loc[2]
        return r

    rows = collections.defaultdict(dict)   # dungeon -> id -> row
    stats = collections.defaultdict(lambda: collections.Counter())
    for (m, e) in sorted(links):
        if e not in client or (m, e) in exclude:
            stats[m]["excluded" if (m, e) in exclude and e in client else "not_in_forever"] += 1
            continue
        inside = any(inside_only(spawn.get(c, set()), m) for c in giverC.get(e, ())) and not giverG.get(e)
        where = "attune" if (m, e) in attune else ("inside" if inside else "outside")
        rows[m][e] = row_for(e, m, where)
        stats[m]["generated"] += 1
    # pre-quest chains
    for m in DUNGEONS:
        for e in sorted(list(rows[m])):
            if (m, e) in exclude:
                continue
            chain, cur, seen = [], e, {e}
            while cur in pred and pred[cur] not in seen:
                cur = pred[cur]; seen.add(cur)
                chain.append(cur)
            chain = [q for q in reversed(chain) if q in client and (m, q) not in exclude]
            if not chain:
                continue
            full = chain + [e]
            name = Q[e]["title"]
            for i, q in enumerate(full):
                if q not in rows[m]:
                    rows[m][q] = row_for(q, m, "outside")
                    stats[m]["pre"] += 1
                r = rows[m][q]
                if "chain" not in r:
                    r["chain"] = name
                    r["step"] = i + 1
                    if i > 0:
                        r["prereq"] = full[i - 1]
    # manual rows
    for n, r in enumerate(csv.DictReader(open(os.path.join(ROOT, "data/manual/dungeon_quests.csv"), encoding="utf-8")), 2):
        m, q = int(r["instanceMapID"] or 0), int(r["questID"] or 0)
        if not m or not q:
            continue
        o = dict(id=q, name=r["name"], where=r["where"] or "outside")
        if r["level"]: o["level"] = int(r["level"])
        if r["minLevel"]: o["min"] = int(r["minLevel"])
        if r["faction"]: o["faction"] = r["faction"][0]
        for k, c in (("giver", "giver"), ("giverZone", "giverZone"), ("turnin", "turnin"), ("turninZone", "turninZone"), ("chain", "chain")):
            if r[c].strip(): o[k] = r[c].strip()
        m2 = re.fullmatch(r"\s*(\d+(?:\.\d+)?)[ ,]+(\d+(?:\.\d+)?)\s*", r.get("coords") or "")
        if m2: o["gx"], o["gy"] = round(float(m2.group(1)), 1), round(float(m2.group(2)), 1)
        if r["prereq"].strip().isdigit(): o["prereq"] = int(r["prereq"])
        if r["step"].strip().isdigit(): o["step"] = int(r["step"])
        rows[m][q] = o
        stats[m]["manual"] += 1

    lines = ["-- GENERATED by tools/gen_quests.py from CMaNGOS classic-db (GPL-3.0) + data/manual/dungeon_quests.csv. Do not edit.",
             "-- [instanceMapID] = { { id, name, level, min, faction (H|A), class (bitmask, only class quests), where (outside|inside|item|attune), giver, giverZone, gx, gy (giver position on that zone's map, percent 0-100, x left->right, y top->bottom), turnin, turninZone, tx, ty, prereq, chain, step } (positions optional), ... }",
             "local _, ns = ...", "ns.QuestData = {"]
    for m in sorted(rows):
        rs = sorted(rows[m].values(), key=lambda r: (r.get("min", 0), r["id"]))
        lines.append(f"  [{m}] = {{ -- {ours.get(m, '?')}")
        for r in rs:
            f = [f"id = {r['id']}", f"name = {lua_str(r['name'])}"]
            if r.get("level"): f.append(f"level = {r['level']}")
            if r.get("min"): f.append(f"min = {r['min']}")
            if r.get("faction"): f.append(f"faction = \"{r['faction']}\"")
            if r.get("class"): f.append(f"class = {r['class']}")
            f.append(f"where = \"{r['where']}\"")
            for k in ("giver", "giverZone", "gx", "gy", "turnin", "turninZone", "tx", "ty"):
                if r.get(k) is None or r.get(k) == "": continue
                f.append(f"{k} = {r[k]:.1f}" if k in ("gx", "gy", "tx", "ty") else f"{k} = {lua_str(r[k])}")
            if r.get("prereq"): f.append(f"prereq = {r['prereq']}")
            if r.get("chain"): f.append(f"chain = {lua_str(r['chain'])}")
            if r.get("step"): f.append(f"step = {r['step']}")
            lines.append("    { " + ", ".join(f) + " },")
        lines.append("  },")
    lines.append("}")
    with open(OUT, "w", encoding="utf-8", newline="\n") as fh:
        fh.write("\n".join(lines) + "\n")
    print(f"{OUT}: {sum(len(v) for v in rows.values())} quests in {len(rows)} dungeons, {os.path.getsize(OUT) // 1024} KB")
    for m in sorted(rows):
        s = stats[m]
        print(f"  {m:5} {ours.get(m, '?'):28} total {len(rows[m]):3}  direct {s['generated']:3} pre {s['pre']:3} manual {s['manual']:3} excluded {s['excluded']:3} not-in-Forever {s['not_in_forever']:3}")

main()
