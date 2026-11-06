#!/usr/bin/env python3
"""Clear-time baseline: how long a kind of run through a dungeon usually takes, before any player data exists.

  tools/gen_clear_times.py --cdb <classic-db.sql>   measure every dungeon from CMaNGOS classic-db (GPL-3.0) into data/draft/clear_times_draft.csv,
                                                    then write addon/DungeonCrawlerForever/Data/ClearTimes.lua
  tools/gen_clear_times.py                          write Data/ClearTimes.lua from the committed draft (no SQL dump needed)
  tools/gen_clear_times.py --fit                    refit the model's three numbers to CALIBRATION (prints them; nothing written)

The model, per kind of run (a set of bosses; "Full clear" = every regular boss of the dungeon or wing, more kinds in data/manual/run_kinds.csv):
  minutes = (SEC_PER_YARD * walk + SEC_PER_MOB * mobs + SEC_PER_BOSS * bosses) / 60
  walk   = length of the shortest tree joining the entrance, the bosses and the monster groups of the run (yards, from spawn positions)
  mobs   = hostile monsters placed in the run's part of the dungeon (each monster belongs to the boss it stands closest to)
  bosses = regular bosses of the run (no rares, summoned or optional ones)
The three numbers were fitted to the clear times players report (CALIBRATION below); refit when real runs come in.
A quest run adds time per dungeon quest of the player's faction: escorts and events most, collecting a little, killing a boss nothing.
Dungeons that classic-db does not have (Forever's new ones) get a boss-count estimate: the median minutes per boss of the classic dungeons.
data/manual/clear_times.csv (instanceMapID, wing, kind, min, max, source) overrides any computed range: hand edits always win.
"""
import collections, csv, math, os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
DRAFT = os.path.join(ROOT, "data/draft/clear_times_draft.csv")
KINDS = os.path.join(ROOT, "data/manual/run_kinds.csv")
MANUAL = os.path.join(ROOT, "data/manual/clear_times.csv")
OUT = os.path.join(ROOT, "addon/DungeonCrawlerForever/Data/ClearTimes.lua")

SEC_PER_YARD, SEC_PER_MOB, SEC_PER_BOSS = 0.4, 6, 195
# Clear times players reported (minutes), used to fit the numbers above (grid search, least squared log error; 2026-11-05):
# Blizzard EU forum "WoW Classic dungeons: how much time should I calculate for X", 2019, pugs at level:
# https://eu.forums.blizzard.com/en/wow/t/wow-classic-dungeons-how-much-time-should-i-calculate-for-x/82677
CALIBRATION = {(389, 0): 30, (43, 0): 75, (36, 0): 60, (33, 0): 45, (48, 0): 60, (34, 0): 30, (90, 0): 90, (189, 1): 22, (189, 2): 18}
LOW, HIGH = 0.8, 1.25          # the range shown around the estimate
QUEST_ESCORT, QUEST_COLLECT, QUEST_KILL = 8, 1.5, 1   # extra minutes per dungeon quest done inside (kill: only for a monster that is not a boss)
CLUSTER_YD, CLUSTER_Z = 14.0, 8.0                                     # monsters this close belong to one group (a pull)
FRIENDLY = {1, 2, 3, 4, 5, 6, 7, 31, 35, 114, 115, 116, 188, 1078, 1080, 1514}
DRAFT_COLS = ["instanceMapID", "wing", "kind", "label", "walk_yd", "mobs", "groups", "bosses", "quest_min_H", "quest_min_A", "minutes", "basis"]

norm = lambda s: re.sub(r"[^a-z0-9]", "", (s or "").lower())
dist = lambda a, b: math.sqrt((a[0] - b[0]) ** 2 + (a[1] - b[1]) ** 2 + (a[2] - b[2]) ** 2)


def dungeons():
    """{instanceMapID: {name, raid, bosses: [{name, trash, regular}]}} from the generated Data/Dungeons.lua, one entry per boss name (the same
    boss is listed once per difficulty). Not regular: trash, summoned, optional (sub) and rare bosses (Data/Rares.lua)."""
    rares = collections.defaultdict(set)
    cur = None
    for line in open(os.path.join(ROOT, "addon/DungeonCrawlerForever/Data/Rares.lua"), encoding="utf-8"):
        m = re.match(r"  \[(\d+)\] = \{(.*)\},", line)
        if m:
            rares[int(m.group(1))] = {norm(b) for b in re.findall(r'\["((?:[^"\\]|\\.)*)"\] = true', m.group(2))}
    out = {}
    for line in open(os.path.join(ROOT, "addon/DungeonCrawlerForever/Data/Dungeons.lua"), encoding="utf-8"):
        m = re.match(r'  \[(\d+)\] = \{ name = "((?:[^"\\]|\\.)*)", raid = (\w+)', line)
        if m:
            cur = int(m.group(1))
            out[cur] = dict(name=m.group(2), raid=m.group(3) == "true", bosses=[])
            continue
        m = re.match(r'    \{ id = \d+, name = "((?:[^"\\]|\\.)*)"', line)
        if m and cur is not None:
            name = m.group(1).replace('\\"', '"')
            if any(norm(b["name"]) == norm(name) for b in out[cur]["bosses"]):
                continue
            flags = ("trash = true", "summoned = true", "sub = true", "rare = true")
            out[cur]["bosses"].append(dict(name=name, trash="trash = true" in line,
                                           regular=not any(f in line for f in flags) and norm(name) not in rares[cur]))
    return out


def wings():
    """{instanceMapID: {wing: {"label", "bosses": {normalised boss name}}}} from Data/Wings.lua."""
    out, cur = collections.defaultdict(dict), None
    for line in open(os.path.join(ROOT, "addon/DungeonCrawlerForever/Data/Wings.lua"), encoding="utf-8"):
        m = re.match(r"  \[(\d+)\] = \{", line)
        if m:
            cur = int(m.group(1))
            continue
        m = re.match(r'    \{ wing = (\d+), name = "([^"]+)".*bosses = \{(.*)\} \},', line)
        if m and cur is not None:
            names = {norm(b) for b in re.findall(r'\["((?:[^"\\]|\\.)*)"\] = true', m.group(3))}
            out[cur][int(m.group(1))] = dict(label=m.group(2).split(" - ")[-1], bosses=names)
    return out


def quests():
    """{instanceMapID: [(questID, faction or None)]}: the dungeon quests the addon lists, class quests left out."""
    out, cur = collections.defaultdict(list), None
    for line in open(os.path.join(ROOT, "addon/DungeonCrawlerForever/Data/Quests.lua"), encoding="utf-8"):
        m = re.match(r"  \[(\d+)\] = \{", line)
        if m:
            cur = int(m.group(1))
            continue
        m = re.match(r"    \{ id = (\d+),", line)
        if m and cur is not None and "class = " not in line:
            f = re.search(r'faction = "([HA])"', line)
            out[cur].append((int(m.group(1)), f.group(1) if f else None))
    return out


def run_kinds():
    if not os.path.exists(KINDS):
        return []
    return [dict(inst=int(r["instanceMapID"]), wing=int(r["wing"] or 0), kind=r["kind"], label=r["label"],
                 bosses={norm(b) for b in r["bosses"].split(";") if b.strip()}) for r in csv.DictReader(open(KINDS, encoding="utf-8"))]


def groups(pts):
    """Monster groups (pulls): single-linkage clusters of spawn positions. Returns their centres."""
    n, par = len(pts), list(range(len(pts)))
    def find(i):
        while par[i] != i:
            par[i] = par[par[i]]
            i = par[i]
        return i
    for i in range(n):
        for j in range(i + 1, n):
            a, b = pts[i], pts[j]
            if abs(a[2] - b[2]) < CLUSTER_Z and (a[0] - b[0]) ** 2 + (a[1] - b[1]) ** 2 < CLUSTER_YD ** 2:
                par[find(i)] = find(j)
    g = collections.defaultdict(list)
    for i in range(n):
        g[find(i)].append(pts[i])
    return [tuple(sum(p[k] for p in v) / len(v) for k in range(3)) for v in g.values()]


def tree_length(pts):
    """Length of the minimum spanning tree (Prim): roughly the walking a clear needs."""
    if len(pts) < 2:
        return 0.0
    done, best, total = [False] * len(pts), [float("inf")] * len(pts), 0.0
    best[0] = 0.0
    for _ in range(len(pts)):
        i = min((k for k in range(len(pts)) if not done[k]), key=lambda k: best[k])
        done[i] = True
        total += best[i]
        for k in range(len(pts)):
            if not done[k]:
                d = dist(pts[i], pts[k])
                if d < best[k]:
                    best[k] = d
    return total


def measure(sql):
    """Read classic-db and return draft rows (dicts with DRAFT_COLS)."""
    from gen_quests import load
    T = load(sql, ("creature", "creature_template", "areatrigger_teleport", "quest_template", "creature_loot_template", "creature_questrelation"))
    tc, tr = T["creature_template"]
    tmpl = {int(r[tc["Entry"]]): dict(name=r[tc["Name"]] or "", type=int(r[tc["CreatureType"]]), fac=int(r[tc["Faction"]]), npc=int(r[tc["NpcFlags"]]),
                                      uf=int(r[tc["UnitFlags"]]), xf=int(r[tc["ExtraFlags"]]), loot=int(r[tc["LootId"]] or 0)) for r in tr}
    byname = collections.defaultdict(set)
    for e, t in tmpl.items():
        byname[norm(t["name"])].add(e)

    def hostile(e):
        t = tmpl.get(e)
        return bool(t) and not t["npc"] and t["type"] not in (8, 11) and t["fac"] not in FRIENDLY \
            and not (t["uf"] & (0x2 | 0x02000000)) and not (t["xf"] & 0x80)

    cc, cr = T["creature"]
    spawns = collections.defaultdict(list)
    for r in cr:
        spawns[int(r[cc["map"]])].append((int(r[cc["id"]]), (float(r[cc["position_x"]]), float(r[cc["position_y"]]), float(r[cc["position_z"]]))))
    ac, ar = T["areatrigger_teleport"]
    doors = collections.defaultdict(list)
    for r in ar:
        doors[int(r[ac["target_map"]])].append((float(r[ac["target_position_x"]]), float(r[ac["target_position_y"]]), float(r[ac["target_position_z"]])))
    qc, qr = T["quest_template"]
    qinfo = {int(r[qc["entry"]]): r for r in qr}
    lc, lr = T["creature_loot_template"]
    drops = collections.defaultdict(set)          # loot id -> item ids
    for r in lr:
        drops[int(r[lc["entry"]])].add(int(r[lc["item"]]))
    gc, gr = T["creature_questrelation"]
    givers = collections.defaultdict(set)         # quest -> creature ids that give it
    for r in gr:
        givers[int(r[gc["quest"]])].add(int(r[gc["id"]]))

    D, W, Q = dungeons(), wings(), quests()
    extra = run_kinds()
    rows = []
    for inst in sorted(D):
        d = D[inst]
        if d["raid"]:
            continue
        regular = [b for b in d["bosses"] if b["regular"]]
        if inst not in spawns:   # Forever's new dungeons: filled in by boss count in build()
            rows.append(dict(instanceMapID=inst, wing=0, kind="full", label="Full clear", walk_yd="", mobs="", groups="", bosses=len(regular),
                             quest_min_H="", quest_min_A="", minutes="", basis="bosses"))
            continue
        # every boss with a spawn position (rares and summoned ones too: they own their part of the dungeon)
        placed = []
        for b in d["bosses"]:
            if b["trash"]:
                continue
            ids = byname.get(norm(b["name"]), set())
            pos = [p for e, p in spawns[inst] if e in ids]
            if pos:
                placed.append((norm(b["name"]), pos[0], b["regular"]))
        if not placed:
            continue
        boss_ids = set().union(*(byname.get(n, set()) for n, _, _ in placed))
        mobs = [p for e, p in spawns[inst] if hostile(e) and e not in boss_ids]
        owner = [min(placed, key=lambda x: dist(x[1], p))[0] for p in mobs]

        def kind_row(wing, kind, label, names):
            mine = [p for p, o in zip(mobs, owner) if o in names]
            bs = [x for x in placed if x[0] in names]
            door = min(doors[inst], key=lambda e: min(dist(e, x[1]) for x in bs)) if doors[inst] and bs else None
            g = groups(mine)
            walk = tree_length(g + [x[1] for x in bs] + ([door] if door else []))
            nb = sum(1 for b in regular if norm(b["name"]) in names)
            minutes = (SEC_PER_YARD * walk + SEC_PER_MOB * len(mine) + SEC_PER_BOSS * nb) / 60
            return dict(instanceMapID=inst, wing=wing, kind=kind, label=label, walk_yd=round(walk), mobs=len(mine), groups=len(g), bosses=nb,
                        quest_min_H="", quest_min_A="", minutes=round(minutes, 1), basis="model")

        if W.get(inst):
            for wing, w in sorted(W[inst].items()):
                rows.append(kind_row(wing, "full", "Full clear", w["bosses"]))
        else:
            every = {x[0] for x in placed}
            full = kind_row(0, "full", "Full clear", every)
            rows.append(full)
            # quest run: the full clear plus the extra time of the dungeon quests of each faction. Only work done in the dungeon counts: an item
            # that monsters placed here drop, a target placed here, an escort or event started by someone here (talk-to and hand-in steps add nothing)
            bossnames = {norm(b["name"]) for b in d["bosses"]}
            here = {e for e, _ in spawns[inst]}
            here_items = set().union(*(drops.get(tmpl[e]["loot"], set()) for e in here if e in tmpl))
            for fac in ("H", "A"):
                add = 0.0
                for qid, qf in Q.get(inst, []):
                    if qf and qf != fac or qid not in qinfo:
                        continue
                    r = qinfo[qid]
                    gi = lambda k: int(r[qc[k]] or 0)
                    items = [gi(f"ReqItemId{i}") for i in range(1, 5) if gi(f"ReqItemId{i}") > 0]
                    kills = [gi(f"ReqCreatureOrGOId{i}") for i in range(1, 5) if gi(f"ReqCreatureOrGOId{i}") > 0]
                    if gi("SpecialFlags") & 2 and givers.get(qid, set()) & here:
                        add += QUEST_ESCORT   # escort or event that starts in the dungeon
                    elif any(i in here_items for i in items):
                        add += QUEST_COLLECT
                    elif any(k in here and norm(tmpl[k]["name"]) not in bossnames for k in kills):
                        add += QUEST_KILL     # monsters that are not bosses (a boss is killed in the clear anyway)
                full["quest_min_" + fac] = round(add, 1)
        for k in extra:
            if k["inst"] == inst:
                rows.append(kind_row(k["wing"], k["kind"], k["label"], k["bosses"]))
    return rows


def fit(rows):
    """Grid search for the three numbers that best match CALIBRATION (least squared log error). Prints them; copy them to the top of this file."""
    obs = [(r, CALIBRATION[(int(r["instanceMapID"]), int(r["wing"]))]) for r in rows
           if r["kind"] == "full" and r["basis"] == "model" and (int(r["instanceMapID"]), int(r["wing"])) in CALIBRATION]
    best = None
    for spy in [x / 20 for x in range(2, 41)]:
        for spm in range(0, 31):
            for spb in range(30, 361, 15):
                err = sum(math.log((spy * float(r["walk_yd"]) + spm * int(r["mobs"]) + spb * int(r["bosses"])) / 60 / v) ** 2 for r, v in obs)
                if best is None or err < best[0]:
                    best = (err, spy, spm, spb)
    err, spy, spm, spb = best
    print("best fit on %d reported times: SEC_PER_YARD, SEC_PER_MOB, SEC_PER_BOSS = %s, %s, %s (typical error %.0f%%)"
          % (len(obs), spy, spm, spb, 100 * (math.exp(math.sqrt(err / len(obs))) - 1)))
    for r, v in obs:
        print("  %-28s reported %3d min, fit %3.0f" % ("%s/%s" % (r["instanceMapID"], r["wing"]), v,
                                                       (spy * float(r["walk_yd"]) + spm * int(r["mobs"]) + spb * int(r["bosses"])) / 60))


def five(m):
    return max(5, int(5 * round(m / 5.0)))


def build(rows):
    """Turn draft rows into Data/ClearTimes.lua (manual ranges win)."""
    manual = {}
    if os.path.exists(MANUAL):
        for r in csv.DictReader(open(MANUAL, encoding="utf-8")):
            manual[(int(r["instanceMapID"]), int(r["wing"] or 0), r["kind"])] = (int(r["min"]), int(r["max"]))
    model = [r for r in rows if r["basis"] == "model" and r["kind"] == "full" and int(r["bosses"] or 0) > 0]
    per_boss = sorted(float(r["minutes"]) / int(r["bosses"]) for r in model)
    mpb = per_boss[len(per_boss) // 2] if per_boss else 10.0
    D = dungeons()
    by = collections.defaultdict(list)
    for r in rows:
        inst, wing, kind = int(r["instanceMapID"]), int(r["wing"] or 0), r["kind"]
        minutes = float(r["minutes"]) if r["minutes"] not in ("", None) else int(r["bosses"] or 0) * mpb
        basis = r["basis"]
        lo, hi = five(minutes * LOW), five(minutes * HIGH)
        if (inst, wing, kind) in manual:
            (lo, hi), basis = manual[(inst, wing, kind)], "manual"
        by[inst].append((wing, kind, r["label"], lo, hi, basis))
        if kind == "full":
            for fac in ("H", "A"):
                q = r.get("quest_min_" + fac)
                if q not in ("", None) and float(q) > 0:
                    qm = minutes + float(q)
                    qlo, qhi, qb = five(qm * LOW), five(qm * HIGH), basis
                    if (inst, wing, "quest" + fac) in manual:
                        (qlo, qhi), qb = manual[(inst, wing, "quest" + fac)], "manual"
                    by[inst].append((wing, "quest" + fac, "Quest run", qlo, qhi, qb))
    lines = ["-- GENERATED by tools/gen_clear_times.py from data/draft/clear_times_draft.csv (+ data/manual/clear_times.csv). Do not edit.",
             "-- Estimated clear times in minutes, before any player data: [instanceMapID] = { { wing, kind, label, min, max, basis }, ... }",
             "-- kind: full | questH | questA (quest run for Horde / Alliance) | named kinds from data/manual/run_kinds.csv",
             "-- basis: model (walk + monsters + bosses, CMaNGOS classic-db positions) | bosses (boss count only) | manual (set by hand)",
             "local _, ns = ...", "ns.ClearTimes = {"]
    for inst in sorted(by):
        lines.append("  [%d] = { -- %s" % (inst, D.get(inst, {}).get("name", "?")))
        for wing, kind, label, lo, hi, basis in by[inst]:
            lines.append('    { wing = %d, kind = "%s", label = "%s", min = %d, max = %d, basis = "%s" },' % (wing, kind, label.replace('"', '\\"'), lo, hi, basis))
        lines.append("  },")
    lines.append("}")
    open(OUT, "w", encoding="utf-8", newline="\n").write("\n".join(lines) + "\n")
    return by, mpb


def main():
    argv = sys.argv[1:]
    if "--cdb" in argv:
        sql = argv[argv.index("--cdb") + 1]
        if not os.path.exists(sql):
            sys.exit("no such file: " + sql)
        rows = measure(sql)
        with open(DRAFT, "w", encoding="utf-8", newline="") as f:
            w = csv.DictWriter(f, DRAFT_COLS, lineterminator="\n")
            w.writeheader()
            w.writerows(rows)
        err = [math.log(float(r["minutes"]) / CALIBRATION[(r["instanceMapID"], r["wing"])]) ** 2
               for r in rows if r["kind"] == "full" and (r["instanceMapID"], r["wing"]) in CALIBRATION]
        print("calibration: %d reported times, typical error %.0f%%" % (len(err), 100 * (math.exp(math.sqrt(sum(err) / len(err))) - 1)) if err else "no calibration rows")
    elif argv and argv != ["--fit"]:
        sys.exit(__doc__)
    if not os.path.exists(DRAFT):
        sys.exit("no draft yet: run with --cdb <classic-db.sql> first")
    rows = list(csv.DictReader(open(DRAFT, encoding="utf-8")))
    if "--fit" in argv:
        fit(rows)
        return
    by, mpb = build(rows)
    print("wrote %s: %d dungeons, %d ranges (boss-count estimate: %.1f min per boss)" % (os.path.relpath(OUT, ROOT), len(by), sum(len(v) for v in by.values()), mpb))


if __name__ == "__main__":
    main()
