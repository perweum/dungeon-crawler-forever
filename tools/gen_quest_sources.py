#!/usr/bin/env python3
"""Generate addon/DungeonCrawlerForever/Data/QuestSources.lua: which boss (or trash) drops the item a dungeon quest asks for, starts a quest, or has to be killed.

  * old dungeons: CMaNGOS classic-db (GPL-3.0): quest_template (ReqItemId, SrcItemId, ReqCreatureOrGOId), creature_loot_template, creature_template, creature.
    A creature counts when it stands in that dungeon's map; it is a boss when its name is one of the dungeon's bosses (Data/Dungeons.lua), else "Trash"
    (only for quest-only drops, negative chance, so Linen Cloth does not mark every mob).
  * data/manual/quest_sources.csv (instanceMapID,questID,boss,item,kind,note): the Forever-new quests, and corrections. item = an item id or the item's exact name
    (resolved in the client's ItemSparse.csv; an item whose StartQuestID is the quest is found when item is empty and kind is "start"). kind = drop | start | kill.
Reads Data/Quests.lua (run tools/gen_quests.py first). Output: [instanceMapID][bossName] = { { q = questID, item = itemID, kind = "drop"|"start"|"kill", mobs = "names" }, ... }
Usage: tools/gen_quest_sources.py <path/to/classic-db.sql>
"""
import collections, csv, os, re, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gen_quests as G
from lupa import LuaRuntime

ROOT = G.ROOT
DATA = os.path.join(ROOT, "addon/DungeonCrawlerForever/Data")
OUT = os.path.join(DATA, "QuestSources.lua")
MANUAL = os.path.join(ROOT, "data/manual/quest_sources.csv")
norm = lambda s: re.sub(r"[^a-z0-9]", "", (s or "").lower())
ALIAS = {"geilhast": "gelihast", "rasfrostwhisperer": "rasfrostwhisper", "jammalanandogom": "jammalantheprophet"}

def main():
    if len(sys.argv) < 2 or not os.path.exists(sys.argv[1]):
        sys.exit(__doc__)
    build = open(os.path.join(ROOT, "data/BUILD")).read().strip()
    # our quests per dungeon
    lua = LuaRuntime(); lua.execute("ns = {}")
    lua.eval("function(src) local f = load(src); return f('x', ns) end")(open(os.path.join(DATA, "Quests.lua"), encoding="utf-8").read())
    ns = lua.globals().ns
    ours = collections.defaultdict(set)   # dungeon -> quest ids
    for m, lst in ns.QuestData.items():
        for _, q in lst.items():
            ours[int(m)].add(int(q["id"]))
    # bosses per dungeon
    text = open(os.path.join(DATA, "Dungeons.lua"), encoding="utf-8").read()
    bosses, cur = collections.defaultdict(dict), None   # dungeon -> normalised name -> display name
    for l in text.split("\n"):
        mm = re.match(r'\s*\[(\d+)\] = \{ name = "[^"]*", raid = \w+', l)
        if mm:
            cur = int(mm.group(1)); continue
        if cur is not None and " id = " in l:
            n = re.search(r'name = "([^"]*)"', l)
            if n: bosses[cur][ALIAS.get(norm(n.group(1)), norm(n.group(1)))] = n.group(1)
    T = G.load(sys.argv[1], tables=("quest_template", "creature", "creature_template", "creature_loot_template", "item_template"))
    qc, qr = T["quest_template"]
    Q = {int(r[qc["entry"]]): r for r in qr}
    cc, cr = T["creature"]
    cmap = collections.defaultdict(set)
    for r in cr:
        cmap[int(r[cc["id"]])].add(int(r[cc["map"]]))
    tc, tr = T["creature_template"]
    cname = {int(r[tc["Entry"]]): r[tc["Name"]] or "" for r in tr}
    clootid = {int(r[tc["Entry"]]): int(r[tc["LootId"]] or 0) for r in tr}
    lc, lr = T["creature_loot_template"]
    droppers = collections.defaultdict(list)   # item -> [(creature entry, chance)]
    loot2c = collections.defaultdict(set)
    for c, l in clootid.items():
        if l:
            loot2c[l].add(c)
    for r in lr:
        ch = float(r[lc["ChanceOrQuestChance"]] or 0)
        for c in loot2c.get(int(r[lc["entry"]]), ()):
            droppers[int(r[lc["item"]])].append((c, ch))
    ic, ir = T["item_template"]
    inames = {int(r[ic["entry"]]): r[ic["name"]] for r in ir}
    out = collections.defaultdict(lambda: collections.defaultdict(list))   # dungeon -> boss -> entries
    def add(m, boss, q, item, kind, mobs=None):
        e = dict(q=q, item=item, kind=kind, mobs=mobs)
        if e not in out[m][boss]:
            out[m][boss].append(e)
    for m, qids in sorted(ours.items()):
        for q in sorted(qids):
            r = Q.get(q)
            if not r:
                continue
            items = [(int(r[qc["ReqItemId%d" % i]] or 0), "drop") for i in range(1, 5)] + [(int(r[qc["SrcItemId"]] or 0), "start")]
            for it, kind in items:
                if not it:
                    continue
                trash = []
                for c, ch in droppers.get(it, ()):
                    if m not in cmap.get(c, ()):
                        continue
                    n = ALIAS.get(norm(cname.get(c)), norm(cname.get(c)))
                    if n in bosses[m]:
                        add(m, bosses[m][n], q, it, kind)
                    elif ch < 0:
                        trash.append(cname.get(c, ""))
                if trash:
                    add(m, "Trash", q, it, kind, ", ".join(sorted(set(trash))[:4]))
            for i in range(1, 5):
                c = int(r[qc["ReqCreatureOrGOId%d" % i]] or 0)
                if c > 0 and m in cmap.get(c, ()):
                    n = ALIAS.get(norm(cname.get(c)), norm(cname.get(c)))
                    if n in bosses[m]:
                        add(m, bosses[m][n], q, None, "kill")
    # an item that drops from many bosses of one dungeon is a random drop (A Crumpled Up Note): not tied to any boss, one "Trash" line instead
    for m in list(out):
        count = collections.defaultdict(set)
        for boss, ents in out[m].items():
            if boss == "Trash":
                continue
            for e in ents:
                if e["item"] and e["kind"] in ("drop", "start"):
                    count[(e["q"], e["item"])].add(boss)
        for (q, it), bs in count.items():
            if len(bs) > 3:
                for boss in bs:
                    out[m][boss] = [e for e in out[m][boss] if not (e["q"] == q and e["item"] == it)]
                add(m, "Trash", q, it, "drop", "random drop from many mobs")
        for boss in list(out[m]):   # the item that starts a quest is also its objective on the same quest: one line
            ents = out[m][boss]
            out[m][boss] = [e for e in ents if not (e["kind"] == "drop" and any(x["kind"] == "start" and x["q"] == e["q"] and x["item"] == e["item"] for x in ents))]
            if not out[m][boss]:
                del out[m][boss]
    # manual rows (Forever-new quests, corrections)
    sparse = {}
    startq = {}
    for r in csv.DictReader(open(os.path.join(ROOT, f"data/raw/{build}/ItemSparse.csv"), encoding="utf-8")):
        nm = r["Display_lang"]
        sparse.setdefault(nm, int(r["ID"]))
        if r["StartQuestID"] not in ("", "0"):
            startq[int(r["StartQuestID"])] = int(r["ID"])
    if os.path.exists(MANUAL):
        for n, r in enumerate(csv.DictReader(open(MANUAL, encoding="utf-8")), 2):
            m, q = int(r["instanceMapID"]), int(r["questID"])
            kind = (r["kind"] or "drop").strip()
            if kind not in ("drop", "start", "kill"):
                print(f"  ? quest_sources.csv line {n}: kind must be drop, start or kill"); continue
            it = (r["item"] or "").strip()
            item = int(it) if it.isdigit() else sparse.get(it) if it else (startq.get(q) if kind == "start" else None)
            if it and not item:
                print(f"  ? quest_sources.csv line {n}: item {it!r} is not in the client's ItemSparse")
            if m not in ours or q not in ours[m]:
                print(f"  ? quest_sources.csv line {n}: quest {q} is not listed for dungeon {m}")
            add(m, r["boss"].strip(), q, item, kind, (r.get("note") or "").strip() or None)
    lines = ["-- GENERATED by tools/gen_quest_sources.py from CMaNGOS classic-db (GPL-3.0) + data/manual/quest_sources.csv. Do not edit.",
             "-- [instanceMapID][bossName] = { { q = questID, item = itemID (nil for a kill), kind = \"drop\" | \"start\" | \"kill\", mobs = \"names\" (trash only) }, ... }",
             "local _, ns = ...", "ns.QuestSources = {"]
    total = 0
    for m in sorted(out):
        lines.append(f"  [{m}] = {{")
        for boss in sorted(out[m]):
            ents = []
            for e in sorted(out[m][boss], key=lambda e: (e["q"], e["kind"], e["item"] or 0)):
                f = [f"q = {e['q']}"]
                if e["item"]: f.append(f"item = {e['item']}")
                f.append(f"kind = \"{e['kind']}\"")
                if e["mobs"]: f.append("mobs = " + G.lua_str(e["mobs"]))
                ents.append("{ " + ", ".join(f) + " }")
                total += 1
            lines.append(f"    [{G.lua_str(boss)}] = {{ " + ", ".join(ents) + " },")
        lines.append("  },")
    lines.append("}")
    with open(OUT, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines) + "\n")
    print(f"wrote {OUT}: {total} entries in {len(out)} dungeons, {os.path.getsize(OUT)} bytes")

main()
