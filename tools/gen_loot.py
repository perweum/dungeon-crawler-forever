#!/usr/bin/env python3
"""Generate addon/DungeonCrawlerForever/Data/Loot.lua (boss loot per dungeon) from the installed AtlasLoot Forever data files.

Source: AtlasLootClassic_DungeonsAndRaids/data.lua (+ droprate.lua) — AtlasLoot (GPL-3.0). We extract only facts:
boss names, NPC IDs, item IDs, which items are Forever additions ("{FOREVER}" comments) and drop rates.
Items are keyed by OUR boss names (Data/Dungeons.lua) so the addon can look loot up directly.
Output per boss: { {itemID, forever(0/1), dropPercent or nil}, ... } in AtlasLoot's slot order.
Usage: tools/gen_loot.py [path/to/AtlasLootClassic_DungeonsAndRaids]
The parsing and boss matching are plain functions (parse_atlas, our_bosses, match_boss, boss_items ...) so tools/check_loot.py and
tools/gen_abilities.py can import them; importing this module does not write anything.
Matching exceptions are a list, data/manual/loot_map.csv (columns kind,ourName,atlasNames,note), never code:
  composite  our (client) encounter ourName gets the loot of the AtlasLoot bosses in atlasNames (";"-separated, merged in that order)
  alias      ourName and the AtlasLoot name atlasNames are the same boss spelled differently (works both ways)
Names are compared normalised (lower case, letters and digits only); a row applies in every instance.
"""
import os, re, sys, collections
WOW_DIR = os.environ.get("WOW_DIR", "/Applications/World of Warcraft/_classic_beta_")  # game client folder; set WOW_DIR to override

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ATLAS = sys.argv[1] if len(sys.argv) > 1 else WOW_DIR + "/Interface/AddOns/AtlasLootClassic_DungeonsAndRaids"
norm = lambda s: re.sub(r"[^a-z0-9]", "", s.lower())
NEW_KEYS = {"TheCityOfDalaran": 2959, "TheHallOfThanes": 3065, "TheRuinsOfLordaeron": 2999, "ExcavationSiteWetlands": 2998,
            "DireMaulEast": 429, "DireMaulWest": 429, "DireMaulNorth": 429}  # keys without an InstanceID in AtlasLoot's data
SKIPPED = []
TRASH = {}
MISMATCH = []
LOOT_MAP_KINDS = ("composite", "alias")

def loot_map(root=ROOT):
    """data/manual/loot_map.csv -> (COMPOSITE {normalised our name: [AtlasLoot boss names]}, ALIAS {normalised name: normalised name})"""
    import csv as _csv
    composite, alias = {}, {}
    p = os.path.join(root, "data/manual/loot_map.csv")
    if os.path.exists(p):
        for n, r in enumerate(_csv.DictReader(open(p, encoding="utf-8")), start=2):
            kind, ours_, names = (r.get("kind") or "").strip(), norm(r.get("ourName") or ""), [x.strip() for x in (r.get("atlasNames") or "").split(";") if x.strip()]
            if kind not in LOOT_MAP_KINDS or not ours_ or not names or (kind == "alias" and len(names) != 1):
                raise ValueError(f"{p} line {n}: bad row {r} (kind composite|alias, ourName, atlasNames; an alias has one name)")
            if kind == "composite":
                composite[ours_] = names
            else:
                alias[ours_], alias[norm(names[0])] = norm(names[0]), ours_
    return composite, alias

COMPOSITE, ALIAS = loot_map()  # module-level so tools/gen_abilities.py keeps matching like gen_loot.py

def parse_atlas(atlas=None):
    src = open(os.path.join(atlas or ATLAS, "data.lua"), encoding="utf-8").read().replace("\r", "")
    out = collections.defaultdict(list)  # instanceID -> [boss dict]
    blocks = re.split(r'\n(?=data\["[^"]+"\] = \{)', src)
    for blk in blocks:
        m = re.match(r'data\["([^"]+)"\] = \{', blk)
        if not m:
            continue
        key = m.group(1)
        im = re.search(r"^\tInstanceID = (\d+)", blk, re.M)
        inst = int(im.group(1)) if im else NEW_KEYS.get(key)
        if not inst:
            if re.search(r"\[NORMAL_DIFF\] = \{\n\s*\{ ?\d+, ?\d+", blk):
                SKIPPED.append(key)
            continue
        for bm in re.split(r'\n\t\t\{ ?(?:--[^\n]*)?\n', blk):
            nm = re.search(r'^\t\t\tname = (?:AL\["([^"]+)"\]|"([^"]+)")', bm, re.M)
            if not nm:
                continue
            name = nm.group(1) or nm.group(2)
            npc = re.search(r"^\t\t\tnpcID = (\d+)", bm, re.M)
            disp = re.search(r"DisplayIDs = \{ \{ (\d+)", bm)
            special = re.search(r'specialType = "(\w+)"', bm)
            normal = re.search(r"\[NORMAL_DIFF\] = \{\n(.*?)\n\t\t\t\},", bm, re.S)
            items = []
            if normal:
                for line in normal.group(1).split("\n"):
                    im2 = re.match(r"\s*\{\s*(\d+)\s*,\s*(\d+)\s*[,}](.*)", line)
                    if im2:
                        items.append((int(im2.group(2)), 1 if "{FOREVER}" in im2.group(3) else 0))
            raw = len(re.findall(r"^\s*\{\s*\d+\s*,\s*\d+\s*[,}]", normal.group(1), re.M)) if normal else 0
            if raw != len(items):
                MISMATCH.append(f"{key}/{name}: raw {raw} parsed {len(items)}")
            npcline = re.search(r"^\t\t\tnpcID = ([^\n]*)", bm, re.M)
            npcs = [int(x) for x in re.findall(r"\d+", npcline.group(1))] if npcline else []
            out[inst].append({"key": key, "name": name, "npc": int(npc.group(1)) if npc else None, "npcs": npcs,
                              "display": int(disp.group(1)) if disp else None, "items": items,
                              "rare": bool(special and special.group(1) == "rare")})
    return out

def parse_droprates(atlas=None):
    src = open(os.path.join(atlas or ATLAS, "droprate.lua"), encoding="utf-8").read()
    d = {}
    for m in re.finditer(r"\[(\d+)\] = \{\n((?:\t\t\[\d+\] = [\d.]+,?\n?)+)\t\}", src):
        d[int(m.group(1))] = {int(i): float(p) for i, p in re.findall(r"\[(\d+)\] = ([\d.]+)", m.group(2))}
    return d

def our_bosses(root=ROOT):
    s = open(os.path.join(root, "addon/DungeonCrawlerForever/Data/Dungeons.lua"), encoding="utf-8").read()
    res = {}
    for m in re.finditer(r'\[(\d+)\] = \{ name = "([^"]+)", raid = (true|false)[^\n]*\n((?:    \{[^\n]*\n)+)', s):
        names = []
        for b in re.finditer(r'name = "([^"]+)"', m.group(4)):
            if b.group(1) not in names:
                names.append(b.group(1))
        res[int(m.group(1))] = (m.group(2), names)
    return res

def trash_entries(root=ROOT):
    """{instanceMapID: {our entry name: AtlasLoot dungeon key}} from data/manual/boss_trash.csv"""
    import csv as _csv
    out = collections.defaultdict(dict)
    p = os.path.join(root, "data/manual/boss_trash.csv")
    if os.path.exists(p):
        for r in _csv.DictReader(open(p, encoding="utf-8")):
            out[int(r["instanceMapID"])][r["name"]] = r["atlasKey"]
    return out

def by_name(al):
    """AtlasLoot bosses of one instance, keyed by normalised name"""
    by = collections.defaultdict(list)
    for b in al:
        by[norm(b["name"])].append(b)
    return by

def match_boss(inst, name, al, by, trash, lmap=None):
    """The AtlasLoot boss dicts whose loot belongs to our boss `name` (instance `inst`); [] when none match.
    lmap: (COMPOSITE, ALIAS) from loot_map(root); default the repo's data/manual/loot_map.csv."""
    composite, alias = lmap or (COMPOSITE, ALIAS)
    k = norm(name)
    cands = by.get(k) or by.get(alias.get(k, ""), [])
    if name in trash.get(inst, {}):  # a "Trash" entry (data/manual/boss_trash.csv): the trash table of its AtlasLoot dungeon
        cands = [b for b in al if b["key"] == trash[inst][name] and re.match(r"trash", b["name"], re.I)]
    if not cands and k in composite:
        cands = [b for part in composite[k] for b in by.get(norm(part), [])]
    if not cands:  # composite encounter ("Sneed" vs "Sneed's Shredder"): merge AtlasLoot bosses whose name contains ours
        cands = [b for kk, bl in by.items() for b in bl if kk and (kk in k or k in kk) and len(kk) > 4]
    return cands

def boss_items(cands, rates):
    """[(itemID, forever 0/1, dropPercent or None)] of the matched AtlasLoot bosses, first occurrence wins, AtlasLoot slot order"""
    seen, items = set(), []
    for b in cands:
        for item, forever in b["items"]:
            if item in seen:
                continue
            seen.add(item)
            pct = rates.get(b["npc"], {}).get(item) if b["npc"] else None
            items.append((item, forever, pct))
    return items

def main():
    atlas, rates, ours = parse_atlas(), parse_droprates(), our_bosses()
    global TRASH
    TRASH = trash_entries()
    lines = ["-- GENERATED by tools/gen_loot.py from AtlasLoot Forever (GPL-3.0). Do not edit.",
             "-- [instanceMapID][bossName] = { {itemID, forever(0/1), dropPercent|nil}, ... }",
             "local _, ns = ...", "ns.Loot = {"]
    matched = unmatched_ours = items_total = 0
    rares = collections.defaultdict(list)
    boss_keys = collections.defaultdict(dict)  # instance -> our boss name -> {AtlasLoot dungeon keys}
    report = []
    for inst in sorted(ours):
        dname, names = ours[inst]
        al = atlas.get(inst, [])
        if not al:
            continue
        by = by_name(al)
        rows = []
        for name in names:
            cands = match_boss(inst, name, al, by, TRASH)
            if not cands:
                unmatched_ours += 1
                report.append(f"  no loot match: {dname} - {name}")
                continue
            boss_keys[inst][name] = {b["key"] for b in cands}
            if any(b["rare"] for b in cands):
                rares[inst].append(name)
            items = ["{%d,%d%s}" % (item, forever, ",%g" % pct if pct is not None else "") for item, forever, pct in boss_items(cands, rates)]
            if items:
                matched += 1
                items_total += len(items)
                rows.append('    ["%s"] = {%s},' % (name.replace('"', '\\"'), ",".join(items)))
        if rows:
            lines.append(f"  [{inst}] = {{ -- {dname}")
            lines.extend(rows)
            lines.append("  },")
    lines.append("}")
    # rares AtlasLoot does not know (Forever-new dungeons): data/manual/boss_rare.csv (instanceMapID,name,note)
    rp = os.path.join(ROOT, "data/manual/boss_rare.csv")
    if os.path.exists(rp):
        import csv as _csv
        for r in _csv.DictReader(open(rp, encoding="utf-8")):
            inst_, nm_ = int(r["instanceMapID"]), r["name"]
            if inst_ in ours and nm_ in ours[inst_][1]:
                if (r.get("rare") or "yes").strip().lower() == "no":
                    if nm_ in rares[inst_]:
                        rares[inst_].remove(nm_) # AtlasLoot flags it rare, the maintainer says it is not
                elif nm_ not in rares[inst_]:
                    rares[inst_].append(nm_)
    ro = ["-- GENERATED by tools/gen_loot.py from AtlasLoot Forever (GPL-3.0) + data/manual/boss_rare.csv: rare bosses. Do not edit.",
          "-- [instanceMapID][bossName] = true", "local _, ns = ...", "ns.Rares = {"]
    for inst in sorted(rares):
        ro.append("  [%d] = { %s }," % (inst, ", ".join('["%s"] = true' % n.replace('"', '\\"') for n in rares[inst])))
    ro.append("}")
    open(os.path.join(ROOT, "addon/DungeonCrawlerForever/Data/Rares.lua"), "w", encoding="utf-8").write("\n".join(ro) + "\n")
    print(f"{sum(len(v) for v in rares.values())} rare bosses flagged")
    # wings: one map, several dungeons (Lower/Upper Blackrock Spire, Dire Maul East/West/North). Boss lists come from AtlasLoot's grouping.
    wings_csv = os.path.join(ROOT, "data/manual/wings.csv")
    wo = ["-- GENERATED by tools/gen_loot.py from data/manual/wings.csv + AtlasLoot Forever grouping. Do not edit.",
          "-- [instanceMapID] = { { wing = n, name = ..., recMin, recMax, bosses = { [bossName] = true } }, ... }", "local _, ns = ...", "ns.Wings = {"]
    if os.path.exists(wings_csv):
        import csv as _csv
        byinst = collections.defaultdict(list)
        for r in _csv.DictReader(open(wings_csv, encoding="utf-8")):
            byinst[int(r["instanceMapID"])].append(r)
        for inst, wrows in sorted(byinst.items()):
            claimed = set()
            wo.append(f"  [{inst}] = {{")
            for r in sorted(wrows, key=lambda r: int(r["wing"])):
                keys = set(r["atlasKeys"].split(";"))
                names = [n for n, ks in boss_keys.get(inst, {}).items() if ks & keys]
                claimed |= set(names)
                raw_floors = (r.get("floors") or "").strip()
                floors = [f for f in raw_floors.split(";") if f.strip() and f.strip() != "none"]
                none_floors = raw_floors == "none"  # explicit: this wing has no map art
                wo.append('    { wing = %s, name = "%s", recMin = %s, recMax = %s%s, bosses = { %s } },' % (
                    r["wing"], r["name"].replace('"', '\\"'), r["recMin"], r["recMax"],
                    (", floors = { %s }" % ", ".join(floors)) if floors else (", floors = { }" if none_floors else ""),
                    ", ".join('["%s"] = true' % n.replace('"', '\\"') for n in names)))
            wo.append("  },")
            allnames = ours[inst][1] if inst in ours else []
            loose = [n for n in allnames if n not in claimed]
            if loose:
                print(f"WINGS: bosses of instance {inst} not claimed by any wing (add to a wing via wings.csv extraBosses): {loose}")
    wo.append("}")
    open(os.path.join(ROOT, "addon/DungeonCrawlerForever/Data/Wings.lua"), "w", encoding="utf-8").write("\n".join(wo) + "\n")
    path = os.path.join(ROOT, "addon/DungeonCrawlerForever/Data/Loot.lua")
    open(path, "w", encoding="utf-8").write("\n".join(lines) + "\n")
    print(f"{matched} bosses with loot, {items_total} item entries, {unmatched_ours} of our bosses without a match -> {path} ({os.path.getsize(path)//1024} KB)")
    print("\n".join(report[:60]))
    if MISMATCH:
        print("PARSE MISMATCHES:", *MISMATCH[:20], sep="\n  ")
    else:
        print("self-check: every AtlasLoot item row was parsed")
    real = [k for k in SKIPPED if not k.startswith("WorldBosses")]
    if real:
        print("AtlasLoot dungeons with loot but no instance mapping (add to NEW_KEYS):", ", ".join(real))

if __name__ == "__main__":
    main()
