#!/usr/bin/env python3
"""Build data/derived/item_facts.csv: facts about every item AtlasLoot lists or Data/Loot.lua ships, from the game's own tables
(data/raw/<data/BUILD>/ItemSparse, SpellEffect, SkillLineAbility; fetched from wago.tools when missing).
Columns: id,name,known,crafted,quality,reqlevel,ilvl,bonding
  known   0 when the build's item table has no such item (it cannot be shown in game)
  crafted 1 when a profession recipe spell creates it (SpellEffect 'create item' of a spell that is in SkillLineAbility): it is not a drop
The file is committed so tests and CI can check loot without the large DB2 tables. Usage: tools/build_item_facts.py [AtlasLoot DungeonsAndRaids folder]"""
import csv, os, re, sys, urllib.request
csv.field_size_limit(10 ** 9)
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
BUILD = open(os.path.join(ROOT, "data/BUILD")).read().strip()
RAW = os.path.join(ROOT, "data/raw", BUILD)
OUT = os.path.join(ROOT, "data/derived/item_facts.csv")

def table(name):
    p = os.path.join(RAW, name + ".csv")
    if not os.path.exists(p):
        os.makedirs(RAW, exist_ok=True)
        req = urllib.request.Request(f"https://wago.tools/db2/{name}/csv?build={BUILD}", headers={"User-Agent": "dungeon-map-tools/0.1"})
        with urllib.request.urlopen(req, timeout=300) as r, open(p, "wb") as f:
            f.write(r.read())
    return csv.DictReader(open(p, encoding="utf-8"))

def wanted_ids(atlas):
    ids = {int(x) for x in re.findall(r"\{(\d+),\d", open(os.path.join(ROOT, "addon/DungeonCrawlerForever/Data/Loot.lua"), encoding="utf-8").read())}
    if atlas:
        import gen_loot
        for bosses in gen_loot.parse_atlas(atlas).values():
            for b in bosses:
                for item, _ in b["items"]:
                    ids.add(item)
                for sb in b.get("subs", ()):
                    for item, _ in sb["items"]:
                        ids.add(item)
    return ids

def main():
    atlas = sys.argv[1] if len(sys.argv) > 1 else None
    ids = wanted_ids(atlas)
    spell_in_skill = {int(r["Spell"]) for r in table("SkillLineAbility")}
    crafted = set()
    for r in table("SpellEffect"):
        if r["Effect"] == "24" and r["EffectItemType"].isdigit() and int(r["EffectItemType"]) in ids and int(r["SpellID"]) in spell_in_skill:
            crafted.add(int(r["EffectItemType"]))
    info = {}
    for r in table("ItemSparse"):
        if r["ID"].isdigit() and int(r["ID"]) in ids:
            info[int(r["ID"])] = r
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(["id", "name", "known", "crafted", "quality", "reqlevel", "ilvl", "bonding"])
        for i in sorted(ids):
            r = info.get(i)
            w.writerow([i, r["Display_lang"] if r else "", 1 if r else 0, 1 if i in crafted else 0,
                        r["OverallQualityID"] if r else "", r["RequiredLevel"] if r else "", r["ItemLevel"] if r else "", r["Bonding"] if r else ""])
    print(f"{len(ids)} items, {len(crafted)} crafted, {len(ids) - len(info)} unknown to build {BUILD} -> {OUT}")

if __name__ == "__main__":
    main()
