#!/usr/bin/env python3
"""Read-only loot check: compares Data/Loot.lua with the installed AtlasLoot Forever data and, optionally, with CMaNGOS classic-db.

Never writes anything (not Data/*.lua, not the CSVs). Plain-text report, sections:
  MISSING                 our bosses (Data/Dungeons.lua) with no entry in Data/Loot.lua and no loot in AtlasLoot either: a real gap
                          (regenerating will not fix it; needs a gen_loot.py mapping, an allowlist row or a maintainer decision)
  NOT RELEASED            the same, but in an instance that data/manual/dungeon_status.csv marks hidden (Season of Discovery /
                          unannounced) or classic (not confirmed for Forever): not released on Forever, so no loot is needed yet and
                          they are not counted as missing. When the status row goes (the instance is released) they are MISSING again.
  NEW IN ATLASLOOT        loot AtlasLoot has now that Data/Loot.lua does not: a whole boss (no Loot.lua entry yet) or extra items
                          -> regenerate with tools/gen_loot.py (a separate task). Also lists AtlasLoot dungeons with loot that gen_loot.py
                          cannot map to an instance (no plain InstanceID, not in NEW_KEYS): counted apart as unmapped=N, since
                          regenerating does not pick them up (needs a gen_loot.py mapping)
  REMOVED FROM ATLASLOOT  bosses or items in Data/Loot.lua that AtlasLoot no longer has
  ALLOWLISTED             bosses with no loot of their own that data/manual/loot_none.csv expects (not gaps)
  STALE ALLOWLIST         allowlist rows whose boss does get loot (Loot.lua or AtlasLoot), or is not in Data/Dungeons.lua
  CROSS-CHECK             only with --cdb: per boss, AtlasLoot items vs CMaNGOS classic-db creature_loot_template (+ reference_loot_template,
                          creature_template NPC -> LootId). Forever items ({FOREVER} or ids >= 100000, which no 1.12 database has) are
                          expected to be AtlasLoot-only and listed apart; so are CMaNGOS quest drops (negative chance). A boss counts as a
                          mismatch when it has other AtlasLoot-only items or CMaNGOS-only normal drops.
Every count is a number of bosses (allowlist rows for STALE, AtlasLoot dungeon keys for unmapped). The last line is machine-readable:
  LOOTCHECK missing=N new=N removed=N stale=N allowlisted=N unmapped=N unreleased=N crosscheck=skipped|N-mismatch
Exit status 0, also when gaps are found; 2 only when an input cannot be read.

Usage: tools/check_loot.py [--atlas <AtlasLootClassic_DungeonsAndRaids folder>] [--cdb <classic-db.sql>] [--root <repo root>]
  --atlas  default: $WOW_DIR/Interface/AddOns/AtlasLootClassic_DungeonsAndRaids
  --root   folder with addon/DungeonCrawlerForever/Data/{Dungeons,Loot}.lua and data/manual/{loot_none,boss_trash,loot_map,dungeon_status}.csv
           (default: this repo; the test points it at tools/test/loot_check/)
"""
import collections, csv, os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
_argv, sys.argv = sys.argv, sys.argv[:1]  # gen_loot reads an AtlasLoot folder from argv[1] at import time; we pass ours explicitly
import gen_loot  # noqa: E402
import gen_quests  # noqa: E402  (its classic-db SQL loader)
sys.argv = _argv

REASONS = ("summoned", "event", "chest", "shared", "noloot")
UNRELEASED = ("hidden", "classic")  # data/manual/dungeon_status.csv statuses of instances not released on Forever (no loot needed yet)
FOREVER_MIN_ID = 100000  # classic 1.12 item ids stay far below this; Forever's own items are 25xxxx-27xxxx
CDB_TABLES = ("creature_template", "creature_loot_template", "reference_loot_template")

def arg(name, default=None):
    a = sys.argv[1:]
    return a[a.index(name) + 1] if name in a and a.index(name) + 1 < len(a) else default

def read_loot_lua(path):
    """Data/Loot.lua -> {instanceMapID: {bossName: [itemID, ...]}}"""
    out, inst = collections.defaultdict(dict), None
    for line in open(path, encoding="utf-8"):
        m = re.match(r"^  \[(\d+)\] = \{", line)
        if m:
            inst = int(m.group(1))
            continue
        m = re.match(r'^    \["((?:[^"\\]|\\.)*)"\] = \{(.*)\},$', line.rstrip("\n"))
        if m and inst is not None:
            out[inst][m.group(1).replace('\\"', '"')] = [int(i) for i in re.findall(r"\{(\d+),\d", m.group(2))]
    return out

def read_allowlist(path):
    """data/manual/loot_none.csv -> {(instanceMapID, name): row}; bad rows -> problems"""
    rows, problems = {}, []
    if not os.path.exists(path):
        return rows, problems
    for n, r in enumerate(csv.DictReader(open(path, encoding="utf-8")), start=2):
        try:
            key = (int(r["instanceMapID"]), r["name"])
        except (KeyError, TypeError, ValueError):
            problems.append(f"line {n}: bad instanceMapID: {r}")
            continue
        if (r.get("reason") or "") not in REASONS:
            problems.append(f"line {n}: {key[1]}: reason {r.get('reason')!r} is not one of {', '.join(REASONS)}")
        rows[key] = r
    return rows, problems

def read_status(path):
    """data/manual/dungeon_status.csv -> {instanceMapID: (status, note)} for the instances not released on Forever"""
    out = {}
    if os.path.exists(path):
        for r in csv.DictReader(open(path, encoding="utf-8")):
            if (r.get("status") or "").strip() in UNRELEASED:
                out[int(r["instanceMapID"])] = (r["status"].strip(), (r.get("note") or "").strip())
    return out

def cdb_loot(path):
    """CMaNGOS classic-db dump -> (npc entry -> LootId, loot id -> {item: chance}) with reference_loot_template resolved."""
    T = gen_quests.load(path, CDB_TABLES)
    tc, tr = T["creature_template"]
    lc, lr = T["creature_loot_template"]
    rc, rr = T["reference_loot_template"]
    for need, cols in (("Entry", tc), ("LootId", tc), ("entry", lc), ("item", lc), ("ChanceOrQuestChance", lc), ("mincountOrRef", lc)):
        if need not in cols:
            raise ValueError(f"column {need} not found (is this a CMaNGOS classic-db dump?)")
    lootid = {int(r[tc["Entry"]]): int(r[tc["LootId"]] or 0) for r in tr}
    def table(rows, c):
        d = collections.defaultdict(list)
        for r in rows:
            d[int(r[c["entry"]])].append((int(r[c["item"]]), float(r[c["ChanceOrQuestChance"]] or 0), int(r[c["mincountOrRef"]] or 0)))
        return d
    creature, reference = table(lr, lc), (table(rr, rc) if rc else {})
    def resolve(rows, seen):
        items = {}
        for item, chance, mref in rows:
            if mref < 0:  # a reference row: its items come from reference_loot_template entry -mincountOrRef
                if -mref not in seen:
                    for i, ch in resolve(reference.get(-mref, ()), seen | {-mref}).items():
                        items.setdefault(i, ch)
            else:
                items.setdefault(item, chance)
        return items
    return lootid, {e: resolve(rows, frozenset()) for e, rows in creature.items()}

def main():
    root = os.path.abspath(arg("--root", gen_loot.ROOT))
    atlas_dir = arg("--atlas", gen_loot.WOW_DIR + "/Interface/AddOns/AtlasLootClassic_DungeonsAndRaids")
    cdb = arg("--cdb")
    allow_path = os.path.join(root, "data/manual/loot_none.csv")
    try:
        atlas, rates = gen_loot.parse_atlas(atlas_dir), gen_loot.parse_droprates(atlas_dir)
        ours, trash, lmap = gen_loot.our_bosses(root), gen_loot.trash_entries(root), gen_loot.loot_map(root)
        snap = read_loot_lua(os.path.join(root, "addon/DungeonCrawlerForever/Data/Loot.lua"))
        allow, allow_problems = read_allowlist(allow_path)
        unrel = read_status(os.path.join(root, "data/manual/dungeon_status.csv"))
    except (OSError, ValueError, KeyError) as e:
        print(f"check_loot: cannot read the inputs: {e}")
        sys.exit(2)
    print(f"Loot check (read-only). AtlasLoot: {atlas_dir}")
    print(f"Ours: {root}/addon/DungeonCrawlerForever/Data/Loot.lua; allowlist: data/manual/loot_none.csv ({len(allow)} rows)")

    # what gen_loot.py would write now, with the same matching
    fresh, cands_of = collections.defaultdict(dict), {}
    manual = gen_loot.manual_loot(root)
    for inst, (dname, names) in ours.items():
        al = atlas.get(inst, [])
        by = gen_loot.by_name(al)
        for name in names:
            cands = gen_loot.match_boss(inst, name, al, by, trash, lmap) if al else []
            cands_of[(inst, name)] = cands
            items = [i for i, _, _ in gen_loot.boss_items(cands, rates)]
            items += [i for i, _ in manual.get((inst, name), []) if i not in items]  # hand-entered drops (data/manual/loot_manual.csv), as gen_loot.py merges them
            if items:
                fresh[inst][name] = items

    missing, new, removed, allowed, stale, notreleased = [], [], [], [], [], []
    for inst in sorted(ours):
        dname, names = ours[inst]
        for name in names:
            label = f"{dname} [{inst}] - {name}"
            have, now = snap.get(inst, {}).get(name), fresh.get(inst, {}).get(name)
            row = allow.get((inst, name))
            if row:
                if have or now:
                    stale.append(f"{label}: allowlisted ({row['reason']}) but has loot "
                                 f"(Loot.lua {len(have or [])} items, AtlasLoot {len(now or [])}): allowlist entry is stale")
                else:
                    allowed.append(f"{label}: {row['reason']} - {row.get('note') or ''}".rstrip(" -"))
            if not have and not now:
                if not row:
                    gap = f"{label}: no loot in Loot.lua or AtlasLoot" + ("" if atlas.get(inst) else " (no AtlasLoot dungeon is mapped to this instance)")
                    if inst in unrel:
                        notreleased.append(f"{gap}; dungeon_status.csv: {unrel[inst][0]}")
                    else:
                        missing.append(gap)
                continue
            if not have:
                new.append(f"{label}: new boss loot, {len(now)} items (Loot.lua has no entry): {', '.join(map(str, now))}")
            elif not now:
                removed.append(f"{label}: AtlasLoot has no loot for it any more (Loot.lua has {len(have)} items)")
            else:
                plus, minus = [i for i in now if i not in have], [i for i in have if i not in now]
                if plus:
                    new.append(f"{label}: +{len(plus)} items: {', '.join(map(str, plus))}")
                if minus:
                    removed.append(f"{label}: -{len(minus)} items: {', '.join(map(str, minus))}")
    for inst in sorted(snap):  # Loot.lua entries for bosses or instances Dungeons.lua no longer has
        for name in snap[inst]:
            if name not in ours.get(inst, ("", []))[1]:
                removed.append(f"[{inst}] - {name}: in Loot.lua but not a boss in Dungeons.lua any more")
    for (inst, name), row in sorted(allow.items()):
        if name not in ours.get(inst, ("", []))[1]:
            stale.append(f"[{inst}] - {name}: allowlisted ({row.get('reason')}) but not a boss in Dungeons.lua")
    stale += [f"loot_none.csv {p}" for p in allow_problems]

    def section(title, lines, extra=()):
        print(f"\n== {title} ({len(lines)})")
        for l in list(lines) + list(extra):
            print("  " + l)
        if not lines and not extra:
            print("  none")
    section("MISSING", missing)
    section("NOT RELEASED", notreleased)
    unmapped = [k for k in gen_loot.SKIPPED if not k.startswith("WorldBosses")]  # same filter as gen_loot.py's own warning
    section("NEW IN ATLASLOOT", new, [f"unmapped AtlasLoot dungeon with loot: {k} (no plain InstanceID and not in gen_loot.py NEW_KEYS;"
                                      " regenerating does not pick it up)" for k in unmapped])
    section("REMOVED FROM ATLASLOOT", removed)
    section("ALLOWLISTED", allowed)
    section("STALE ALLOWLIST", stale)

    print("\n== CROSS-CHECK")
    if not cdb:
        print("  skipped: no --cdb <classic-db.sql> given (CMaNGOS cross-check needs the dump)")
        cross = "skipped"
    else:
        try:
            lootid, ctab = cdb_loot(cdb)
        except (OSError, ValueError, KeyError, IndexError) as e:
            print(f"check_loot: cannot read the classic-db dump {cdb}: {e}")
            sys.exit(2)
        mism, agree, nodata, forever_only = [], 0, [], []
        for inst in sorted(ours):
            dname, names = ours[inst]
            for name in names:
                cands = cands_of[(inst, name)]
                if not cands or name in trash.get(inst, {}):
                    continue
                label = f"{dname} [{inst}] - {name}"
                npcs = sorted({n for b in cands for n in (b.get("npcs") or ([b["npc"]] if b["npc"] else []))})
                cm = {}
                for n in npcs:
                    for i, ch in ctab.get(lootid.get(n, 0), {}).items():
                        cm.setdefault(i, ch)
                if not cm:
                    nodata.append(f"{label} (npc {', '.join(map(str, npcs)) or 'none'})")
                    continue
                al = gen_loot.boss_items(cands, rates)
                al_ids = {i for i, _, _ in al}
                forever = {i for i, f, _ in al if f or i >= FOREVER_MIN_ID}
                both = al_ids & set(cm)
                only_al = sorted(al_ids - set(cm) - forever)
                only_al_forever = sorted(forever - set(cm))
                only_cm = sorted(i for i in cm if i not in al_ids and cm[i] >= 0)
                only_cm_quest = sorted(i for i in cm if i not in al_ids and cm[i] < 0)
                if only_al_forever:
                    forever_only.append(f"{label}: {only_al_forever}")
                if only_al or only_cm:
                    mism.append(f"{label}: both {len(both)}; only AtlasLoot {only_al}; only CMaNGOS {only_cm}"
                                + (f"; CMaNGOS quest drops {only_cm_quest}" if only_cm_quest else ""))
                else:
                    agree += 1
        print(f"  CMaNGOS: {cdb}")
        print(f"  {agree} bosses agree (Forever items and quest drops aside), {len(mism)} differ, {len(nodata)} have no CMaNGOS loot")
        for l in mism:
            print("  MISMATCH " + l)
        for l in nodata:
            print("  no CMaNGOS loot: " + l)
        for l in forever_only:
            print("  Forever items, expected AtlasLoot-only: " + l)
        cross = f"{len(mism)}-mismatch"
    print(f"\nLOOTCHECK missing={len(missing)} new={len(new)} removed={len(removed)} stale={len(stale)} allowlisted={len(allowed)} unmapped={len(unmapped)} unreleased={len(notreleased)} crosscheck={cross}")

if __name__ == "__main__":
    main()
