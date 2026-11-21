#!/usr/bin/env python3
"""Audit addon/DungeonCrawlerForever/Data/Loot.lua against data/derived/item_facts.csv (built from the game's tables by tools/build_item_facts.py). Read-only.
HARD (exit 1): a Forever-range item (id >= 240000) that a profession recipe creates = crafted, not a drop. (Classic ids are not checked: AtlasLoot's classic
               tables are curated and the build's item table is incomplete for them.)
SOFT (listed, exit 0): the same Forever-range item on more than REPEAT bosses of one dungeon (the helms were on nearly every boss; classic items are left
               out because classic loot pools and raid tokens legitimately repeat); a required level more than LEVEL_SLACK
               above the dungeon's top recommended level; and a count of shipped items the build's table does not know (information only: the table lacks many
               Forever-added drops, so unknown does not mean wrong).
Accepted items go in data/manual/loot_audit_ok.csv (itemID,reason); they are not reported again. Usage: tools/audit_loot.py [--quiet]"""
import csv, os, re, sys, collections
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FOREVER_MIN = 240000
REPEAT = 3
LEVEL_SLACK = 6

def load(root=ROOT):
    facts = {int(r["id"]): r for r in csv.DictReader(open(os.path.join(root, "data/derived/item_facts.csv"), encoding="utf-8"))}
    ok = {}
    p = os.path.join(root, "data/manual/loot_audit_ok.csv")
    if os.path.exists(p):
        ok = {int(r["itemID"]): r["reason"] for r in csv.DictReader(open(p, encoding="utf-8")) if (r.get("itemID") or "").isdigit()}
    loot = open(os.path.join(root, "addon/DungeonCrawlerForever/Data/Loot.lua"), encoding="utf-8").read()
    dung = open(os.path.join(root, "addon/DungeonCrawlerForever/Data/Dungeons.lua"), encoding="utf-8").read()
    levels = {int(m.group(1)): (m.group(2), int(m.group(3))) for m in re.finditer(r'\n  \[(\d+)\] = \{ name = "([^"]*)".*?recMax = (\d+)', dung)}
    inst = {}
    for m in re.finditer(r"^  \[(\d+)\] = \{ -- ([^\n]*)\n(.*?)^  \},", loot, re.M | re.S):
        bosses = {}
        for b in re.finditer(r'\["((?:[^"\\]|\\.)+)"\] = \{(.*?)\},?\n', m.group(3)):
            bosses[b.group(1)] = [int(x) for x in re.findall(r"\{(\d+),\d", b.group(2))]
        inst[int(m.group(1))] = (m.group(2), bosses)
    return facts, ok, levels, inst

def audit(root=ROOT):
    facts, ok, levels, inst = load(root)
    hard, soft = [], []
    unknown = set()
    for iid, (dname, bosses) in sorted(inst.items()):
        seen = collections.defaultdict(list)
        for boss, items in bosses.items():
            for i in items:
                f = facts.get(i)
                if i >= FOREVER_MIN and f and f["crafted"] == "1" and i not in ok:
                    hard.append(f"{dname} - {boss}: {f['name']} ({i}) is made by a profession recipe, not a drop")
                if f and f["known"] == "0":
                    unknown.add(i)
                if boss != "Trash":
                    seen[i].append(boss)
                if f and f["reqlevel"].isdigit() and iid in levels and i not in ok and int(f["reqlevel"]) > levels[iid][1] + LEVEL_SLACK and f["quality"] != "":
                    soft.append(f"{dname} - {boss}: {f['name']} ({i}) needs level {f['reqlevel']}, the dungeon tops out at {levels[iid][1]}")
        for i, bs in seen.items():
            if len(bs) > REPEAT and i >= FOREVER_MIN and i not in ok:
                name = facts.get(i, {}).get("name") or str(i)
                soft.append(f"{dname}: {name} ({i}) is listed on {len(bs)} bosses ({', '.join(sorted(bs)[:4])}...)")
    return hard, soft, len(unknown)

def main():
    hard, soft, unk = audit()
    if "--quiet" not in sys.argv:
        for h in hard:
            print("HARD ", h)
        for s in soft:
            print("SOFT ", s)
        print(f"INFO  {unk} shipped items are not in the build's item table (not checked)")
    print(f"LOOTAUDIT hard={len(hard)} soft={len(soft)}")
    return 1 if hard else 0

if __name__ == "__main__":
    sys.exit(main())
