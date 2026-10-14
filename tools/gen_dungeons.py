#!/usr/bin/env python3
"""Generate addon/DungeonCrawlerForever/Data/Dungeons.lua: instances, floors, bosses (+coords/portraits where known).

Inputs (all public DB2 via wago.tools, fetched by gen_art.py / fetch_db2.sh):
  Forever build : Map, DungeonEncounter           -> authoritative instance + boss list
  retail live   : JournalEncounter(+Creature)     -> boss map coords (Map_0/Map_1 on a UiMapID floor) + portrait FileDataID
  data/manual/bosses.csv (ours, optional)         -> hand/recorder-authored coords; override everything
Matching retail->Forever: DungeonEncounterID first, else (instance MapID, normalised name).
"""
import csv, os, re, sys, urllib.request, collections

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FOREVER = open(os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "data/BUILD")).read().strip()
FD = os.path.join(ROOT, "data/raw", FOREVER)
LIVE = os.path.join(ROOT, "data/raw/live")
SKIP_MAPS = {"13", "29", "44", "169", "269", "2853", "2720", "2921"}  # test/unused/unannounced (2720 test boss "Testwerk", 2921 single-boss Naxx variant)

def fetch(name):
    os.makedirs(LIVE, exist_ok=True)
    p = os.path.join(LIVE, name + ".csv")
    if not os.path.exists(p):
        req = urllib.request.Request(f"https://wago.tools/db2/{name}/csv", headers={"User-Agent": "dungeon-map-tools/0.1"})
        with urllib.request.urlopen(req, timeout=180) as r, open(p, "wb") as f:
            f.write(r.read())
    return list(csv.DictReader(open(p, encoding="utf-8")))

def fetch_build(name, build):
    """Journal tables from an older client build (cached under data/raw/<build>/)."""
    d = os.path.join(ROOT, "data/raw", "journal-" + build)
    os.makedirs(d, exist_ok=True)
    p = os.path.join(d, name + ".csv")
    if not os.path.exists(p):
        req = urllib.request.Request(f"https://wago.tools/db2/{name}/csv?build={build}", headers={"User-Agent": "dungeon-map-tools/0.1"})
        with urllib.request.urlopen(req, timeout=180) as r, open(p, "wb") as f:
            f.write(r.read())
    return list(csv.DictReader(open(p, encoding="utf-8")))

MOP = "5.5.4.70032"  # MoP Classic: Blizzard-authored pins for several classic dungeons (RFK, BFD, RFD, BRD, BRS, ZF...)

def norm(s): return re.sub(r"[^a-z0-9]", "", s.lower())
def lua(s): return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'

def main():
    maps = {r["ID"]: r for r in csv.DictReader(open(os.path.join(FD, "Map.csv"), encoding="utf-8"))}
    enc = list(csv.DictReader(open(os.path.join(FD, "DungeonEncounter.csv"), encoding="utf-8")))
    je, ji, jc = fetch("JournalEncounter"), {r["ID"]: r for r in fetch("JournalInstance")}, fetch("JournalEncounterCreature")
    art = open(os.path.join(ROOT, "addon/DungeonCrawlerForever/Data/Art.lua"), encoding="utf-8").read()
    floors_by_inst = {}
    for m in re.finditer(r"\[(\d+)\] = \{ -- [^\n]*\n((?:    \{[^\n]*\n)+)", art):
        floors_by_inst[m.group(1)] = re.findall(r"uiMapID = (\d+)", m.group(2))
    for fa in (os.path.join(ROOT, "addon/DungeonCrawlerForever/Data/ArtForever.lua"), os.path.join(ROOT, "addon/DungeonCrawlerForever/Data/ArtCustom.lua")):
      if os.path.exists(fa):  # Forever-new dungeons (stitched WMO minimap tiles)
        for m in re.finditer(r"\[(\d+)\] = \{ -- [^\n]*\n((?:    \{[^\n]*\n)+)", open(fa, encoding="utf-8").read()):
            floors_by_inst[m.group(1)] = re.findall(r"uiMapID = (\d+)", m.group(2))
    all_floors = {u for v in floors_by_inst.values() for u in v}  # floors the addon shows
    # the game's own floors of a dungeon that now has an overview map are not shown any more, but the journal entries on them still carry
    # the boss portraits: they are matched on these too (positions are only taken from floors that are shown)
    cand_floors = all_floors | set(re.findall(r"uiMapID = (\d+)", art))

    portrait = {}
    for c in sorted(jc, key=lambda r: int(r["OrderIndex"])):
        if c["FileDataID"] not in ("", "0"):
            portrait.setdefault(c["JournalEncounterID"], c["FileDataID"])
    by_de, by_name = collections.defaultdict(list), collections.defaultdict(list)
    for e in je:
        if not float(e["Map_0"] or 0) and not float(e["Map_1"] or 0):
            continue
        if e["UiMapID"] not in cand_floors:
            continue
        by_de[e["DungeonEncounterID"]].append(e)
        by_name[(ji.get(e["JournalInstanceID"], {}).get("MapID"), norm(e["Name_lang"]))].append(e)

    # secondary source: MoP Classic journal pins (same uiMap space), used only where live retail has none
    mji = {r["ID"]: r for r in fetch_build("JournalInstance", MOP)}
    mop_by_name = collections.defaultdict(list)
    for e in fetch_build("JournalEncounter", MOP):
        if (float(e["Map_0"] or 0) or float(e["Map_1"] or 0)) and e["UiMapID"] in all_floors:
            mop_by_name[(mji.get(e["JournalInstanceID"], {}).get("MapID"), norm(e["Name_lang"]))].append(e)
    manual = {}
    mp = os.path.join(ROOT, "data/manual/bosses.csv")  # instanceMapID,uiMapID,name,x,y
    if os.path.exists(mp):
        for r in csv.DictReader(open(mp, encoding="utf-8")):
            manual[(r["instanceMapID"], norm(r["name"]))] = r

    # Entry levels from MapDifficulty messages ("You must be at least level N to enter.")
    minlvl = {}
    for r in csv.DictReader(open(os.path.join(FD, "MapDifficulty.csv"), encoding="utf-8")):
        mm = re.search(r"level (\d+)", r["Message_lang"])
        if mm and r["DifficultyID"] in ("1", "0"):
            minlvl[r["MapID"]] = int(mm.group(1))
    # Our own authored info (levels, entrances): data/manual/dungeon_info.csv
    info = {}
    for fn in ("entrances_classic.csv", "dungeon_info.csv", "overrides.csv"):  # later files override per non-empty field
        ip = os.path.join(ROOT, "data/manual", fn)
        if os.path.exists(ip):
            for r in csv.DictReader(open(ip, encoding="utf-8")):
                cur = info.setdefault(r["instanceMapID"], {})
                cur.update({k: v for k, v in r.items() if v not in ("", None)})

    # Display-name fixes where the client's encounter name differs from what players see: data/manual/boss_names.csv
    renames = {}
    rp = os.path.join(ROOT, "data/manual/boss_names.csv")  # instanceMapID,clientName,displayName
    if os.path.exists(rp):
        for r in csv.DictReader(open(rp, encoding="utf-8")):
            renames[(r["instanceMapID"], norm(r["clientName"]))] = r["displayName"]

    # Encounters the client lists that players don't treat as bosses: data/manual/boss_hide.csv (instanceMapID,name,reason)
    hidden = set()
    hp = os.path.join(ROOT, "data/manual/boss_hide.csv")
    if os.path.exists(hp):
        for r in csv.DictReader(open(hp, encoding="utf-8")):
            hidden.add((r["instanceMapID"], norm(r["name"])))

    # Hand-set route numbers: data/manual/boss_order.csv (instanceMapID,name,num). Shown on the pins and used to order the boss list.
    nums = {}
    nop = os.path.join(ROOT, "data/manual/boss_order.csv")
    if os.path.exists(nop):
        for r in csv.DictReader(open(nop, encoding="utf-8")):
            nums[(r["instanceMapID"], norm(r["name"]))] = int(r["num"])

    displays = {}  # creature display IDs recorded in-game: data/manual/boss_display.csv
    dpp = os.path.join(ROOT, "data/manual/boss_display.csv")
    if os.path.exists(dpp):
        for r in csv.DictReader(open(dpp, encoding="utf-8")):
            displays[(r["instanceMapID"], norm(r["name"]))] = r["displayID"]

    # Per-instance status: data/manual/dungeon_status.csv (instanceMapID,status,note). hidden = not shown at all (unannounced /
    # Season-of-Discovery content), classic = classic data, not confirmed for Forever yet (the UI says so).
    status = {}
    stp = os.path.join(ROOT, "data/manual/dungeon_status.csv")
    if os.path.exists(stp):
        for r in csv.DictReader(open(stp, encoding="utf-8")):
            status[r["instanceMapID"]] = r["status"]

    draft = {}  # approximate positions (lowest priority): data/draft/bosses_draft.csv
    dp = os.path.join(ROOT, "data/draft/bosses_draft.csv")
    if os.path.exists(dp):
        for r in csv.DictReader(open(dp, encoding="utf-8")):
            draft[(r["instanceMapID"], norm(r["name"]))] = r

    per = collections.OrderedDict()
    stats = collections.Counter()
    for d in sorted(enc, key=lambda r: (int(r["MapID"]), r["DifficultyID"], int(r["OrderIndex"]))):
        m = maps.get(d["MapID"])
        if not m or m["InstanceType"] not in ("1", "2") or d["MapID"] in SKIP_MAPS or status.get(d["MapID"]) == "hidden":
            continue
        inst = per.setdefault(d["MapID"], {"name": m["MapName_lang"], "raid": m["InstanceType"] == "2", "bosses": [], "seen": set()})
        key = (d["DifficultyID"], norm(d["Name_lang"]))
        if key in inst["seen"]:
            continue
        inst["seen"].add(key)
        cands = by_de.get(d["ID"]) or by_name.get((d["MapID"], norm(d["Name_lang"]))) or []
        if (d["MapID"], norm(d["Name_lang"])) in hidden:
            continue
        display = renames.get((d["MapID"], norm(d["Name_lang"])), d["Name_lang"])
        b = {"id": d["ID"], "name": display, "diff": d["DifficultyID"], "order": d["OrderIndex"]}
        if cands:
            e = cands[0]
            if e["UiMapID"] in all_floors:
                b.update(floor=e["UiMapID"], x=float(e["Map_0"]), y=float(e["Map_1"]), src="retail-ej")
            if e["ID"] in portrait:
                b["portrait"] = portrait[e["ID"]]
        if not cands:
            mc = mop_by_name.get((d["MapID"], norm(d["Name_lang"])))
            if mc:
                e = mc[0]
                b.update(floor=e["UiMapID"], x=float(e["Map_0"]), y=float(e["Map_1"]), src="mop-ej")
        if "x" not in b:
            drow = draft.get((d["MapID"], norm(display))) or draft.get((d["MapID"], norm(d["Name_lang"])))
            if drow and drow["uiMapID"] in all_floors:
                b.update(floor=drow["uiMapID"], x=float(drow["x"]), y=float(drow["y"]), src="draft", approx=True)
        mrow = manual.get((d["MapID"], norm(display))) or manual.get((d["MapID"], norm(d["Name_lang"])))
        if mrow:
            b.update(floor=mrow["uiMapID"], x=float(mrow["x"]), y=float(mrow["y"]), src="manual")
        num = nums.get((d["MapID"], norm(display)))
        if num:
            b["num"] = num
        disp = displays.get((d["MapID"], norm(display)))
        if disp:
            b["display"] = disp
        stats["with_coords" if "x" in b else "no_coords"] += 1
        inst["bosses"].append(b)

    # Sub-encounters the client folds into one encounter (the Ring of Law champions): data/manual/boss_extra.csv
    # (instanceMapID,name,parent,displayID,note). They are listed right after their parent, keep its floor but have no pin of their own
    # (the parent carries the position and the kill state), and get loot / abilities by name like any boss.
    xp = os.path.join(ROOT, "data/manual/boss_extra.csv")
    if os.path.exists(xp):
        counter = collections.Counter()
        for r in csv.DictReader(open(xp, encoding="utf-8")):
            inst = per.get(r["instanceMapID"])
            parent = next((b for b in inst["bosses"] if b["name"] == r["parent"]), None) if inst else None
            if not parent:
                print(f"boss_extra.csv: parent {r['parent']!r} not found in instance {r['instanceMapID']}")
                continue
            counter[r["parent"]] += 1
            sub = {"id": 900000 + int(r["instanceMapID"]) * 10 + counter[r["parent"]], "name": r["name"], "diff": parent["diff"],
                   "order": str(int(float(parent["order"])) + counter[r["parent"]]), "sub": True, "parent": parent["id"]}
            if "floor" in parent:
                sub["floor"] = parent["floor"]
            if r.get("displayID"):
                sub["display"] = r["displayID"]
            at = max(i for i, b in enumerate(inst["bosses"]) if b["name"] == r["parent"] or b.get("parent") == parent["id"])
            inst["bosses"].insert(at + 1, sub)

    # Bosses and rares the game's encounter list does not have (data/manual/boss_add.csv: instanceMapID,name,displayID,order,note). They get a
    # synthetic id, are placed by data/manual/bosses.csv like any boss, and get loot / the rare ring from AtlasLoot by name.
    ap = os.path.join(ROOT, "data/manual/boss_add.csv")
    if os.path.exists(ap):
        added = collections.Counter()
        for r in csv.DictReader(open(ap, encoding="utf-8")):
            inst = per.get(r["instanceMapID"])
            if not inst:
                print(f"boss_add.csv: instance {r['instanceMapID']} not found")
                continue
            if any(b["name"] == r["name"] for b in inst["bosses"]):
                continue
            added[r["instanceMapID"]] += 1
            b = {"id": 950000 + int(r["instanceMapID"]) * 10 + added[r["instanceMapID"]], "name": r["name"], "diff": "0", "order": r["order"] or "9000"}
            if r.get("displayID"):
                b["display"] = r["displayID"]
            mrow = manual.get((r["instanceMapID"], norm(r["name"])))
            if mrow:
                b.update(floor=mrow["uiMapID"], x=float(mrow["x"]), y=float(mrow["y"]), src="manual")
            disp = displays.get((r["instanceMapID"], norm(r["name"])))
            if disp:
                b["display"] = disp
            inst["bosses"].append(b)

    # Bosses that need something special (data/manual/boss_summoned.csv: instanceMapID,name,kind,displayID,how,note). `how` is a one-line hint shown in
    # the boss header. kind = summoned: you need an item or a quest chain from outside the dungeon (Dreadsteed, Tier 0.5 gear, the Zul'Farrak mallet): purple
    # tag and ring, listed after the regular bosses. kind = event: part of the dungeon itself (Aku'mai, Archaedas ...): a normal boss with the hint only.
    # A boss that is not in the list yet is added (its portrait comes from `displayID` or AtlasLoot's data).
    atlas_src = ""
    atlas_p = "/Applications/World of Warcraft/_classic_beta_/Interface/AddOns/AtlasLootClassic_DungeonsAndRaids/data.lua"
    if os.path.exists(atlas_p):
        atlas_src = open(atlas_p, encoding="utf-8").read().replace("\r", "")
    def atlas_display(name):
        m = re.search(r'name = AL\["' + re.escape(name) + r'"\][^\n]*(?:\n[^\n]*){0,8}?\n\s*DisplayIDs = \{ \{ (\d+)', atlas_src)
        return m.group(1) if m else None
    sp = os.path.join(ROOT, "data/manual/boss_summoned.csv")
    if os.path.exists(sp):
        sn = collections.Counter()
        for r in csv.DictReader(open(sp, encoding="utf-8")):
            inst = per.get(r["instanceMapID"])
            if not inst:
                print(f"boss_summoned.csv: instance {r['instanceMapID']} not found")
                continue
            summoned = (r.get("kind") or "summoned") == "summoned"
            sn[r["instanceMapID"]] += 1
            boss = next((b for b in inst["bosses"] if norm(b["name"]) == norm(r["name"])), None)
            if boss is None:
                boss = {"id": 970000 + int(r["instanceMapID"]) * 100 + sn[r["instanceMapID"]], "name": r["name"], "diff": "0",
                        "order": "98000" if summoned else "97000"}
                disp = r.get("displayID") or atlas_display(r["name"])
                if disp:
                    boss["display"] = disp
                mrow = manual.get((r["instanceMapID"], norm(r["name"])))
                if mrow:
                    boss.update(floor=mrow["uiMapID"], x=float(mrow["x"]), y=float(mrow["y"]), src="manual")
                d2 = displays.get((r["instanceMapID"], norm(r["name"])))
                if d2:
                    boss["display"] = d2
                inst["bosses"].append(boss)
            if summoned:
                boss["summoned"] = True
                boss["order"] = str(98000 + sn[r["instanceMapID"]])
            if r.get("how"):
                boss["how"] = r["how"]

    # a short note for a rare ("patrols", "has three spawn locations"): data/manual/boss_rare.csv, column `how`
    rp = os.path.join(ROOT, "data/manual/boss_rare.csv")
    if os.path.exists(rp):
        for r in csv.DictReader(open(rp, encoding="utf-8")):
            inst = per.get(r["instanceMapID"])
            if inst and (r.get("how") or "").strip():
                for b in inst["bosses"]:
                    if norm(b["name"]) == norm(r["name"]):
                        b["how"] = r["how"].strip()

    # "Trash" entries (data/manual/boss_trash.csv, made by tools/gen_trash_rows.py): the loot of the regular mobs, listed last. No pin, no portrait.
    tp = os.path.join(ROOT, "data/manual/boss_trash.csv")
    if os.path.exists(tp):
        tn = collections.Counter()
        for r in csv.DictReader(open(tp, encoding="utf-8")):
            inst = per.get(r["instanceMapID"])
            if not inst:
                continue
            tn[r["instanceMapID"]] += 1
            inst["bosses"].append({"id": 960000 + int(r["instanceMapID"]) * 10 + tn[r["instanceMapID"]], "name": r["name"], "diff": "0",
                                   "order": r["order"] or "99000", "trash": True})

    out = ["-- GENERATED by tools/gen_dungeons.py. Do not edit; put hand-made coords in data/manual/bosses.csv.",
           "-- bosses: id=DungeonEncounterID, diff=DifficultyID, floor=uiMapID (see Art.lua), x/y 0..1 on that floor, portrait=FileDataID",
           "local _, ns = ...", "ns.Dungeons = {"]
    for mid, inst in per.items():
        if not inst["bosses"]:
            continue
        extra = ""
        row = info.get(mid, {})
        if inst["raid"] and not row.get("recMinLevel"):
            row = dict(row, recMinLevel="60", recMaxLevel="60")  # classic raids: level 60 content
        mn = row.get("minEnterLevel") or minlvl.get(mid)
        if mn: extra += f", minLevel = {int(float(mn))}"
        if row.get("recMinLevel") and row.get("recMaxLevel"):
            extra += f", recMin = {int(float(row['recMinLevel']))}, recMax = {int(float(row['recMaxLevel']))}"
        if status.get(mid) == "classic":
            extra += ', status = "classic"'
        out.append(f'  [{mid}] = {{ name = {lua(inst["name"])}, raid = {"true" if inst["raid"] else "false"}, hasArt = {"true" if mid in floors_by_inst else "false"}{extra}, bosses = {{')
        for b in inst["bosses"]:
            f = f'    {{ id = {b["id"]}, name = {lua(b["name"])}, diff = {b["diff"]}, order = {b["order"]}'
            if "x" in b:
                f += f', floor = {b["floor"]}, x = {b["x"]:.4f}, y = {b["y"]:.4f}'
            elif b.get("sub") and "floor" in b:
                f += f', floor = {b["floor"]}'
            if b.get("sub"):
                f += f', sub = true, parent = {b["parent"]}'
            if b.get("trash"):
                f += ", trash = true"
            if b.get("summoned"):
                f += ", summoned = true"
            if b.get("how"):
                f += f", how = {lua(b['how'])}"
            if b.get("num"):
                f += f', num = {b["num"]}'
            if b.get("display"):
                f += f', display = {b["display"]}'
            if b.get("approx"):
                f += ", approx = true"
            if "portrait" in b:
                f += f', portrait = {b["portrait"]}'
            out.append(f + " },")
        out.append("  } },")
    out.append("}")
    p = os.path.join(ROOT, "addon/DungeonCrawlerForever/Data/Dungeons.lua")
    open(p, "w", encoding="utf-8").write("\n".join(out) + "\n")
    # entrances: zone map pins from the csv files, plus the same entrances converted onto the continent maps
    ent = collections.defaultdict(list)
    zone_assign, cont_assign = {}, {}
    for a in csv.DictReader(open(os.path.join(FD, "UiMapAssignment.csv"), encoding="utf-8")):
        reg = [float(a["Region_%d" % i]) for i in range(6)]
        zone_assign.setdefault(a["UiMapID"], (a["MapID"], reg))
    for cid, mid_ in (("1415", "0"), ("1414", "1")):
        if cid in zone_assign:
            cont_assign[mid_] = (cid, zone_assign[cid][1])
    for mid, row in info.items():
        if status.get(mid) == "hidden" or mid not in per or not per[mid]["bosses"]:
            continue
        if row.get("entranceZoneUiMapID") and row.get("entranceX") and row.get("entranceY"):
            zone, x, y = row["entranceZoneUiMapID"], float(row["entranceX"]), float(row["entranceY"])
            ent[zone].append((mid, x, y))
            za = zone_assign.get(zone)
            if za and za[0] in cont_assign:  # zone (u,v) -> world (x,y) -> continent (u,v)
                zr, cid_reg = za[1], cont_assign[za[0]]
                wx, wy = zr[3] - y * (zr[3] - zr[0]), zr[4] - x * (zr[4] - zr[1])
                cr = cid_reg[1]
                cu, cv = (cr[4] - wy) / (cr[4] - cr[1]), (cr[3] - wx) / (cr[3] - cr[0])
                if 0 <= cu <= 1 and 0 <= cv <= 1:
                    ent[cid_reg[0]].append((mid, cu, cv))
    # extra zone-map entrances for an instance that is reachable from several zone maps (no continent duplicate)
    xp = os.path.join(ROOT, "data/manual/entrances_extra.csv")
    if os.path.exists(xp):
        for r in csv.DictReader(open(xp, encoding="utf-8")):
            if r["instanceMapID"] in per and per[r["instanceMapID"]]["bosses"]:
                ent[r["zoneUiMapID"]].append((r["instanceMapID"], float(r["entranceX"]), float(r["entranceY"])))

    # clusters: entrances that share a place (Blackrock Mountain, Dire Maul, Scarlet Monastery) get ONE position and per-pin offsets
    # measured in pin sizes (ox, oy), so they stay tightly grouped on every map regardless of its size. member@dx,dy sets an offset by hand.
    cp = os.path.join(ROOT, "data/manual/entrance_clusters.csv")
    if os.path.exists(cp):
        crow = list(csv.DictReader(open(cp, encoding="utf-8")))
        members_all = {m.split("@")[0].split(":")[0] for r in crow for m in r["members"].split()}
        for zone in list(ent):
            ent[zone] = [e for e in ent[zone] if str(e[0]).split(":")[0] not in members_all]
        for r in crow:
            members = []
            for tok in r["members"].split():
                key, _, off = tok.partition("@")
                if key.split(":")[0] in per and per[key.split(":")[0]]["bosses"]:
                    members.append((key, tuple(float(v) for v in off.split(",")) if off else None))
            if not members:
                continue
            n = len(members)
            per_row = int(r.get("perRow") or 0) or n
            rows = (n + per_row - 1) // per_row
            def offsets(i):
                key, manual_off = members[i]
                if manual_off:
                    return manual_off
                row, col = divmod(i, per_row)
                in_row = min(per_row, n - row * per_row)
                return (col - (in_row - 1) / 2, row - (rows - 1) / 2)
            ax, ay, zone = float(r["anchorX"]), float(r["anchorY"]), r["zoneUiMapID"]
            for i, (key, _) in enumerate(members):
                ox, oy = offsets(i)
                if r.get("continent") == "only":  # offset only on the continent map; the zone map keeps one plain pin
                    ent[zone].append((key, ax, ay))
                else:
                    ent[zone].append((key, ax, ay, ox, oy))
            za = zone_assign.get(zone)
            if r.get("continent") in ("yes", "only") and za and za[0] in cont_assign:
                zr, (cid, cr) = za[1], cont_assign[za[0]]
                wx, wy = zr[3] - ay * (zr[3] - zr[0]), zr[4] - ax * (zr[4] - zr[1])
                cu, cv = (cr[4] - wy) / (cr[4] - cr[1]), (cr[3] - wx) / (cr[3] - cr[0])
                for i, (key, _) in enumerate(members):
                    ox, oy = offsets(i)
                    ent[cid].append((key, cu, cv, ox, oy))
    # floor markers (entrance / exit / stairs / portal) recorded in game
    mk = collections.defaultdict(lambda: collections.defaultdict(list))
    mp = os.path.join(ROOT, "data/manual/markers.csv")
    if os.path.exists(mp):
        for r in csv.DictReader(open(mp, encoding="utf-8")):
            mk[r["instanceMapID"]][r["uiMapID"]].append((r["kind"], float(r["x"]), float(r["y"]), (r.get("boss") or "").strip(), (r.get("label") or "").strip()))
    mo = ["-- GENERATED by tools/gen_dungeons.py from data/manual/markers.csv. Do not edit.", "local _, ns = ...", "ns.Markers = {"]
    for inst_, floors_ in sorted(mk.items(), key=lambda kv: int(kv[0])):
        mo.append(f"  [{inst_}] = {{")
        for fl_, lst_ in sorted(floors_.items(), key=lambda kv: int(kv[0])):
            def one(m):  # triggers carry the boss they start and a short label
                extra = (", boss = %s" % lua(m[3]) if m[3] else "") + (", label = %s" % lua(m[4]) if m[4] else "")
                return '{ kind = "%s", x = %.4f, y = %.4f%s }' % (m[0], m[1], m[2], extra)
            mo.append(f"    [{fl_}] = {{ " + ", ".join(one(m) for m in lst_) + " },")
        mo.append("  },")
    mo.append("}")
    # floor links: two markers (any icon) on different floors that lead to each other
    links = collections.defaultdict(list)
    lp = os.path.join(ROOT, "data/manual/marker_links.csv")
    if os.path.exists(lp):
        for r in csv.DictReader(open(lp, encoding="utf-8")):
            links[r["instanceMapID"]].append(r)
    mo.append("ns.MarkerLinks = {")
    for inst_, lst_ in sorted(links.items(), key=lambda kv: int(kv[0])):
        mo.append(f"  [{inst_}] = {{")
        for r in lst_:
            mo.append("    { fa = %s, xa = %.4f, ya = %.4f, fb = %s, xb = %.4f, yb = %.4f }," % (
                r["floorA"], float(r["xA"]), float(r["yA"]), r["floorB"], float(r["xB"]), float(r["yB"])))
        mo.append("  },")
    mo.append("}")
    open(os.path.join(ROOT, "addon/DungeonCrawlerForever/Data/Markers.lua"), "w", encoding="utf-8").write("\n".join(mo) + "\n")

    # routes (data/manual/routes.csv, made with the Route tool and tools/import_manual.py)
    rts = collections.OrderedDict()
    rp_ = os.path.join(ROOT, "data/manual/routes.csv")
    if os.path.exists(rp_):
        for r in csv.DictReader(open(rp_, encoding="utf-8")):
            rts.setdefault((int(r["instanceMapID"]), int(r["wing"])), []).append(r)
    ro_ = ["-- GENERATED by tools/gen_dungeons.py from data/manual/routes.csv. Do not edit.", "-- [instanceMapID][wing or 0] = { { f = floor, x, y, boss = name (a stop), kind = marker kind, tag, mboss, pair = true }, ... }",
           "local _, ns = ...", "ns.RouteData = {"]
    last_inst = None
    for (inst_, wing_), pts in sorted(rts.items()):
        if inst_ != last_inst:
            if last_inst is not None: ro_.append("  },")
            ro_.append(f"  [{inst_}] = {{")
            last_inst = inst_
        parts = []
        for r in sorted(pts, key=lambda r: int(r["seq"])):
            f = "f = %s, x = %.4f, y = %.4f" % (r["floor"], float(r["x"]), float(r["y"]))
            if r["boss"]: f += ", boss = %s" % lua(r["boss"])
            if r["kind"]: f += ', kind = "%s"' % r["kind"]
            if r["tag"]: f += ", tag = %s" % lua(r["tag"])
            if r["mboss"]: f += ", mboss = %s" % lua(r["mboss"])
            if r["pair"]: f += ", pair = true"
            parts.append("{ " + f + " }")
        ro_.append(f"    [{wing_}] = {{ " + ", ".join(parts) + " },")
    if last_inst is not None: ro_.append("  },")
    ro_.append("}")
    open(os.path.join(ROOT, "addon/DungeonCrawlerForever/Data/Routes.lua"), "w", encoding="utf-8").write("\n".join(ro_) + "\n")

    eo = ["-- GENERATED by tools/gen_dungeons.py from data/manual/*.csv. Do not edit.", "local _, ns = ...", "ns.Entrances = {"]
    for zone, lst in sorted(ent.items(), key=lambda kv: int(kv[0])):
        eo.append(f"  [{zone}] = {{")
        for e in lst:
            mid, x, y = e[0], e[1], e[2]
            inst_, _, wing_ = str(mid).partition(":")
            off = f", ox = {e[3]:g}, oy = {e[4]:g}" if len(e) > 3 else ""
            eo.append(f"    {{ instance = {inst_}, {'wing = ' + wing_ + ', ' if wing_ else ''}x = {x:.4f}, y = {y:.4f}{off} }},")
        eo.append("  },")
    eo.append("}")
    open(os.path.join(ROOT, "addon/DungeonCrawlerForever/Data/Entrances.lua"), "w", encoding="utf-8").write("\n".join(eo) + "\n")
    print(f"entrances: {sum(len(v) for v in ent.values())}")
    print(f"wrote {p}: {len([i for i in per.values() if i['bosses']])} instances; bosses {dict(stats)}")
    for mid, inst in per.items():
        nb = [b for b in inst["bosses"] if "x" not in b]
        if nb and mid in floors_by_inst:
            print(f"  art but {len(nb)}/{len(inst['bosses'])} bosses lack coords: {inst['name']}")

main()
