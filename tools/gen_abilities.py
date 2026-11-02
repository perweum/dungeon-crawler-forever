#!/usr/bin/env python3
"""Generate addon/DungeonCrawlerForever/Data/Abilities.lua: boss ability spell IDs per dungeon boss (IDs only; names, icons and descriptions
come from the game client at runtime, so they follow patches and the player's language).

Sources (facts only):
  * boss -> NPC IDs: AtlasLoot Forever data.lua (GPL-3.0), matched to our boss names exactly like gen_loot.py does
  * NPC -> spells: CMaNGOS classic-db (GPL-3.0) tables creature_template_spells and creature_ai_scripts (cast actions)
  * filter: spell must exist in the Forever client's SpellName table (data/raw/<build>/SpellName.csv), duplicates by name dropped,
    internal/scripting names dropped (internal_name(): SKIP_NAMES prefixes, all-caps tags like "(FAST)", threat wipes, passive/visual auras)
  * manual additions: data/manual/abilities_extra.csv (instanceMapID,boss,spellID,note), added after the generated list
    (not counted against MAX_PER_BOSS, never name-filtered; IDs already in the list are skipped). Each row's note names its source.
  * maintainer-verified lists: data/manual/abilities_verified.csv (instanceMapID,boss,spellID,note). A boss with any row there gets
    exactly those spells (generated list and abilities_extra.csv ignored, no name filter, no MAX_PER_BOSS); a row with an empty spellID
    means "verified: no abilities" and the boss gets no entry (the addon shows its fallback). Rows come from the maintainer's own check
    on Wowhead (agents never fetch it); each note says who checked and when.
  * order: each boss's final list is sorted by spell name (case-insensitive, then spell ID), like Wowhead; the game has no ability order.
Classic bosses only (a 1.12 database): Forever-new dungeons have no entry, the addon shows a fallback text for them.
Usage: tools/gen_abilities.py <path/to/classic-db.sql> [path/to/AtlasLootClassic_DungeonsAndRaids]
"""
import csv, collections, os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
CDB = sys.argv[1] if len(sys.argv) > 1 else None
if __name__ == "__main__":  # importing this module (tests, abilities_checklist.py) leaves sys.argv alone
    if len(sys.argv) > 2:
        sys.argv = [sys.argv[0], sys.argv[2]]  # gen_loot reads the AtlasLoot folder from argv[1]
    else:
        sys.argv = [sys.argv[0]]
import gen_loot  # noqa: E402

MAX_PER_BOSS = 8
SKIP_NAMES = re.compile(r"^(dummy|dnd|test|visual|\[?unused|cosmetic|summon |despawn|set |periodic|aggro|reset|spawn|teleport self|stun self|"
                        r"frenzied|root self|channel|trigger|banish self|self|dual wield|defensive stance|battle stance|berserker stance|"
                        r"parry|dodge|block|shoot$|throw$|melee|attack$)", re.I)
# Internal/scripting spells that are not player-facing abilities (D-068), matched anywhere in the name. Extra-CSV spells are never filtered.
INTERNAL_TAG = re.compile(r"\((?![IVX]+\))[A-Z][A-Z _]{2,}\)|\bDND\b|\bNYI\b")  # all-caps tags: "Disturb Rookery Egg (FAST)", "(DND)", "(OLD)"
INTERNAL_WORDS = re.compile(r"\bhate to zero\b|\bthreat (?:wipe|reset)\b"  # threat-wipe helpers ("Hate to Zero")
                            r"|\bpassive\b|\bvisual\b"                   # passive/visual auras ("Kirtonos Gargoyle Passive", "... Passive Visual")
                            r"|\bweap \d+\b"                              # item-enchant helpers ("Add Lightning Dam - Weap 03")
                            r"|^\w+ channeling$"                           # colour channel visuals ("Green Channeling"), like SKIP_NAMES "channel"
                            r"|\bcredit\b|\bserver ?side\b|\bscript\b", re.I)  # quest/kill credit, server-side and script helpers
ACTION_CAST = 11  # creature_ai_scripts action type "cast spell"
EXTRA_CSV = os.path.join(ROOT, "data/manual/abilities_extra.csv")
VERIFIED_CSV = os.path.join(ROOT, "data/manual/abilities_verified.csv")

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

def column_index(sql_path, table):
    cols, grab = [], False
    for line in open(sql_path, encoding="utf-8", errors="replace"):
        if line.startswith(f"CREATE TABLE `{table}`"):
            grab = True; continue
        if grab:
            m = re.match(r"\s+`(\w+)`", line)
            if m:
                cols.append(m.group(1))
            else:
                break
    return {c: i for i, c in enumerate(cols)}

def load_spells(sql_path):
    """npc entry -> ordered list of spell ids (template spells first, then EventAI casts)."""
    ts_cols, ai_cols = column_index(sql_path, "creature_template_spells"), column_index(sql_path, "creature_ai_scripts")
    spells = collections.defaultdict(list)
    for line in open(sql_path, encoding="utf-8", errors="replace"):
        if line.startswith("INSERT INTO `creature_template_spells`"):
            for r in sql_rows(line):
                for k in range(1, 11):
                    v = int(r[ts_cols[f"spell{k}"]] or 0)
                    if v:
                        spells[int(r[ts_cols["entry"]])].append(v)
        elif line.startswith("INSERT INTO `creature_ai_scripts`"):
            for r in sql_rows(line):
                for a in (1, 2, 3):
                    if int(r[ai_cols[f"action{a}_type"]] or 0) == ACTION_CAST:
                        v = int(r[ai_cols[f"action{a}_param1"]] or 0)
                        if v:
                            spells[int(r[ai_cols["creature_id"]])].append(v)
    return spells

def forever_spell_names():
    build = open(os.path.join(ROOT, "data/BUILD")).read().strip()
    names = {}
    with open(os.path.join(ROOT, "data/raw", build, "SpellName.csv"), encoding="utf-8") as f:
        for r in csv.DictReader(f):
            names[int(r["ID"])] = r["Name_lang"]
    return names

def load_extra(path, ours, names):
    """(instanceMapID, boss) -> [spellID, ...] from the manual list, in file order. Fails on unknown bosses or spells."""
    extra = collections.defaultdict(list)
    if not os.path.exists(path):
        return extra
    with open(path, encoding="utf-8") as f:
        for n, r in enumerate(csv.DictReader(f), start=2):
            inst, boss, sp = int(r["instanceMapID"]), r["boss"].strip(), int(r["spellID"])
            if inst not in ours or boss not in ours[inst][1]:
                sys.exit(f"{os.path.relpath(path, ROOT)}:{n}: unknown boss {boss!r} in instance {inst}")
            if sp not in names:
                sys.exit(f"{os.path.relpath(path, ROOT)}:{n}: spell {sp} is not in this build's SpellName.csv")
            if sp not in extra[(inst, boss)]:
                extra[(inst, boss)].append(sp)
    return extra

def load_verified(path, ours, names):
    """(instanceMapID, boss) -> [spellID, ...] (empty list = verified: no abilities) from the maintainer-verified list. Fails (file:line)
    on unknown bosses, spells missing from SpellName.csv, and a boss that has both an empty row and spell rows."""
    verified, empty_line, spell_line = {}, {}, {}
    if not os.path.exists(path):
        return verified
    rel = os.path.relpath(path, ROOT)
    with open(path, encoding="utf-8") as f:
        for n, r in enumerate(csv.DictReader(f), start=2):
            inst, boss, raw = int(r["instanceMapID"]), r["boss"].strip(), (r["spellID"] or "").strip()
            if inst not in ours or boss not in ours[inst][1]:
                sys.exit(f"{rel}:{n}: unknown boss {boss!r} in instance {inst}")
            key = (inst, boss)
            ids = verified.setdefault(key, [])
            if not raw:
                if key in spell_line:
                    sys.exit(f"{rel}:{n}: empty spellID (no abilities) for {boss!r}, but line {spell_line[key]} lists a spell for it")
                empty_line.setdefault(key, n)
                continue
            sp = int(raw)
            if sp not in names:
                sys.exit(f"{rel}:{n}: spell {sp} is not in this build's SpellName.csv")
            if key in empty_line:
                sys.exit(f"{rel}:{n}: spell {sp} for {boss!r}, but line {empty_line[key]} says it has no abilities (empty spellID)")
            spell_line.setdefault(key, n)
            if sp not in ids:
                ids.append(sp)
    return verified

def verified_dates(path=None):
    """(instanceMapID, boss) -> latest YYYY-MM-DD found in the notes of abilities_verified.csv ("" if none), for the checklist."""
    path, out = path or VERIFIED_CSV, {}
    if os.path.exists(path):
        with open(path, encoding="utf-8") as f:
            for r in csv.DictReader(f):
                key, d = (int(r["instanceMapID"]), r["boss"].strip()), re.findall(r"\d{4}-\d{2}-\d{2}", r.get("note") or "")
                out[key] = max([out.get(key, "")] + d)
    return out

def internal_name(nm):
    """True for spell names that are internal/scripting helpers rather than abilities a player sees."""
    return bool(SKIP_NAMES.match(nm) or INTERNAL_TAG.search(nm) or INTERNAL_WORDS.search(nm))

def by_norm_name(al):
    by = collections.defaultdict(list)
    for b in al:
        by[gen_loot.norm(b["name"])].append(b)
    return by

def boss_npcs(by, name):
    """NPC IDs (in AtlasLoot order, may repeat) of our boss `name`, matched in one instance's AtlasLoot bosses `by` like gen_loot does."""
    k = gen_loot.norm(name)
    cands = by.get(k) or by.get(gen_loot.ALIAS.get(k, ""), [])
    if not cands and k in gen_loot.COMPOSITE:
        cands = [b for part in gen_loot.COMPOSITE[k] for b in by.get(gen_loot.norm(part), [])]
    if not cands:
        cands = [b for kk, bl in by.items() for b in bl if kk and (kk in k or k in kk) and len(kk) > 4]
    return [npc for b in cands for npc in (b.get("npcs") or ([b["npc"]] if b["npc"] else []))]

def by_spell_name(ids, names):
    """Wowhead order: spell name (case-insensitive), then spell ID."""
    return sorted(ids, key=lambda sp: (names.get(sp, "").lower(), sp))

def boss_spells(npcs, npc_spells, names, extra_ids=()):
    """(spell IDs for one boss in final order, the extra IDs that were added). Selection: the NPCs' spells in database order, unknown,
    internal and same-name spells dropped, cut to MAX_PER_BOSS; then the manual extra IDs not already chosen (never filtered)."""
    ids, seen_names = [], set()
    for npc in npcs:
        for sp in npc_spells.get(npc, []):
            nm = names.get(sp)
            if not nm or internal_name(nm) or nm.lower() in seen_names or sp in ids:
                continue
            seen_names.add(nm.lower())
            ids.append(sp)
    ids = ids[:MAX_PER_BOSS]
    added = [sp for sp in extra_ids if sp not in ids]
    return by_spell_name(ids + added, names), added

def select_spells(key, npcs, npc_spells, names, extra, verified):
    """(final spell IDs for boss `key`, {spellID: tag} for the report). A maintainer-verified list replaces everything else."""
    if key in verified:
        return by_spell_name(verified[key], names), {sp: "verified" for sp in verified[key]}
    ids, added = boss_spells(npcs, npc_spells, names, extra.get(key, []))
    return ids, {sp: "manual" for sp in added}

def main():
    if not CDB or not os.path.exists(CDB):
        sys.exit(__doc__)
    npc_spells, names = load_spells(CDB), forever_spell_names()
    atlas, ours = gen_loot.parse_atlas(), gen_loot.our_bosses()
    extra, verified = load_extra(EXTRA_CSV, ours, names), load_verified(VERIFIED_CSV, ours, names)
    out = ["-- GENERATED by tools/gen_abilities.py from CMaNGOS classic-db (GPL-3.0) via AtlasLoot Forever NPC IDs. Do not edit.",
           "-- [instanceMapID][bossName] = { spellID, ... } (names, icons, descriptions come from the client at runtime)",
           "local _, ns = ...", "ns.Abilities = {"]
    bosses_with = bosses_total = spells_total = 0
    report = []
    for inst in sorted(ours):
        dname, bnames = ours[inst]
        al = atlas.get(inst, [])
        if not al and not any(k[0] == inst for k in list(extra) + list(verified)):
            continue
        by = by_norm_name(al)
        rows = []
        for name in bnames:
            bosses_total += 1
            ids, tags = select_spells((inst, name), boss_npcs(by, name), npc_spells, names, extra, verified)
            if ids:
                bosses_with += 1
                spells_total += len(ids)
                rows.append('    ["%s"] = {%s},' % (name.replace('"', '\\"'), ",".join(map(str, ids))))
                report.append(f"  {dname} - {name}: " + ", ".join(names[i] + (f" ({tags[i]})" if i in tags else "") for i in ids))
        if rows:
            out.append(f"  [{inst}] = {{ -- {dname}")
            out.extend(rows)
            out.append("  },")
    out.append("}")
    path = os.path.join(ROOT, "addon/DungeonCrawlerForever/Data/Abilities.lua")
    open(path, "w", encoding="utf-8").write("\n".join(out) + "\n")
    print(f"{bosses_with} of {bosses_total} bosses have abilities, {spells_total} spells -> {path}")
    open(os.path.join(ROOT, "data/raw/abilities_report.txt"), "w", encoding="utf-8").write("\n".join(report) + "\n")

if __name__ == "__main__":
    main()
